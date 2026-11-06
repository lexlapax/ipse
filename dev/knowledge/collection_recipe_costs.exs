# Reduce explicitly ordered current traces. No Native, Session or provider work.
{opts, [], []} = OptionParser.parse(System.argv(), strict: [input: :keep, out: :string])
inputs = Enum.map(Keyword.get_values(opts, :input), &Path.expand/1)
true = inputs !== []
out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)

phases =
  Enum.map(inputs, fn root ->
    summary = root |> Path.join("summary.json") |> File.read!() |> Jason.decode!()
    rows = root |> Path.join("invocations.jsonl") |> File.stream!() |> Enum.map(&Jason.decode!/1)
    descriptors = get_in(summary, ["final_store", "record_descriptors"]) || []

    families =
      Enum.reduce(descriptors, %{}, fn row, families ->
        family = row["key"] |> String.split(".") |> hd()

        Map.update(
          families,
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

    requests = Enum.flat_map(rows, & &1["requests"])
    publications = summary["result_publications"] || []

    %{
      input: root,
      trace_sha256: Ipse.JSON.sha256(File.read!(Path.join(root, "invocations.jsonl"))),
      status: get_in(summary, ["shared_result", "status"]),
      sources: summary["sources"],
      invocations: length(rows),
      reads: Enum.sum(Enum.map(rows, & &1["reads"])),
      effects: Enum.sum(Enum.map(rows, & &1["effects"])),
      actions: length(requests),
      actions_by_class: Enum.frequencies_by(requests, & &1["class"]),
      known_modeled_native_ids:
        requests
        |> Enum.filter(&(&1["native_receipt_modeled"] === true))
        |> Enum.map(& &1["operation_id"]),
      unknown_actions: Enum.count(requests, &(&1["outcome_status"] === "unknown")),
      public_families: families,
      action_high_water_marks: summary["action_high_water_marks"],
      source_result_documents: length(publications),
      retained_result_bytes:
        Enum.sum(Enum.map(publications, &get_in(&1, ["ref", "delivery", "byte_count"]))),
      result_codec_events: Enum.sum(Enum.map(publications, & &1["event_count"])),
      result_codec_bytes: Enum.sum(Enum.map(publications, & &1["journal_bytes"])),
      result_action_codec_bytes:
        Enum.sum(Enum.map(publications, &(&1["action_journal_bytes"] || 0))),
      result_action_codec_events:
        Enum.sum(Enum.map(publications, &(&1["action_event_count"] || 0))),
      maximum_worker_frame_bytes:
        Enum.max(Enum.map(rows, &(get_in(&1, ["public_result", "input_bytes"]) || 0)), fn -> 0 end)
    }
  end)

ids = phases |> Enum.flat_map(& &1.known_modeled_native_ids) |> MapSet.new()

result = %{
  version: 2,
  kind: "ordered_public_controller_model_costs",
  phases: phases,
  unique_modeled_native_ids: MapSet.size(ids),
  native_id_ceiling: 32_768,
  model_seed_generation: 0,
  actual_native_operations: 0,
  complete_production_recipe: false,
  actual_known_target_union: nil,
  imported_operation_union: nil,
  terminal_reservation_ids: nil,
  actual_native_flat_manifest_bytes: nil,
  actual_physical_peak_bytes: nil,
  complete_session_journal_bytes: nil,
  capacity_fit: nil,
  scope:
    "actual controller requests/production result codecs over modeled Native and declared embedding replies; no authority, Native or capacity qualification",
  omissions: [
    "full-target lifecycle/migration not executed; no historical 28258 reuse or proposed accept multiplier",
    "record allocation lower bounds do not include actual block/manifest/staging/checkpoint/rollback peaks",
    "result codec events and action pairs omit remaining actual Session/approval/context/lifecycle records"
  ]
}

File.write!(out, Jason.encode!(result, pretty: true), [:exclusive])
IO.puts(Jason.encode!(result, pretty: true))
