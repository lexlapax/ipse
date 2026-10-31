graph = "_build/document-source-use-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/document-source-use"
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
files = ~w(lib/ipse/extension/collection/document_source_use.ex test/ipse/extension/collection_document_source_use_test.exs)
Code.compiler_options(ignore_module_conflict: true)
Enum.each(files, fn file -> File.write!(file, IO.iodata_to_binary(Code.format_file!(file)) <> "\n") end)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  [hd(files)], graph <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.puts("Documentation-only production clarification compiled with empty diagnostics; no tests/effects rerun")
sources = Enum.map(files, fn source ->
  target = archive <> "/" <> String.replace(source, "/", "__") <> ".txt"
  File.cp!(source, target)
  Map.put(entry.(target), "source", source)
end)
retained = (Path.wildcard("/tmp/ipse-document-source-use-*471*.exs") ++
  Path.wildcard("/tmp/ipse-document-source-use-*471*.log") ++ [__ENV__.file])
  |> Enum.uniq() |> Enum.sort() |> Enum.map(fn source ->
    target = archive <> "/" <> Path.basename(source)
    File.cp!(source, target)
    entry.(target)
  end)
graphs = Enum.map(~w(_build/document-held-value-sol-20261029 _build/document-source-use-sol-20261029), fn tree ->
  rows = (walk.(walk, tree <> "/_build/dev/lib") ++ walk.(walk, tree <> "/priv")) |> Enum.map(entry)
  target = archive <> "/" <> Path.basename(tree) <> ".json"
  File.write!(target, Jason.encode!(rows, pretty: true) <> "\n")
  %{"graph" => tree, "files" => length(rows), "inventory" => entry.(target)}
end)
ancestors = Enum.map(~w(document-held-value/manifest.json shared-producer-host-seed/manifest.json shared-producer-relation-seeds/manifest.json),
  &entry.("docs/archive/2026-10-26-p30-p31-implementation/" <> &1))
path = archive <> "/manifest.json"
File.write!(path, Jason.encode!(%{"version" => 1, "scope" => "unwired closed document input byte/time relation",
  "sources" => sources, "retained" => retained, "graphs" => graphs, "ancestors" => ancestors}, pretty: true) <> "\n")
IO.puts("Document source use " <> hash.(File.read!(path)) <> " retained=" <> to_string(length(retained)))
