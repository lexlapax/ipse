root = "docs/archive/2026-10-26-p30-p31-implementation/management-held-target"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
parse = fn p -> File.read!(p) |> String.split("\n",trim: true) |> Map.new(fn row -> [h,f] = String.split(row,"  ",parts: 2); {f,h} end) end
true = sha.(File.read!(root <> "/manifest.sha256")) == "65505253ebcc71b826a5849829f8e9703a41b11369f90cd6567f36aad49a7d09"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(p)) == h end)
{:ok,sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
source_map = Map.new(sources,fn {p,b} -> {List.to_string(p),b} end)
source_rows = parse.(root <> "/source.sha256")
true = Enum.sort(Map.keys(source_map)) == Enum.sort(Map.keys(source_rows))
Enum.each(source_rows,fn {p,h} -> true = sha.(source_map[p]) == h end)
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows,fn {p,h} -> true = sha.(File.read!(p)) == h end)
relative = fn m,g -> Map.new(m,fn {p,h} -> {Path.relative_to(Path.expand(p),Path.expand(g)),h} end) end
base = parse.("docs/archive/2026-10-26-p30-p31-implementation/collection-held-read-v2/runtime.sha256") |> relative.("_build/collection-held-read-v2-sol-20261029")
new = relative.(rows,"_build/management-held-target-sol-20261029")
true = Enum.sort(Map.keys(base)) == Enum.sort(Map.keys(new))
changed = for {p,h} <- base,new[p] != h,do: Path.basename(p)
["Elixir.Ipse.Extension.Collection.ObservedRead.beam"] = changed
[{helper,h}] = Map.to_list(parse.(root <> "/helper.sha256"))
true = sha.(File.read!(helper)) == h
true = h == "a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995"
IO.inspect(%{manifest_entries: map_size(entries),source_files: map_size(source_map),runtime_files: map_size(rows),changed_from_collection_v2: changed,helper_unchanged: true},label: "HELD_TARGET_MANIFEST_OK")
