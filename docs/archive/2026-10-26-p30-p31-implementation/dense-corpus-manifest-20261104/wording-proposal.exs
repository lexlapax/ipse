rows = [
  {"query", "Read current cited evidence", "Current cited evidence", 2},
  {"query_selected", "Read cited evidence from explicit source IDs", "Cited evidence from explicit source IDs", 2},
  {"generation_job", "Begin, inspect, finalize or abort a supplied shared projection build", "Supplied shared projection builds", 2},
  {"projection_selected", "Inspect current supplied shared projections with exact citations", "Current supplied shared projections with exact citations", 2},
  {"lexical_index", "Build, rebuild or inspect the catalog-bound namespace lexical index", "Catalog-bound namespace lexical index", 2},
  {"generation_produce", "Stage explicit facts, produce guarded vector pages or inspect producer progress", "Explicit facts, guarded vector pages, producer progress", 2}
]

source = File.read!("extensions/knowledge/src/corpus.ex")

{derived, saved} =
  Enum.reduce(rows, {source, 0}, fn {id, before, after_text, multiplicity}, {text, saved} ->
    # Query has one command and one tool source literal. Shared collection entries
    # have one source literal inserted into both catalog groups.
    source_occurrences = if id == "query", do: 2, else: 1
    ^source_occurrences = length(:binary.matches(text, inspect(before)))
    delta = (byte_size(before) - byte_size(after_text)) * multiplicity
    IO.puts("#{id}: #{inspect(before)} -> #{inspect(after_text)}; aggregate_saved=#{delta}")
    {String.replace(text, inspect(before), inspect(after_text)), saved + delta}
  end)

packet = Path.expand("_build/verification/ipse-dense-build-diagnostic-20261104-01")
File.write!(Path.join(packet, "corpus-wording.ex"), derived)
IO.puts("saved_bytes=#{saved}")
IO.puts("predicted_manifest_bytes=#{16_397 - saved}")
IO.puts("predicted_headroom=#{16_384 - (16_397 - saved)}")
IO.puts("prediction_scope=export text only; unchanged inventory field widths must be confirmed by real build")
