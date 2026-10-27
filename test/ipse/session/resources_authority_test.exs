defmodule Ipse.Session.ResourcesAuthorityTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "only the owning Session can recognize its current worker and actual file effect" do
    owner = self()
    {:ok, scope} = Resources.start(owner)

    worker =
      spawn(fn ->
        Process.flag(:trap_exit, true)

        receive do
          :start -> :ok
        end

        Resources.bind(scope)

        Resources.async(fn ->
          send(owner, {:ordinary, self()})
          receive do: (:finish -> :ok)
        end)

        Resources.file_effect(fn ->
          send(owner, {:effect, self()})
          receive do: (:finish -> :ok)
        end)

        send(owner, :effect_finished)
        receive do: (:stop -> :ok)
      end)

    on_exit(fn ->
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(scope), do: Resources.close(scope)
    end)

    assert :ok = Resources.attach(scope, worker)
    send(worker, :start)
    assert_receive {:ordinary, ordinary}
    assert_receive {:effect, effect}
    assert Resources.authorized_effect?(worker, worker)
    assert Resources.authorized_effect?(worker, effect)
    refute Resources.authorized_effect?(worker, ordinary)
    refute Resources.authorized_effect?(ordinary, effect)
    refute Resources.authorized_effect?(worker, self())

    refute Task.async(fn -> Resources.authorized_effect?(worker, effect) end) |> Task.await()
    send(effect, :finish)
    assert_receive :effect_finished
    assert :ok = Resources.finish(scope)
    refute Resources.authorized_effect?(worker, worker)
    refute Resources.authorized_effect?(worker, effect)
    assert :ok = Resources.close(scope)
    refute Resources.authorized_effect?(worker, worker)
  end
end
