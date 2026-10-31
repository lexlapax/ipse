# Requires the isolated diagnostic-only Journal rendezvous graph.
{:ok, _} = Application.ensure_all_started(:ipse)
root = Path.join(System.tmp_dir!(), "ipse-legacy-header-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
dir = Path.join(root, "state")
File.mkdir!(dir)
File.chmod!(dir, 0o700)
Process.register(self(), :ipse_header_interposition)

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

    Ipse.Session.start_link(
      config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
      cwd: root,
      state_dir: dir,
      subscriber: self()
    )
  end)

  {session, server, path} =
    receive do
      {:header_before_write, session, server, path} -> {session, server, path}
    after
      10_000 -> raise "header rendezvous not reached"
    end

  true = :erlang.suspend_process(server)

  try do
    send(session, :header_go)

    :queued =
      poll.(
        poll,
        fn ->
          case Process.info(server, :message_queue_len) do
            {:message_queue_len, n} when n > 0 -> {:ok, :queued}
            _ -> :wait
          end
        end,
        System.monotonic_time(:millisecond) + 5_000
      )

    true = Process.alive?(session)
    lock_path = String.replace_suffix(path, ".jsonl", ".lock")
    {:ok, contender} = Ipse.Runner.protected_lock(lock_path)
    0 = File.stat!(path).size
    true = :erlang.resume_process(server)

    bytes =
      poll.(
        poll,
        fn ->
          case File.stat(path) do
            {:ok, %{size: size}} when size > 0 -> {:ok, size}
            _ -> :wait
          end
        end,
        System.monotonic_time(:millisecond) + 5_000
      )

    IO.puts("LEGACY_HEADER_WRITE_WHILE_CONTENDER_HOLDS_LOCK bytes=#{bytes}")
    Process.exit(session, :kill)
    :ok = Ipse.Runner.unlock(contender)
  after
    if Process.alive?(server) do
      try do
        :erlang.resume_process(server)
      catch
        :error, _ -> :ok
      end

      File.close(server)
    end
  end
after
  File.rm_rf!(root)
end
