Code.require_file("../../dev/knowledge/storage_continuation.exs", __DIR__)
Code.require_file("../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("../../dev/knowledge/storage_workload.ex", __DIR__)
Code.require_file("../../dev/knowledge/storage_annual.exs", __DIR__)

defmodule Ipse.Development.StorageContinuationTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.StorageContinuation, as: Continuation

  test "checkpoint admission binds the exact runtime, options and unfinished progress" do
    c = checkpoint()
    assert :ok = Continuation.validate(c, c["binding"], c["options"])

    for changed <- [
          Map.put(c, "binding", String.duplicate("b", 64)),
          Map.put(c, "unknown", true),
          Map.put(c, "segment", 4),
          Map.put(c, "segment", 1.0),
          Map.put(c, "progress", %{"day" => 365, "cycle" => 10_000}),
          Map.put(c, "progress", %{"day" => 1, "cycle" => 1}),
          Map.put(c, "progress", %{"day" => 0.0, "cycle" => 0}),
          put_in(c, ["options", "payload"], "representative"),
          put_in(c, ["descriptor", "operations"], 2),
          put_in(c, ["state", "samples"], ["invalid"]),
          put_in(c, ["state", "samples"], []),
          put_in(c, ["state", "samples"], [7_200_001]),
          put_in(c, ["state", "peak_allocated"], 67_108_865),
          put_in(c, ["state", "generation"], 2),
          put_in(c, ["state", "queued_actions"], 218),
          Map.put(c, "cumulative_ms", 21_600_001)
        ] do
      assert {:error, :continuation_binding_or_progress} =
               Continuation.validate(changed, c["binding"], c["options"])
    end
  end

  test "revision and complete value changes alter the oracle digest" do
    rows = %{
      "b" => %{"revision" => 2, "value" => %{"text" => "b", "evidence" => %{"v" => 2}}},
      "a" => %{"revision" => 1, "value" => %{"text" => "a", "evidence" => %{"v" => 1}}}
    }

    digest = Continuation.record_digest(rows)
    assert digest == Continuation.record_digest(Map.new(Enum.reverse(Enum.to_list(rows))))
    refute digest == Continuation.record_digest(put_in(rows, ["a", "revision"], 2))
    refute digest == Continuation.record_digest(put_in(rows, ["a", "value", "evidence", "v"], 2))
  end

  test "an offline checkpoint reconstructs unstarted actions without renewing note times" do
    {_, before_offline, [], 0} =
      Ipse.Development.StorageAnnual.regenerate(119, 0, "representative")

    {desired, actual, queue, 217} =
      Ipse.Development.StorageAnnual.regenerate(126, 0, "representative")

    assert actual == before_offline
    refute actual == desired
    assert length(queue) == 217

    assert Enum.reduce(
             Enum.reverse(queue),
             actual,
             &Ipse.Development.StorageWorkload.apply_action(&2, &1)
           ) == desired

    {desired, actual, [], 217} =
      Ipse.Development.StorageAnnual.regenerate(127, 0, "representative")

    assert actual == desired
  end

  defp checkpoint do
    %{
      "version" => 1,
      "binding" => String.duplicate("a", 64),
      "options" => %{"days" => 365, "cycles" => 10_000, "payload" => "maximum"},
      "segment" => 1,
      "progress" => %{"day" => 1, "cycle" => 0},
      "descriptor" => %{
        "version" => 3,
        "project" => String.duplicate("a", 64),
        "generation" => 1,
        "floor" => 0,
        "floor_anchor" => nil,
        "floor_lineage" => [],
        "floor_lineage_sha256" => Ipse.JSON.digest([[]]),
        "records" => 1,
        "data_bytes" => 2,
        "records_sha256" => String.duplicate("a", 64),
        "operations" => 1,
        "operations_sha256" => String.duplicate("a", 64)
      },
      "records_digest" => String.duplicate("a", 64),
      "state" => %{
        "generation" => 1,
        "samples" => [1.0],
        "peak" => 1,
        "peak_allocated" => 1,
        "peak_ram" => 1,
        "pauses" => 0,
        "migrations" => [],
        "queued_actions" => 0,
        "checkpoints" => %{}
      },
      "calls" => %{"commit" => 1},
      "resume_calls" => %{},
      "first_wall_ms" => 1,
      "cumulative_ms" => 1,
      "previous" => nil,
      "report_sha256" => String.duplicate("a", 64)
    }
  end
end
