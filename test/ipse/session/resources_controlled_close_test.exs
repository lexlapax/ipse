defmodule IndependentNormalCloseFixedTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "normal child close fences peer before acknowledging closure" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :start ->
            Resources.bind(root)

            outcome =
              Resources.controlled_owned_effect(
                fn ->
                  send(parent, {:ready, self(), Resources.current()})

                  receive do
                    :continue ->
                      send(parent, :effect_after_close)
                      :effect_returned
                  end
                end,
                3000
              )

            send(parent, {:outcome, outcome})
            receive do: (:done -> :ok)
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :start)
      assert_receive {:ready, peer, child}, 3000
      assert :ok == Resources.close(child)
      send(peer, :continue)
      refute_receive :effect_after_close, 100
      assert_receive {:outcome, {:unknown, :effect_interrupted}}, 3000
    after
      send(worker, :done)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end

defmodule ChildSelfCloseDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "active peer cannot close its own scope and continue" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :start ->
            Resources.bind(root)

            outcome =
              Resources.controlled_owned_effect(
                fn ->
                  Resources.close(Resources.current())
                  send(parent, :self_close_escaped)
                end,
                3000
              )

            send(parent, {:self_close_outcome, outcome})
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :start)
      assert_receive {:self_close_outcome, {:unknown, :effect_interrupted}}, 5000
      refute_receive :self_close_escaped, 100
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end

defmodule ChildStopCastDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "child stop fences peer before child exit even when guard is suspended" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :start ->
            Resources.bind(root)

            outcome =
              Resources.controlled_owned_effect(
                fn ->
                  send(parent, {:cast_ready, self(), Resources.current()})
                  receive do: (:continue -> send(parent, :effect_after_cast))
                end,
                5000
              )

            send(parent, {:cast_outcome, outcome})
            receive do: (:done -> :ok)
        end
      end)

    :ok = Resources.attach(root, worker)
    send(worker, :start)
    assert_receive {:cast_ready, peer, child}, 3000
    {:links, links} = Process.info(peer, :links)
    [guard] = Enum.filter(links, &(is_pid(&1) and &1 != child))
    assert :erlang.suspend_process(guard)

    try do
      child_ref = Process.monitor(child)
      Resources.stop_async(child)
      assert_receive {:DOWN, ^child_ref, :process, ^child, _}, 5000
      send(peer, :continue)
      refute_receive :effect_after_cast, 100
      refute Process.alive?(peer)

      receive do
        {:cast_outcome, {:unknown, :effect_interrupted}} ->
          refute Process.alive?(guard)
      after
        100 ->
          if Process.alive?(guard), do: :erlang.resume_process(guard)
          assert_receive {:cast_outcome, {:unknown, :effect_interrupted}}, 5000
      end
    after
      if Process.alive?(guard), do: :erlang.resume_process(guard)
      send(worker, :done)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end
