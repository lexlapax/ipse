root = "docs/archive/2026-10-26-p30-p31-implementation/embedding-selection-bootstrap"
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
b = File.read!(root <> "/manifest.json")
true = sha.(b) == "f28479373cf24fc3d82daae2e9f1c0b8370d0d137d557fcf0b39bf6157c071b9"
m = :json.decode(b)
check.(m["ancestor"])
for section <- ~w(sources retained), row <- m[section], do: check.(row)
walk = fn f, p ->
  case File.lstat!(p).type do
    :regular -> [Path.expand(p)]
    :symlink -> [Path.expand(p)]
    :directory -> Enum.flat_map(File.ls!(p), fn n -> f.(f, Path.join(p, n)) end)
  end
end
graphs = for g <- m["graphs"] do
  check.(g["inventory"])
  rows = File.read!(g["inventory"]["path"]) |> :json.decode()
  Enum.each(rows, check)
  true = length(rows) == g["files"]
  true = Enum.sort(Enum.map(rows, &Path.expand(&1["path"]))) == Enum.sort(walk.(walk, Path.expand(g["graph"] <> "/lib")))
  {g["graph"], Map.new(rows, fn r -> {Path.relative_to(r["path"], g["graph"]), Map.drop(r, ["path"])} end)}
end
[{_, base}, {_, final}] = graphs
true = Enum.sort(Map.keys(base)) == Enum.sort(Map.keys(final))
delta = for {p, r} <- base, final[p] != r, do: p
expected = ~w(Actions Host EmbeddingCall Inference ModelCall)
|> Enum.map(&"lib/ipse/ebin/Elixir.Ipse.Extension.#{&1}.beam")
|> Kernel.++(["lib/ipse/ebin/Elixir.Ipse.Session.Invocation.beam"])
true = Enum.sort(delta) == Enum.sort(expected)
IO.inspect(%{sources: length(m["sources"]), retained: length(m["retained"]), graphs: Enum.map(graphs, fn {n, rows} -> {n, map_size(rows), Enum.frequencies_by(Map.values(rows), & &1["type"])} end), delta: Enum.sort(delta)}, label: "EMBEDDING_SELECTION_BOOTSTRAP_OK")
