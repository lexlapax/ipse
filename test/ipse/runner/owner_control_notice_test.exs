defmodule Ipse.Runner.OwnerControlNoticeTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  @moduletag :native_sandbox
  @root Path.expand("../../..", __DIR__)
  @expiry 2_000_000_000_000

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-notice-peer-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    owner_source = File.read!(Path.join(@root, "native/ipse-owner-control.rs"))
    needle = "command[1..17] != *operation"
    assert length(String.split(owner_source, needle)) == 2
    duplicate_guard = "if !notice_mode || noticed || fds[0].revents != INPUT {"
    assert length(String.split(owner_source, duplicate_guard)) == 2
    altered = Path.join(root, "owner.rs")

    File.write!(
      altered,
      owner_source
      |> String.replace(needle, "false")
      |> String.replace(duplicate_guard, "if !notice_mode || fds[0].revents != INPUT {")
    )

    wrapper = Path.join(root, "peer.rs")

    File.write!(wrapper, """
    #[path=#{inspect(Path.join(@root, "native/ipse-lease-sink.rs"))}] mod ipse_lease_sink;
    #[path=#{inspect(Path.join(@root, "native/ipse-lease-transfer.rs"))}] mod ipse_lease_transfer;
    #[path=#{inspect(altered)}] mod ipse_owner_control;
    fn main() {
      let args: Vec<String> = std::env::args().collect();
      let result = if args[1] == "--owner-control-send-v2" || args[1] == "--owner-control-send-review-notice-v4" {
        ipse_owner_control::send(&args)
      } else {
        ipse_owner_control::observe(&args)
      };
      if result.is_err() { std::process::exit(1); }
    }
    """)

    peer = Path.join(root, "peer")

    assert {_, 0} =
             System.cmd("rustc", ["--edition=2021", "-A", "dead_code", wrapper, "-o", peer],
               stderr_to_stdout: true
             )

    review_helper = Path.join(root, "review-helper")

    assert {"", 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.join(@root, "native/ipse-runner.rs"),
                 "-o",
                 review_helper
               ],
               stderr_to_stdout: true
             )

    %{adversarial_peer: peer, review_helper: review_helper}
  end

  defp open(mode, executable, extra \\ []) do
    helper = executable || Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: [mode | extra]
      ])

    on_exit(fn -> if Port.info(port), do: Port.close(port) end)
    port
  end

  defp transferred_review(helper, lifetime, notice \\ false) do
    mode =
      if notice,
        do: "--owner-control-send-review-notice-v4",
        else: "--owner-control-send-review-v3"

    sender = open(mode, helper, [Integer.to_string(lifetime)])
    assert frame(sender, ?R) == if(notice, do: "owner-control-v2", else: "owner-control-v1")
    {:os_pid, sender_pid} = Port.info(sender, :os_pid)
    stat = File.stat!("/proc/#{sender_pid}/fd/0")

    receiver =
      open(
        if(notice, do: "--owner-control-observe-v2", else: "--owner-control-observe-v1"),
        helper
      )

    assert frame(receiver, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(receiver, :os_pid)
    operation = :crypto.strong_rand_bytes(16)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<sender_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    request = <<operation::binary, 1, entry::binary, lifetime::64>>
    assert Port.command(receiver, <<?I, byte_size(request)::32, request::binary>>)
    assert :ok = Runner.send_owner_control(sender, operation, :session, recipient, name, secret)
    assert frame(sender, ?H) == <<operation::binary, 1>>
    assert frame(sender, ?T) == <<operation::binary, 1>>
    assert frame(receiver, ?L) == <<operation::binary, 1>>
    {sender, receiver, operation}
  end

  test "review owner control remains live past setup and closes with its owner", c do
    {sender, receiver, operation} = transferred_review(c.review_helper, 9_000)
    Process.sleep(5_200)
    assert Port.info(sender) != nil and Port.info(receiver) != nil
    assert :ok = Runner.close_owner_control(sender)
    assert frame(receiver, ?D) == <<operation::binary, 1>>
    assert_receive {^receiver, {:exit_status, _}}, 5_000
  end

  test "review owner control ends at its own finite lifetime", c do
    {sender, receiver, _} = transferred_review(c.review_helper, 6_000)
    assert_receive {^sender, {:exit_status, status}}, 8_000
    assert status != 0
    assert_receive {^receiver, {:exit_status, _}}, 5_000
  end

  test "review notice stays authenticated after setup and expires at the review deadline", c do
    {sender, receiver, operation} = transferred_review(c.review_helper, 7_000, true)
    Process.sleep(5_200)
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert frame(sender, ?N) == <<operation::binary, 1, @expiry::64>>
    assert_receive {^sender, {:exit_status, status}}, 3_000
    assert status != 0
    assert_receive {^receiver, {:exit_status, _}}, 5_000
  end

  test "review notice refuses a forged operation from its authenticated peer", c do
    {sender, receiver, operation} = transferred_review(c.adversarial_peer, 9_000, true)
    wrong = :crypto.strong_rand_bytes(16)
    refute wrong == operation
    assert Port.command(receiver, <<?N, wrong::binary, @expiry::64>>)
    assert_receive {^sender, {:exit_status, status}}, 5_000
    assert status != 0
    assert Process.get({__MODULE__, sender}, <<>>) == <<>>
    refute_receive {^sender, {:data, _}}, 50
  end

  test "review notice refuses a repeated notice from its authenticated peer", c do
    {sender, receiver, operation} = transferred_review(c.adversarial_peer, 9_000, true)
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert frame(sender, ?N) == <<operation::binary, 1, @expiry::64>>
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert_receive {^sender, {:exit_status, status}}, 5_000
    assert status != 0
    assert Process.get({__MODULE__, sender}, <<>>) == <<>>
    refute_receive {^sender, {:data, _}}, 50
  end

  test "review owner control rejects lifetimes outside its bound", c do
    for mode <- ["--owner-control-send-review-v3", "--owner-control-send-review-notice-v4"],
        lifetime <- ["4999", "120001", "invalid"] do
      port = open(mode, c.review_helper, [lifetime])
      assert_receive {^port, {:exit_status, status}}, 5_000
      assert status != 0
    end
  end

  test "review owner control keeps the five-second setup limit", c do
    sender = open("--owner-control-send-review-v3", c.review_helper, ["9000"])
    assert frame(sender, ?R) == "owner-control-v1"
    assert_receive {^sender, {:exit_status, status}}, 6_500
    assert status != 0
  end

  test "review owner control preparation is bound to its owner, action and deadline" do
    owner = self()
    job = make_ref()
    intent = %{"operation" => "synthetic review"}
    now = System.monotonic_time(:millisecond)

    assert {:ok, prepared} =
             Runner.prepare_owner_control(
               job,
               intent,
               make_ref(),
               :crypto.strong_rand_bytes(16),
               now + 4_000
             )

    assert {:error, :owner_control_unavailable} =
             Runner.open_review_owner_control(
               prepared,
               owner,
               job,
               Map.put(intent, "operation", "other"),
               now + 9_000
             )

    assert {:error, :owner_control_unavailable} =
             Runner.open_review_owner_control(prepared, owner, job, intent, now + 121_000)

    assert {:error, :owner_control_unavailable} =
             Task.async(fn ->
               Runner.open_review_owner_control(prepared, owner, job, intent, now + 9_000)
             end)
             |> Task.await()

    assert {:ok, port} =
             Runner.open_review_owner_control(prepared, owner, job, intent, now + 9_000)

    assert frame(port, ?R) == "owner-control-v1"
    assert :ok = Runner.close_owner_control(port)

    assert {:error, :owner_control_unavailable} =
             Runner.open_review_notice_owner_control(
               prepared,
               owner,
               job,
               Map.put(intent, "operation", "other"),
               now + 9_000
             )

    assert {:error, :owner_control_unavailable} =
             Task.async(fn ->
               Runner.open_review_notice_owner_control(prepared, owner, job, intent, now + 9_000)
             end)
             |> Task.await()

    assert {:ok, notice_port} =
             Runner.open_review_notice_owner_control(prepared, owner, job, intent, now + 9_000)

    assert frame(notice_port, ?R) == "owner-control-v2"
    assert :ok = Runner.close_owner_control(notice_port)
  end

  defp frame(port, kind) do
    buffer = Process.get({__MODULE__, port}, <<>>)

    case buffer do
      <<^kind, size::32, body::binary-size(size), rest::binary>> ->
        Process.put({__MODULE__, port}, rest)
        body

      _ when byte_size(buffer) > 256 ->
        flunk("invalid owner-control frame")

      _ ->
        receive do
          {^port, {:data, bytes}} ->
            Process.put({__MODULE__, port}, buffer <> bytes)
            frame(port, kind)

          {^port, {:exit_status, status}} ->
            flunk("owner-control exited before frame: #{status}")
        after
          5_000 -> flunk("owner-control frame timed out")
        end
    end
  end

  defp transferred(peer \\ nil) do
    sender = open("--owner-control-send-v2", peer)
    assert frame(sender, ?R) == "owner-control-v2"
    {:os_pid, sender_pid} = Port.info(sender, :os_pid)
    stat = File.stat!("/proc/#{sender_pid}/fd/0")
    receiver = open("--owner-control-observe-v2", peer)
    assert frame(receiver, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(receiver, :os_pid)
    operation = :crypto.strong_rand_bytes(16)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<sender_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    request = <<operation::binary, 1, entry::binary, 10_000::64>>
    assert Port.command(receiver, <<?I, byte_size(request)::32, request::binary>>)
    assert :ok = Runner.send_owner_control(sender, operation, :session, recipient, name, secret)
    assert frame(sender, ?H) == <<operation::binary, 1>>
    assert frame(sender, ?T) == <<operation::binary, 1>>
    assert frame(receiver, ?L) == <<operation::binary, 1>>
    {sender, receiver, operation}
  end

  defp assert_sender_stopped_without_notice(sender) do
    assert_receive {^sender, {:exit_status, status}}, 5_000
    assert Process.get({__MODULE__, sender}, <<>>) == <<>>

    if status == 0,
      do: refute_receive({^sender, {:data, _}}, 50),
      else: assert(frame(sender, ?E) == "owner-control unavailable")

    assert Process.get({__MODULE__, sender}, <<>>) == <<>>
    refute_receive {^sender, {:data, _}}, 50
  end

  test "authenticated peer sends one operation-bound notice while controls remain live" do
    {sender, receiver, operation} = transferred()
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert frame(sender, ?N) == <<operation::binary, 1, @expiry::64>>
    assert Port.info(sender) != nil
    assert Port.info(receiver) != nil
  end

  test "a different operation cannot produce a notice" do
    {sender, receiver, operation} = transferred()
    wrong = :crypto.strong_rand_bytes(16)
    refute wrong == operation
    assert Port.command(receiver, <<?N, wrong::binary, @expiry::64>>)
    assert_receive {^receiver, {:exit_status, status}}, 5_000
    assert status != 0
    assert_sender_stopped_without_notice(sender)
  end

  test "a second notice is refused and cannot be reported twice" do
    {sender, receiver, operation} = transferred()
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert frame(sender, ?N) == <<operation::binary, 1, @expiry::64>>
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert_receive {^receiver, {:exit_status, status}}, 5_000
    assert status != 0
    assert_sender_stopped_without_notice(sender)
  end

  test "the sender refuses a wrong operation from its authenticated peer", c do
    {sender, receiver, operation} = transferred(c.adversarial_peer)
    wrong = :crypto.strong_rand_bytes(16)
    refute wrong == operation
    assert Port.command(receiver, <<?N, wrong::binary, @expiry::64>>)
    assert_receive {^sender, {:exit_status, status}}, 5_000
    assert status != 0
    assert Process.get({__MODULE__, sender}, <<>>) == <<>>
    refute_receive {^sender, {:data, _}}, 50
  end

  test "the sender refuses a second notice from its authenticated peer", c do
    {sender, receiver, operation} = transferred(c.adversarial_peer)
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert frame(sender, ?N) == <<operation::binary, 1, @expiry::64>>
    assert Port.command(receiver, <<?N, operation::binary, @expiry::64>>)
    assert_receive {^sender, {:exit_status, status}}, 5_000
    assert status != 0
    assert Process.get({__MODULE__, sender}, <<>>) == <<>>
    refute_receive {^sender, {:data, _}}, 50
  end

  test "a different helper executable cannot become the notice peer", c do
    sender = open("--owner-control-send-v2", nil)
    assert frame(sender, ?R) == "owner-control-v2"
    receiver = open("--owner-control-observe-v2", c.adversarial_peer)
    assert frame(receiver, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(receiver, :os_pid)
    operation = :crypto.strong_rand_bytes(16)

    assert :ok =
             Runner.send_owner_control(
               sender,
               operation,
               :session,
               recipient,
               :crypto.strong_rand_bytes(16),
               :crypto.strong_rand_bytes(32)
             )

    assert_receive {^sender, {:exit_status, status}}, 5_000
    assert status != 0
    assert frame(sender, ?E) == "owner-control unavailable"
  end
end
