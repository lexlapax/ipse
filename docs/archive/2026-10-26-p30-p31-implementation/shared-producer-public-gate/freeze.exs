dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-public-gate")
false = File.exists?(dir)
File.mkdir_p!(dir)

row = fn p ->
  %{
    path: Path.relative_to_cwd(p),
    bytes: File.stat!(p).size,
    sha256:
      File.stream!(p, 65536, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
  }
end

copy = fn p, n ->
  q = Path.join(dir, n)
  File.mkdir_p!(Path.dirname(q))
  File.cp!(p, q)
  Map.put(row.(q), :original, Path.relative_to_cwd(p))
end

source =
  for p <-
        ~w(extensions/knowledge/src/corpus.ex test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_test.exs test/extensions/knowledge/shared_producer_session_test.exs),
      do: copy.(p, "source/" <> p)

source = source ++ [copy.(__ENV__.file, "freeze.exs")]

logs =
  for n <-
        ~w(shared-producer-public-gate-47149.log shared-producer-gated-build-47150.log shared-producer-public-gate-session-47151.log),
      do: copy.("_build/" <> n, n)

reports =
  for p <- Path.wildcard("_build/shared-producer-worker-policy-20261029/public-gate-47151/*"),
      do: copy.(p, "actual/" <> Path.basename(p))

artifact = Path.expand("_build/shared-producer-gated-corpus-20261029")

files =
  Path.wildcard(artifact <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

runtime =
  Path.wildcard(Path.expand("_build/shared-finalization-native-20261029/lib") <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

ancestor =
  row.(
    "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-worker-policy-repair/manifest.json"
  )

true = ancestor.sha256 == "7f880bd4bc594fea9dfb8026c1aaa530e98b958ddf8f568bcb758b88225b9ad7"

m = %{
  version: 1,
  kind: "temporary_public_page_gate",
  source: source,
  logs: logs,
  reports: reports,
  artifact_files: files,
  runtime_files: runtime,
  ancestor: ancestor,
  scope:
    "47151 actual source/Job setup; zero additional actions/claims/inference for gated page; inspect read-only; Host source dispatch still open"
}

p = Path.join(dir, "manifest.json")
File.write!(p, Jason.encode!(m, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(p),
      source: length(source),
      logs: length(logs),
      reports: length(reports),
      artifact_files: length(files),
      runtime_files: length(runtime)
    }, pretty: true)
)
