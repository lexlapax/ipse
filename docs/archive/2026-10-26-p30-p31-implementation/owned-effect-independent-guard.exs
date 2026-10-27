defmodule IndependentGuardAuthorityTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.{Lock, Resources}
  alias Ipse.Runner.Transaction

  test "a controlled child may register and release a real native lock under a retained Session guard" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    dir = Path.join(Path.expand(System.tmp_dir!()), "child-guard-authority-" <> Ipse.Usage.id())
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    domain = Path.join(dir, "domain")
    File.mkdir!(domain)
    File.chmod!(domain, 0o700)
    {:ok, _} = Lock.acquire(Path.join(dir, "session.lock"))
    guard = Lock.current()
    {:ok, root} = Resources.start(self())
    :ok = Lock.track(root, :scope)
    parent = self()
    worker = spawn(fn ->
      receive do
        :start ->
          Resources.bind(root)
          result = Resources.controlled_owned_effect(fn ->
            case Transaction.acquire(Path.join(domain, ".lock")) do
              {:ok, cap} -> Transaction.release(cap)
              other -> other
            end
          end, 3000)
          send(parent, {:outcome, result})
          receive do: (:done -> :ok)
      end
    end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :start)
      assert_receive {:outcome, {:ok, :ok}}, 8000
    after
      send(worker, :done)
      if Process.alive?(root), do: Resources.close(root)
      if Process.alive?(guard), do: Lock.release(guard)
      File.rm_rf!(dir)
    end
  end
end
