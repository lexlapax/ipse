Code.require_file("../../dev/knowledge/managed_storage_continuation.ex", __DIR__)

defmodule Ipse.Development.ManagedStorageContinuationTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.ManagedStorageContinuation, as: C
  alias Ipse.JSON

  # Declared in-memory shapes exercise refusal rules; they are not stored rows
  # or evidence of any actual publication count.
  defp checkpoint do
    hash = JSON.sha256("fixture")
    project = JSON.sha256("project fixture")

    descriptor = %{
      "version" => 3,
      "project" => project,
      "generation" => 1000,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "floor_lineage_sha256" => JSON.digest([[]]),
      "records" => 1002,
      "data_bytes" => 1002,
      "records_sha256" => hash,
      "operations" => 1000,
      "operations_sha256" => hash
    }

    snapshot = %{
      "root_sha256" => hash,
      "descriptor" => descriptor,
      "rows_sha256" => hash,
      "receipt_count" => 1000,
      "record_count" => 1002,
      "note_count" => 1000,
      "classes" => %{
        "note" => %{"records" => 1000, "bytes" => 1000},
        "anchor" => %{"records" => 1, "bytes" => 1},
        "live" => %{"records" => 1, "bytes" => 1}
      }
    }

    %{
      "version" => 1,
      "kind" => "managed_storage_capacity",
      "binding" => hash,
      "original" =>
        Map.new(~w(report_sha256 runtime_sha256 wire_sha256 runtime_binding_sha256), &{&1, hash}),
      "location" => %{"root" => "/tmp/explicit-in-memory-fixture", "project" => project},
      "snapshot" => snapshot,
      "progress" => 1000,
      "segment" => 1,
      "target" => 2000,
      "bootstrap_wall_ms" => 1,
      "baseline_elapsed_ms" => 186_636,
      "cumulative_elapsed_ms" => 1,
      "previous" => nil,
      "report_sha256" => hash
    }
  end

  test "closed checkpoint binds actual root, semantic descriptor and original timing scope" do
    c = checkpoint()
    assert :ok == C.validate(c, c["binding"], 2000)
    assert C.matches?(c["snapshot"], c["snapshot"])

    refute C.matches?(
             c["snapshot"],
             Map.put(c["snapshot"], "root_sha256", JSON.sha256("changed"))
           )

    for bad <- [
          Map.put(c, "extra", true),
          Map.put(c, "progress", 1000.0),
          Map.put(c, "segment", 8),
          Map.put(c, "baseline_elapsed_ms", 0),
          Map.put(c, "cumulative_elapsed_ms", 3_840_001),
          put_in(c, ["snapshot", "rows_sha256"], "bad"),
          put_in(c, ["snapshot", "record_count"], 1003),
          put_in(c, ["snapshot", "classes", "live", "bytes"], 2),
          put_in(c, ["snapshot", "descriptor", "operations"], 999)
        ] do
      assert {:error, _} = C.validate(bad, c["binding"], 2000)
    end

    assert {:error, _} = C.validate(c, JSON.sha256("source drift"), 2000)
  end

  test "segment and target limits cannot silently reset or expand publication counts" do
    c = checkpoint()
    assert {:error, _} = C.validate(%{c | "target" => 4000}, c["binding"], 2000)
    assert {:error, _} = C.validate(%{c | "segment" => 2}, c["binding"], 2000)
    assert {:error, _} = C.validate(%{c | "progress" => 2000}, c["binding"], 2000)
    assert {:error, _} = C.validate(%{c | "progress" => 2001, "segment" => 2}, c["binding"], 4000)

    assert {:error, _} =
             C.validate(
               put_in(c, ["original", "runtime_binding_sha256"], "bad"),
               c["binding"],
               2000
             )
  end
end
