root = "docs/archive/2026-10-26-p30-p31-implementation/generation-compact-progress"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
file_sha = fn p -> File.stream!(p,65536,[]) |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2,&1)) |> :crypto.hash_final() |> Base.encode16(case: :lower) end
parse = fn p -> p |> File.read!() |> String.split("\n",trim: true) |> Enum.map(fn r -> [h,f] = String.split(r,"  ",parts: 2); {f,h} end) end
true = sha.(File.read!(root <> "/manifest.sha256")) == "61b4c7492d54d100bb762664064dec2e80f63bd5eaf63f8e94708dec3352811e"
rows = parse.(root <> "/manifest.sha256")
Enum.each(rows,fn {p,h} -> true = file_sha.(p) == h end)
{:ok,source_rows} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
sources = Map.new(source_rows,fn {p,b} -> {List.to_string(p),b} end)
Enum.each(parse.(root <> "/source.sha256"),fn {p,h} -> true = sha.(Map.fetch!(sources,p)) == h end)
inventories = for name <- ~w(runtime artifact session-artifacts helper) do
  inventory = parse.(root <> "/" <> name <> ".sha256")
  Enum.each(inventory,fn {p,h} -> true = file_sha.(p) == h end)
  {name,length(inventory)}
end
ancestor = File.read!("docs/archive/2026-10-26-p30-p31-implementation/document-packed-layout/manifest.json") |> :json.decode()
for {p,m} <- ancestor["runtime"] do
  relative = Path.relative_to(p,Path.expand("_build/document-layout-inventory-sol-20261029/lib"))
  true = file_sha.("_build/generation-progress-sol-20261029/lib/" <> relative) == m["sha256"]
end
artifact = "_build/generation-progress-corpus-sol-20261029"
manifest_bytes = File.read!(artifact <> "/extension.json")
true = sha.(manifest_bytes) == "004654fe41ab870398d806d51ad72fa5ef6d0e5b1396133deac8a43a933e72b0"
manifest = :json.decode(manifest_bytes)
for row <- manifest["files"] do
  p = artifact <> "/" <> row["path"]
  true = File.stat!(p).size == row["bytes"] and file_sha.(p) == row["sha256"]
end
old = "_build/shared-finalization-native-20261029/root2-public-artifacts-47072/95b9ffe3a1a00496b14ccbbeecd245f2306cf8bb096247cbffbc19a1b3b6cb55/ebin"
beams = File.ls!(artifact <> "/ebin") |> Enum.filter(&String.ends_with?(&1,".beam")) |> Enum.sort()
true = beams == (File.ls!(old) |> Enum.filter(&String.ends_with?(&1,".beam")) |> Enum.sort())
code_delta = for b <- beams, :beam_lib.md5(String.to_charlist(artifact <> "/ebin/" <> b)) != :beam_lib.md5(String.to_charlist(old <> "/" <> b)), do: b
["Elixir.IpseKnowledge.Corpus.beam", "Elixir.IpseKnowledge.Store.Collection.Job.beam"] = code_delta
ledger_root = "docs/archive/2026-10-26-p30-p31-implementation/document-compact-finalization-ledger"
ledger_bytes = File.read!(ledger_root <> "/manifest.json")
true = sha.(ledger_bytes) == "31bc1edfc68842076f7115e27abf2348304be27fd79120ea6fef4a652b229ee2"
ledger = :json.decode(ledger_bytes)
ledger_rows = Enum.flat_map(~w(source logs reports retained artifact_files), &ledger[&1]) ++ [ledger["ancestor"]]
for row <- ledger_rows, do: true = File.stat!(row["path"]).size == row["bytes"] and file_sha.(row["path"]) == row["sha256"]
objects = File.stream!(ledger_root <> "/reports/compact-finalization-47121/public-results.jsonl") |> Enum.map(&:json.decode/1)
true = length(objects) == 655
for %{"output" => output} <- objects do
  true = output["coverage"]["representation"] == "compact_v1"
  false = Map.has_key?(output["coverage"],"job")
  if is_map(output["continuation"]), do: true = output["continuation"]["arguments"]["response"] == "compact_v1"
end
IO.inspect(%{manifest_entries: length(rows), source_inputs: map_size(sources), inventories: inventories, unchanged_ancestor_host_paths: map_size(ancestor["runtime"]), declared_artifact_files: length(manifest["files"]), executable_code_delta: code_delta, compact_ledger_pinned_rows: length(ledger_rows), retained_public_objects: length(objects)},label: "GENERATION_COMPACT_PROGRESS_OK")
