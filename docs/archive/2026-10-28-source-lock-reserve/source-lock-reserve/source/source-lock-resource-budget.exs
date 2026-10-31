defmodule Ipse.Session.SourceLockResourceBudgetTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "an existing controlled child remains admissible at the ordinary resource ceiling" do
    parent = self()
    {:ok, scope} = Resources.start(parent)
    previous = Resources.bind(scope)

    tickets =
      for _ <- 1..32,
          do:
            (
              assert {:ok, ticket} = Resources.register(:http)
              ticket
            )

    task =
      Task.async(fn ->
        receive do
          :start -> :ok
        end

        Resources.bind(scope)

        assert {:ok, :done} =
                 Resources.controlled_owned_effect(
                   fn ->
                     send(parent, {:controlled_child, self()})

                     receive do
                       :release -> :done
                     end
                   end,
                   10_000
                 )

        assert :ok = Resources.finish(scope)
        :done
      end)

    try do
      assert :ok = Resources.attach(scope, task.pid)
      send(task.pid, :start)
      assert_receive {:controlled_child, peer}, 5000
      assert {:error, :cleanup_scope_closed} = Resources.register(:lock)
      assert {:ok, source_ticket} = Resources.register(:source_lock)
      Resources.closed(source_ticket, :ok)
      Enum.each(tickets, &Resources.closed(&1, :ok))
      send(peer, :release)
      assert :done = Task.await(task, 10_000)
      assert :ok = Resources.close(scope)
    after
      Resources.bind(previous)
    end
  end
end
