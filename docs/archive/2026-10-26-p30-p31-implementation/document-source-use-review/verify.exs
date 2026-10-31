base = "docs/archive/2026-10-26-p30-p31-implementation/"
manifest_path = base <> "document-source-use/manifest.json"
expected = "77ec4fd5cfb91e1d7be513f3c2aea0eb2d2a5a5841312f189d153b17d2f0371b"

sha = fn path ->
  File.stream!(path, 65_536, [])
  |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
  |> :crypto.hash_final()
  |> Base.encode16(case: :lower)
end

^expected = sha.(manifest_path)
decode = fn path -> Jason.decode!(File.read!(path)) end

verify = fn row ->
  path = row["path"]

  if row["type"] == "symlink" do
    true = File.lstat!(path).type == :symlink
    true = File.read_link!(path) == row["target"]
    if row["mode"], do: true = File.lstat!(path).mode == row["mode"]
    if row["uid"], do: true = File.lstat!(path).uid == row["uid"]
  else
    true = File.stat!(path).size == row["bytes"]
    true = sha.(path) == row["sha256"]
  end
end

collect = fn collect, value ->
  cond do
    is_map(value) and is_binary(value["path"]) and
        (is_binary(value["sha256"]) or value["type"] == "symlink") ->
      [value]

    is_map(value) ->
      Enum.flat_map(Map.values(value), &collect.(collect, &1))

    is_list(value) ->
      Enum.flat_map(value, &collect.(collect, &1))

    true ->
      []
  end
end

m = decode.(manifest_path)
rows = collect.(collect, m)
Enum.each(rows, verify)

Enum.each(m["sources"], fn row ->
  true = sha.(row["source"]) == row["sha256"]
end)

graphs =
  Enum.map(m["graphs"], fn graph ->
    inventory = decode.(graph["inventory"]["path"])
    true = length(inventory) == graph["files"]
    Enum.each(inventory, verify)
    %{root: graph["graph"], rows: inventory}
  end)

[parent, candidate] = graphs

indexed = fn graph ->
  Map.new(graph.rows, fn row ->
    {Path.relative_to(row["path"], graph.root), Map.delete(row, "path")}
  end)
end

parent_index = indexed.(parent)
candidate_index = indexed.(candidate)
Enum.each(parent_index, fn {path, row} -> true = candidate_index[path] === row end)
added = Map.keys(candidate_index) -- Map.keys(parent_index)

true =
  added === ["_build/dev/lib/ipse/ebin/Elixir.Ipse.Extension.Collection.DocumentSourceUse.beam"]

held_value = decode.(hd(m["ancestors"])["path"])
held_parent = Enum.find(held_value["graphs"], &(&1["graph"] == parent.root))
true = held_parent["inventory"]["sha256"] === hd(m["graphs"])["inventory"]["sha256"]

ancestor_rows =
  Enum.flat_map(m["ancestors"], fn ancestor ->
    rows = decode.(ancestor["path"]) |> then(&collect.(collect, &1))
    Enum.each(rows, verify)
    rows
  end)

helpers =
  for graph <- graphs do
    row = Enum.find(graph.rows, &String.ends_with?(&1["path"], "/priv/ipse-runner"))
    true = row["sha256"] == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"
    row["sha256"]
  end

source_snapshots = hd(m["sources"])["path"]

true =
  File.read!(source_snapshots) ==
    File.read!("lib/ipse/extension/collection/document_source_use.ex")

IO.puts(
  Jason.encode!(
    %{
      manifest_sha256: expected,
      direct_manifest_rows: length(rows),
      source_snapshots: length(m["sources"]),
      retained: length(m["retained"]),
      graph_rows: Enum.map(graphs, &length(&1.rows)),
      graph_regular:
        Enum.map(graphs, fn graph -> Enum.count(graph.rows, &(&1["type"] == "regular")) end),
      ancestors: length(m["ancestors"]),
      ancestor_bound_rows: length(ancestor_rows),
      exact_added_runtime_paths: added,
      inherited_graph_inventory_matches: true,
      helpers: helpers,
      no_tests_or_effects: true
    }, pretty: true)
)
