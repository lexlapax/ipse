# Diagnostic against the historical candidate cohort, not the gated runtime.
defmodule HeaderShutdownFixture do
  def complete(config, _, _, _) do
    send(config.fixture_owner, {:provider_started, self()})

    receive do
      :finish -> {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
    end
  end
end

{:ok, _} = Application.ensure_all_started(:ipse)
root = Path.join(System.tmp_dir!(), "ipse-shutdown-contender-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
dir = Path.join(root, "state")
File.mkdir!(dir)
File.chmod!(dir, 0o700)

config = %{
  provider: :demo,
  provider_module: HeaderShutdownFixture,
  fixture_owner: self(),
  model: "fixture",
  home: root,
  approval: :deny
}

try do
  {:ok, session} =
    Ipse.Session.start_export_candidate_link(
      config: config,
      cwd: root,
      state_dir: dir,
      subscriber: self()
    )

  Process.unlink(session)
  state = :sys.get_state(session)
  :ok = Ipse.Session.prompt(session, "synthetic in-flight close")

  provider =
    receive do
      {:provider_started, pid} -> pid
    after
      5_000 -> raise "provider did not start"
    end

  task = :sys.get_state(session).task.pid
  writer = state.journal_writer
  path = Path.join(dir, state.id <> ".lock")
  parent = self()

  spawn(fn ->
    {:error, _} = Ipse.Runner.protected_lock(path)
    send(parent, :contender_ready)

    receive do
      :start -> :ok
    end

    acquire = fn acquire ->
      case Ipse.Runner.protected_lock(path) do
        {:ok, lock} ->
          observed = {Process.alive?(task), Process.alive?(provider), Process.alive?(writer)}
          send(parent, {:acquired, observed})
          :ok = Ipse.Runner.unlock(lock)

        {:error, _} ->
          Process.sleep(5)
          acquire.(acquire)
      end
    end

    acquire.(acquire)
  end)
  |> then(fn contender ->
    receive do
      :contender_ready -> :ok
    after
      5_000 -> raise "contender not ready"
    end

    send(contender, :start)
    :ok = Ipse.Session.close_confirmed(session)

    receive do
      {:acquired, {false, false, false}} ->
        IO.puts("CONTENDER_ACQUIRED_AFTER_TASK_AND_WRITER_STOP")

      {:acquired, other} ->
        raise "live dependent at acquisition: #{inspect(other)}"
    after
      5_000 -> raise "contender did not acquire"
    end
  end)
after
  File.rm_rf!(root)
end
