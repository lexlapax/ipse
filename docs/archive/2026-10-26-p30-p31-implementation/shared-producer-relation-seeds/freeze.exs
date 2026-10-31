dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-relation-seeds")
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
        ~w(test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_test.exs extensions/knowledge/src/store/collection/producer.ex extensions/knowledge/src/evidence.ex extensions/knowledge/src/documents.ex extensions/knowledge/src/documents/docx.ex extensions/knowledge/src/documents/zip.ex dev/knowledge/collection_recipe_model.ex),
      do: copy.(path, "source/" <> path)

source = source ++ [copy.(__ENV__.file, "freeze.exs")]

files =
  for name <- ~w(pending-v3-reverse-order.exs pending-v3-segmented-document.exs),
      do: copy.("_build/shared-producer-relation-seeds-20261029/" <> name, name)

files =
  files ++
    [
      copy.(
        "_build/shared-producer-relation-seeds-47180.log",
        "shared-producer-relation-seeds-47180.log"
      )
    ]

ancestors =
  Enum.map(
    ~w(docs/archive/2026-10-26-p30-p31-implementation/shared-producer-host-seed/manifest.json docs/archive/2026-10-26-p30-p31-implementation/shared-producer-range-claim/manifest.json),
    row
  )

manifest = %{
  version: 1,
  kind: "private_pending_model_reverse_catalog_and_extracted_docx_seeds",
  source: source,
  files: files,
  ancestors: ancestors,
  scope:
    "47180 two new seed controls only,seventeenexcluded; authentic private pending models before first inference; no native/provider authority; modeled operation IDs preserve uppercase format; frozen fixture consumers are deterministic, generating new production job IDs/epochs is intentionally random",
  domain_source_unchanged: true
}

path = Path.join(dir, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(path),
      sources: length(source),
      files: length(files),
      ancestors: length(ancestors)
    }, pretty: true)
)
