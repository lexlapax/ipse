defmodule Ipse.Extension.CollectionJobBindingTest do
  use ExUnit.Case, async: true

  alias Ipse.JSON, as: J
  alias Ipse.Extension.Collection.DocumentSourceUse, as: SourceUse

  @seed "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-host-seed/pending-v3-model.exs"
  @now 20
  @generation 2000

  defp bytes(value), do: IO.iodata_to_binary(JSON.encode!(value))

  defp parts(""), do: []

  defp parts(data) do
    n = prefix(data, min(byte_size(data), 6144))
    [binary_part(data, 0, n) | parts(binary_part(data, n, byte_size(data) - n))]
  end

  defp prefix(data, n),
    do: if(String.valid?(binary_part(data, 0, n)), do: n, else: prefix(data, n - 1))

  # The retained reader is synthetic: it exercises host authentication but does
  # not claim a native lease, CAS, live Session, or operator approval.
  defp reader(records) do
    fn key ->
      case records[key] do
        nil ->
          {:ok, nil}

        row ->
          if String.starts_with?(key, "host.stage.") and String.ends_with?(key, ".header") do
            {:ok, row}
          else
            raw = bytes(row["value"])

            packed = %{
              "version" => 1,
              "kind" => "document_value",
              "parts" => parts(raw),
              "sha256" => J.sha256(raw),
              "byte_count" => byte_size(raw)
            }

            {:ok, Map.put(row, "value", packed)}
          end
      end
    end
  end

  defp row(value, revision),
    do: %{"value" => value, "revision" => revision, "operation_id" => nil}

  defp setup_stage(records, slot, key, value, owner, revision) do
    epoch = String.duplicate(Integer.to_string(slot + 1), 32)
    body = bytes(value)

    header = %{
      "version" => 1,
      "epoch" => epoch,
      "owner" => owner,
      "state" => "sealed",
      "offset" => byte_size(body),
      "byte_count" => byte_size(body),
      "sha256" => J.sha256(body),
      "expires_at_ms" => 1_000,
      "key" => key,
      "expected_revision" => revision
    }

    records =
      records
      |> Map.put("host.stage.#{slot}.header", row(header, 100))
      |> Map.put("host.stage.#{slot}.ready", row(value, 101))

    {records, %{"slot" => slot, "epoch" => epoch}}
  end

  defp fixture(epoch) do
    {seed, _} = Code.eval_file(@seed)
    records = seed["records"]
    old_row = records["genjob.notes"]
    catalog = records["catalog.notes"]

    owner = %{
      "project_id" => J.sha256("project"),
      "session_id" => String.duplicate("a", 32),
      "identity_sha256" => J.sha256("identity"),
      "invocation_id" => String.duplicate("b", 32)
    }

    job =
      old_row["value"]
      |> Map.merge(%{"version" => if(epoch == 0, do: 7, else: 8), "input_binding" => nil})

    job = if epoch == 0, do: job, else: Map.put(job, "maintenance_epoch", epoch)
    records = put_in(records, ["genjob.notes", "value"], job)

    {:ok, proof} =
      SourceUse.authenticate_catalog_group(reader(records), "notes", job["catalog_sha256"], 0)

    input = %{"ref_sha256" => J.sha256("result reference"), "raw_sha256" => J.sha256("bytes")}

    binding = %{
      "version" => 1,
      "ref_sha256" => input["ref_sha256"],
      "raw_sha256" => input["raw_sha256"],
      "source_set_sha256" => J.digest([proof.group["sources"]]),
      "cursor" => 0,
      "vector_job_revision" => old_row["revision"],
      "owner" => Map.delete(owner, "invocation_id")
    }

    %{
      records: records,
      owner: owner,
      job: job,
      row: old_row,
      catalog: catalog,
      binding: binding,
      input: input,
      group: proof.group,
      epoch: epoch
    }
  end

  defp check(f, new_job, input \\ :selected, now \\ @now) do
    {records, first} =
      setup_stage(f.records, 0, "genjob.notes", new_job, f.owner, f.row["revision"])

    {records, second} =
      setup_stage(records, 1, "catalog.notes", f.catalog["value"], f.owner, f.catalog["revision"])

    request = %{"op" => "commit", "stages" => [first, second], "generation" => @generation}
    request = if f.epoch == 0, do: request, else: Map.put(request, "maintenance_epoch", f.epoch)
    input = if input == :selected, do: f.input, else: input

    SourceUse.authenticate_group_commit(
      reader(records),
      %{"root" => %{"generation" => @generation}},
      request,
      f.owner,
      now,
      input
    )
  end

  test "bind authenticates the captured input, current group, owner, revision and epoch" do
    for epoch <- [0, 1] do
      f = fixture(epoch)
      proposed = Map.put(f.job, "input_binding", f.binding)
      assert {:ok, %{generation: @generation}} = check(f, proposed)

      for altered <- [
            put_in(proposed, ["input_binding", "ref_sha256"], J.sha256("other ref")),
            put_in(proposed, ["input_binding", "raw_sha256"], J.sha256("other body")),
            put_in(proposed, ["input_binding", "source_set_sha256"], J.sha256("other sources")),
            put_in(proposed, ["input_binding", "vector_job_revision"], f.row["revision"] - 1),
            put_in(proposed, ["input_binding", "owner", "session_id"], String.duplicate("c", 32)),
            put_in(proposed, ["input_binding", "cursor"], 8),
            Map.put(proposed, "facts", 1)
          ] do
        assert {:error, :document_source_use_refused} = check(f, altered)
      end

      assert {:error, :document_source_use_refused} = check(f, proposed, nil)

      assert {:error, :document_source_use_refused} =
               check(f, proposed, %{f.input | "raw_sha256" => J.sha256("other")})

      assert {:error, :document_source_use_refused} = check(%{f | epoch: epoch + 1}, proposed)
      assert {:error, :document_source_use_refused} = check(f, proposed, :selected, 1_000)

      source_key = hd(f.group["sources"])["source_key"]

      stale_records =
        update_in(f.records, ["source.notes." <> source_key, "value", "ordinal"], &(&1 + 1))

      assert {:error, :document_source_use_refused} =
               check(%{f | records: stale_records}, proposed)
    end
  end

  test "owned reducing abort is independent of old input and current source eligibility" do
    f = fixture(1)
    bound = Map.put(f.job, "input_binding", f.binding)
    records = put_in(f.records, ["genjob.notes", "value"], bound)
    f = %{f | records: records, job: bound, epoch: 2}

    aborted =
      bound
      |> Map.delete("input_binding")
      |> Map.put("version", 4)
      |> Map.put("status", "aborted")

    assert {:ok, %{purpose: :bound_job_abort}} = check(f, aborted, nil)
    assert {:error, :document_source_use_refused} = check(f, Map.put(aborted, "facts", 1), nil)
    other = put_in(f, [:owner, "identity_sha256"], J.sha256("another owner"))
    assert {:error, :document_source_use_refused} = check(other, aborted, nil)
    assert {:error, :document_source_use_refused} = check(%{f | epoch: 0}, aborted, nil)
  end

  test "final group clears the binding only with the selected input and current source summary" do
    for epoch <- [0, 1] do
      f = fixture(epoch)
      bound = Map.put(f.job, "input_binding", f.binding)

      header = %{
        "version" => 1,
        "kind" => "shared_projection_group",
        "cursor" => 0,
        "vector_selection" => bound["vector_selection"],
        "fact_selection" => bound["fact_selection"],
        "facts" => 0,
        "sources" => 1
      }

      header_sha = J.sha256(bytes(header))

      header_ref = %{
        "key" => "gengrp.notes." <> header_sha,
        "sha256" => header_sha,
        "byte_count" => byte_size(bytes(header))
      }

      summary = %{
        "header" => header,
        "ref" => header_ref,
        "sources" => f.group["sources"],
        "entities" => []
      }

      summary_sha = J.sha256(bytes(summary))

      summary_ref = %{
        "key" => "gensum.notes." <> summary_sha,
        "sha256" => summary_sha,
        "byte_count" => byte_size(bytes(summary))
      }

      records =
        f.records
        |> put_in(["genjob.notes", "value"], bound)
        |> Map.put(header_ref["key"], row(header, 1200))
        |> Map.put(summary_ref["key"], row(summary, 1201))

      f = %{f | records: records, job: bound}

      next =
        bound
        |> Map.delete("input_binding")
        |> Map.merge(%{
          "version" => if(epoch == 0, do: 1, else: 4),
          "status" => "manifests",
          "cursor" => 1,
          "summaries" => [summary_ref]
        })

      assert {:ok, %{generation: @generation}} = check(f, next)
      assert {:error, :document_source_use_refused} = check(f, next, nil)
      assert {:error, :document_source_use_refused} = check(f, Map.put(next, "facts", 1))
      assert {:error, :document_source_use_refused} = check(f, Map.put(next, "status", "groups"))

      assert {:error, :document_source_use_refused} =
               check(f, Map.put(next, "input_binding", f.binding))
    end
  end
end
