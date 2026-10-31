graph = "_build/document-embedding-admission-return-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/document-source-admission-return"
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
source = graph <> "/lib/ipse/session/document_embedding.ex"
target = archive <> "/document_embedding.ex.txt"
File.cp!(source, target)
retained = Enum.map(~w(/tmp/ipse-document-embedding-return-47212.exs /tmp/ipse-document-embedding-return-47212.log /tmp/ipse-freeze-document-return-47215.exs), fn file ->
  target = archive <> "/" <> Path.basename(file)
  File.cp!(file, target)
  entry.(target)
end)
trees = Enum.map(~w(_build/document-embedding-admission-inventory-sol-20261029 _build/document-embedding-admission-return-sol-20261029), fn tree ->
  rows = (walk.(walk, tree <> "/_build/dev/lib") ++ walk.(walk, tree <> "/priv")) |> Enum.map(entry)
  target = archive <> "/" <> Path.basename(tree) <> ".json"
  File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
  %{"graph" => tree, "files" => length(rows), "inventory" => entry.(target)}
end)
layer = archive <> "/admission-return-overlay.sha256"
File.cp!(graph <> "/admission-return-overlay.sha256", layer)
manifest = %{"version" => 1, "scope" => "exact private success marker through retained reader and Identity cleanup",
  "source" => Map.put(entry.(target), "source", "lib/ipse/session/document_embedding.ex"),
  "retained" => retained, "graphs" => trees, "layer" => entry.(layer),
  "ancestor" => entry.("docs/archive/2026-10-26-p30-p31-implementation/document-source-admission-initial/manifest.json")}
path = archive <> "/manifest.json"
File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")
IO.puts("Frozen exact marker repair " <> hash.(File.read!(path)))
