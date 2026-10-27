defmodule IndependentNormalCloseDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "external normal child close fences the effect peer" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()
    worker = spawn(fn ->
      receive do
        :start ->
          Resources.bind(root)
          outcome = Resources.controlled_owned_effect(fn ->
            send(parent, {:ready, self(), Resources.current()})
            receive do
              :continue ->
                send(parent, :effect_after_close)
                :effect_returned
            end
          end, 3000)
          send(parent, {:outcome, outcome})
          receive do: (:done -> :ok)
      end
    end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :start)
      assert_receive {:ready, peer, child}, 3000
      assert :ok == Resources.close(child)
      refute Process.alive?(peer)
      send(peer, :continue)
      refute_receive :effect_after_close, 100
      assert_receive {:outcome, {:unknown, :effect_interrupted}}, 3000
    after
      send(worker, :done)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end
