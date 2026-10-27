defmodule RetainedGuardDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.{Lock, Resources}
  alias Ipse.Runner.Transaction, as: T

  test "actual retained Session lock guard permits a child native controller" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    dir = Path.join(Path.expand(System.tmp_dir!()), "controlled-retained-" <> Ipse.Usage.id())
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    domain = Path.join(dir, "domain")
    File.mkdir_p!(domain)
    File.chmod!(domain, 0o700)
    {:ok, _} = Lock.acquire(Path.join(dir, "session.lock"))
    guard = Lock.current()
    {:ok, root} = Resources.start(self())
    :ok = Lock.track(root, :scope)
    assert {:error, :session_lock_refused} = Lock.track_child_scope(guard, self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :run ->
            Resources.bind(root)

            result =
              Resources.controlled_file_effect(
                fn ->
                  result = T.acquire(Path.join(domain, ".lock"))
                  send(parent, {:guarded_acquire, result})

                  case result do
                    {:ok, cap} -> T.release(cap)
                    _ -> result
                  end
                end,
                5000
              )

            send(parent, {:guarded_result, result})
            receive do: (:finish -> :ok)
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :run)
      assert_receive {:guarded_acquire, {:ok, _}}, 8000
      assert_receive {:guarded_result, {:ok, :ok}}, 8000
      send(worker, :finish)
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
      if Process.alive?(guard), do: Lock.release(guard)
      File.rm_rf!(dir)
    end
  end
end
