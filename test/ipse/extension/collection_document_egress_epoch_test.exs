defmodule Ipse.Extension.Collection.DocumentEgressEpochTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}
  alias Ipse.Extension.Collection.{DocumentSourceUse, Profile}

  @seed "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-host-seed/pending-v3-model.exs"

  defp parts(""), do: []

  defp parts(bytes) do
    size = valid_size(bytes, min(6144, byte_size(bytes)))
    [binary_part(bytes, 0, size) | parts(binary_part(bytes, size, byte_size(bytes) - size))]
  end

  defp valid_size(bytes, size),
    do:
      if(String.valid?(binary_part(bytes, 0, size)), do: size, else: valid_size(bytes, size - 1))

  defp packed(value) do
    body = Elixir.JSON.encode!(value) |> IO.iodata_to_binary()

    %{
      "version" => 1,
      "kind" => "document_value",
      "parts" => parts(body),
      "sha256" => JSON.sha256(body),
      "byte_count" => byte_size(body)
    }
  end

  @tag :document_egress_epoch
  test "the held native reader refuses the original claim while active and after a fence" do
    {seed, _} = Code.eval_file(@seed)
    parent = Path.join(System.tmp_dir!(), "ipse-egress-epoch-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "collections")
    project_id = JSON.sha256("synthetic egress epoch")
    namespace = CollectionStore.namespace(project_id)
    key = seed["guard"]["claim_key"]

    changes =
      for {record_key, row} <- Map.delete(seed["records"], key),
          do: %{"key" => record_key, "expected_revision" => 0, "value" => packed(row["value"])}

    assert {:ok, %{"generation" => 1}} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => changes
               },
               Usage.id(),
               Profile.documents()
             )

    claim =
      seed["records"][key]["value"]
      |> Map.put("job_revision", 1)
      |> Map.update!("source_bindings", &Enum.map(&1, fn b -> Map.put(b, "head_revision", 1) end))

    assert {:ok, %{"generation" => 2}} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => key, "expected_revision" => 0, "value" => packed(claim)}
                 ]
               },
               Usage.id(),
               Profile.documents()
             )

    guard =
      Map.merge(seed["guard"], %{
        "claim_revision" => 2,
        "claim_sha256" => JSON.sha256(Elixir.JSON.encode!(claim) |> IO.iodata_to_binary())
      })

    read_claim = fn ->
      Collection.with_document_read(root, namespace, fn witness, read ->
        {:ok,
         {witness["document_maintenance"],
          DocumentSourceUse.authenticate(
            read,
            guard,
            seed["inputs"],
            seed["selection"],
            witness["document_maintenance"]
          )}}
      end)
    end

    assert {:ok, {%{"epoch" => 0, "status" => "idle"}, {:ok, %{maintenance_epoch: 0}}}} =
             read_claim.()

    owner = %{
      "project_id" => project_id,
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("fixture artifact"),
      "invocation_id" => Usage.id()
    }

    opening = %{
      "op" => "maintenance.open",
      "expected_generation" => 2,
      "expected_epoch" => 0,
      "maintenance_id" => Usage.id(),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => Usage.id()
    }

    assert {:ok, _} = Collection.document_maintenance(root, namespace, opening, Usage.id(), owner)

    assert {:ok, {%{"epoch" => 1, "status" => "active"}, {:error, :document_source_use_refused}}} =
             read_claim.()

    assert {:ok, snapshot} = Collection.document_snapshot(root, namespace)

    closing = %{
      "op" => "maintenance.close",
      "expected_generation" => snapshot["generation"],
      "expected_epoch" => 1,
      "maintenance_id" => opening["maintenance_id"]
    }

    assert {:ok, _} =
             Collection.document_maintenance(
               root,
               namespace,
               closing,
               opening["close_operation_id"],
               owner
             )

    assert {:ok, {%{"epoch" => 1, "status" => "idle"}, {:error, :document_source_use_refused}}} =
             read_claim.()
  end
end
