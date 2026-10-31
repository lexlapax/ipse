dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-host-seed")
false = File.exists?(dir)
File.mkdir_p!(dir)

row = fn path ->
  bytes = File.read!(path)

  %{
    path: Path.relative_to_cwd(path),
    bytes: byte_size(bytes),
    sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  }
end

copy = fn path, name ->
  target = Path.join(dir, name)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(path, target)
  Map.put(row.(target), :original, Path.relative_to_cwd(path))
end

source =
  for path <-
        ~w(extensions/knowledge/src/store/collection/producer.ex test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_test.exs),
      do: copy.(path, "source/" <> path)

files = [
  copy.("_build/shared-producer-ranges-20261029/pending-v3-model.exs", "pending-v3-model.exs"),
  copy.(
    "_build/shared-producer-ranges-20261029/host-seed-tested-47177.exs",
    "host-seed-tested-47177.exs"
  ),
  copy.("_build/shared-producer-host-seed-47177.log", "shared-producer-host-seed-47177.log"),
  copy.(
    "_build/shared-producer-host-seed-default-47178.log",
    "shared-producer-host-seed-default-47178.log"
  ),
  copy.(__ENV__.file, "freeze-seed.exs")
]

ancestor =
  row.("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-range-claim/manifest.json")

true = ancestor.sha256 == "c464ec617ef4d403f47582068de49f749185263d0a95361ef6ddb5acd84d5d12"

manifest = %{
  version: 1,
  kind: "synthetic_v3_pending_relation_before_first_inference",
  source: source,
  files: files,
  ancestor: ancestor,
  scope:
    "47177 emitted trusted Elixir fixture from actual private producer over closed model;47178 same fixture has optional serialization; no native record history/inference/authority; claim modeled operation ID carried separately, other retained opIDs nil"
}

path = Path.join(dir, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(path),
      sources: length(source),
      files: length(files),
      ancestor: ancestor.sha256
    }, pretty: true)
)
