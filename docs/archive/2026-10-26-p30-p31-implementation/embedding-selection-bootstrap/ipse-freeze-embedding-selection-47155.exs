Path.wildcard("_build/embedding-selection-sol-20261029/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/embedding-selection-bootstrap"
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
sources = ~w(lib/ipse/extension/inference.ex lib/ipse/extension/actions.ex lib/ipse/extension/host.ex lib/ipse/session/invocation.ex test/ipse/extension/embedding_result_test.exs test/ipse/extension/embedding_call_session_test.exs)
snapshots = Enum.map(sources, fn source ->
  target = Path.join(archive, String.replace(source, "/", "__") <> ".txt")
  File.cp!(source, target)
  Map.put(entry.(target), "source", source)
end)
files = ~w(/tmp/ipse-embedding-selection-compile-47151.exs /tmp/ipse-embedding-selection-compile-47151.log /tmp/ipse-embedding-selection-pure-47152.exs /tmp/ipse-embedding-selection-pure-47152.log /tmp/ipse-embedding-selection-session-47153.exs /tmp/ipse-embedding-selection-session-47153.log /tmp/ipse-embedding-selection-bootstrap-47154.exs /tmp/ipse-embedding-selection-bootstrap-47154.log /tmp/ipse-embedding-selection-initial-session-47153.exs /tmp/ipse-freeze-embedding-selection-47155.exs)
retained = Enum.map(files, fn source ->
  target = Path.join(archive, Path.basename(source))
  File.cp!(source, target)
  entry.(target)
end)
graphs = Enum.map(~w(_build/reviewed-forget-cli-sol-20261029 _build/embedding-selection-sol-20261029), fn graph ->
  rows = walk.(walk, graph <> "/lib") |> Enum.map(entry)
  target = Path.join(archive, Path.basename(graph) <> ".json")
  File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
  %{"graph" => graph, "files" => length(rows), "inventory" => entry.(target)}
end)
ancestor = entry.("docs/archive/2026-10-26-p30-p31-implementation/reviewed-forget-core/manifest.json")
m = %{"version" => 1, "scope" => "embedding profile bootstrap and optional v2 selection pin; no source-policy fence", "sources" => snapshots, "retained" => retained, "graphs" => graphs, "ancestor" => ancestor}
path = archive <> "/manifest.json"
File.write!(path, Jason.encode!(m, pretty: true) <> "\n")
IO.puts("Frozen selection manifest " <> hash.(File.read!(path)))
Enum.each(graphs, &IO.inspect(Map.take(&1, ~w(graph files))))
