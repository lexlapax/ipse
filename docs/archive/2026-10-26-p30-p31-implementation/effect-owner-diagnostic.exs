defmodule EffectOwnerDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "effect continues after its initiating worker is killed" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, scope} = Resources.start(self())
    observer = self()
    worker = spawn(fn ->
      receive do
        :begin ->
          Resources.bind(scope)
          Resources.file_effect(fn ->
            send(observer, {:effect_started, self()})
            receive do
              :continue -> send(observer, :effect_continued)
            end
          end)
      end
    end)
    :ok = Resources.attach(scope, worker)
    ref = Process.monitor(worker)
    send(worker, :begin)
    assert_receive {:effect_started, peer}, 5000
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}, 5000
    send(peer, :continue)
    assert_receive :effect_continued, 5000
  end
end
