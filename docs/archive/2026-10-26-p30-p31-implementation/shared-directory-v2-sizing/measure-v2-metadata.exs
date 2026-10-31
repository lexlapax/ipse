# Proposed metadata geometry only, not a directory-v2 implementation.
root = Path.expand("_build/shared-finalization-native-20261029")
Path.wildcard(root <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Path.join(root, "tested-metadata-native-wrapper-beams/metadata_transport_geometry") |> Code.prepend_path()
alias IpseKnowledge.Evidence, as: E
json = &IO.iodata_to_binary(JSON.encode!(&1))
partition = "abcdefghijklmnop"
sha = E.sha256("proposal")
ref = fn prefix, n -> %{"key" => prefix <> "." <> partition <> "." <> E.sha256("#{prefix}#{n}"), "sha256" => E.sha256("#{prefix}#{n}"), "byte_count" => 49_152} end
manifests = for n <- 0..7, do: ref.("genman", n)
entities = for n <- 0..156, do: ref.("genent", n)
runs = for n <- 0..7, do: ref.("genruns", n)
selection = %{"selection_sha256" => sha, "profile" => String.duplicate(<<0>>, 128), "model" => String.duplicate(<<0>>, 128), "dimensions" => 1024, "encoding" => "float32le"}
fact = %{"kind" => "model_complete", "profile" => String.duplicate(<<0>>, 128), "version" => 1}
true = IpseKnowledge.Store.Collection.Projection.valid_selection?(selection)
true = IpseKnowledge.Store.Collection.Projection.valid_extraction?(fact)
catalog = %{"version" => 1, "kind" => "catalog", "partition" => partition, "generation" => 1000, "floor" => 9007199254740991, "sources" => 1000, "extracted_bytes" => 20 * 1024 * 1024, "chunks" => 10_000, "entities" => 0, "assertions" => 0, "pages" => for(n <- 0..62, do: %{"key" => "catalog.#{partition}.#{n}", "sha256" => sha})}
root_value = %{"version" => 2, "kind" => "shared_generation_directory", "recipe" => "ipse.evidence.shared_directory.v2", "partition" => partition, "generation" => 9007199254740991, "catalog_sha256" => E.sha256(json.(catalog)), "catalog_generation" => catalog["generation"], "floor" => catalog["floor"], "sources" => 1000, "extracted_bytes" => 20 * 1024 * 1024, "chunks" => 10_000, "vectors" => 10_000, "facts" => 20_000, "entities" => 5000, "groups" => 125, "vector_selection" => selection, "fact_selection" => fact, "source_heads_sha256" => sha, "entity_pages_sha256" => sha, "entity_page_rows" => 32, "manifests" => manifests, "entity_pages" => entities}
reduction = %{"recipe" => "ipse.evidence.shared_directory.v2", "phase" => "entities", "batch" => 8, "manifests" => manifests, "runs" => runs, "positions" => List.duplicate(5000, 8), "entity_pages" => entities, "entities" => 5000, "text_bytes" => 20 * 1024 * 1024, "chunks" => 10_000, "facts" => 20_000, "heads_sha256" => sha, "entity_pages_sha256" => sha, "digest_cursor" => 157, "verified_entities" => 5000, "last_entity_id" => sha}
job = %{"version" => 3, "kind" => "shared_generation_job", "id" => String.duplicate("f", 32), "partition" => partition, "status" => "reducing", "catalog" => catalog, "catalog_sha256" => E.sha256(json.(catalog)), "generation" => 9007199254740991, "root_revision" => 9007199254740991, "root_sha256" => sha, "vector_selection" => selection, "fact_selection" => fact, "cursor" => 1000, "summaries" => [], "facts" => 20_000, "reduction" => reduction}

source = File.read!("test/support/metadata_transport_geometry.exs")
writer = "write = fn write" <> (source |> String.split("write = fn write", parts: 2) |> List.last() |> String.split("largest =", parts: 2) |> hd())
inline = """
"value.prepare_inline" ->
  stage = Map.take(r, ~w(slot epoch key expected_revision byte_count sha256)) |> Map.merge(%{"version" => 1, "state" => "sealed", "offset" => byte_size(r["data"]), "expires_at_ms" => 2_000_000_000_000})
  write.(write, C.resume(continuation, reply.(request, %{"generation" => r["generation"] + 1, "stage" => stage})), r["data"], div(byte_size(r["data"]) + 6143, 6144), frames ++ [byte_size(json.(frame))], count + 1)
"value.write_parts" ->
"""
writer = String.replace(writer, "\"value.write_parts\" ->", inline, global: false)
reply = fn request, result -> {:ok, digest} = Ipse.Extension.canonical_digest([request]); %{"status" => "ok", "value" => %{"version" => 1, "operation_id" => String.duplicate("a", 32), "request_sha256" => digest, "result" => result}} end
{_, vars} = Code.eval_string("import ExUnit.Assertions\nalias IpseKnowledge.Store.Collection, as: C\n" <> writer, json: json, reply: reply, marker: %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2})
write = Keyword.fetch!(vars, :write)
profile = %{"kind" => "collection", "scope" => "project", "partition" => partition}
records = for {key, value} <- [{"generation.#{partition}", root_value}, {"genjob.#{partition}", job}, {"catalog.#{partition}", catalog}], into: %{} do
  bytes = json.(value)
  true = byte_size(bytes) <= 48 * 1024
  {:ok, _} = Ipse.Extension.ResultDocument.decode(bytes, %{"type" => "object"})
  result = IpseKnowledge.Store.Collection.start(profile, :value_prepare, %{"key" => key, "value" => value, "expected_revision" => 0, "reuse" => false, "continuation" => nil})
  {^bytes, parts, frames, effects} = write.(write, result, "", 0, [], 0)
  pieces = Stream.unfold(bytes, fn "" -> nil; rest -> n = min(byte_size(rest), 6144); {binary_part(rest, 0, n), binary_part(rest, n, byte_size(rest) - n)} end) |> Enum.to_list()
  packed = json.(%{"version" => 1, "kind" => "document_value", "sha256" => E.sha256(bytes), "byte_count" => byte_size(bytes), "parts" => pieces})
  true = byte_size(packed) <= 65_536 and parts <= 10
  {key, %{"body_bytes" => byte_size(bytes), "packed_bytes" => byte_size(packed), "parts" => parts, "write_frames" => effects, "maximum_frame_bytes" => Enum.max(frames)}}
end
IO.puts(Jason.encode!(%{"proposal_only" => true, "records" => records, "decoded_selector_bytes" => 128, "selected_refs" => 165, "active_run_refs" => 8, "catalog_pages" => 63, "native_operations" => 0, "model_calls" => 0}, pretty: true))
