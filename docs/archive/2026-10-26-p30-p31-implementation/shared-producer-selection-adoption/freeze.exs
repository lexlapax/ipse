dir =
  Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-selection-adoption")

false = File.exists?(dir)
File.mkdir_p!(dir)

row = fn path ->
  hash =
    File.stream!(path, 65_536, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)

  %{path: Path.relative_to_cwd(path), bytes: File.stat!(path).size, sha256: hash}
end

copy = fn path, name ->
  target = Path.join(dir, name)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(path, target)
  Map.put(row.(target), :original, Path.relative_to_cwd(path))
end

source =
  for path <-
        ~w(extensions/knowledge/src/adapters.ex extensions/knowledge/src/store/collection/producer.ex extensions/knowledge/src/corpus.ex extensions/knowledge/build.exs test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_test.exs test/extensions/knowledge/shared_producer_session_test.exs),
      do: copy.(path, "source/" <> path)

source =
  source ++
    for(
      name <-
        ~w(initial-fixture-47157.exs initial-context-47162.exs initial-errorshape-47165.exs check-actual.exs),
      do: copy.("_build/shared-producer-selection-adoption-20261029/" <> name, "source/" <> name)
    ) ++ [copy.(__ENV__.file, "freeze.exs")]

logs =
  for name <-
        ~w(shared-producer-selection-adoption-47157.log shared-producer-selection-adoption-47158.log shared-producer-selection-build-47159.log shared-producer-selection-marker-47160.log shared-producer-current-marker-47161.log shared-producer-selection-current-47162.log shared-producer-selection-current-build-47163.log shared-producer-selection-fixture-diagnostic-47164.log shared-producer-selection-focused-47165.log shared-producer-selection-session-47166.log shared-producer-selection-schema-diagnostic-47167.log shared-producer-selection-focused-47168.log shared-producer-selection-final-build-47169.log shared-producer-selection-session-47170.log shared-producer-selection-readback-47171.log),
      do: copy.("_build/" <> name, name)

reports =
  for path <- Path.wildcard("_build/shared-producer-selection-adoption-20261029/session-47170/*"),
      do: copy.(path, "actual/" <> Path.basename(path))

reports =
  reports ++
    [
      copy.(
        "_build/shared-producer-selection-current-corpus-20261029/extension.json",
        "initial-unsupported-extension.json"
      )
    ]

walk = fn root ->
  visit = fn visit, path ->
    stat = File.lstat!(path)

    case stat.type do
      :directory ->
        File.ls!(path) |> Enum.sort() |> Enum.flat_map(&visit.(visit, Path.join(path, &1)))

      :regular ->
        [Map.put(row.(path), :type, "regular")]

      :symlink ->
        [
          %{
            path: Path.relative_to_cwd(path),
            type: "symlink",
            target: File.read_link!(path),
            mode: stat.mode,
            uid: stat.uid
          }
        ]
    end
  end

  visit.(visit, root)
end

runtime_root = Path.expand("_build/document-held-read-sol-20261029/_build/dev/lib")
runtime = walk.(runtime_root)
helper = row.(Path.join(runtime_root, "ipse/priv/ipse-runner"))
true = helper.sha256 == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"

artifacts =
  for root <-
        ~w(_build/shared-producer-selection-corpus-20261029 _build/shared-producer-selection-current-corpus-20261029 _build/shared-producer-selection-final-corpus-20261029),
      do: %{root: root, files: walk.(Path.expand(root))}

ancestors =
  for path <-
        ~w(docs/archive/2026-10-26-p30-p31-implementation/embedding-selection-bootstrap/manifest.json docs/archive/2026-10-26-p30-p31-implementation/document-held-reader/manifest.json docs/archive/2026-10-26-p30-p31-implementation/shared-producer-public-gate/manifest.json),
      do: row.(path)

manifest = %{
  version: 1,
  kind: "producer_selection_adoption_public_page_still_gated",
  source: source,
  logs: logs,
  reports: reports,
  artifacts: artifacts,
  runtime: runtime,
  helper: helper,
  ancestors: ancestors,
  scope:
    "nine prior controls passed in47162; four new corrected controls47168; actual configured-only selection/gate47170; no public/private source dispatch acceptance or capacity",
  note:
    "runtime symlinks recorded without traversal; helper separately authenticated; no Core overlays"
}

path = Path.join(dir, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(path),
      source: length(source),
      logs: length(logs),
      reports: length(reports),
      runtime_files: Enum.count(runtime, &(&1.type == "regular")),
      runtime_symlinks: Enum.count(runtime, &(&1.type == "symlink")),
      artifact_files: Enum.sum(Enum.map(artifacts, &length(&1.files)))
    }, pretty: true)
)
