defmodule Ipse.Extension.PendingCapacityTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.{Migration, PendingCapacity}

  test "an exact replacement can use a full queue without silently evicting another candidate" do
    old = %{"text" => "old"}
    record = %{"value" => old, "bytes" => byte_size(Migration.encode(old))}
    candidate = %{"kind" => "proposal"}
    read = fn %{"op" => "pending_summary"} -> {:ok, %{"count" => 64, "bytes" => 262_144}} end
    assert :ok = PendingCapacity.replace(candidate, %{"text" => "new"}, record, read)
    assert :ok = PendingCapacity.replace(candidate, %{"text" => "n"}, record, read)

    assert {:error, :pending_capacity_refused} =
             PendingCapacity.replace(candidate, %{"text" => "longer"}, record, read)

    assert {:error, :pending_capacity_refused} =
             PendingCapacity.check(
               %{"kind" => "proposal", "key" => "pending.synthetic"},
               old,
               read
             )
  end

  test "replacement refuses missing, inconsistent, oversized or malformed pending summaries" do
    value = %{"text" => "old"}
    record = %{"value" => value, "bytes" => byte_size(Migration.encode(value))}

    for summary <- [
          %{"count" => 0, "bytes" => 100},
          %{"count" => 65, "bytes" => 100},
          %{"count" => 1, "bytes" => 0},
          %{"count" => 1, "bytes" => -1},
          %{"count" => 1, "bytes" => 262_145},
          %{"count" => 1, "bytes" => 100, "unseen" => true}
        ] do
      assert {:error, :pending_capacity_refused} =
               PendingCapacity.replace(%{"kind" => "proposal"}, value, record, fn _ ->
                 {:ok, summary}
               end)
    end

    assert {:error, :pending_capacity_refused} =
             PendingCapacity.replace(
               %{"kind" => "proposal"},
               value,
               %{record | "bytes" => 0},
               fn _ -> {:ok, %{"count" => 1, "bytes" => 100}} end
             )
  end
end
