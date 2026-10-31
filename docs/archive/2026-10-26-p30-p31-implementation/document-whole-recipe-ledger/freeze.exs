root = Path.expand("_build/document-recipe-ledger-20261029")

archive =
  Path.expand("docs/archive/2026-10-26-p30-p31-implementation/document-whole-recipe-ledger")

false = File.exists?(archive)
File.mkdir_p!(archive)

hash = fn path ->
  File.stream!(path, 65_536, [])
  |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
  |> :crypto.hash_final()
  |> Base.encode16(case: :lower)
end

row = fn path ->
  %{path: Path.relative_to_cwd(path), bytes: File.stat!(path).size, sha256: hash.(path)}
end

copy = fn source, relative ->
  dest = Path.join(archive, relative)
  File.mkdir_p!(Path.dirname(dest))
  File.cp!(source, dest)
  Map.put(row.(dest), :original, Path.relative_to_cwd(source))
end

sources =
  Enum.flat_map(~w(cohort-47083 cohort-47085 cohort-47092 cohort-47095-47096), fn cohort ->
    for path <- Path.wildcard(Path.join([root, cohort, "*.ex*"])),
        do: copy.(path, "source/" <> cohort <> "/" <> Path.basename(path))
  end) ++
    for(
      name <-
        ~w(collection_artifact_geometry.exs collection_recipe_costs.exs collection_recipe_report.exs collection_journal_measure.exs),
      do: copy.("dev/knowledge/" <> name, "source/final/" <> name)
    ) ++
    [copy.(__ENV__.file, "freeze.exs")]

small_logs =
  for name <- ~w(
    document-recipe-ledger-session-47085.log
    document-recipe-ledger-journal-verified-47088.log
    document-recipe-ledger-checkpoint-match-47094.log
    document-recipe-ledger-import-minimum-47098.log
    document-recipe-ledger-rebuild-summary-47108.log
    document-recipe-geometry-pilot-47109.log
    document-recipe-geometry-rebuild-47110.log
    document-recipe-ledger-rebuild-report-47111.log
    document-recipe-ledger-combined-report-47113.log
    document-recipe-geometry-initial-47114.log
    document-recipe-ledger-costs-47115.log
  ),
      do: copy.("_build/" <> name, name)

reports =
  for relative <- ~w(
    initial-report-47093.json rebuild-report-47111.json combined-report-47113.json
    costs-47115.json journal-verified-47088.json
    geometry-rebuild-47110/summary.json geometry-rebuild-47110/records.json
    geometry-initial-47114/summary.json geometry-initial-47114/records.json
    transport-full-47095/per-value-transport.json
    transport-rebuild-47112/per-value-transport.json
    session-47085/synthetic-first.jsonl session-47085/synthetic-second.jsonl
  ),
      do: copy.(Path.join(root, relative), "reports/" <> relative)

reports = reports ++ [copy.(Path.join(root, "HANDOFF.md"), "reports/HANDOFF-at-freeze.md")]

retained =
  Path.wildcard(Path.join(root, "**/*"))
  |> Enum.filter(&File.regular?/1)
  |> Enum.reject(&String.ends_with?(&1, "/freeze.exs"))
  |> Enum.reject(&String.ends_with?(&1, "/HANDOFF.md"))
  |> Enum.sort()
  |> Enum.map(row)

artifact =
  Path.expand(
    "_build/shared-finalization-native-20261029/root2-public-artifacts-47072/95b9ffe3a1a00496b14ccbbeecd245f2306cf8bb096247cbffbc19a1b3b6cb55"
  )

runtime = Path.expand("_build/shared-finalization-native-20261029/lib")

runtime_files =
  Path.wildcard(runtime <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

artifact_files =
  Path.wildcard(artifact <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

original_logs =
  Path.wildcard("_build/document-recipe*log")
  |> Enum.reject(&String.contains?(&1, "-freeze-"))
  |> Enum.sort()
  |> Enum.map(row)

ancestors =
  for path <- ~w(
    docs/archive/2026-10-26-p30-p31-implementation/shared-directory-v2-implementation/manifest.json
    docs/archive/2026-10-26-p30-p31-implementation/document-packed-layout/manifest.json
  ),
      do: row.(path)

manifest = %{
  version: 1,
  kind: "document_whole_recipe_closed_model_and_small_actual_session_ledger",
  actual_native_populated_effects: 0,
  actual_session: "47085 only, two 5320-byte supplied plaintext sources",
  synthetic_generation_seed: 1000,
  runtime_files: runtime_files,
  artifact_files: artifact_files,
  ancestors: ancestors,
  source: sources,
  logs: small_logs,
  reports: reports,
  retained_build_files: retained,
  retained_original_logs: original_logs,
  limits:
    "no native model-store objects/receipts or complete intermediate legacy output objects retained; no complete public producer, artifact import, metadata/orphan/terminal peak or full qualification",
  permanent_history: "32768 operation IDs;8192 live map keys, not lifetime names"
}

path = Path.join(archive, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(path),
      sources: length(sources),
      logs: length(small_logs),
      reports: length(reports),
      retained: length(retained),
      runtime_files: length(runtime_files),
      artifact_files: length(artifact_files)
    },
    pretty: true
  )
)
