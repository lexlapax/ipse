dir =
  Path.expand(
    "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-worker-policy-repair"
  )

false = File.exists?(dir)
File.mkdir_p!(dir)

row = fn path ->
  %{
    path: Path.relative_to_cwd(path),
    bytes: File.stat!(path).size,
    sha256:
      File.stream!(path, 65536, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
  }
end

copy = fn path, name ->
  target = Path.join(dir, name)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(path, target)
  Map.put(row.(target), :original, Path.relative_to_cwd(path))
end

source =
  for p <-
        ~w(extensions/knowledge/src/store/collection/producer.ex test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_test.exs),
      do: copy.(p, "source/" <> p)

source = source ++ [copy.(__ENV__.file, "freeze.exs")]

logs =
  for name <-
        ~w(shared-producer-policy-original-47145.log shared-producer-worker-policy-47146.log shared-producer-worker-build-47147.log),
      do: copy.("_build/" <> name, name)

artifact = Path.expand("_build/shared-producer-policy-corpus-20261029")

files =
  Path.wildcard(artifact <> "/**/*")
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()
  |> Enum.map(row)

ancestor =
  row.("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-first-page/manifest.json")

true = ancestor.sha256 == "92c215154e5d948f66f02adb12af21793f9619d3c69cdb83a5a66c9c1d6a5245"

m = %{
  version: 1,
  kind: "worker_only_policy_partial_repair_hold",
  source: source,
  logs: logs,
  artifact_files: files,
  ancestor: ancestor,
  runtime: "unchangedRoot2 host graph pinned by ancestor; no new native/model run",
  scope: "before public dispatch gate; worker checks do not fence human approval/actual send"
}

p = Path.join(dir, "manifest.json")
File.write!(p, Jason.encode!(m, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(p),
      source: length(source),
      logs: length(logs),
      artifact_files: length(files)
    }, pretty: true)
)
