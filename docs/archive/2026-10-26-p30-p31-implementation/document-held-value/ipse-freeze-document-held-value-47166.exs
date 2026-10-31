Path.wildcard("_build/document-held-value-sol-20261029/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/document-held-value"
File.mkdir_p!(archive)
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
snapshots = Enum.map(~w(lib/ipse/extension/collection/document_stage.ex test/ipse/extension/collection_document_held_value_test.exs), fn source ->
  target = archive <> "/" <> String.replace(source, "/", "__") <> ".txt"
  File.cp!(source, target)
  Map.put(entry.(target), "source", source)
end)
retained = Enum.map(~w(/tmp/ipse-document-held-value-compile-47164.exs /tmp/ipse-document-held-value-compile-47164.log /tmp/ipse-document-held-value-test-47165.exs /tmp/ipse-document-held-value-test-47165.log /tmp/ipse-freeze-document-held-value-47166.exs), fn source ->
  target = archive <> "/" <> Path.basename(source)
  File.cp!(source, target)
  entry.(target)
end)
graphs = Enum.map(~w(_build/document-held-read-sol-20261029 _build/document-held-value-sol-20261029), fn graph ->
  rows = (walk.(walk, graph <> "/_build/dev/lib") ++ walk.(walk, graph <> "/priv")) |> Enum.map(entry)
  target = archive <> "/" <> Path.basename(graph) <> ".json"
  File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
  %{"graph" => graph, "files" => length(rows), "inventory" => entry.(target)}
end)
m = %{"version" => 1, "scope" => "complete logical packed document read under trusted retained closure", "sources" => snapshots, "retained" => retained, "graphs" => graphs, "ancestor" => entry.("docs/archive/2026-10-26-p30-p31-implementation/document-held-reader/manifest.json")}
path = archive <> "/manifest.json"
File.write!(path, Jason.encode!(m, pretty: true) <> "\n")
IO.puts("Frozen complete logical document reader " <> hash.(File.read!(path)))
