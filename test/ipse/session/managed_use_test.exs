defmodule Ipse.Session.ManagedUseTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.ManagedUse

  test "expiry during the final observation prevents the use callback" do
    owner = self()
    deadline = System.system_time(:millisecond) + 30

    observe = fn ->
      Process.sleep(max(deadline - System.system_time(:millisecond) + 1, 0))
      {:ok, :observed}
    end

    assert {:error, :managed_dependency_unavailable} =
             ManagedUse.checked_observation(%{"expires_at_ms" => deadline}, observe, fn _ ->
               send(owner, :released_after_expiry)
               :ok
             end)

    refute_receive :released_after_expiry, 10
  end

  test "a checked handoff preserves opaque continuation results and refuses failed observations" do
    policy = %{"expires_at_ms" => System.system_time(:millisecond) + 60_000}
    result = {:native_send, make_ref(), :completed}

    assert ^result =
             ManagedUse.checked_observation(policy, fn -> {:ok, :current} end, fn :current ->
               result
             end)

    assert {:error, :managed_dependency_unavailable} =
             ManagedUse.checked_observation(policy, fn -> {:error, :unavailable} end, fn _ ->
               flunk("failed observation reached use")
             end)
  end
end
