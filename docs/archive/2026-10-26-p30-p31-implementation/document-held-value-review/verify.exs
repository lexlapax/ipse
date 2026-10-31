root = "docs/archive/2026-10-26-p30-p31-implementation/document-held-value"
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
check = fn r ->
  case r["type"] do
    "regular" ->
      true = File.lstat!(r["path"]).type == :regular
      b = File.read!(r["path"])
      true = byte_size(b) == r["bytes"] and sha.(b) == r["sha256"]
    "symlink" -> true = File.read_link!(r["path"]) == r["target"]
  end
end
b = File.read!(root <> "/manifest.json")
true = sha.(b) == "86342fa9c06e719ef8c062d65cbfce419c575515033c90306d613f990f35679a"
m = :json.decode(b)
check.(m["ancestor"])
for k <- ~w(sources retained), r <- m[k], do: check.(r)
walk = fn f, p ->
  case File.lstat!(p).type do
    t when t in [:regular, :symlink] -> [Path.expand(p)]
    :directory -> Enum.flat_map(File.ls!(p), &f.(f, Path.join(p, &1)))
  end
end
graphs = for g <- m["graphs"] do
  check.(g["inventory"])
  rows = :json.decode(File.read!(g["inventory"]["path"]))
  Enum.each(rows, check)
  true = length(rows) == g["files"]
  physical = walk.(walk, g["graph"] <> "/_build/dev/lib") ++ walk.(walk, g["graph"] <> "/priv")
  true = Enum.sort(physical) == Enum.sort(Enum.map(rows, &Path.expand(&1["path"])))
  {g["graph"], Map.new(rows, fn r -> {Path.relative_to(r["path"], g["graph"]), Map.drop(r, ["path"])} end)}
end
[{_, prior}, {_, final}] = graphs
true = Enum.sort(Map.keys(prior)) == Enum.sort(Map.keys(final))
delta = for {p, r} <- final, prior[p] != r, do: p
true = delta == ["_build/dev/lib/ipse/ebin/Elixir.Ipse.Extension.Collection.DocumentStage.beam"]
source = hd(m["sources"])
true = File.read!(source["path"]) == File.read!("_build/document-held-value-sol-20261029/" <> source["source"])
IO.inspect(%{source_snapshots: length(m["sources"]), retained: length(m["retained"]), graph_nodes: Enum.map(graphs, fn {n, rows} -> {n, Enum.frequencies_by(Map.values(rows), & &1["type"])} end), delta: delta, repeated_tests: 0}, label: "DOCUMENT_HELD_VALUE_OK")
