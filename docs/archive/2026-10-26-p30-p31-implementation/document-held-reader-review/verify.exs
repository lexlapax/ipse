root = "docs/archive/2026-10-26-p30-p31-implementation/document-held-reader"
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
check = fn r ->
  case r["type"] do
    "regular" ->
      true = File.lstat!(r["path"]).type == :regular
      b = File.read!(r["path"])
      true = byte_size(b) == r["bytes"] and sha.(b) == r["sha256"]
    "symlink" ->
      true = File.lstat!(r["path"]).type == :symlink
      true = File.read_link!(r["path"]) == r["target"]
  end
end
bytes = File.read!(root <> "/manifest.json")
true = sha.(bytes) == "848a8394f1fa2c4e72c7532a4d9ee4cb7c324a1587a96219d2e5c019a4f5fd44"
m = :json.decode(bytes)
for k <- ~w(host_source host_source_hashes), do: check.(m[k])
for k <- ~w(sources retained), r <- m[k], do: check.(r)
{:ok, members} = :erl_tar.extract(String.to_charlist(m["host_source"]["path"]), [:memory])
sources = Map.new(members, fn {p, b} -> {List.to_string(p), b} end)
hashes = for line <- String.split(File.read!(m["host_source_hashes"]["path"]), "\n", trim: true), into: %{} do
  [h, p] = String.split(line, "  ", parts: 2)
  true = sha.(Map.fetch!(sources, p)) == h
  {p, h}
end
true = map_size(sources) == 208 and map_size(hashes) == 208 and m["host_source_files"] == 208
true = Enum.sort(Map.keys(sources)) == Enum.sort(Map.keys(hashes))
collection = "lib/ipse/extension/collection.ex"
overlay = Enum.find(m["sources"], &(&1["source"] == collection))
for {p, h} <- hashes do
  true = sha.(File.read!("_build/p30-p31-integrated-source-20261029/" <> p)) == h
  expected = if p == collection, do: overlay["sha256"], else: h
  true = sha.(File.read!("_build/document-held-read-sol-20261029/" <> p)) == expected
end
walk = fn f, p ->
  case File.lstat!(p).type do
    t when t in [:regular, :symlink] -> [Path.expand(p)]
    :directory -> Enum.flat_map(File.ls!(p), &f.(f, Path.join(p, &1)))
  end
end
graphs = for g <- m["graphs"] do
  check.(g["inventory"])
  check.(g["helper"])
  true = g["helper"]["sha256"] == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"
  rows = :json.decode(File.read!(g["inventory"]["path"]))
  Enum.each(rows, check)
  true = length(rows) == g["files"]
  physical = walk.(walk, g["graph"] <> "/_build/dev/lib") ++ walk.(walk, g["graph"] <> "/priv")
  true = Enum.sort(Enum.map(rows, &Path.expand(&1["path"]))) == Enum.sort(physical)
  {g["graph"], Map.new(rows, fn r -> {Path.relative_to(r["path"], g["graph"]), Map.drop(r, ["path"])} end)}
end
[{_, base}, {_, final}] = graphs
true = Enum.sort(Map.keys(base)) == Enum.sort(Map.keys(final))
delta = for {p, r} <- final, base[p] != r, do: p
true = delta == ["_build/dev/lib/ipse/ebin/Elixir.Ipse.Extension.Collection.beam"]
IO.inspect(%{source_inputs: map_size(sources), source_delta: [collection], affected_snapshots: length(m["sources"]), retained_scripts_logs: length(m["retained"]), runtime_nodes: Enum.map(graphs, fn {n, rows} -> {n, map_size(rows), Enum.frequencies_by(Map.values(rows), & &1["type"])} end), runtime_delta: delta, helper_identical: true, repeated_tests: 0}, label: "DOCUMENT_HELD_READER_OK")
