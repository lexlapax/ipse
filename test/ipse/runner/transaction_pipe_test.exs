defmodule Ipse.Runner.TransactionPipeTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner
  alias Ipse.Runner.Transaction, as: T

  if :os.type() != {:unix, :linux}, do: @moduletag(skip: "Linux retained stdin descriptions")

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-pipe-backpressure-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    executable = Path.join(root, "reader")

    assert {"", 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/stdin_backpressure.rs",
                 "-o",
                 executable
               ],
               stderr_to_stdout: true
             )

    %{reader: executable}
  end

  setup do
    Process.flag(:trap_exit, true)
    root = Path.join(System.tmp_dir!(), "ipse-native-pipe-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..4 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, paths: paths}
  end

  test "the existing native owner writes one bounded frame and returns stdin after settlement",
       c do
    p = prepare(c)
    bytes = :binary.copy(<<0, 255, 1, 10>>, 8193)
    assert {:error, :transaction_pipe_frozen} = T.check(p.cap)

    assert {:error, :invalid_transaction_capability} =
             Task.async(fn ->
               GenServer.call(p.cap.controller, {:pipe_write, p.cap, p.op, bytes})
             end)
             |> Task.await()

    assert :ok = GenServer.call(p.cap.controller, {:pipe_write, p.cap, p.op, bytes})

    assert {:error, :invalid_transaction_capability} =
             GenServer.call(p.cap.controller, {:pipe_write, p.cap, p.op, "replayed"})

    assert {:error, :invalid_transaction_capability} =
             GenServer.call(
               p.cap.controller,
               {:pipe_write, p.cap, p.op, :binary.copy("x", 32_773)}
             )

    assert :ok = close_pipe(p)
    assert :ok = T.check(p.cap)
    assert :ok = Runner.send_stdio(p.stdio, "ordinary after settlement\n")
    expected = bytes <> "ordinary after settlement\n"
    await_file(p.output, expected)

    assert :ok =
             Runner.prepare_stdio_share(p.stdio, p.op, System.system_time(:millisecond) + 3_000)

    assert_receive {port, {:exit_status, _}} when port == p.stdio, 5_000
    assert File.read!(p.output) == expected
    cleanup(p)
  end

  for kind <- [:writer, :session, :source] do
    test "loss of #{kind} ownership before a pipe write releases no bytes", c do
      p = prepare(c)

      case unquote(kind) do
        :source ->
          Process.exit(p.source, :kill)

          assert_receive {:DOWN, ref, :process, source, _}
                         when ref == p.source_ref and source == p.source

          await_native_exit(p.source_native_pid)

        kind ->
          Port.close(Map.fetch!(p, kind))
      end

      assert {:unknown, :transaction_lost} =
               GenServer.call(
                 p.cap.controller,
                 {:pipe_write, p.cap, p.op, "must not reach worker"}
               )

      assert File.read!(p.output) == ""
      assert {:unknown, :transaction_unavailable} = T.check(p.cap)
      assert {:error, :invalid_transaction_capability} = T.check(p.cap)
      cleanup(p)
    end
  end

  test "an elapsed pipe handoff cannot be renewed by the write request", c do
    p = prepare(c, 700)
    Process.sleep(max(p.deadline - System.monotonic_time(:millisecond) + 5, 0))

    assert {:unknown, :transaction_lost} =
             GenServer.call(p.cap.controller, {:pipe_write, p.cap, p.op, "expired"})

    assert File.read!(p.output) == ""
    cleanup(p)
  end

  test "ordinary input cannot run concurrently with a prepared descriptor handoff", c do
    p = prepare(c)
    assert :ok = Runner.send_stdio(p.stdio, "must not race\n")
    assert_receive {port, {:exit_status, _}} when port == p.stdio, 5_000
    assert File.read!(p.output) == ""

    assert {:unknown, :transaction_lost} =
             GenServer.call(p.cap.controller, {:pipe_write, p.cap, p.op, "closed"})

    cleanup(p)
  end

  test "the native pipe writer refuses without all protected owners", c do
    [a, b, d | _] = c.paths

    caps =
      Enum.map([a, b, d], fn path ->
        {:ok, cap} = T.acquire(path)
        cap
      end)

    cap = List.last(caps)

    assert {:error, :invalid_transaction_capability} =
             GenServer.call(
               cap.controller,
               {:pipe_import, cap, :crypto.strong_rand_bytes(16), <<0::544>>,
                System.system_time(:millisecond) + 3_000,
                System.monotonic_time(:millisecond) + 3_000}
             )

    assert :ok = T.check(cap)
    Enum.each(Enum.reverse(caps), fn c -> assert :ok = T.release(c) end)
  end

  for boundary <- [:session, :source, :supervisor] do
    test "#{boundary} loss under actual pipe backpressure preserves a partial delivery as unknown",
         c do
      p = prepare(Map.put(c, :backpressure, true))
      parent = self()

      watcher =
        Task.async(fn ->
          await_file(Path.join(c.root, "pipe-partial"), "4096")

          case unquote(boundary) do
            :session -> assert Port.command(p.session, "invalidate retained owner")
            :source -> Process.exit(p.source, :kill)
            :supervisor -> Port.close(p.stdio)
          end

          send(parent, :partial_owner_invalidated)
        end)

      assert {:unknown, :transaction_lost} =
               GenServer.call(
                 p.cap.controller,
                 {:pipe_write, p.cap, p.op, :binary.copy("x", 32_768)}
               )

      assert System.monotonic_time(:millisecond) < p.deadline
      assert_receive :partial_owner_invalidated, 5_000
      assert Task.await(watcher, 5_000) == :partial_owner_invalidated
      assert File.read!(p.output) == :binary.copy("x", 4096)
      assert {:unknown, :transaction_unavailable} = T.check(p.cap)
      assert {:error, :invalid_transaction_capability} = T.check(p.cap)
      cleanup(p)
    end
  end

  for binding <- [:operation, :expiry] do
    test "a different #{binding} cannot receive the prepared stdin descriptor", c do
      p = prepare(Map.put(c, :bad_binding, unquote(binding)))
      assert p.import_refused
      assert File.read!(p.output) == ""
      cleanup(p)
    end
  end

  # These are actual kernel owners and descriptors, with synthetic policy/source
  # lock contents. This component test grants no Session or SDK delivery authority.
  defp prepare(c, lifetime \\ 4_000) do
    [a, b, d, source_path] = c.paths

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
    output = Path.join(c.root, "worker-input")

    {executable, args} =
      if c[:backpressure],
        do: {c.reader, [c.root]},
        else: {"/bin/sh", ["-c", "exec /bin/cat > worker-input"]}

    assert {:ok, stdio} =
             Runner.open_stdio(
               executable,
               args,
               c.root,
               %{},
               15_000,
               protected_supervisor: true
             )

    await_file(output, "")
    op = :crypto.strong_rand_bytes(16)
    wall = System.system_time(:millisecond) + lifetime
    deadline = System.monotonic_time(:millisecond) + lifetime
    assert :ok = Runner.prepare_stdio_share(stdio, op, wall)
    assert <<^op::binary-size(16), pid::32, device::64, inode::64>> = frame(stdio, ?B)
    {name, secret} = pair()

    importing =
      :gen_server.send_request(
        cap.controller,
        {:pipe_import, cap,
         if(c[:bad_binding] == :operation, do: :crypto.strong_rand_bytes(16), else: op),
         entry(pid, name, secret, device, inode),
         if(c[:bad_binding] == :expiry, do: wall + 1, else: wall), deadline}
      )

    assert :ok =
             Runner.export_stdio_share(stdio, op, entry(recipient, name, secret, device, inode))

    if c[:bad_binding] do
      assert_receive {^stdio, {:exit_status, _}}, 5_000

      assert {:reply, {:unknown, :transaction_lost}} =
               :gen_server.receive_response(importing, 5_000)
    else
      assert frame(stdio, ?F) == op
      assert {:reply, :ok} = :gen_server.receive_response(importing, 5_000)
    end

    %{
      caps: caps,
      cap: cap,
      source: source,
      source_ref: source_ref,
      source_op: source_op,
      source_native_pid: source_id.pid,
      source_deadline: limit,
      stdio: stdio,
      output: output,
      op: op,
      writer: writer,
      session: session,
      deadline: deadline,
      import_refused: not is_nil(c[:bad_binding])
    }
  end

  defp close_pipe(p) do
    request = :gen_server.send_request(p.cap.controller, {:pipe_close, p.cap, p.op})
    assert :ok = Runner.settle_stdio_share(p.stdio, p.op)
    assert frame(p.stdio, ?K) == p.op
    assert {:reply, :ok} = :gen_server.receive_response(request, 5_000)
    :ok
  end

  defp cleanup(p) do
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

    for port <- [p.stdio, p.writer, p.session],
        Port.info(port),
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

  defp await_file(path, bytes, limit \\ nil) do
    limit = limit || System.monotonic_time(:millisecond) + 5_000

    cond do
      File.read(path) == {:ok, bytes} ->
        :ok

      System.monotonic_time(:millisecond) >= limit ->
        flunk("worker input did not match expected bytes")

      true ->
        Process.sleep(5)
        await_file(path, bytes, limit)
    end
  end

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
