defmodule ControlledEffectReceiptReplayTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "a replayed prior child receipt cannot settle a later scope" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :start ->
            Resources.bind(root)

            first =
              Resources.controlled_owned_effect(
                fn ->
                  send(parent, {:first_ready, self(), Resources.current()})
                  receive do: (:continue -> :ok)
                end,
                3000
              )

            send(parent, {:first_result, first})
            receive do: (:second -> :ok)

            second =
              Resources.controlled_owned_effect(
                fn ->
                  scope = Resources.current()

                  resource =
                    spawn(fn ->
                      Resources.bind(scope)
                      {:ok, ticket} = Resources.register(:lock)
                      send(parent, {:withholding_resource, self()})

                      receive do
                        {:ipse_cancel_resource, id} when id == ticket.id ->
                          receive do: (:never -> :ok)
                      end
                    end)

                  send(parent, {:second_ready, self(), resource})
                  receive do: (:never -> :ok)
                end,
                800
              )

            send(parent, {:second_result, second})
            receive do: (:finish -> :ok)
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :start)
      assert_receive {:first_ready, peer, child}, 3000
      [{old_token, _}] = Map.to_list(:sys.get_state(root).child_tokens)
      send(peer, :continue)
      assert_receive {:first_result, {:ok, :ok}}, 5000
      send(worker, :second)
      assert_receive {:withholding_resource, resource}, 3000
      assert_receive {:second_ready, _, ^resource}, 3000

      try do
        send(worker, {:child_scope_finished, old_token, child, :ok})
        assert_receive {:second_result, {:unknown, :cleanup_unconfirmed}}, 9000
      after
        Process.exit(resource, :kill)
      end

      send(worker, :finish)
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end

defmodule ControlledEffectDuplicateNonceTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "a duplicate root nonce cannot replace the original peer" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    peer = spawn(fn -> receive do: (:never -> :ok) end)
    other = spawn(fn -> receive do: (:never -> :ok) end)
    token = make_ref()
    parent = self()

    reporter =
      spawn(fn ->
        receive do
          :run ->
            first = GenServer.call(root, {:track_child_effect, peer, token})
            second = GenServer.call(root, {:track_child_effect, other, token})
            send(parent, {:duplicate_results, first, second})
            receive do: (:finish -> :ok)
            GenServer.cast(root, {:abandon_child, token, peer, self()})
        end
      end)

    try do
      assert {:error, :cleanup_scope_closed} =
               GenServer.call(root, {:track_child_effect, peer, token})

      :ok = Resources.attach(root, reporter)
      send(reporter, :run)
      assert_receive {:duplicate_results, {:ok, _}, {:error, :cleanup_scope_closed}}, 3000
      assert :sys.get_state(root).child_tokens[token].peer == peer
      Process.exit(peer, :kill)
      send(reporter, :finish)
    after
      if Process.alive?(reporter), do: Process.exit(reporter, :kill)
      if Process.alive?(peer), do: Process.exit(peer, :kill)
      if Process.alive?(other), do: Process.exit(other, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end
