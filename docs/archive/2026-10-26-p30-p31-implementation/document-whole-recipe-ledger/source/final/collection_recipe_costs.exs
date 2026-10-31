# Reduces retained client traces only; it neither retries nor executes effects.
{opts, [], []} = OptionParser.parse(System.argv(), strict: [root: :string, out: :string])
root = Path.expand(Keyword.fetch!(opts, :root))
out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)

read = fn path -> Jason.decode!(File.read!(Path.join(root, path))) end
initial = read.("private-full-47083/summary.json")
rebuilt = read.("rebuild-full-47096/summary.json")
combined = read.("combined-report-47113.json")
initial_transport = read.("transport-full-47095/per-value-transport.json")
rebuild_transport = read.("transport-rebuild-47112/per-value-transport.json")

traces =
  for dir <- ~w(private-full-47083 rebuild-full-47096),
      line <- File.stream!(Path.join([root, dir, "invocations.jsonl"])),
      do: Jason.decode!(line)

families = fn rows ->
  Enum.reduce(rows, %{}, fn row, acc ->
    family = row["key"] |> String.split(".") |> hd()

    Map.update(
      acc,
      family,
      %{records: 1, logical_bytes: row["logical_bytes"], packed_bytes: row["packed_bytes"]},
      fn old ->
        %{
          records: old.records + 1,
          logical_bytes: old.logical_bytes + row["logical_bytes"],
          packed_bytes: old.packed_bytes + row["packed_bytes"]
        }
      end
    )
  end)
end

migration = fn transport, known ->
  values = transport["values"]
  preparation = transport["actual_prepare_mutations"]
  pages = div(values + 7, 8)

  %{
    records: values,
    exact_client_prepare_mutations: preparation,
    individual_accept_total: known + preparation + values,
    proposed_eight_accept_total: known + preparation + pages,
    proposed_native_page_total: known + pages,
    native_page_headroom_before_omissions: 32_768 - known - pages,
    omitted:
      "actual Known(target)/incoming union and missing seed history, epoch/plan/adopt/progress/abort/commit/close/checkpoint/reclaim IDs and receipts; native-page API is not implemented"
  }
end

public =
  File.stream!(Path.join(root, "output-full-47092/invocations.jsonl"))
  |> Stream.map(&Jason.decode!/1)
  |> Stream.filter(&(&1["section"] == "shared_finalize"))
  |> Enum.map(& &1["public_result"])

true = length(public) == 654
true = Enum.all?(public, &(&1["kind"] in ["inline", "sdk2_paged"]))

boundaries =
  for {transport, geometry} <- [
        {initial_transport, read.("geometry-initial-47114/records.json")},
        {rebuild_transport, read.("geometry-rebuild-47110/records.json")}
      ] do
    by_key = Map.new(geometry, &{&1["key"], &1})

    %{
      records: transport["values"],
      changed_part_layouts:
        Enum.count(transport["per_value"], fn row ->
          row["original_part_lengths"] != by_key[row["key"]]["part_lengths"]
        end),
      cost_histogram:
        transport["per_value"]
        |> Enum.frequencies_by(
          &{&1["actual_prepare_mutations"], length(&1["original_part_lengths"])}
        )
        |> Enum.sort()
        |> Enum.map(fn {{mutations, parts}, count} ->
          %{mutations: mutations, parts: parts, values: count}
        end)
    }
  end

true = Enum.all?(boundaries, &(&1.changed_part_layouts == 0))

result = %{
  version: 1,
  kind: "completed_private_recipe_cost_reduction",
  model_seed_generation: 1000,
  actual_native_mutations: 0,
  complete_production_recipe: false,
  initial_migration: migration.(initial_transport, 18_640),
  rebuild_migration: migration.(rebuild_transport, combined["modeled_native_mutation_ids"]),
  actual_client_part_layout_comparison: boundaries,
  initial_families: families.(initial["final_store"]["record_descriptors"]),
  rebuild_families: families.(rebuilt["final_store"]["record_descriptors"]),
  maximum_public_records_at_observed_invocation_boundary:
    Enum.max(Enum.map(traces, & &1["record_count"])),
  maximum_active_stages_at_observed_invocation_boundary:
    Enum.max(Enum.map(traces, & &1["stage_count"])),
  conservative_public_plus_all_sixteen_maximal_stage_slots:
    Enum.max(Enum.map(traces, & &1["record_count"])) + 16 * 12,
  key_bound_scope:
    "live record-map slots only; 12 per maximal document stage (10 parts/header/ready), excludes unimplemented maintenance control keys; inner-action/orphan/metadata/native allocation peaks not modeled",
  legacy_full_public_finalization: %{
    replies: length(public),
    kinds: Enum.frequencies_by(public, & &1["kind"]),
    document_bytes: Enum.sum(Enum.map(public, & &1["document_bytes"])),
    output_events: Enum.sum(Enum.map(public, & &1["output_events"])),
    result_source_slots: Enum.sum(Enum.map(public, & &1["source_slots"])),
    maximum_document_bytes: Enum.max(Enum.map(public, & &1["document_bytes"])),
    source_limit_minimum_sessions: div(Enum.sum(Enum.map(public, & &1["source_slots"])) + 63, 64),
    scope:
      "actual frozen ResultPublication encoder, excludes the extra checkpoint inspection; not Session bytes or current optional compact output"
  },
  operation_history: %{
    modeled_unique_mutations: combined["modeled_native_mutation_ids"],
    ordered_ids_digest: combined["native_ids_sha256"],
    limit: 32_768,
    initial_plus_rebuild_headroom_before_missing_baseline:
      32_768 - combined["modeled_native_mutation_ids"],
    scope:
      "synthetic unique wrapper operation IDs/request digests, not native commit receipts; an empty map at generation1000 has no supplied corresponding native history"
  },
  journal: %{
    modeled_action_events: combined["action_events_lower_bound"],
    modeled_request_outcome_pair_bytes: combined["action_journal_bytes_lower_bound"],
    generation_independent_raw_action_events: 128_084,
    lower_bound_scope:
      "model request/outcome pairs at synthetic generation1000; excludes Session metadata, invocation inputs, approvals, result pages/messages/header and missing public producer",
    actual_small_sessions: read.("journal-verified-47088.json")
  }
}

File.write!(out, Jason.encode!(result, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(Map.update!(result, :journal, &Map.delete(&1, :actual_small_sessions)),
    pretty: true
  )
)
