graph = "_build/document-embedding-admission-inventory-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/document-source-admission-initial"
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
sources = File.read!(graph <> "/admission-source.sha256") |> String.split("\n", trim: true)
  |> Enum.map(fn row -> [_old_hash, path] = String.split(row, "  ", parts: 2); path end)
members = Enum.map(sources, fn path -> {String.to_charlist(path), File.read!(graph <> "/" <> path)} end)
tar = archive <> "/source.tar"
:ok = :erl_tar.create(String.to_charlist(tar), members, [])
File.write!(archive <> "/source.sha256", Enum.map(members, fn {path, body} -> hash.(body) <> "  " <> List.to_string(path) <> "\n" end))
test = "test/ipse/session/document_embedding_test.exs"
File.cp!(test, archive <> "/document_embedding_test.exs.txt")
retained = (Path.wildcard("/tmp/ipse-document-embedding-*4719*.exs") ++
  Path.wildcard("/tmp/ipse-document-embedding-*4719*.log") ++
  Path.wildcard("/tmp/ipse-document-embedding-*4720*.exs") ++
  Path.wildcard("/tmp/ipse-document-embedding-*4720*.log") ++
  ["/tmp/ipse-document-embedding-session-handlers.patch", __ENV__.file])
  |> Enum.uniq() |> Enum.sort() |> Enum.map(fn source ->
    target = archive <> "/" <> Path.basename(source)
    File.cp!(source, target)
    entry.(target)
  end)
inventories = Enum.map(~w(_build/document-embedding-admission-sol-20261029 _build/document-embedding-admission-clock-sol-20261029 _build/document-embedding-admission-inventory-sol-20261029), fn tree ->
  rows = (walk.(walk, tree <> "/_build/dev/lib") ++ walk.(walk, tree <> "/priv")) |> Enum.map(entry)
  target = archive <> "/" <> Path.basename(tree) <> ".json"
  File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
  %{"graph" => tree, "files" => length(rows), "inventory" => entry.(target)}
end)
layers = Enum.map(~w(admission-source.sha256 admission-clock-overlays.sha256 ipse.app-before-inventory), fn file ->
  target = archive <> "/" <> file
  File.cp!(graph <> "/" <> file, target)
  entry.(target)
end)
ancestors = Enum.map(~w(document-source-use/manifest.json shared-producer-guarded-wire/manifest.json),
  &entry.("docs/archive/2026-10-26-p30-p31-implementation/" <> &1))
manifest = %{"version" => 1, "scope" => "initial document source admission wiring; actual transport qualification unresolved",
  "source_count" => length(sources), "source_tar" => entry.(tar),
  "source_hashes" => entry.(archive <> "/source.sha256"), "test" => entry.(archive <> "/document_embedding_test.exs.txt"),
  "retained" => retained, "layers" => layers, "graphs" => inventories, "ancestors" => ancestors}
path = archive <> "/manifest.json"
File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")
IO.puts("Frozen #{length(sources)} host inputs, #{length(retained)} launchers/logs; manifest " <> hash.(File.read!(path)))
