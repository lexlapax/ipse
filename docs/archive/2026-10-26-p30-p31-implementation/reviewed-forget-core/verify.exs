Path.wildcard("_build/reviewed-forget-cli-sol-20261029/lib/*/ebin")
|> Enum.each(&Code.prepend_path/1)
archive = "docs/archive/2026-10-26-p30-p31-implementation/reviewed-forget-core"
hash = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
manifest_bytes = File.read!(archive <> "/manifest.json")
"47ec7ccfc5cd45581b5d21679eeed4f0533afe536d992072070af770ae477544" = hash.(manifest_bytes)
m = Jason.decode!(manifest_bytes)
verify = fn row ->
  case row["type"] do
    "symlink" ->
      :symlink = File.lstat!(row["path"]).type
      true = File.read_link!(row["path"]) == row["target"]
    "regular" ->
      :regular = File.lstat!(row["path"]).type
      bytes = File.read!(row["path"])
      true = byte_size(bytes) == row["bytes"] and hash.(bytes) == row["sha256"]
  end
end
Enum.each(m["sources"] ++ m["launches_and_logs"] ++ m["freeze_helpers"], verify)
graphs = Enum.map(m["graphs"], fn graph ->
  verify.(graph["inventory"])
  rows = graph["inventory"]["path"] |> File.read!() |> Jason.decode!()
  true = length(rows) == graph["files"]
  Enum.each(rows, verify)
  Map.new(rows, fn row ->
    {Path.relative_to(row["path"], graph["graph"] <> "/lib"), Map.drop(row, ["path"])}
  end)
end)
[original, core, cli] = graphs
delta = fn before, later ->
  true = Map.keys(before) |> Enum.sort() == (Map.keys(later) |> Enum.sort())
  Enum.filter(Map.keys(before), &(before[&1] != later[&1])) |> Enum.sort()
end
["ipse/ebin/Elixir.Ipse.Extension.Collection.beam"] = delta.(original, core)
["ipse/ebin/Elixir.Ipse.CLI.Errors.beam", "ipse/ebin/Elixir.Ipse.CLI.Knowledge.beam"] = delta.(core, cli)
IO.puts("Verified 6 source snapshots, 8 launch/log files, 2 freeze helpers, 3 inventories and all 2097 runtime entries; exact one-then-two BEAM deltas")
