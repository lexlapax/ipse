defmodule Ipse.InferenceSlots.LedgerTest do
  use ExUnit.Case, async: true
  alias Ipse.InferenceSlots.Ledger
  @now 100_000
  @origins ["http://127.0.0.1:11434"]
  defp id(n), do: Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(32, "0")

  defp meta(priority \\ "background"),
    do: %{
      "session_id" => id(100),
      "project_id" => Ipse.JSON.sha256("project"),
      "request_sha256" => Ipse.JSON.sha256("request"),
      "route_sha256" => Ipse.JSON.sha256("route"),
      "priority" => priority,
      "dispatch_timeout_ms" => 100_000
    }

  defp enqueue(state, n, priority \\ "background"),
    do: Ledger.enqueue(state, "local", @origins, id(n), meta(priority), @now, 60_000)

  test "foreground priority is rechecked at admission and services keep separate slots" do
    assert {:ok, state, _} = enqueue(Ledger.empty(), 1)
    assert Ledger.eligible?(state, id(1), @now)
    assert {:ok, state, _} = enqueue(state, 2, "foreground")
    refute Ledger.eligible?(state, id(1), @now)
    assert {:error, _} = Ledger.admit(state, id(1), @now)
    assert {:ok, state, active} = Ledger.admit(state, id(2), @now)
    assert active["id"] == id(2)
    assert {:error, _} = Ledger.admit(state, id(1), @now)

    assert {:ok, state, _} =
             Ledger.enqueue(state, "other", ["https://example.com"], id(3), meta(), @now, 1)

    assert Ledger.slot(state, "local") != Ledger.slot(state, "other")
    assert {:ok, _, _} = Ledger.admit(state, id(3), @now)
  end

  test "admitted work cannot expire and exact reconciliation cannot clear another reservation" do
    assert {:ok, state, _} = enqueue(Ledger.empty(), 1)
    assert {:ok, state, _} = Ledger.admit(state, id(1), @now)

    receipt = %{
      "version" => 1,
      "reason" => "shared_service_reconciled",
      "service_id" => "local",
      "reservation_id" => id(1),
      "expected_revision" => state["revision"],
      "operator_receipt_sha256" => Ipse.JSON.sha256("review")
    }

    assert {:error, _} =
             Ledger.reconcile(state, "local", id(2), state["revision"], receipt, @now + 1_000_000)

    assert {:error, _} =
             Ledger.reconcile(state, "local", id(1), state["revision"] * 1.0, receipt, @now)

    assert {:error, _} =
             Ledger.reconcile(state, "local", id(1), state["revision"] - 1, receipt, @now)

    assert {:error, _} =
             Ledger.reconcile(
               state,
               "local",
               id(1),
               state["revision"],
               Map.put(receipt, "extra", true),
               @now
             )

    for receipt <- [
          Map.put(receipt, "service_id", "other"),
          Map.put(receipt, "reservation_id", id(2)),
          Map.put(receipt, "expected_revision", state["revision"] - 1)
        ] do
      assert {:error, _} =
               Ledger.reconcile(state, "local", id(1), state["revision"], receipt, @now)
    end

    assert {:ok, next, recent} =
             Ledger.reconcile(state, "local", id(1), state["revision"], receipt, @now + 1_000_000)

    assert next["services"]["local"]["active"] == nil
    assert recent["status"] == "reconciled" and recent["receipt"] == receipt
  end

  test "service renames, alias replacements and overlapping historical aliases refuse" do
    assert {:ok, state, _} = enqueue(Ledger.empty(), 1)

    for {service, origins} <- [{"renamed", @origins}, {"local", ["http://localhost:11434"]}] do
      assert {:error, :service_identity_conflict} =
               Ledger.enqueue(state, service, origins, id(2), meta(), @now, 10)
    end

    assert {:ok, state, _} = Ledger.cancel_waiting(state, id(1))

    assert {:error, :service_identity_conflict} =
             Ledger.enqueue(state, "renamed", @origins, id(2), meta(), @now, 10)
  end

  test "only known-unstarted waiters expire and time cannot silently move backwards" do
    assert {:ok, state, _} = enqueue(Ledger.empty(), 1)
    refute Ledger.eligible?(state, id(1), @now - 1)

    assert {:error, :service_clock_regressed} =
             Ledger.enqueue(state, "local", @origins, id(2), meta(), @now - 1, 10)

    assert {:ok, next, _} =
             Ledger.enqueue(state, "local", @origins, id(2), meta(), @now + 60_000, 10)

    assert Enum.map(next["queue"], & &1["id"]) == [id(2)]
    assert {:ok, state, _} = Ledger.admit(state, id(1), @now)

    assert {:ok, next, _} =
             Ledger.enqueue(state, "local", @origins, id(2), meta(), @now + 60_000, 10)

    assert next["services"]["local"]["active"]["id"] == id(1)
  end

  test "queue and service registries have finite capacity and exact integer counters" do
    state =
      Enum.reduce(1..64, Ledger.empty(), fn n, state ->
        {:ok, state, _} = enqueue(state, n)
        state
      end)

    assert {:error, :service_queue_refused} = enqueue(state, 65)
    assert {:error, _} = enqueue(state, 1)
    assert {:ok, state, _} = Ledger.cancel_waiting(state, id(1))
    assert {:ok, _, _} = enqueue(state, 65)

    for bad <- [
          put_in(state, ["revision"], 1.0),
          put_in(state, ["sequence"], 0),
          Map.put(state, "extra", true)
        ] do
      refute Ledger.valid?(bad)
    end

    state =
      Enum.reduce(1..8, Ledger.empty(), fn n, state ->
        {:ok, state, _} =
          Ledger.enqueue(
            state,
            "service#{n}",
            ["https://s#{n}.example.com"],
            id(n),
            meta(),
            @now,
            10
          )

        state
      end)

    assert {:error, :service_identity_conflict} =
             Ledger.enqueue(
               state,
               "ninth",
               ["https://ninth.example.com"],
               id(9),
               meta(),
               @now,
               10
             )
  end

  test "recent outcomes remain bounded without evicting unresolved work" do
    state =
      Enum.reduce(1..40, Ledger.empty(), fn n, state ->
        {:ok, state, _} = enqueue(state, n)
        {:ok, state, _} = Ledger.admit(state, id(n), @now)
        {:ok, state, _} = Ledger.settle(state, "local", id(n), @now)
        state
      end)

    assert length(state["recent"]) == 32
    assert hd(state["recent"])["id"] == id(9)
    assert {:ok, state, _} = enqueue(state, 41)
    assert {:ok, state, _} = Ledger.admit(state, id(41), @now)
    assert state["services"]["local"]["active"]["id"] == id(41)
    assert length(state["recent"]) == 32
    assert Ledger.valid?(state)
  end
end
