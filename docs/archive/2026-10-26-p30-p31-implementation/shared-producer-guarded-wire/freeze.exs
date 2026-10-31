dir = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-producer-guarded-wire")
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

modules =
  ~w(profiles evidence store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer adapters documents documents/zip documents/docx documents/parser_stage documents/pdf)

paths =
  Enum.map(modules, &("extensions/knowledge/src/" <> &1 <> ".ex")) ++
    ~w(extensions/knowledge/src/corpus.ex test/support/shared_producer_fixture.exs test/extensions/knowledge/shared_producer_test.exs dev/knowledge/collection_recipe_model.ex)

source = Enum.map(paths, &copy.(&1, "source/" <> &1)) ++ [copy.(__ENV__.file, "freeze.exs")]
sdk_root = "_build/document-embedding-sdk-sol-20261029"

sdk_source =
  for path <-
        ~w(lib/ipse/extension/collection_store.ex lib/ipse/extension/inference.ex lib/ipse/extension/actions.ex),
      do: copy.(sdk_root <> "/" <> path, "sdk-source/" <> path)

logs = [
  copy.(
    "_build/shared-producer-guard-adapter-47187.log",
    "shared-producer-guard-adapter-47187.log"
  ),
  copy.("_build/shared-producer-guard-flow-47193.log", "shared-producer-guard-flow-47193.log")
]

sdk_build =
  for path <-
        ~w(/tmp/ipse-document-embedding-sdk-47191.exs /tmp/ipse-document-embedding-sdk-47191.log /tmp/ipse-document-embedding-sdk-47192.exs /tmp/ipse-document-embedding-sdk-47192.log),
      do: copy.(path, Path.basename(path))

walk = fn root ->
  visit = fn visit, path ->
    stat = File.lstat!(path)

    case stat.type do
      :directory ->
        File.ls!(path) |> Enum.sort() |> Enum.flat_map(&visit.(visit, Path.join(path, &1)))

      :regular ->
        [Map.put(row.(path), :type, "regular")]

      :symlink ->
        [%{path: Path.relative_to_cwd(path), type: "symlink", target: File.read_link!(path)}]
    end
  end

  visit.(visit, root)
end

graphs =
  for root <- ["_build/document-source-use-sol-20261029", sdk_root],
      do: %{root: root, rows: walk.(root <> "/_build/dev/lib") ++ walk.(root <> "/priv")}

indexed = fn graph ->
  Map.new(graph.rows, fn r -> {Path.relative_to(r.path, graph.root), Map.delete(r, :path)} end)
end

[parent, sdk] = graphs
a = indexed.(parent)
b = indexed.(sdk)
added = Map.keys(b) -- Map.keys(a)
removed = Map.keys(a) -- Map.keys(b)
changed = for {path, value} <- a, Map.has_key?(b, path), b[path] !== value, do: path
true = added == [] and removed == []
helper = row.(sdk_root <> "/priv/ipse-runner")
true = helper.sha256 == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"

ancestors =
  Enum.map(
    ~w(shared-producer-selection-adoption/manifest.json shared-producer-range-claim/manifest.json document-source-use/manifest.json),
    &row.("docs/archive/2026-10-26-p30-p31-implementation/" <> &1)
  )

manifest = %{
  version: 1,
  kind: "worker_guarded_embedding_v2_wire_public_page_gated",
  source: source,
  sdk_source: sdk_source,
  logs: logs,
  sdk_build: sdk_build,
  graphs: graphs,
  helper: helper,
  ancestors: ancestors,
  runtime_delta: %{added: added, removed: removed, changed: Enum.sort(changed)},
  scope:
    "47187 two new adapter-only controls on earlier held-reader SDK;47193 one new fourbatch/unknown private model control on new guarded SDK, no older range/selection positives rerun; domain modules compiled in memory; no Session admission/native/provider/public acceptance"
}

path = Path.join(dir, "manifest.json")
File.write!(path, Jason.encode!(manifest, pretty: true), [:exclusive])

IO.puts(
  Jason.encode!(
    %{
      manifest: row.(path),
      source: length(source),
      sdk_source: length(sdk_source),
      logs: length(logs),
      sdk_build: length(sdk_build),
      graph_rows: Enum.map(graphs, &length(&1.rows)),
      delta: manifest.runtime_delta
    }, pretty: true)
)
