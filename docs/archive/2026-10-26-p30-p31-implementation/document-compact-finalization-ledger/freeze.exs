archive =
  Path.expand(
    "docs/archive/2026-10-26-p30-p31-implementation/document-compact-finalization-ledger"
  )

root = Path.expand("_build/document-recipe-ledger-20261029")
artifact = Path.expand("_build/generation-progress-corpus-sol-20261029")
false = File.exists?(archive)
File.mkdir_p!(archive)

row = fn path ->
  hash =
    File.stream!(path, 65_536, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)

  %{path: Path.relative_to_cwd(path), bytes: File.stat!(path).size, sha256: hash}
end

copy = fn source, name ->
  target = Path.join(archive, name)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(source, target)
  Map.put(row.(target), :original, Path.relative_to_cwd(source))
end

sources =
  for(
    name <- ~w(collection_recipe_ledger.exs collection_recipe_model.ex),
    do: copy.(Path.join([root, "cohort-47121", name]), "source/" <> name)
  ) ++
    [
      copy.(
        "dev/knowledge/collection_compact_ledger_report.exs",
        "source/collection_compact_ledger_report.exs"
      ),
      copy.(
        Path.join(root, "compact-report-before-digest-check-fix-47129.exs"),
        "source/initial-report-47129.exs"
      ),
      copy.(__ENV__.file, "freeze.exs")
    ]

logs =
  for name <-
        ~w(document-recipe-compact-artifact-47120.log document-recipe-compact-code-md5-47122.log document-recipe-ledger-verify-47127.log document-recipe-compact-comparison-47129.log document-recipe-compact-comparison-47130.log),
      do: copy.("_build/" <> name, name)

reports =
  for name <-
        ~w(compact-comparison-47130.json compact-finalization-47121/summary.json compact-finalization-47121/public-results.jsonl),
      do: copy.(Path.join(root, name), "reports/" <> name)

retained =
  for(path <- Path.wildcard(Path.join(root, "compact-finalization-47121/*")), do: row.(path)) ++
    [
      row.(Path.join(root, "private-full-47083/shared-appended-model.term")),
      row.(Path.join(root, "output-full-47092/summary.json")),
      row.(Path.join(root, "output-full-47092/invocations.jsonl")),
      row.("_build/document-recipe-compact-finalization-47121.log"),
      row.("_build/document-recipe-compact-summary-47128.log")
    ]

artifact_files =
  Path.wildcard(artifact <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

ancestor =
  row.(
    "docs/archive/2026-10-26-p30-p31-implementation/document-whole-recipe-ledger/manifest.json"
  )

true = ancestor.sha256 == "a06f8940224472bbb3da5feec88e26d97a70716a9eecc77dba410b2d8de4213f"

manifest = %{
  version: 1,
  kind: "new_compact_only_finalization_model",
  ancestor: ancestor,
  source: sources,
  logs: logs,
  reports: reports,
  retained: retained,
  artifact_files: artifact_files,
  runtime: "unchanged669-file frozenRoot2 host inventory pinned by ancestor",
  native_effects: 0,
  restrictions:
    "known synthetic checkpoint and fresh IDs, no native replay/acquisition/rebuild/model/capacity/Session adoption qualification"
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
      retained: length(retained),
      artifact_files: length(artifact_files)
    }, pretty: true)
)
