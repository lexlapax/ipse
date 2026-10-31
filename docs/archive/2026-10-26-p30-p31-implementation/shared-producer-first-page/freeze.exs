archive = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-first-page")
false = File.exists?(archive)
File.mkdir_p!(archive)

row = fn path ->
  hash =
    File.stream!(path, 65536, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)

  %{path: Path.relative_to_cwd(path), bytes: File.stat!(path).size, sha256: hash}
end

copy = fn path, name ->
  target = Path.join(archive, name)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(path, target)
  Map.put(row.(target), :original, Path.relative_to_cwd(path))
end

sources =
  for path <-
        ~w(extensions/knowledge/src/store/collection/producer.ex extensions/knowledge/src/store/collection/generation.ex extensions/knowledge/src/corpus.ex extensions/knowledge/src/profiles.ex extensions/knowledge/spec.exs extensions/knowledge/build.exs dev/knowledge/collection_recipe_model.ex test/extensions/knowledge/shared_producer_test.exs test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_session_test.exs),
      do: copy.(path, "source/" <> path)

sources =
  sources ++
    for(
      name <-
        ~w(initial-session-47137.exs executed-session-47138.exs executed-pure-47135.exs check-actual.exs),
      do: copy.("_build/shared-producer-evidence-20261029/" <> name, "source/" <> name)
    ) ++ [copy.(__ENV__.file, "freeze.exs")]

logs =
  for name <-
        ~w(shared-producer-build-47133.log shared-producer-pure-47134.log shared-producer-pure-47135.log shared-producer-session-47136.log shared-producer-session-47137.log shared-producer-session-47138.log shared-producer-pure-isolated-47139.log shared-producer-receipt-check-47140.log),
      do: copy.("_build/" <> name, name)

reports =
  for path <- Path.wildcard("_build/shared-producer-evidence-20261029/session-47138/*"),
      do: copy.(path, "actual/" <> Path.basename(path))

artifact = Path.expand("_build/shared-producer-corpus-20261029")

artifact_files =
  Path.wildcard(artifact <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

runtime = Path.expand("_build/shared-finalization-native-20261029/lib")

runtime_files =
  Path.wildcard(runtime <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

ancestors =
  for path <-
        ~w(docs/archive/2026-10-26-p30-p31-implementation/document-whole-recipe-ledger/manifest.json docs/archive/2026-10-26-p30-p31-implementation/document-compact-finalization-ledger/manifest.json),
      do: row.(path)

design =
  copy.(
    "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-v1-design.md",
    "design.md"
  )

manifest = %{
  version: 1,
  kind: "first_public_shared_page_receipt_flow",
  source: sources,
  logs: logs,
  reports: reports,
  artifact_files: artifact_files,
  runtime_files: runtime_files,
  ancestors: ancestors,
  design: design,
  limits:
    "one first1024D shared page, no facts/group completion/history provenance/public bootstrap/wholecapacity or GC/migration qualification",
  local_fixture:
    "47138 only, actual/tmp tmpfs and registered loopback synthetic provider; no external/paid model"
}

path = Path.join(archive, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(path),
      sources: length(sources),
      logs: length(logs),
      reports: length(reports),
      artifact_files: length(artifact_files),
      runtime_files: length(runtime_files)
    }, pretty: true)
)
