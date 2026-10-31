base = "docs/archive/2026-10-26-p30-p31-implementation"
root = base <> "/management-forget-current-source"
graph = "_build/management-forget-current-source-sol-20261029"
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
parse = fn p ->
  for line <- String.split(File.read!(p), "\n", trim: true), into: %{} do
    [h, f] = String.split(line, "  ", parts: 2)
    {f, h}
  end
end
tar = fn p ->
  {:ok, rows} = :erl_tar.extract(String.to_charlist(p), [:memory])
  Map.new(rows, fn {p, b} -> {List.to_string(p), b} end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "9cf92a186e19fb99a7c7d3fd7b9977e18d3bd5338d60ad064aa23e79ecaf9322"
manifest = parse.(root <> "/manifest.sha256")
for {p, h} <- manifest, do: true = sha.(File.read!(Path.join(root, p))) == h
sources = tar.(root <> "/source.tar")
hashes = parse.(root <> "/source.sha256")
for {p, h} <- hashes, do: true = sha.(Map.fetch!(sources, p)) == h
for {p, bytes} <- sources, do: true = File.read!(Path.join(graph, p)) == bytes
true = File.read!(root <> "/base-source.sha256") == File.read!(base <> "/document-held-reader/host-source.sha256")
prior_sources = tar.(base <> "/document-held-reader/host-source.tar")
source_delta = for {p, bytes} <- prior_sources, sources[p] != bytes, do: p
true = Enum.sort(source_delta) == ["lib/ipse/cli/knowledge/management.ex", "lib/ipse/extension/collection.ex"]
true = sha.(sources["lib/ipse/extension/collection.ex"]) == "ba6c994d97df9de90f84a783374caa9885e61d1b78007a68ca8d9e56bc0932fd"
public_sources = tar.(base <> "/management-forget-public/source.tar")
for p <- ~w(lib/ipse/cli.ex lib/ipse/cli/knowledge.ex), do: true = public_sources[p] == sources[p]
old_comment = "  # Private actual-effect candidate. The public forget route remains gated."
current_management = sources["lib/ipse/cli/knowledge/management.ex"]
false = String.contains?(current_management, old_comment)
runtime = parse.(root <> "/runtime.sha256")
priv = parse.(root <> "/priv.sha256")
final = Map.merge(runtime, priv)
for {p, h} <- final, do: true = sha.(File.read!(Path.join(graph, p))) == h
runtime_tar = tar.(root <> "/runtime.tar")
true = Enum.sort(Map.keys(runtime_tar)) == Enum.sort(Map.keys(final))
for {p, bytes} <- runtime_tar, do: true = sha.(bytes) == final[p]
walk = fn f, p ->
  case File.lstat!(p).type do
    :regular -> [Path.expand(p)]
    :symlink -> []
    :directory -> Enum.flat_map(File.ls!(p), &f.(f, Path.join(p, &1)))
  end
end
physical = walk.(walk, graph <> "/_build/dev/lib") ++ walk.(walk, graph <> "/priv")
true = Enum.sort(physical) == Enum.sort(Enum.map(Map.keys(final), &Path.expand(Path.join(graph, &1))))
prior_root = "_build/document-held-read-sol-20261029"
prior_rows = :json.decode(File.read!(base <> "/document-held-reader/document-held-read-sol-20261029.json"))
links = for r <- prior_rows, r["type"] == "symlink" do
  p = Path.join(graph, Path.relative_to(r["path"], prior_root))
  true = File.lstat!(p).type == :symlink and File.read_link!(p) == r["target"]
  p
end
prior = for r <- prior_rows, r["type"] == "regular", into: %{}, do: {Path.relative_to(r["path"], prior_root), r["sha256"]}
delta = for {p, h} <- prior, final[p] != h, do: p
true = Enum.sort(delta) == ["_build/dev/lib/ipse/ebin/Elixir.Ipse.CLI.Knowledge.Management.beam", "_build/dev/lib/ipse/ebin/Elixir.Ipse.CLI.Knowledge.beam", "_build/dev/lib/ipse/ebin/Elixir.Ipse.CLI.beam", "priv/extension-bundles/catalog.json"]
true = Map.keys(prior) -- Map.keys(final) == []
true = length(Map.keys(final) -- Map.keys(prior)) == 10
for p <- Path.wildcard(root <> "/beams/*.beam"), do: true = File.read!(p) == File.read!(graph <> "/_build/dev/lib/ipse/ebin/" <> Path.basename(p))
true = sha.(File.read!(root <> "/ipse-runner")) == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"
true = File.read!(root <> "/ipse-runner") == File.read!(graph <> "/priv/ipse-runner")
artifacts = for {prefix, artifact_dir} <- [{"current", "knowledge-current"}, {"old", "knowledge"}] do
  files = tar.(root <> "/#{prefix}-knowledge-artifact.tar")
  catalog = :json.decode(File.read!(root <> "/#{prefix}-bundle-catalog.json"))
  [entry] = catalog["artifacts"]
  bytes = files[artifact_dir <> "/extension.json"]
  true = sha.(bytes) == entry["manifest_sha256"]
  am = :json.decode(bytes)
  for r <- am["files"] do
    b = files[artifact_dir <> "/" <> r["path"]]
    true = byte_size(b) == r["bytes"] and sha.(b) == r["sha256"]
    true = b == File.read!(graph <> "/priv/extension-bundles/" <> artifact_dir <> "/" <> r["path"])
  end
  true = map_size(files) == length(am["files"]) + 1
  {prefix, entry["manifest_sha256"], map_size(files)}
end
events = File.stream!(root <> "/management-journal.jsonl") |> Enum.map(&:json.decode/1)
[%{"type" => "session"}, %{"type" => "managed_lifecycle_intent"} = intent, %{"type" => "managed_lifecycle_result", "status" => "settled"} = result] = events
true = intent["operation_id"] == result["operation_id"]
IO.inspect(%{manifest_entries: map_size(manifest), source_tar_files: map_size(sources), source_hash_entries: map_size(hashes), source_tar_not_in_list: Enum.sort(Map.keys(sources) -- Map.keys(hashes)), changed_from_pre_reader_source: Enum.sort(source_delta), runtime_files: map_size(runtime), priv_files: map_size(priv), inherited_symlinks: length(links), runtime_delta_from_held_reader: Enum.sort(delta), additional_artifact_files: 10, artifact_manifests: artifacts, journal_events: length(events), repeated_tests: 0}, label: "CURRENT_SOURCE_FORGET_OK")
