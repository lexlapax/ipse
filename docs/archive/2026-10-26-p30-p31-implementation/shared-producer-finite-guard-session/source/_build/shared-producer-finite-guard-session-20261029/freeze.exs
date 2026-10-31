dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-finite-guard-session")
false = File.exists?(dir)
File.mkdir_p!(dir)
row = fn path ->
  data = File.read!(path)
  %{path: Path.relative_to_cwd(path), bytes: byte_size(data), sha256: Base.encode16(:crypto.hash(:sha256, data), case: :lower)}
end
copy = fn path, name ->
  dest = Path.join(dir, name)
  File.mkdir_p!(Path.dirname(dest))
  File.cp!(path, dest)
  Map.put(row.(dest), :original, Path.relative_to_cwd(path))
end
base = "_build/shared-producer-finite-guard-session-20261029"
parent = "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session/manifest.json"
parent_manifest = Jason.decode!(File.read!(parent))
verify = fn r ->
  case r do
    %{"type" => "symlink", "path" => path, "target" => target} -> true = File.read_link!(path) === target
    %{"path" => path, "sha256" => sha, "bytes" => size} ->
      actual = row.(path)
      true = actual.sha256 === sha and actual.bytes === size
  end
end
graph = Enum.find(parent_manifest["graphs"], &(&1["root"] == "_build/document-embedding-admission-return-sol-20261029"))
Enum.each(graph["rows"] ++ parent_manifest["artifact"]["rows"], verify)
paths = ["test/extensions/knowledge/shared_producer_guard_session_test.exs", base <> "/readback.exs", __ENV__.file]
source = Enum.map(paths, &copy.(&1, "source/" <> Path.relative_to_cwd(&1)))
logs = for path <- Path.wildcard("_build/shared-producer-guard-session-finite-*.log"), do: copy.(path, "logs/" <> Path.basename(path))
evidence = for path <- Path.wildcard(base <> "/evidence/**/*"), File.regular?(path), do: copy.(path, "evidence/" <> Path.relative_to(path, base <> "/evidence"))
manifest = %{version: 1, scope: "one new actual all-four finite-TTL source positive; unchanged original deadlines, four guarded batches; no prior controls repeated", ancestor: row.(parent), source: source, logs: logs, evidence: evidence, exact_parent_runtime: graph, exact_parent_artifact: parent_manifest["artifact"]}
target = Path.join(dir, "manifest.json")
File.write!(target, Jason.encode!(manifest, pretty: true), [:exclusive])
IO.puts(Jason.encode!(%{manifest: row.(target), source: length(source), logs: length(logs), evidence: length(evidence), unchanged_graph_rows: length(graph["rows"]), unchanged_artifact_rows: length(parent_manifest["artifact"]["rows"])}, pretty: true))
