dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-public-adoption")
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
source = for path <- ~w(extensions/knowledge/src/corpus.ex extensions/knowledge/src/store/collection/producer.ex extensions/knowledge/src/adapters.ex extensions/knowledge/config.exs extensions/knowledge/spec.exs extensions/knowledge/build.exs test/extensions/knowledge/producer_configuration_test.exs test/extensions/knowledge/shared_producer_guard_session_test.exs test/extensions/knowledge/shared_producer_session_test.exs test/extensions/knowledge/shared_producer_test.exs test/support/shared_producer_fixture.exs docs/operator/corpus.md docs/developer/knowledge-extensions.md docs/developer/collection-sdk.md), do: copy.(path, "source/" <> path)
root = "_build/shared-producer-public-adoption-20261029"
scripts = Enum.map([root <> "/check.exs", __ENV__.file], &copy.(&1, "scripts/" <> Path.basename(&1)))
logs = for path <- Path.wildcard("_build/shared-producer-public-*.log"), do: copy.(path, "logs/" <> Path.basename(path))
configuration = for path <- ~w(options.json inference.json operator.json), do: copy.(root <> "/" <> path, path)
artifacts = for path <- [root <> "/artifact", root <> "/artifact-current"], do: %{root: path, rows: walk.(path)}
ancestors = for path <- ~w(shared-producer-guard-session/manifest.json shared-producer-finite-guard-session/manifest.json), do: row.("docs/archive/2026-10-26-p30-p31-implementation/" <> path)
reviews = for path <- ~w(shared-producer-guard-session-independent-review.md shared-producer-finite-guard-session-independent-review.md shared-producer-public-page-reopening-direction-independent-review.md), do: row.("docs/archive/2026-10-26-p30-p31-implementation/" <> path)
manifest = %{version: 1, scope: "canonical public first-page adoption by exact source/descriptor comparison, strict artifact build and focused protocol/configuration controls; actual native qualification belongs to private ancestor artifact only; no new native/effect/model calls", source: source, scripts: scripts, logs: logs, configuration: configuration, artifacts: artifacts, ancestors: ancestors, reviews: reviews}
target = Path.join(dir, "manifest.json")
File.write!(target, Jason.encode!(manifest, pretty: true), [:exclusive])
IO.puts(Jason.encode!(%{manifest: row.(target), source: length(source), scripts: length(scripts), logs: length(logs), artifacts: Enum.map(artifacts, &length(&1.rows))}, pretty: true))
