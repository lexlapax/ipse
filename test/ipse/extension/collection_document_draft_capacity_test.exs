defmodule Ipse.Extension.Collection.DocumentDraftCapacityTest do
  use ExUnit.Case, async: true

  alias Ipse.JSON
  alias Ipse.Extension.Collection.{Blocks, DocumentDraft, DocumentMaintenance}
  alias Ipse.Extension.CollectionStore

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp receipt(n),
    do: %{"generation" => n, "floor" => n, "request_sha256" => JSON.sha256("receipt #{n}")}

  defp state(n) do
    project = JSON.sha256("cleanup capacity project")

    owner = %{
      "project_id" => project,
      "session_id" => id(100_001),
      "identity_sha256" => JSON.sha256("artifact")
    }

    head = %{
      "id" => id(1),
      "kind" => "projection",
      "owner" => owner,
      "plan_sha256" => JSON.sha256("plan"),
      "body_sha256" => JSON.sha256("body"),
      "maintenance_epoch" => 1,
      "retirement_epoch" => nil,
      "unit_limit" => 2,
      "unit" => 0,
      "revision" => n,
      "slots" => [0, 1],
      "prepared" => [],
      "active" => %{
        "slot" => 0,
        "epoch" => id(100_002),
        "key" => "document.body",
        "expected_revision" => 0,
        "byte_count" => 20,
        "sha256" => JSON.sha256("body bytes"),
        "offset" => 2,
        "publish" => true
      }
    }

    records =
      Map.new(["host.stage.0.header", "host.stage.0.part.0"], fn key ->
        {key,
         %{
           "key" => key,
           "revision" => 1,
           "operation_id" => id(1),
           "sha256" => JSON.sha256(key),
           "bytes" => 32
         }}
      end)

    %{
      "version" => 3,
      "project" => CollectionStore.namespace(project),
      "generation" => n,
      "floor" => n,
      "floor_anchor" => id(n),
      "floor_lineage" => Enum.map(1..n, &id/1),
      "records" => records,
      "operations" => Map.new(1..n, &{id(&1), receipt(&1)}),
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil,
      "document_maintenance" => %{"version" => 1, "epoch" => 1, "status" => "idle"},
      "document_drafts" => %{id(1) => head}
    }
  end

  defp encode(state) do
    assert {:ok, bytes, blocks} = Blocks.encode(state)
    {bytes, blocks}
  end

  defp reserve(state) do
    {bytes, blocks} = encode(state)
    assert {:ok, sizes} = DocumentDraft.cleanup_reserve(state, bytes, blocks)
    {sizes, blocks}
  end

  defp completed_cleanup(state) do
    generation = state["generation"] + 1

    state
    |> Map.put("generation", generation)
    |> Map.put("floor", generation)
    |> Map.put("floor_anchor", id(generation))
    |> Map.update!("floor_lineage", &(&1 ++ [id(generation)]))
    |> Map.update!("operations", &Map.put(&1, id(generation), receipt(generation)))
    |> Map.put("records", %{})
    |> Map.delete("document_drafts")
  end

  defp dominated?(reserved, actual) do
    reserved = Enum.sort(reserved, :desc)
    actual = Enum.sort(actual, :desc)

    length(reserved) >= length(actual) and
      Enum.all?(Enum.zip(actual, reserved), fn {need, bound} -> need <= bound end)
  end

  test "the reserved vector dominates actual cleanup across receipt and lineage block boundaries" do
    for generation <- [255, 256, 511, 512] do
      original = state(generation)
      {reserved, old_blocks} = reserve(original)
      {next_root, next_blocks} = original |> completed_cleanup() |> encode()
      new_blocks = Map.drop(next_blocks, Map.keys(old_blocks))

      actual = [
        byte_size(next_root),
        1 | Enum.map(new_blocks, fn {_, bytes} -> byte_size(bytes) end)
      ]

      assert dominated?(reserved, actual),
             "cleanup vector does not dominate generation #{generation}"
    end
  end

  test "active maintenance reserves its close before the same stage can be cleaned" do
    original = state(255)
    {idle_sizes, _} = reserve(original)
    head = original["document_drafts"][id(1)]
    owner = Map.put(head["owner"], "invocation_id", id(100_003))

    request = %{
      "op" => "maintenance.open",
      "expected_generation" => 255,
      "expected_epoch" => 1,
      "maintenance_id" => id(100_004),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => id(100_005),
      "owner" => owner
    }

    assert {:ok, active, %{}, %{}} =
             DocumentMaintenance.prepare(original, request, id(256), 32_768)

    active =
      active
      |> Map.put("generation", 256)
      |> Map.update!(
        "operations",
        &Map.put(&1, id(256), %{
          "generation" => 256,
          "floor" => 255,
          "request_sha256" => JSON.digest([request])
        })
      )

    {active_sizes, _} = reserve(active)
    assert length(active_sizes) == length(idle_sizes) + 4
    assert Enum.sum(active_sizes) > Enum.sum(idle_sizes)
  end

  test "closed head scalars remain bounded and reject an oversized stage key" do
    original = state(255)
    id = id(1)

    maximum =
      put_in(original, ["document_drafts", id, "active", "key"], String.duplicate("k", 96))

    assert DocumentDraft.valid?(maximum)
    assert byte_size(Jason.encode!(maximum["document_drafts"][id])) < 4096

    refute DocumentDraft.valid?(
             put_in(maximum, ["document_drafts", id, "active", "key"], String.duplicate("k", 97))
           )
  end
end
