defmodule Ipse.Session.ObservationLineageTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.ObservationLineage, as: Lineage

  defp receipt(n), do: Ipse.JSON.sha256("synthetic-#{n}")

  test "all workers and later workers inherit the session union after confirmed closure" do
    {:ok, state, a} = Lineage.start_worker(Lineage.new())
    {:ok, state, b} = Lineage.start_worker(state)
    {:ok, state} = Lineage.observed(state, a, receipt(1))
    {:ok, state} = Lineage.observed(state, b, receipt(2))
    expected = Enum.sort([receipt(1), receipt(2)])
    assert {:ok, ^expected} = Lineage.obligations(state, a)
    assert {:ok, ^expected} = Lineage.obligations(state, b)
    {:ok, state} = Lineage.finish_worker(state, a, :ok)
    {:ok, state, c} = Lineage.start_worker(state)
    assert {:ok, ^expected} = Lineage.obligations(state, c)
    assert {:error, poisoned} = Lineage.obligations(state, a)
    assert {:error, _} = Lineage.obligations(poisoned, c)
  end

  test "untracked edges and uncertain cleanup poison without a reset" do
    {:ok, state, worker} = Lineage.start_worker(Lineage.new())
    {:ok, state} = Lineage.observed(state, worker, receipt(1))
    assert {:error, poisoned} = Lineage.finish_worker(state, worker, :unknown)
    assert {:error, _} = Lineage.obligations(poisoned, worker)
    assert {:error, _} = Lineage.start_worker(poisoned)
    assert {:error, _} = Lineage.observed(Lineage.untracked(state), worker, receipt(2))
    assert {:error, poisoned} = Lineage.observed(state, make_ref(), receipt(2))
    assert {:error, _} = Lineage.obligations(poisoned, worker)
  end

  test "origin capacity is monotonic, deduplicated, and exhaustion refuses" do
    {:ok, state, worker} = Lineage.start_worker(Lineage.new())

    state =
      Enum.reduce(1..32, state, fn n, s ->
        {:ok, next} = Lineage.observed(s, worker, receipt(n))
        next
      end)

    assert {:ok, state} = Lineage.observed(state, worker, receipt(1))
    assert {:ok, origins} = Lineage.obligations(state, worker)
    assert length(origins) == 32
    assert {:error, poisoned} = Lineage.observed(state, worker, receipt(33))
    assert {:error, _} = Lineage.obligations(poisoned, worker)
  end

  test "worker-capacity and malformed receipt fail closed" do
    state =
      Enum.reduce(1..16, Lineage.new(), fn _, s ->
        {:ok, next, _} = Lineage.start_worker(s)
        next
      end)

    assert {:error, poisoned} = Lineage.start_worker(state)
    assert {:error, _} = Lineage.start_worker(poisoned)
    {:ok, fresh, worker} = Lineage.start_worker(Lineage.new())
    assert {:error, poisoned} = Lineage.observed(fresh, worker, "not-a-hash")
    assert {:error, _} = Lineage.finish_worker(poisoned, worker, :ok)
  end
end
