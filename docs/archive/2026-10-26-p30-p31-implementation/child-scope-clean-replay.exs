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
              Resources.controlled_file_effect(
                fn ->
                  send(parent, {:first_ready, self(), Resources.current()})
                  receive do: (:continue -> :ok)
                end,
                3000
              )

            send(parent, {:first_result, first})
            receive do: (:second -> :ok)

            second =
              Resources.controlled_file_effect(
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
