defmodule Ipse.Session.OwnerControlTest do
  use ExUnit.Case, async: false
  import Bitwise
  alias Ipse.{Runner, Session, Usage}
  @moduletag :native_sandbox
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux owner-control")

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-owner-control-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    opts = [
      config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
      cwd: root,
      state_dir: Path.join(root, "sessions"),
      subscriber: self()
    ]

    {:ok, session} = Session.start_share_candidate_link(opts)
    Process.unlink(session)
    on_exit(fn -> if Process.alive?(session), do: Process.exit(session, :kill) end)
    on_exit(fn -> File.rm_rf!(root) end)
    %{session: session}
  end

  test "actual Session owner death makes the handed-off read end permanently lost", c do
    {port, observer, operation} = open_handoff(c.session, :session)
    {:os_pid, pid} = Port.info(port, :os_pid)
    pipe = File.read_link!("/proc/#{pid}/fd/0")
    assert beam_pipe_write_count(pipe) == 1
    assert {:error, :owner_control_unavailable} = Runner.close_owner_control(port)
    monitor = Process.monitor(c.session)
    Process.exit(c.session, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
    assert receive_frame(observer, ?D) == <<operation::binary, 1>>
    assert_receive {^observer, {:exit_status, 0}}, 5_000
    assert Process.alive?(self())
  end

  test "handoff-helper death is loss even while its real Session owner remains alive", c do
    {port, observer, operation} = open_handoff(c.session, :session)
    {:os_pid, pid} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
    assert receive_frame(observer, ?D) == <<operation::binary, 1>>
    assert_receive {^observer, {:exit_status, 0}}, 5_000
    assert Process.alive?(c.session)
    assert :ok = Session.close_confirmed(c.session)
  end

  test "an owner byte after transfer is sticky loss and is never consumed", c do
    {port, observer, operation} = open_handoff(c.session, :session)
    test = self()

    :sys.replace_state(c.session, fn s ->
      send(test, {:wrote, Port.command(port, "forbidden")})
      s
    end)

    assert_receive {:wrote, true}
    assert receive_frame(observer, ?D) == <<operation::binary, 1>>
    assert_receive {^observer, {:exit_status, 0}}, 5_000
    assert Process.alive?(c.session)
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :owner_control_close
  test "Session can close its control while its Writer is suspended", c do
    {port, observer, operation} = open_handoff(c.session, :session)
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    test = self()

    :sys.replace_state(c.session, fn s ->
      send(test, {:owner_close, Runner.close_owner_control(port)})
      s
    end)

    assert_receive {:owner_close, :ok}, 1_000
    assert receive_frame(observer, ?D) == <<operation::binary, 1>>
    assert_receive {^observer, {:exit_status, 0}}, 5_000
    :ok = :sys.resume(writer)
    assert :ok = Session.close_confirmed(c.session)
  end

  test "wrong operation and role cannot complete a handoff", c do
    for mismatch <- [:operation, :role] do
      {port, sender, info} = source(c.session)
      {observer, recipient} = observer()
      operation = :crypto.strong_rand_bytes(16)
      observed = if mismatch == :operation, do: :crypto.strong_rand_bytes(16), else: operation
      role = if mismatch == :role, do: 2, else: 1
      name = :crypto.strong_rand_bytes(16)
      secret = :crypto.strong_rand_bytes(32)
      entry = <<sender::32, name::binary, secret::binary, info.major_device::64, info.inode::64>>
      request = <<observed::binary, role, entry::binary, 30_000::64>>
      assert Port.command(observer, <<?I, byte_size(request)::32, request::binary>>)
      send_from_session(c.session, port, operation, :session, recipient, name, secret)
      assert_receive {^observer, {:exit_status, status}}, 8_000
      assert status != 0
    end

    assert :ok = Session.close_confirmed(c.session)
  end

  test "a different helper PID cannot take the intended recipient's handoff", c do
    {port, sender, info} = source(c.session)
    {observer, _wrong_pid} = observer()
    {intended, intended_pid} = observer()
    operation = :crypto.strong_rand_bytes(16)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    entry = <<sender::32, name::binary, secret::binary, info.major_device::64, info.inode::64>>
    request = <<operation::binary, 1, entry::binary, 30_000::64>>
    assert Port.command(observer, <<?I, byte_size(request)::32, request::binary>>)
    send_from_session(c.session, port, operation, :session, intended_pid, name, secret)
    assert_receive {^observer, {:exit_status, status}}, 8_000
    assert status != 0
    if Port.info(intended), do: Port.close(intended)
    assert :ok = Session.close_confirmed(c.session)
  end

  test "owner death aborts a stalled handoff before a recipient connects", c do
    {port, sender, _info} = source(c.session)
    {observer, recipient} = observer()
    operation = :crypto.strong_rand_bytes(16)
    assert 1 == :erlang.trace(c.session, true, [:receive])

    send_from_session(
      c.session,
      port,
      operation,
      :session,
      recipient,
      :crypto.strong_rand_bytes(16),
      :crypto.strong_rand_bytes(32)
    )

    await_h(c.session, port, operation)
    assert 1 == :erlang.trace(c.session, false, [:receive])
    monitor = Process.monitor(c.session)
    Process.exit(c.session, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
    assert eventually_gone?(sender, 100)
    if Port.info(observer), do: Port.close(observer)
  end

  @tag :owner_control_deadline
  test "stalled handoff closes its helper within the single setup deadline", c do
    {port, sender, _info} = source(c.session)
    {observer, recipient} = observer()
    operation = :crypto.strong_rand_bytes(16)
    assert 1 == :erlang.trace(c.session, true, [:receive])
    started = System.monotonic_time(:millisecond)

    send_from_session(
      c.session,
      port,
      operation,
      :session,
      recipient,
      :crypto.strong_rand_bytes(16),
      :crypto.strong_rand_bytes(32)
    )

    await_h(c.session, port, operation)
    assert eventually_gone?(sender, 700)
    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed in 4_000..7_000
    assert 1 == :erlang.trace(c.session, false, [:receive])
    if Port.info(observer), do: Port.close(observer)
    assert :ok = Session.close_confirmed(c.session)
  end

  defp source(session) do
    test = self()
    assert 1 == :erlang.trace(session, true, [:receive])

    :sys.replace_state(session, fn s ->
      send(test, {:owner_port, Runner.open_owner_control()})
      s
    end)

    assert_receive {:owner_port, {:ok, port}}
    await_ready(session, port)
    assert 1 == :erlang.trace(session, false, [:receive])
    assert Port.info(port, :connected) == {:connected, session}
    {:os_pid, sender} = Port.info(port, :os_pid)
    {port, sender, File.stat!("/proc/#{sender}/fd/0")}
  end

  defp observer do
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    observer =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--owner-control-observe-v1"]
      ])

    assert receive_frame(observer, ?H) == "owner-observer-v1"
    {:os_pid, pid} = Port.info(observer, :os_pid)
    {observer, pid}
  end

  defp send_from_session(session, port, operation, role, recipient, name, secret) do
    test = self()

    :sys.replace_state(session, fn s ->
      send(
        test,
        {:owner_send, Runner.send_owner_control(port, operation, role, recipient, name, secret)}
      )

      s
    end)

    assert_receive {:owner_send, :ok}
  end

  defp eventually_gone?(_, 0), do: false

  defp eventually_gone?(pid, attempts) do
    if File.exists?("/proc/#{pid}"),
      do:
        (
          Process.sleep(10)
          eventually_gone?(pid, attempts - 1)
        ),
      else: true
  end

  defp await_h(session, port, operation, buffer \\ <<>>) do
    case buffer do
      <<?H, 17::32, ^operation::binary-size(16), 1>> ->
        :ok

      _ ->
        receive do
          {:trace, ^session, :receive, {^port, {:data, bytes}}}
          when byte_size(buffer) + byte_size(bytes) <= 64 ->
            await_h(session, port, operation, buffer <> bytes)
        after
          5_000 -> flunk("sender did not reach its bound listener")
        end
    end
  end

  defp await_ready(session, port, buffer \\ <<>>) do
    case buffer do
      <<?R, 16::32, "owner-control-v1">> ->
        :ok

      _ ->
        receive do
          {:trace, ^session, :receive, {^port, {:data, bytes}}}
          when byte_size(buffer) + byte_size(bytes) <= 64 ->
            await_ready(session, port, buffer <> bytes)
        after
          5_000 -> flunk("sender did not report descriptor readiness")
        end
    end
  end

  defp open_handoff(session, role) do
    {port, sender, info} = source(session)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    observer =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--owner-control-observe-v1"]
      ])

    assert receive_frame(observer, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(observer, :os_pid)
    operation = :crypto.strong_rand_bytes(16)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    role_id = if role == :session, do: 1, else: 2
    entry = <<sender::32, name::binary, secret::binary, info.major_device::64, info.inode::64>>
    request = <<operation::binary, role_id, entry::binary, 30_000::64>>
    assert Port.command(observer, <<?I, byte_size(request)::32, request::binary>>)

    send_from_session(session, port, operation, role, recipient, name, secret)
    assert receive_frame(observer, ?L) == <<operation::binary, role_id>>
    {port, observer, operation}
  end

  defp beam_pipe_write_count(pipe) do
    base = "/proc/#{System.pid()}/fd"

    File.ls!(base)
    |> Enum.count(fn fd ->
      with {:ok, ^pipe} <- File.read_link(Path.join(base, fd)),
           {:ok, info} <- File.read("/proc/#{System.pid()}/fdinfo/#{fd}"),
           [_, flags] <- Regex.run(~r/^flags:\s+([0-7]+)/m, info),
           {value, ""} <- Integer.parse(flags, 8) do
        (value &&& 3) in [1, 2]
      else
        _ -> false
      end
    end)
  end

  defp receive_frame(port, kind, buffer \\ <<>>) do
    case buffer do
      <<^kind, length::32, body::binary-size(length)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            receive_frame(port, kind, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("observer exited before reply: #{status}")
        after
          8_000 -> flunk("owner-control observer timed out")
        end
    end
  end
end
