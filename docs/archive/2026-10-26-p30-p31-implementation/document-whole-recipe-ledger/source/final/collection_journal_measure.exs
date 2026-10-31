# Analyze retained synthetic actual Session journals, with no runtime effects.
{opts, paths, []} = OptionParser.parse(System.argv(), strict: [out: :string])
out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)
reads = ~w(snapshot value.stat value.read value.index stage.list stage.inspect)

rows =
  Enum.map(paths, fn path ->
    raw = File.read!(path)
    lines = String.split(raw, "\n", trim: true)
    events = Enum.map(lines, &Jason.decode!/1)
    results = Enum.filter(events, &(&1["type"] == "extension_action_result"))

    {active, mutations, ids} =
      Enum.reduce(results, {%{}, 0, []}, fn event, {active, count, ids} ->
        request = event["request"]["request"]
        true = event["outcome"]["status"] == "ok"
        r = event["outcome"]["value"]["result"]

        active =
          case request["op"] do
            "value.prepare_inline" ->
              Map.put(active, {r["stage"]["slot"], r["stage"]["epoch"]}, r["stage"])

            "value.write_parts" ->
              if r["write"]["state"] == "published",
                do: Map.delete(active, {request["slot"], request["epoch"]}),
                else: Map.put(active, {request["slot"], request["epoch"]}, r["write"])

            "commit" ->
              Enum.reduce(request["stages"], active, fn ref, acc ->
                true = Map.has_key?(acc, {ref["slot"], ref["epoch"]})
                Map.delete(acc, {ref["slot"], ref["epoch"]})
              end)

            _ ->
              active
          end

        mutating = request["op"] not in reads

        {active, count + if(mutating, do: 1, else: 0),
         if(mutating, do: [event["operation_id"] | ids], else: ids)}
      end)

    true = map_size(active) == 0
    true = length(Enum.uniq(ids)) == length(ids)
    first = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    input = first["payload"]["arguments"]["args"]["text"]
    true = byte_size(input) == 5320

    types =
      Enum.zip(lines, events)
      |> Enum.reduce(%{}, fn {line, event}, acc ->
        Map.update(acc, event["type"], %{bytes: byte_size(line) + 1, events: 1}, fn old ->
          %{bytes: old.bytes + byte_size(line) + 1, events: old.events + 1}
        end)
      end)

    true = Enum.sum(Enum.map(types, fn {_, x} -> x.bytes end)) == byte_size(raw)
    namespaces = results |> Enum.map(& &1["namespace"]) |> Enum.uniq()

    %{
      path: path,
      sha256: Ipse.JSON.sha256(raw),
      bytes: byte_size(raw),
      events: length(events),
      invocations: types["extension_invocation_intent"].events,
      input_text_bytes: byte_size(input),
      types: types,
      known_successful_native_mutations: mutations,
      native_operation_ids: Enum.sort(ids),
      known_active_stages_at_close: map_size(active),
      namespaces: namespaces,
      session_id: first["payload"]["session_id"],
      artifact_sha256: first["identity"]["artifact_sha256"]
    }
  end)

true = length(Enum.uniq(Enum.map(rows, & &1.session_id))) == length(rows)
true = length(Enum.uniq(Enum.map(rows, & &1.artifact_sha256))) == 1
true = length(Enum.uniq(Enum.map(rows, & &1.namespaces))) == 1
all_ids = Enum.flat_map(rows, & &1.native_operation_ids)
true = length(Enum.uniq(all_ids)) == length(all_ids)

report = %{
  version: 1,
  kind: "actual_synthetic_session_journal_measurement",
  sessions: rows,
  total_bytes: Enum.sum(Enum.map(rows, & &1.bytes)),
  total_events: Enum.sum(Enum.map(rows, & &1.events)),
  total_known_native_mutations: length(all_ids),
  source: "47085 actual independent public Corpus and native document store, full approvals",
  limitations:
    "two small supplied plaintext inputs; no Word acquisition, graph/vector producer, full recipe journal extrapolation, unknown recovery or active stage transfer"
}

File.write!(out, Jason.encode!(report, pretty: true), [:exclusive])
IO.puts(Jason.encode!(report, pretty: true))
