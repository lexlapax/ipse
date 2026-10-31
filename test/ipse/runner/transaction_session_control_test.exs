defmodule Ipse.Runner.TransactionSessionControlTest do
  use ExUnit.Case, async: false

  alias Ipse.Runner
  alias Ipse.Runner.Transaction, as: T

  @moduletag :native_sandbox

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-session-control-switch-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    %{paths: paths}
  end

  test "writer and Session controls remain live through a real root switch", %{paths: paths} do
    {caps, cap, stage, root} = prepare(paths)
    writer = import_control(cap, :writer)
    session = import_control(cap, :session)

    assert {:error, :invalid_transaction_capability} =
             GenServer.call(cap.controller, {
               :writer_control_close,
               cap,
               System.monotonic_time(:millisecond) + 5_000
             })

    assert :ok =
             T.switch_before(cap, stage, "root.json", System.system_time(:millisecond) + 30_000)

    assert File.read!(Path.join(root, "root.json")) == "new"
    deadline = System.monotonic_time(:millisecond) + 5_000
    assert :ok = GenServer.call(cap.controller, {:session_control_close, cap, deadline})
    assert :ok = GenServer.call(cap.controller, {:writer_control_close, cap, deadline})
    assert_receive {^session, {:exit_status, 0}}, 5_000
    assert_receive {^writer, {:exit_status, 0}}, 5_000
    Enum.each(Enum.reverse(caps), fn c -> assert :ok = T.release(c) end)
  end

  test "loss of either control before the switch cannot select the new root", %{paths: paths} do
    for kind <- [:session, :writer] do
      {caps, cap, stage, root} = prepare(paths)
      writer = import_control(cap, :writer)
      session = import_control(cap, :session)
      lost = if kind == :session, do: session, else: writer
      Port.close(lost)

      assert {:unknown, _} =
               T.switch_before(cap, stage, "root.json", System.system_time(:millisecond) + 30_000)

      assert File.read!(Path.join(root, "root.json")) == "old"
      for port <- [writer, session], Port.info(port), do: Port.close(port)
      Enum.each(Enum.reverse(caps), &T.release/1)
      File.rm!(Path.join(root, "root.json"))
    end
  end

  defp prepare(paths) do
    caps =
      Enum.map(paths, fn path ->
        {:ok, cap} = T.acquire(path)
        cap
      end)

    cap = List.last(caps)
    root = Path.dirname(List.last(paths))
    initial = ".pending-" <> Ipse.Usage.id()
    assert :ok = T.stage(cap, ".", [{initial, "old"}])
    assert :ok = T.switch(cap, initial, "root.json")
    stage = ".pending-" <> Ipse.Usage.id()
    assert :ok = T.stage(cap, ".", [{stage, "new"}])
    {caps, cap, stage, root}
  end

  defp import_control(cap, kind) do
    {:ok, sender} = Runner.open_owner_control()
    assert frame(sender, ?R) == "owner-control-v1"
    {:os_pid, sender_pid} = Port.info(sender, :os_pid)
    stat = File.stat!("/proc/#{sender_pid}/fd/0")
    {:ok, %{pid: recipient}} = T.retained_share_identity(cap)
    operation = :crypto.strong_rand_bytes(16)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<sender_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    deadline = System.monotonic_time(:millisecond) + 5_000
    tag = if kind == :writer, do: :writer_control_import, else: :session_control_import
    role = if kind == :writer, do: :host, else: :session
    request = :gen_server.send_request(cap.controller, {tag, cap, operation, entry, deadline})
    assert :ok = Runner.send_owner_control(sender, operation, role, recipient, name, secret)
    id = if kind == :writer, do: 2, else: 1
    assert frame(sender, ?H) == <<operation::binary, id>>
    assert frame(sender, ?T) == <<operation::binary, id>>
    assert {:reply, :ok} = :gen_server.receive_response(request, 5_000)
    sender
  end

  defp frame(port, kind), do: frame(port, kind, Process.get({__MODULE__, port}, <<>>))

  defp frame(port, kind, buffer) do
    case buffer do
      <<^kind, size::32, body::binary-size(size), rest::binary>> ->
        Process.put({__MODULE__, port}, rest)
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 128 ->
            frame(port, kind, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("owner control exited: #{status}")
        after
          5_000 -> flunk("owner control timed out")
        end
    end
  end
end
