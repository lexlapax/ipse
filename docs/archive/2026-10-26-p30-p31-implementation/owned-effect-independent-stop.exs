defmodule IndependentStopRaceTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "asynchronous stop fences the peer before scope exits even when guard is suspended" do
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
              :continue -> send(parent, :late_effect)
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
      state = :sys.get_state(root)
      [guard] = Map.keys(state.effects) -- [peer]
      Process.put(:audit_guard, guard)
      assert :erlang.suspend_process(guard)
      child_ref = Process.monitor(child)
      Resources.stop_async(child)
      assert_receive {:DOWN, ^child_ref, :process, ^child, _}, 3000
      refute Process.alive?(peer)
      send(peer, :continue)
      refute_receive :late_effect, 100
      if Process.alive?(guard), do: :erlang.resume_process(guard)
      assert_receive {:outcome, {:unknown, :effect_interrupted}}, 5000
    after
      if guard = Process.get(:audit_guard) do
        try do
          :erlang.resume_process(guard)
        rescue
          _ -> :ok
        end
      end
      send(worker, :done)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end
