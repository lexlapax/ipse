defmodule Ipse.Test.NativePipeScope do
  @moduledoc false
  import ExUnit.Assertions
  alias Ipse.Runner
  alias Ipse.Runner.Transaction, as: T

  # Actual kernel owners with synthetic lock contents; no Session authority.
  def open(root) when is_binary(root) do
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..4 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    open(paths)
  end

  def open(paths) when is_list(paths) do
    [a, b, d, source_path] = paths

    caps =
      Enum.map([a, b, d], fn path ->
        {:ok, cap} = T.acquire(path)
        cap
      end)

    cap = List.last(caps)
    {:ok, %{pid: recipient}} = T.retained_share_identity(cap)
    writer = import_control(cap, :writer, recipient)
    session = import_control(cap, :session, recipient)
    parent = self()

    {source, source_ref} =
      spawn_monitor(fn ->
        Process.monitor(parent)
        {:ok, source_cap} = T.acquire(source_path)
        {:ok, identity} = T.retained_share_identity(source_cap)
        send(parent, {:source_ready, self(), identity})
        source_loop(parent, source_cap)
      end)

    assert_receive {:source_ready, ^source, source_id}, 5_000
    source_op = :crypto.strong_rand_bytes(16)
    {name, secret} = pair()
    limit = System.monotonic_time(:millisecond) + 5_000
    entry = entry(source_id.pid, name, secret, source_id.device, source_id.inode)

    importing =
      :gen_server.send_request(cap.controller, {:source_import, cap, source_op, entry, limit})

    send(
      source,
      {:export, source_op, entry(recipient, name, secret, source_id.device, source_id.inode),
       limit}
    )

    assert_receive {:source_exported, ^source, :ok}, 5_000
    assert {:reply, :ok} = :gen_server.receive_response(importing, 5_000)

    %{
      caps: caps,
      cap: cap,
      recipient: recipient,
      source: source,
      source_ref: source_ref,
      source_op: source_op,
      source_native_pid: source_id.pid,
      source_deadline: limit,
      writer: writer,
      session: session
    }
  end

  def close(p) do
    if Process.alive?(p.cap.controller) do
      limit = p.source_deadline

      request =
        :gen_server.send_request(p.cap.controller, {:source_close, p.cap, p.source_op, limit})

      send(p.source, {:settle, p.source_op, limit})
      assert_receive {:source_settled, source, :ok} when source == p.source, 5_000
      assert {:reply, :ok} = :gen_server.receive_response(request, 5_000)
      assert :ok = GenServer.call(p.cap.controller, {:session_control_close, p.cap, limit})
      assert :ok = GenServer.call(p.cap.controller, {:writer_control_close, p.cap, limit})
      Enum.each(Enum.reverse(p.caps), fn c -> assert :ok = T.release(c) end)
    end

    for port <- [Map.get(p, :stdio), p.writer, p.session],
        is_port(port) and Port.info(port),
        do: assert(:ok == Runner.close_stdio(port))

    if Process.alive?(p.source) do
      send(p.source, :stop)

      assert_receive {:DOWN, ref, :process, source, _}
                     when ref == p.source_ref and source == p.source,
                     5_000
    end

    await_native_exit(p.source_native_pid)
    Process.demonitor(p.source_ref, [:flush])
  end

  defp source_loop(parent, cap) do
    receive do
      {:export, operation, recipient, deadline} ->
        send(
          parent,
          {:source_exported, self(), T.retained_share_export(cap, operation, recipient, deadline)}
        )

        source_loop(parent, cap)

      {:settle, operation, deadline} ->
        send(parent, {:source_settled, self(), T.retained_share_settle(cap, operation, deadline)})
        source_loop(parent, cap)

      :stop ->
        T.release(cap)

      {:DOWN, _, :process, ^parent, _} ->
        :ok
    end
  end

  defp import_control(cap, kind, recipient) do
    {:ok, port} = Runner.open_owner_control()
    assert frame(port, ?R) == "owner-control-v1"
    {:os_pid, pid} = Port.info(port, :os_pid)
    stat = File.stat!("/proc/#{pid}/fd/0")
    operation = :crypto.strong_rand_bytes(16)
    {name, secret} = pair()
    entry = entry(pid, name, secret, stat.major_device, stat.inode)
    deadline = System.monotonic_time(:millisecond) + 5_000
    tag = if kind == :writer, do: :writer_control_import, else: :session_control_import
    role = if kind == :writer, do: :host, else: :session
    request = :gen_server.send_request(cap.controller, {tag, cap, operation, entry, deadline})
    assert :ok = Runner.send_owner_control(port, operation, role, recipient, name, secret)
    id = if kind == :writer, do: 2, else: 1
    assert frame(port, ?H) == <<operation::binary, id>>
    assert frame(port, ?T) == <<operation::binary, id>>
    assert {:reply, :ok} = :gen_server.receive_response(request, 5_000)
    port
  end

  defp pair, do: {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}

  defp entry(pid, name, secret, device, inode),
    do: <<pid::32, name::binary, secret::binary, device::64, inode::64>>

  defp await_native_exit(pid, limit \\ nil) do
    limit = limit || System.monotonic_time(:millisecond) + 5_000

    case File.read("/proc/#{pid}/stat") do
      {:error, :enoent} ->
        :ok

      {:ok, stat} ->
        cond do
          Regex.match?(~r/\) [ZX] /, stat) ->
            :ok

          System.monotonic_time(:millisecond) >= limit ->
            flunk("native source owner did not exit")

          true ->
            Process.sleep(5)
            await_native_exit(pid, limit)
        end

      _ ->
        flunk("native source owner state unavailable")
    end
  end

  defp frame(port, kind), do: frame(port, kind, Process.get({__MODULE__, port}, <<>>))

  defp frame(port, kind, buffer) do
    case buffer do
      <<^kind, size::32, body::binary-size(size), rest::binary>> ->
        Process.put({__MODULE__, port}, rest)
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            frame(port, kind, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("pipe owner exited: #{status}")
        after
          5_000 -> flunk("pipe owner timed out")
        end
    end
  end
end
