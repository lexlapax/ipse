root = "docs/archive/2026-10-26-p30-p31-implementation/reviewed-forget-core"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
check = fn r ->
  case r["type"] do
    "regular" -> true = File.lstat!(r["path"]).type == :regular; b=File.read!(r["path"]); true = byte_size(b)==r["bytes"] and sha.(b)==r["sha256"]
    "symlink" -> true = File.lstat!(r["path"]).type == :symlink; true = File.read_link!(r["path"]) == r["target"]
  end
end
bytes = File.read!(root <> "/manifest.json")
true = sha.(bytes) == "47ec7ccfc5cd45581b5d21679eeed4f0533afe536d992072070af770ae477544"
m = :json.decode(bytes)
for section <- ~w(sources launches_and_logs freeze_helpers), row <- m[section], do: check.(row)
walk = fn f,p -> case File.lstat!(p).type do :regular -> [Path.expand(p)]; :symlink -> [Path.expand(p)]; :directory -> Enum.flat_map(File.ls!(p),fn n -> f.(f,Path.join(p,n)) end) end end
graphs = for g <- m["graphs"] do
  check.(g["inventory"])
  rows = File.read!(g["inventory"]["path"]) |> :json.decode()
  Enum.each(rows,check)
  true = length(rows) == g["files"]
  true = Enum.sort(Enum.map(rows,&Path.expand(&1["path"]))) == Enum.sort(walk.(walk,Path.expand(g["graph"] <> "/lib")))
  {g["graph"],Map.new(rows,fn r -> {Path.relative_to(r["path"],g["graph"]),Map.drop(r,["path"])} end)}
end
[{_,base},{_,core},{_,cli}] = graphs
true = Enum.sort(Map.keys(base)) == Enum.sort(Map.keys(core)) and Enum.sort(Map.keys(core)) == Enum.sort(Map.keys(cli))
delta = fn a,b -> for {p,r} <- a, b[p] != r, do: p end
["lib/ipse/ebin/Elixir.Ipse.Extension.Collection.beam"] = delta.(base,core)
true = Enum.sort(delta.(core,cli)) == ["lib/ipse/ebin/Elixir.Ipse.CLI.Errors.beam", "lib/ipse/ebin/Elixir.Ipse.CLI.Knowledge.beam"]
IO.inspect(%{source_snapshots: length(m["sources"]), launch_logs: length(m["launches_and_logs"]), freeze_helpers: length(m["freeze_helpers"]), inventories: Enum.map(graphs,fn {n,r} -> {n,map_size(r),Enum.frequencies_by(Map.values(r),& &1["type"])} end), core_delta: delta.(base,core), cli_delta: Enum.sort(delta.(core,cli))},label: "REVIEWED_FORGET_CORE_OK")
