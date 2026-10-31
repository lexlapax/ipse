Path.wildcard("_build/notes-absence-publication-sol-20261029/_build/dev/lib/*/ebin")
|> Enum.each(&Code.prepend_path/1)

base = "docs/archive/2026-10-26-p30-p31-implementation"
hash = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
entry = fn path ->
  case File.lstat!(path).type do
    :symlink -> %{"path" => path, "type" => "symlink", "target" => File.read_link!(path)}
    :regular ->
      bytes = File.read!(path)
      %{"path" => path, "type" => "regular", "bytes" => byte_size(bytes), "sha256" => hash.(bytes)}
  end
end
walk = fn walk, dir ->
  File.ls!(dir) |> Enum.sort() |> Enum.flat_map(fn name ->
    path = Path.join(dir, name)
    if File.lstat!(path).type == :directory, do: walk.(walk, path), else: [path]
  end)
end

for {name, sources, retained, graphs, ancestor} <- [
  {"notes-publication-admission",
   ~w(lib/ipse/extension/collection.ex lib/ipse/extension/managed_collection_call.ex lib/ipse/session/invocation.ex lib/ipse/extension/collection/document_stage.ex test/ipse/extension/notes_publication_admission_test.exs test/ipse/extension/managed_collection_call_test.exs test/ipse/extension/collection_normalizer_v3_integration_test.exs test/ipse/extension/collection_normalizer_v3_test.exs test/support/managed_policy.exs extensions/knowledge/src/notes.ex extensions/knowledge/src/knowledge/contracts.ex extensions/knowledge/src/knowledge/records.ex),
   Path.wildcard("/tmp/ipse-notes-admission-*4716*.exs") ++
     Path.wildcard("/tmp/ipse-notes-admission-*4716*.log") ++
     Path.wildcard("/tmp/ipse-notes-admission-*47170.*") ++ [__ENV__.file],
   ~w(_build/remember-intake-sol-20261029 _build/notes-publication-admission-sol-20261029),
   base <> "/remember-intake/manifest.sha256"},
  {"notes-publication-prerequisites",
   ~w(lib/ipse/session/managed_reads.ex lib/ipse/session/managed_tool_use.ex test/ipse/session/managed_tool_use_test.exs),
   Path.wildcard("/tmp/ipse-notes-absence-*4717*.*") ++ [__ENV__.file],
   ~w(_build/notes-publication-admission-sol-20261029 _build/notes-absence-publication-sol-20261029),
   base <> "/notes-publication-admission/manifest.json"}
] do
  archive = base <> "/" <> name
  File.mkdir_p!(archive)
  snapshots = Enum.map(sources, fn source ->
    target = archive <> "/" <> String.replace(source, "/", "__") <> ".txt"
    File.cp!(source, target)
    Map.put(entry.(target), "source", source)
  end)
  retained = Enum.uniq(retained) |> Enum.sort() |> Enum.map(fn source ->
    target = archive <> "/" <> Path.basename(source)
    File.cp!(source, target)
    entry.(target)
  end)
  graphs = Enum.map(graphs, fn graph ->
    rows = (walk.(walk, graph <> "/_build/dev/lib") ++ walk.(walk, graph <> "/priv")) |> Enum.map(entry)
    target = archive <> "/" <> Path.basename(graph) <> ".json"
    File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
    %{"graph" => graph, "files" => length(rows), "inventory" => entry.(target)}
  end)
  manifest = %{"version" => 1, "scope" => name, "sources" => snapshots,
    "retained" => retained, "graphs" => graphs, "ancestor" => entry.(ancestor)}
  path = archive <> "/manifest.json"
  File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")
  IO.puts(name <> " " <> hash.(File.read!(path)) <> " sources=" <> to_string(length(snapshots)) <>
    " retained=" <> to_string(length(retained)))
end
