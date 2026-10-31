root = "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-first-page"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
file_sha = fn p -> File.stream!(p,65536,[]) |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2,&1)) |> :crypto.hash_final() |> Base.encode16(case: :lower) end
bytes = File.read!(root <> "/manifest.json")
true = sha.(bytes) == "92c215154e5d948f66f02adb12af21793f9619d3c69cdb83a5a66c9c1d6a5245"
m = :json.decode(bytes)
rows = Enum.flat_map(~w(source logs reports artifact_files runtime_files ancestors), &m[&1]) ++ [m["design"]]
for r <- rows, do: true = File.stat!(r["path"]).size == r["bytes"] and file_sha.(r["path"]) == r["sha256"]
runtime_root = Path.expand("_build/shared-finalization-native-20261029/lib")
walk = fn f,p -> case File.lstat!(p).type do :regular -> [Path.expand(p)]; :directory -> Enum.flat_map(File.ls!(p),fn n -> f.(f,Path.join(p,n)) end); :symlink -> [] end end
physical = walk.(walk,runtime_root)
inventory_paths = Enum.map(m["runtime_files"],&Path.expand(&1["path"]))
unlisted = physical -- inventory_paths
true = length(unlisted) == 36 and Enum.all?(unlisted,&String.contains?(&1,"/.mix/"))
extra = inventory_paths -- physical
true = Enum.all?(extra,&String.contains?(&1,"/telemetry/src/"))
artifact = "_build/shared-producer-corpus-20261029"
artifact_bytes = File.read!(artifact <> "/extension.json")
am = :json.decode(artifact_bytes)
for r <- am["files"] do p = artifact <> "/" <> r["path"]; true = File.stat!(p).size == r["bytes"] and file_sha.(p) == r["sha256"] end
true = "host.embedding" in am["capabilities"] and "host.results" in am["capabilities"] and "host.model" not in am["capabilities"]
prior = "_build/generation-progress-corpus-sol-20261029/ebin"
old_beams = File.ls!(prior) |> Enum.filter(&String.ends_with?(&1,".beam")) |> Enum.sort()
new_beams = File.ls!(artifact <> "/ebin") |> Enum.filter(&String.ends_with?(&1,".beam")) |> Enum.sort()
["Elixir.IpseKnowledge.Store.Collection.Producer.beam"] = new_beams -- old_beams
delta = for b <- old_beams, :beam_lib.md5(String.to_charlist(prior <> "/" <> b)) != :beam_lib.md5(String.to_charlist(artifact <> "/ebin/" <> b)), do: b
true = Enum.sort(delta) == ["Elixir.IpseKnowledge.Corpus.beam", "Elixir.IpseKnowledge.Profiles.beam", "Elixir.IpseKnowledge.Store.Collection.Generation.beam"]
journal = File.read!(root <> "/actual/synthetic-session.jsonl")
events = journal |> String.split("\n",trim: true) |> Enum.map(&:json.decode/1)
ready = File.read!(root <> "/actual/ready.json") |> :json.decode()
results = Enum.filter(events,&(&1["type"] == "extension_action_result"))
[embedding] = Enum.filter(results,&(&1["request"]["op"] == "embedding.create"))
pending = Enum.find(results,&(&1["request"]["request"]["op"] == "value.prepare_inline" and &1["request"]["request"]["key"] == "genproducer.notes"))
claim = :json.decode(pending["request"]["request"]["data"])
true = claim["status"] == "pending"
ref = pending["outcome"]["value"]["result"]["stage"] |> Map.take(~w(slot epoch))
commit = Enum.find(results,&(&1["request"]["request"]["op"] == "commit" and &1["request"]["request"]["stages"] == [ref]))
intent = Enum.find(events,&(&1["type"] == "extension_action_intent" and &1["operation_id"] == embedding["operation_id"]))
true = Enum.find_index(events,&(&1 == commit)) < Enum.find_index(events,&(&1 == intent))
[source] = Enum.filter(events,&(&1["type"] == "extension_effect_result" and &1["kind"] == "embedding.f32le"))
[receipt] = ready["receipts"]
true = receipt["operation_id"] == source["operation_id"] and receipt["source_sha256"] == source["source_sha256"]
true = receipt["raw_input_sha256"] == Enum.map(embedding["request"]["inputs"],sha)
true = receipt["input_sha256"] == Enum.map(source["data"]["vectors"],& &1["input_sha256"])
parts = Enum.filter(results,&(&1["request"]["request"]["op"] == "value.write_parts" and &1["request"]["request"]["key"] == ready["page"]["key"]))
page_bytes = Enum.map_join(parts,&Enum.join(&1["request"]["request"]["data"]))
true = sha.(page_bytes) == ready["page"]["sha256"] and byte_size(page_bytes) == ready["page"]["byte_count"]
page = :json.decode(page_bytes)
true = length(page["rows"]) == 2
for {row,v} <- Enum.zip(page["rows"],source["data"]["vectors"]) do b = Enum.at(row,4) |> Enum.map_join(&Base.decode64!/1); true = sha.(b) == Enum.at(row,3) and b == Base.decode64!(v["values"]) end
IO.inspect(%{pinned_rows: length(rows), sources: length(m["source"]), logs: length(m["logs"]), reports: length(m["reports"]), runtime_resolved_paths: length(inventory_paths), runtime_physical_files: length(physical), unlisted_mix_cache_paths: length(unlisted), inherited_symlink_sources: length(extra), artifact_files: length(m["artifact_files"]), artifact_manifest_sha256: sha.(artifact_bytes), executable_existing_module_delta: Enum.sort(delta), new_producer_module: true, actual_journal_events: length(events), actual_claim_before_embedding: true, actual_receipt_inputs_and_vector_bytes_match: true},label: "SHARED_PRODUCER_FIRST_PAGE_VERIFIED")
