root = Path.expand("_build/shared-producer-evidence-20261029/session-47138")
bytes = File.read!(Path.join(root, "synthetic-session.jsonl"))
events = bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
ready = Jason.decode!(File.read!(Path.join(root, "ready.json")))
output = Jason.decode!(File.read!(Path.join(root, "output.json")))
results = Enum.filter(events, &(&1["type"] == "extension_action_result"))
true = Enum.all?(results, &(&1["outcome"]["status"] == "ok"))

effects =
  Enum.filter(
    events,
    &(&1["type"] == "extension_effect_result" and &1["kind"] == "embedding.f32le")
  )

[source] = effects
[receipt] = ready["receipts"]
true = receipt["operation_id"] == source["operation_id"]
true = receipt["source_sha256"] == source["source_sha256"]
true = receipt["input_sha256"] == Enum.map(source["data"]["vectors"], & &1["input_sha256"])
[embedding] = Enum.filter(results, &(&1["request"]["op"] == "embedding.create"))

true =
  receipt["raw_input_sha256"] == Enum.map(embedding["request"]["inputs"], &Ipse.JSON.sha256/1)

true = embedding["outcome"]["value"]["result"] == Ipse.Extension.EffectResult.descriptor(source)

pending =
  Enum.find(results, fn e ->
    e["request"]["request"]["key"] == "genproducer.notes" and
      e["request"]["request"]["op"] == "value.prepare_inline"
  end)

claim = pending["request"]["request"]["data"] |> Jason.decode!()
true = claim["status"] == "pending"
claim_ref = Map.take(pending["outcome"]["value"]["result"]["stage"], ~w(slot epoch))

claim_commit =
  Enum.find(
    results,
    &(&1["request"]["request"]["op"] == "commit" and
        &1["request"]["request"]["stages"] == [claim_ref])
  )

true = claim_commit != nil
index = fn event -> Enum.find_index(events, &(&1 == event)) end

embedding_intent =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_intent" and &1["operation_id"] == embedding["operation_id"])
  )

true = index.(claim_commit) < index.(embedding_intent)
true = Enum.map(claim["inputs"], &Enum.at(&1, 3)) == receipt["input_sha256"]
true = Enum.map(claim["inputs"], &Enum.at(&1, 4)) == receipt["raw_input_sha256"]

page_parts =
  Enum.filter(
    results,
    &(&1["request"]["request"]["key"] == ready["page"]["key"] and
        &1["request"]["request"]["op"] == "value.write_parts")
  )

page_bytes = Enum.map_join(page_parts, &Enum.join(&1["request"]["request"]["data"]))

true =
  byte_size(page_bytes) == ready["page"]["byte_count"] and
    Ipse.JSON.sha256(page_bytes) == ready["page"]["sha256"]

page = Jason.decode!(page_bytes)
true = page["kind"] == "shared_vectors" and length(page["rows"]) == 2

for {row, vector} <- Enum.zip(page["rows"], source["data"]["vectors"]) do
  true = Enum.at(row, 2) == vector["input_sha256"]
  raw = Enum.at(row, 4) |> Enum.map_join(&Base.decode64!/1)
  true = Ipse.JSON.sha256(raw) == Enum.at(row, 3)
  true = raw == Base.decode64!(vector["values"])
end

active =
  Enum.reduce(results, %{}, fn event, active ->
    request = event["request"]["request"]
    result = event["outcome"]["value"]["result"]

    case request["op"] do
      "value.prepare_inline" ->
        ref = result["stage"]
        Map.put(active, {ref["slot"], ref["epoch"]}, ref["key"])

      "value.write_parts" ->
        write = result["write"]
        ref = {write["slot"], write["epoch"]}

        if write["state"] == "published",
          do: Map.delete(active, ref),
          else: Map.put(active, ref, write["key"])

      "commit" ->
        Enum.reduce(request["stages"], active, fn ref, active ->
          true = Map.has_key?(active, {ref["slot"], ref["epoch"]})
          Map.delete(active, {ref["slot"], ref["epoch"]})
        end)

      _ ->
        active
    end
  end)

true = map_size(active) == 0
true = output["coverage"]["coverage"]["model_receipt_provenance"] == false

report = %{
  version: 1,
  scope:
    "read-only synthetic actual Session receipt/order/stage reduction, not historical external receipt authentication",
  journal_bytes: byte_size(bytes),
  journal_events: length(events),
  journal_sha256: Ipse.JSON.sha256(bytes),
  claim_commit_precedes_embedding_intent: true,
  typed_embedding_sources: 1,
  exact_vectors: 2,
  raw_and_canonical_input_hashes_match: true,
  page_f32_bytes_equal_actual_effect_source: true,
  active_stages_at_captured_boundary: map_size(active),
  event_types: Enum.frequencies_by(events, & &1["type"]),
  existing_provenance_flag: false
}

File.write!(Path.join(root, "checked.json"), Jason.encode!(report, pretty: true), [:exclusive])
IO.puts(Jason.encode!(report, pretty: true))
