# Compares retained synthetic finalization traces; never runs a controller/effect.
{opts, [], []} =
  OptionParser.parse(System.argv(), strict: [root: :string, input: :string, out: :string])

root = Path.expand(Keyword.fetch!(opts, :root))
input = Path.expand(Keyword.fetch!(opts, :input))
out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)
read = fn path -> Jason.decode!(File.read!(path)) end
trace = fn path -> File.stream!(path) |> Enum.map(&Jason.decode!/1) end
legacy = read.(Path.join(root, "output-full-47092/summary.json"))
new = read.(Path.join(input, "summary.json"))
true = legacy["final_store"] === new["final_store"]
true = legacy["totals"] === new["totals"]
true = new["shared_result"]["status"] == "selected"
true = new["public_response"] == "compact_v1"
old_trace = trace.(Path.join(root, "output-full-47092/invocations.jsonl"))
new_trace = trace.(Path.join(input, "invocations.jsonl"))
true = length(old_trace) == length(new_trace)

for {old, new} <- Enum.zip(old_trace, new_trace) do
  true =
    Map.drop(old, ["public_result", "requests"]) === Map.drop(new, ["public_result", "requests"])

  true =
    Enum.map(old["requests"], &Map.delete(&1, "operation_id")) ===
      Enum.map(new["requests"], &Map.delete(&1, "operation_id"))
end

objects = trace.(Path.join(input, "public-results.jsonl"))
true = length(objects) == length(new_trace)

for {%{"output" => output}, row} <- Enum.zip(objects, new_trace) do
  true = output["coverage"]["representation"] == "compact_v1"
  false = Map.has_key?(output["coverage"], "job")

  if output["continuation"],
    do: true = output["continuation"]["arguments"]["response"] == "compact_v1"

  {:ok, encoded} = Ipse.Extension.ResultPublication.prepare(output)
  true = is_map(encoded) and not is_struct(encoded)
  true = row["public_result"]["kind"] == "inline"

  true =
    byte_size(IO.iodata_to_binary(JSON.encode!(output))) == row["public_result"]["document_bytes"]

  true =
    byte_size(IO.iodata_to_binary(JSON.encode!(encoded))) == row["public_result"]["frame_bytes"]
end

selected = Enum.filter(new_trace, &(&1["section"] == "shared_finalize"))
old_selected = Enum.filter(old_trace, &(&1["section"] == "shared_finalize"))
true = length(selected) == 654

counts = fn rows ->
  %{
    replies: length(rows),
    kinds: Enum.frequencies_by(rows, & &1["public_result"]["kind"]),
    document_bytes: Enum.sum(Enum.map(rows, & &1["public_result"]["document_bytes"])),
    result_source_slots: Enum.sum(Enum.map(rows, & &1["public_result"]["source_slots"])),
    output_events: Enum.sum(Enum.map(rows, & &1["public_result"]["output_events"])),
    maximum_document_bytes: Enum.max(Enum.map(rows, & &1["public_result"]["document_bytes"]))
  }
end

all_requests = Enum.flat_map(new_trace, & &1["requests"])
ids = Enum.map(all_requests, & &1["operation_id"])
true = length(ids) == length(Enum.uniq(ids))
true = Enum.all?(ids, &(String.to_integer(&1, 16) > 1_000_000))

result = %{
  version: 1,
  kind: "new_code_compact_finalization_closed_model_comparison",
  fresh_ids: %{
    start: 1_000_000,
    unique_actions: length(ids),
    first: Enum.min(ids),
    last: Enum.max(ids)
  },
  native_mutations_executed: 0,
  old_native_receipts_replayed: 0,
  selected_map_exact_equal: true,
  selected_records: new["final_store"]["records"],
  selected_generation: new["final_store"]["generation"],
  descriptors_sha256: Ipse.JSON.digest(new["final_store"]["record_descriptors"]),
  totals_exact_equal: true,
  actual_request_bodies_hashes_sizes_exact_equal_except_fresh_ids: true,
  totals_with_one_checkpoint_inspection: new["totals"],
  finalization_only: counts.(selected),
  old_full_finalization_only: counts.(old_selected),
  complete_new_public_objects: length(objects),
  maximum_inline_frame_bytes: Enum.max(Enum.map(new_trace, & &1["public_result"]["frame_bytes"])),
  scope:
    "new artifact/explicit response compact_v1 from known private shared-appended checkpoint; only modeled finalization, not acquisition/rebuild/native effects, Session appends or cross-Session adoption",
  remaining:
    "action events/pair bytes still exceed one Session; public producer, safe durable boundaries, whole native allocation/history/maintenance/migration and provenance remain unqualified"
}

File.write!(out, Jason.encode!(result, pretty: true), [:exclusive])
IO.puts(Jason.encode!(result, pretty: true))
