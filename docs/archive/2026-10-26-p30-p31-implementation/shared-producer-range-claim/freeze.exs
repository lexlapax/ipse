dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-range-claim")
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

copy = fn path, relative ->
  target = Path.join(dir, relative)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(path, target)
  Map.put(row.(target), :original, Path.relative_to_cwd(path))
end

modules =
  ~w(profiles evidence store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer adapters documents documents/zip documents/docx documents/parser_stage documents/pdf)

sources =
  Enum.map(modules, &("extensions/knowledge/src/" <> &1 <> ".ex")) ++
    ~w(extensions/knowledge/src/corpus.ex test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_test.exs dev/knowledge/collection_recipe_model.ex)

source = Enum.map(sources, &copy.(&1, "source/" <> &1)) ++ [copy.(__ENV__.file, "freeze.exs")]

logs =
  for id <- ~w(47174 47175),
      do: copy.("_build/shared-producer-ranges-#{id}.log", "shared-producer-ranges-#{id}.log")

ancestor_paths =
  ~w(docs/archive/2026-10-26-p30-p31-implementation/shared-producer-selection-adoption/manifest.json docs/archive/2026-10-26-p30-p31-implementation/document-held-reader/manifest.json)

ancestors = Enum.map(ancestor_paths, row)
base = Jason.decode!(File.read!(hd(ancestor_paths)))
runtime = base["runtime"]

Enum.each(runtime, fn r ->
  if r["type"] == "symlink" do
    true = File.read_link!(r["path"]) == r["target"]
    true = File.lstat!(r["path"]).mode == r["mode"]
    true = File.lstat!(r["path"]).uid == r["uid"]
  else
    actual = row.(r["path"])
    true = actual.sha256 == r["sha256"] and actual.bytes == r["bytes"]
  end
end)

helper = row.(base["helper"]["path"])
true = helper.sha256 == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"

manifest = %{
  version: 1,
  kind: "private_producer_v3_exact_source_ranges_public_page_gated",
  source: source,
  logs: logs,
  ancestors: ancestors,
  runtime: runtime,
  helper: helper,
  scope:
    "47175 three focused private/model controls, thirteen excluded; new domain modules strictly compiled in fixture memory, no emitted domain BEAM cohort; no native/provider/public page acceptance",
  compatibility:
    "v2 five-field claims remain read-only inspectable and never replayable; v3 seven-field exact source ranges; adapter wire unchanged"
}

path = Path.join(dir, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(path),
      source: length(source),
      logs: length(logs),
      runtime: length(runtime),
      helper: helper.sha256
    }, pretty: true)
)
