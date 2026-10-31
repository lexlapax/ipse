# Reduces an ordered client trace; does not execute or authorize storage effects.
{opts, [], []} = OptionParser.parse(System.argv(), strict: [input: :string, out: :string])
input = Path.expand(Keyword.fetch!(opts, :input))
out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)
reads = ~w(snapshot value.stat value.read value.index stage.list stage.inspect)

initial = %{
  sections: %{},
  ids: MapSet.new(),
  native_ids: MapSet.new(),
  events: 0,
  bytes: 0,
  first_event_overflow: nil,
  first_byte_overflow: nil
}

result =
  File.stream!(Path.join(input, "invocations.jsonl"))
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
        id = Map.fetch!(r, "operation_id")
        false = MapSet.member?(ids, id)

        {MapSet.put(ids, id),
         if(r["op"] in reads, do: native_ids, else: MapSet.put(native_ids, id))}
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
            if(bytes > 134_217_728, do: Map.take(row, ~w(sequence section item stage_count)))
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
  sections: result.sections,
  total_action_ids: MapSet.size(result.ids),
  modeled_native_mutation_ids: known,
  model_seed_generation: 1000,
  missing_seed_history:
    "synthetic generation1000 is not a native manifest; no corresponding baseline IDs/receipts were supplied or counted. Lifetime admission must add actual Known(target).",
  native_ids_sha256: Ipse.JSON.digest(Enum.sort(result.native_ids)),
  action_events_lower_bound: result.events,
  action_journal_bytes_lower_bound: result.bytes,
  first_single_session_event_refusal: result.first_event_overflow,
  first_single_session_byte_refusal: result.first_byte_overflow,
  public_record_count: records,
  fresh_migration_optimistic_operation_minimum: known + 2 * records,
  fresh_migration_minimum_assumptions:
    "imports every known unique native operation identity; each existing public value costs at least one prepare and one accept; excludes larger multipart values, plans, operation pages, epoch open, progress, checkpoint, recovery, close and terminal cleanup",
  native_lifetime_ceiling: 32768,
  public_plus_private_lifetime_key_ceiling: 8192,
  mutation_admission:
    "not authorized; maintenance and physical-layout export/import are not implemented",
  actual_native_operations: 0,
  actual_session_journal_measured: false,
  serialized_record_note:
    "JSON pair lower bounds are sufficient refusal evidence; full actual Session journal bytes/events remain unmeasured"
}

File.write!(out, Jason.encode!(report, pretty: true), [:exclusive])
IO.puts(Jason.encode!(report, pretty: true))
