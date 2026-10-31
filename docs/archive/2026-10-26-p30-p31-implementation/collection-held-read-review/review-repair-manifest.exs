root = "docs/archive/2026-10-26-p30-p31-implementation/collection-held-read-v2"
prior = "docs/archive/2026-10-26-p30-p31-implementation/collection-held-read"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
parse = fn path ->
  File.read!(path) |> String.split("\n",trim: true) |> Map.new(fn row ->
    [h,p] = String.split(row,"  ",parts: 2)
    {p,h}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "36cbbcca5a594b9b63f5ecbab63aab743c459ff9616bc7711eb843bd628c3edb"
true = sha.(File.read!(prior <> "/manifest.sha256")) == "d6432213d91cc9abeebd230861ca2a4bfa9b6d898dd7129d72d1c5a54849c934"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(p)) == h end)
{:ok,sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
source_map = Map.new(sources,fn {p,b} -> {List.to_string(p),b} end)
source_rows = parse.(root <> "/source.sha256")
true = Enum.sort(Map.keys(source_map)) == Enum.sort(Map.keys(source_rows))
Enum.each(source_rows,fn {p,h} -> true = sha.(source_map[p]) == h end)
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows,fn {p,h} -> true = sha.(File.read!(p)) == h end)
relative = fn map,graph -> Map.new(map,fn {p,h} -> {Path.relative_to(Path.expand(p),Path.expand(graph)),h} end) end
base = parse.(prior <> "/runtime.sha256") |> relative.("_build/collection-held-read-sol-20261029")
new = relative.(rows,"_build/collection-held-read-v2-sol-20261029")
true = Enum.sort(Map.keys(base)) == Enum.sort(Map.keys(new))
changed = for {p,h} <- base,new[p] != h,do: Path.basename(p)
["Elixir.Ipse.Extension.Collection.beam"] = changed
[{helper,h}] = Map.to_list(parse.(root <> "/helper.sha256"))
true = sha.(File.read!(helper)) == h
true = h == "a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995"
IO.inspect(%{manifest_entries: map_size(entries),source_files: map_size(source_map),runtime_files: map_size(rows),changed_from_initial: changed,helper_unchanged: true},label: "COLLECTION_HELD_READ_REPAIR_MANIFEST_OK")
