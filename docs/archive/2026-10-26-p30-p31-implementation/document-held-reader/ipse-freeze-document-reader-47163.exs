Path.wildcard("_build/document-held-read-sol-20261029/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/document-held-reader"
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
base = "_build/p30-p31-integrated-source-20261029"
paths = File.read!(base <> "/source.sha256") |> String.split("\n", trim: true) |> Enum.map(fn line ->
  [sha, path] = String.split(line, "  ", parts: 2)
  true = hash.(File.read!(base <> "/" <> path)) == sha
  path
end)
:ok = :erl_tar.create(String.to_charlist(archive <> "/host-source.tar"), Enum.map(paths, fn path ->
  {String.to_charlist(path), File.read!(base <> "/" <> path)}
end), [])
File.cp!(base <> "/source.sha256", archive <> "/host-source.sha256")
snapshots = Enum.map(~w(lib/ipse/extension/collection.ex test/ipse/extension/collection_document_held_read_test.exs test/ipse/extension/collection_held_read_test.exs), fn source ->
  target = archive <> "/" <> String.replace(source, "/", "__") <> ".txt"
  File.cp!(source, target)
  Map.put(entry.(target), "source", source)
end)
retained = Enum.map(~w(/tmp/ipse-integrated-source-snapshot-47159.exs /tmp/ipse-integrated-host-compile-47160.log /tmp/ipse-document-held-read-compile-47161.exs /tmp/ipse-document-held-read-compile-47161.log /tmp/ipse-document-held-read-test-47162.exs /tmp/ipse-document-held-read-test-47162.log /tmp/ipse-freeze-document-reader-47163.exs), fn source ->
  target = archive <> "/" <> Path.basename(source)
  File.cp!(source, target)
  entry.(target)
end)
graphs = Enum.map([base, "_build/document-held-read-sol-20261029"], fn graph ->
  paths = walk.(walk, graph <> "/_build/dev/lib") ++ walk.(walk, graph <> "/priv")
  rows = Enum.map(paths, entry)
  target = archive <> "/" <> Path.basename(graph) <> ".json"
  File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
  %{"graph" => graph, "files" => length(rows), "inventory" => entry.(target), "helper" => entry.(graph <> "/priv/ipse-runner")}
end)
m = %{"version" => 1, "scope" => "full current host/native compile then fixed document held-read overlay; no source-use admission", "host_source" => entry.(archive <> "/host-source.tar"), "host_source_hashes" => entry.(archive <> "/host-source.sha256"), "host_source_files" => length(paths), "sources" => snapshots, "retained" => retained, "graphs" => graphs}
path = archive <> "/manifest.json"
File.write!(path, Jason.encode!(m, pretty: true) <> "\n")
IO.puts("Frozen document reader manifest " <> hash.(File.read!(path)))
Enum.each(graphs, fn g -> IO.inspect(%{graph: g["graph"], entries: g["files"], helper: g["helper"]["sha256"]}) end)
