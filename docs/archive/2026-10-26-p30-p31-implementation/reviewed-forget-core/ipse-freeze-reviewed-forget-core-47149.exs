Path.wildcard("_build/reviewed-forget-cli-sol-20261029/lib/*/ebin")
|> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/reviewed-forget-core"
File.mkdir_p!(archive)
hash = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
entry = fn path ->
  case File.lstat!(path).type do
    :symlink ->
      %{"path" => path, "type" => "symlink", "target" => File.read_link!(path)}
    :regular ->
      bytes = File.read!(path)
      %{"path" => path, "type" => "regular", "bytes" => byte_size(bytes), "sha256" => hash.(bytes)}
  end
end
walk = fn walk, dir ->
  File.ls!(dir)
  |> Enum.sort()
  |> Enum.flat_map(fn name ->
    path = Path.join(dir, name)
    case File.lstat!(path).type do
      :directory -> walk.(walk, path)
      :regular -> [path]
      :symlink -> [path]
    end
  end)
end
sources = ~w(lib/ipse/extension/collection.ex lib/ipse/cli/knowledge.ex lib/ipse/cli/errors.ex test/ipse/extension/collection_review_gate_test.exs test/ipse/extension/collection_managed_test.exs test/ipse/extension/collection_deadline_gate_test.exs)
snapshots = Enum.map(sources, fn source ->
  target = Path.join(archive, String.replace(source, "/", "__") <> ".txt")
  File.cp!(source, target)
  Map.put(entry.(target), "source", source)
end)
true = File.read!("lib/ipse/extension/collection.ex") == File.read!("/tmp/ipse-reviewed-forget-core-47145.ex")
logs = for number <- [47145, 47146, 47147, 47148], suffix <- ["exs", "log"] do
  stem = case number do
    47145 -> "ipse-reviewed-forget-core-compile"
    47146 -> "ipse-reviewed-forget-core-test"
    47147 -> "ipse-reviewed-forget-cli-compile"
    47148 -> "ipse-reviewed-forget-cli-test"
  end
  source = "/tmp/#{stem}-#{number}.#{suffix}"
  target = Path.join(archive, Path.basename(source))
  File.cp!(source, target)
  entry.(target)
end
graphs = Enum.map(~w(_build/management-review-input-sol-20261029 _build/reviewed-forget-core-sol-20261029 _build/reviewed-forget-cli-sol-20261029), fn graph ->
  rows = walk.(walk, graph <> "/lib") |> Enum.map(entry)
  target = Path.join(archive, Path.basename(graph) <> ".json")
  File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
  %{"graph" => graph, "inventory" => entry.(target), "files" => length(rows)}
end)
helpers = Enum.map(~w(/tmp/ipse-freeze-reviewed-forget-core-initial-47149.exs /tmp/ipse-freeze-reviewed-forget-core-47149.exs), fn source ->
  target = Path.join(archive, Path.basename(source))
  File.cp!(source, target)
  entry.(target)
end)
manifest = %{"version" => 1, "scope" => "forget-only Core fence and retained public refusals", "sources" => snapshots, "launches_and_logs" => logs, "freeze_helpers" => helpers, "graphs" => graphs}
path = Path.join(archive, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true) <> "\n")
IO.puts("Frozen scoped Core manifest " <> hash.(File.read!(path)))
Enum.each(graphs, &IO.inspect(Map.take(&1, ~w(graph files))))
