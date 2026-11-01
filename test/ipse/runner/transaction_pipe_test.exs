Code.require_file("../../support/native_pipe_scope.exs", __DIR__)

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
    bytes = :binary.copy(<<0, 255, 1, 10>>, 8193)
    p = prepare(Map.put(c, :frame, bytes))
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
    p = prepare(Map.put(c, :frame, "expired"), 700)
    Process.sleep(max(p.deadline - System.monotonic_time(:millisecond) + 5, 0))

    assert {:unknown, :transaction_lost} =
             GenServer.call(p.cap.controller, {:pipe_write, p.cap, p.op, "expired"})

    assert File.read!(p.output) == ""
    cleanup(p)
  end

  test "ordinary input cannot run concurrently with a prepared descriptor handoff", c do
    p = prepare(Map.put(c, :frame, "closed"))
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
                System.monotonic_time(:millisecond) + 3_000, "no authority"}
             )

    assert :ok = T.check(cap)
    Enum.each(Enum.reverse(caps), fn c -> assert :ok = T.release(c) end)
  end

  for boundary <- [:session, :source, :supervisor] do
    test "#{boundary} loss under actual pipe backpressure preserves a partial delivery as unknown",
         c do
      p = prepare(c |> Map.put(:backpressure, true) |> Map.put(:frame, :binary.copy("x", 32_768)))
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

  for binding <- [:operation, :expiry, :frame] do
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
    p = Ipse.Test.NativePipeScope.open(c.paths)
    %{cap: cap, recipient: recipient} = p
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
    op = <<1::64, :crypto.strong_rand_bytes(8)::binary>>
    payload = Map.get(c, :frame, "must not reach worker")
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
         if(c[:bad_binding] == :expiry, do: wall + 1, else: wall), deadline,
         if(c[:bad_binding] == :frame, do: payload <> "altered", else: payload)}
      )

    assert :ok =
             Runner.export_stdio_share(
               stdio,
               op,
               entry(recipient, name, secret, device, inode),
               payload
             )

    if c[:bad_binding] do
      assert_receive {^stdio, {:exit_status, _}}, 5_000

      assert {:reply, {:unknown, :transaction_lost}} =
               :gen_server.receive_response(importing, 5_000)
    else
      assert frame(stdio, ?F) == op
      assert {:reply, :ok} = :gen_server.receive_response(importing, 5_000)
    end

    Map.merge(p, %{
      stdio: stdio,
      output: output,
      op: op,
      deadline: deadline,
      import_refused: not is_nil(c[:bad_binding])
    })
  end

  defp close_pipe(p) do
    request = :gen_server.send_request(p.cap.controller, {:pipe_close, p.cap, p.op})
    assert :ok = Runner.settle_stdio_share(p.stdio, p.op)
    assert frame(p.stdio, ?K) == p.op
    assert {:reply, :ok} = :gen_server.receive_response(request, 5_000)
    :ok
  end

  defp cleanup(p), do: Ipse.Test.NativePipeScope.close(p)

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
