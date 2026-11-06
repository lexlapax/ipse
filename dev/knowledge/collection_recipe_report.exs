# Reduces an ordered client trace; does not execute or authorize storage effects.
{opts, [], []} =
  OptionParser.parse(System.argv(), strict: [input: :string, out: :string, prefix: :keep])

input = Path.expand(Keyword.fetch!(opts, :input))
inputs = Enum.map(Keyword.get_values(opts, :prefix), &Path.expand/1) ++ [input]
out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)

initial = %{
  sections: %{},
  ids: MapSet.new(),
  native_ids: MapSet.new(),
  events: 0,
  bytes: 0,
  first_event_overflow: nil,
  first_byte_overflow: nil,
  unknown: 0,
  output_events: 0,
  output_codec_bytes: 0
}

result =
  inputs
  |> Stream.flat_map(&File.stream!(Path.join(&1, "invocations.jsonl")))
  |> Enum.reduce(initial, fn line, state ->
    row = Jason.decode!(line)
    section = row["section"]

    delta = %{
      reads: row["reads"],
      effects: row["effects"],
      invocations: 1,
      events: 2 * length(row["requests"]),
      action_journal_lower_bytes:
        Enum.reduce(row["requests"], 0, fn r, n ->
          n + 2 * r["request_bytes"] + r["outcome_bytes"]
        end)
    }

    sections =
      Map.update(state.sections, section, delta, fn previous ->
        Map.merge(previous, delta, fn _, a, b -> a + b end)
      end)

    {ids, native_ids} =
      Enum.reduce(row["requests"], {state.ids, state.native_ids}, fn r, {ids, native_ids} ->
        id = Map.fetch!(r, "action_id")
        false = MapSet.member?(ids, id)

        {MapSet.put(ids, id),
         if(r["native_receipt_modeled"] === true,
           do: MapSet.put(native_ids, r["operation_id"]),
           else: native_ids
         )}
      end)

    events = state.events + delta.events
    bytes = state.bytes + delta.action_journal_lower_bytes

    %{
      state
      | sections: sections,
        ids: ids,
        native_ids: native_ids,
        events: events,
        bytes: bytes,
        first_event_overflow:
          state.first_event_overflow ||
            if(events > 100_000, do: Map.take(row, ~w(sequence section item stage_count))),
        first_byte_overflow:
          state.first_byte_overflow ||
            if(bytes > 134_217_728, do: Map.take(row, ~w(sequence section item stage_count))),
        unknown:
          state.unknown + Enum.count(row["requests"], &(&1["outcome_status"] === "unknown")),
        output_events:
          state.output_events + (get_in(row, ["public_result", "output_events"]) || 0),
        output_codec_bytes:
          state.output_codec_bytes + (get_in(row, ["public_result", "codec_journal_bytes"]) || 0)
    }
  end)

summary = Jason.decode!(File.read!(Path.join(input, "summary.json")))
records = summary["final_store"]["records"]
known = MapSet.size(result.native_ids)

report = %{
  version: 1,
  kind: "document_recipe_ledger_reduction",
  input: input,
  input_trace_sha256: Ipse.JSON.sha256(File.read!(Path.join(input, "invocations.jsonl"))),
  ordered_input_traces:
    Enum.map(inputs, fn path ->
      %{
        directory: path,
        sha256: Ipse.JSON.sha256(File.read!(Path.join(path, "invocations.jsonl")))
      }
    end),
  sections: result.sections,
  total_action_ids: MapSet.size(result.ids),
  modeled_native_mutation_ids: known,
  model_seed_generation: 0,
  missing_seed_history:
    "This is a zero-based modeled sequence, not an observed native manifest. Real admission must bind actual Known(target), incoming identity union and reserved/unknown liabilities.",
  native_ids_sha256: Ipse.JSON.digest(Enum.sort(result.native_ids)),
  action_events_lower_bound: result.events,
  action_journal_bytes_lower_bound: result.bytes,
  first_aggregate_action_event_crossing: result.first_event_overflow,
  first_aggregate_action_byte_crossing: result.first_byte_overflow,
  session_limit_comparison:
    "aggregate lower bounds only; separate publisher Sessions and unproduced consumer lifecycle/handoffs do not establish an actual per-Session refusal",
  actual_session_limit_refusal: nil,
  public_record_count: records,
  unresolved_unknown_actions: result.unknown,
  result_output_events: result.output_events,
  result_codec_journal_bytes: result.output_codec_bytes,
  fresh_migration_optimistic_operation_minimum: nil,
  fresh_migration_minimum_assumptions:
    "No full-target migration sequence was dispatched by this ledger; no prepare-plus-accept arithmetic is treated as implemented cost.",
  native_lifetime_ceiling: 32768,
  public_plus_private_live_key_ceiling: 8192,
  mutation_admission:
    "model only; bounded completed-data restore is separate implementation/evidence, full-target lifecycle/migration remains unexecuted here",
  actual_native_operations: 0,
  actual_session_journal_measured: false,
  exact_session_journal_bytes: nil,
  actual_physical_peak: nil,
  capacity_fit: nil,
  serialized_record_note:
    "JSON pair lower bounds aggregate modeled actions across invocations; actual per-Session journal bytes/events and refusals remain unmeasured"
}

File.write!(out, Jason.encode!(report, pretty: true), [:exclusive])
IO.puts(Jason.encode!(report, pretty: true))
