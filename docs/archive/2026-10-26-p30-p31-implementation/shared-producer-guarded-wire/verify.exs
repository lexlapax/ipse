base = "docs/archive/2026-10-26-p30-p31-implementation/"
manifest_path = base <> "shared-producer-guarded-wire/manifest.json"
expected = "fc79fe5cef7190e5b2a0f6414b1107e9470f39758e566c6d759a2e0a8a558388"

sha = fn path ->
  File.stream!(path, 65_536, [])
  |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
  |> :crypto.hash_final()
  |> Base.encode16(case: :lower)
end

^expected = sha.(manifest_path)
m = Jason.decode!(File.read!(manifest_path))

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

rows = collect.(collect, m)

Enum.each(rows, fn row ->
  if row["type"] == "symlink" do
    true = File.lstat!(row["path"]).type == :symlink
    true = File.read_link!(row["path"]) === row["target"]
  else
    true = File.stat!(row["path"]).size == row["bytes"]
    true = sha.(row["path"]) == row["sha256"]
  end
end)

ancestor = Jason.decode!(File.read!(base <> "document-source-use/manifest.json"))
[parent, sdk] = m["graphs"]
ancestor_parent = Enum.find(ancestor["graphs"], &(&1["graph"] === parent["root"]))
true = Jason.decode!(File.read!(ancestor_parent["inventory"]["path"])) === parent["rows"]

index = fn graph ->
  Map.new(graph["rows"], fn row ->
    {Path.relative_to(row["path"], graph["root"]), Map.delete(row, "path")}
  end)
end

a = index.(parent)
b = index.(sdk)
true = Map.keys(a) |> Enum.sort() == Map.keys(b) |> Enum.sort()
changed = Enum.filter(Map.keys(a), &(a[&1] !== b[&1])) |> Enum.sort()
true = changed === m["runtime_delta"]["changed"]

IO.puts(
  Jason.encode!(
    %{
      manifest_sha256: expected,
      exact_rows_verified: length(rows),
      graph_rows: Enum.map(m["graphs"], &length(&1["rows"])),
      sdk_sources: length(m["sdk_source"]),
      source_snapshots: length(m["source"]),
      source_use_parent_inventory_exact: true,
      runtime_delta: m["runtime_delta"],
      no_tests_or_effects: true
    }, pretty: true)
)
