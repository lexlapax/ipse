# Isolated diagnostic: the copied Journal module contains a rendezvous just
# before IO.binwrite. This script never installs that instrumented module.
{:ok, _} = Application.ensure_all_started(:ipse)
root = Path.join(System.tmp_dir!(), "ipse-header-owner-loss-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
dir = Path.join(root, "state")
File.mkdir!(dir)
File.chmod!(dir, 0o700)
Process.register(self(), :ipse_header_interposition)

opts = [
  config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
  cwd: root,
  state_dir: dir
]

poll = fn poll, fun, deadline ->
  case fun.() do
    {:ok, result} ->
      result

    _ ->
      if System.monotonic_time(:millisecond) >= deadline, do: raise("diagnostic timeout")
      Process.sleep(10)
      poll.(poll, fun, deadline)
  end
end

try do
  spawn(fn ->
    Process.flag(:trap_exit, true)
    Ipse.Session.start_export_candidate_link(opts)
  end)

  {session, file_server, path} =
    receive do
      {:header_before_write, session, server, path} -> {session, server, path}
    after
      10_000 -> raise "header rendezvous not reached"
    end

  true = is_pid(file_server)
  :ok = File.write!(Path.join(root, "header-path"), path)
  true = :erlang.suspend_process(file_server)
  ref = Process.monitor(session)

  try do
    send(session, :header_go)
    deadline = System.monotonic_time(:millisecond) + 5_000

    :queued =
      poll.(
        poll,
        fn ->
          case Process.info(file_server, :message_queue_len) do
            {:message_queue_len, n} when n > 0 -> {:ok, :queued}
            _ -> :wait
          end
        end,
        deadline
      )

    0 = File.stat!(path).size
    Process.exit(session, :kill)

    receive do
      {:DOWN, ^ref, :process, ^session, :killed} -> :ok
    after
      5_000 -> raise "Session did not die"
    end

    lock_path = String.replace_suffix(path, ".jsonl", ".lock")
    deadline = System.monotonic_time(:millisecond) + 5_000

    lock =
      poll.(
        poll,
        fn ->
          case Ipse.Runner.protected_lock(lock_path) do
            {:ok, lock} -> {:ok, lock}
            _ -> :wait
          end
        end,
        deadline
      )

    0 = File.stat!(path).size
    true = :erlang.resume_process(file_server)
    deadline = System.monotonic_time(:millisecond) + 5_000

    result =
      poll.(
        poll,
        fn ->
          case File.stat(path) do
            {:ok, %{size: size}} when size > 0 -> {:ok, size}
            _ -> :wait
          end
        end,
        deadline
      )

    IO.puts("HEADER_WRITE_AFTER_OWNER_DEATH_AND_COMPETING_LOCK bytes=#{result}")
    :ok = Ipse.Runner.unlock(lock)
  after
    if Process.alive?(file_server) do
      try do
        :erlang.resume_process(file_server)
      catch
        :error, _ -> :ok
      end

      File.close(file_server)
    end
  end
after
  File.rm_rf!(root)
end
