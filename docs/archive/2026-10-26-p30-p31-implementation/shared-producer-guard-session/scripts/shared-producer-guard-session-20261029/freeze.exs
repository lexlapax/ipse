dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session")
false = File.exists?(dir)
File.mkdir_p!(dir)
row = fn path ->
  bytes = File.read!(path)
  %{path: Path.relative_to_cwd(path), bytes: byte_size(bytes), sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
end
copy = fn path, name ->
  target = Path.join(dir, name)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(path, target)
  Map.put(row.(target), :original, Path.relative_to_cwd(path))
end
walk = fn root ->
  visit = fn visit, path ->
    case File.lstat!(path).type do
      :directory -> File.ls!(path) |> Enum.sort() |> Enum.flat_map(&visit.(visit, Path.join(path, &1)))
      :regular -> [Map.put(row.(path), :type, "regular")]
      :symlink -> [%{path: Path.relative_to_cwd(path), type: "symlink", target: File.read_link!(path)}]
    end
  end
  visit.(visit, root)
end
base = "_build/shared-producer-guard-session-20261029"
package = base <> "/package/extensions/knowledge"
package_sources = Path.wildcard(package <> "/src/**/*.ex") ++ Enum.map(~w(build.exs spec.exs), &(package <> "/" <> &1))
source = Enum.map(package_sources, &copy.(&1, "private-package/" <> Path.relative_to(&1, package)))
source = source ++ [copy.("test/extensions/knowledge/shared_producer_guard_session_test.exs", "source/test/extensions/knowledge/shared_producer_guard_session_test.exs"), copy.("extensions/knowledge/src/corpus.ex", "production-corpus.ex.txt")]
scripts = Path.wildcard(base <> "/*.exs") ++ Path.wildcard("_build/shared-producer-guard-diagnostic-20261029/*.exs")
scripts = Enum.map(scripts, &copy.(&1, "scripts/" <> Path.relative_to(&1, "_build")))
logs = Path.wildcard("_build/shared-producer-guard-*.log") |> Enum.reject(&String.contains?(&1, "freeze")) |> Enum.map(&copy.(&1, "logs/" <> Path.basename(&1)))
evidence = walk.(base <> "/evidence") |> Enum.filter(&(&1.type == "regular")) |> Enum.map(&copy.(&1.path, "evidence/" <> Path.relative_to(&1.path, base <> "/evidence")))
diagnostic_sources = for path <- ~w(lib/ipse/session/document_embedding.ex lib/ipse/session/inference_dispatch.ex lib/ipse/session.ex lib/ipse/inference_dispatch.ex), do: copy.("_build/document-embedding-gate-diagnostic-sol-20261029/" <> path, "diagnostic-source/" <> path <> ".txt")
graphs = for root <- ~w(_build/document-embedding-admission-inventory-sol-20261029 _build/document-embedding-admission-return-sol-20261029 _build/document-embedding-gate-diagnostic-sol-20261029), do: %{root: root, rows: walk.(root <> "/_build/dev/lib") ++ walk.(root <> "/priv")}
artifact = %{root: base <> "/artifact", rows: walk.(base <> "/artifact")}
ancestors = for path <- ~w(shared-producer-guarded-wire/manifest.json document-source-admission-initial/manifest.json document-source-admission-return/manifest.json), do: row.("docs/archive/2026-10-26-p30-p31-implementation/" <> path)
helper = row.("_build/document-embedding-admission-return-sol-20261029/priv/ipse-runner")
true = helper.sha256 == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"
manifest = %{version: 1, scope: "actual private-artifact synthetic local-loopback four-batch nil-TTL positive and whole-claim-source approval-delay expiry refusal; public Corpus page remains gated; no live model, no complete producer/capacity/Word qualification", source: source, scripts: scripts, logs: logs, evidence: evidence, diagnostic_sources: diagnostic_sources, graphs: graphs, artifact: artifact, ancestors: ancestors, helper: helper}
target = Path.join(dir, "manifest.json")
File.write!(target, Jason.encode!(manifest, pretty: true), [:exclusive])
IO.puts(Jason.encode!(%{manifest: row.(target), source: length(source), scripts: length(scripts), logs: length(logs), evidence: length(evidence), graph_rows: Enum.map(graphs, &length(&1.rows)), artifact_rows: length(artifact.rows)}, pretty: true))
