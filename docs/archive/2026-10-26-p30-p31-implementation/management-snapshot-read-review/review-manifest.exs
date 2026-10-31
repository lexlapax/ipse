parent = "docs/archive/2026-10-26-p30-p31-implementation"
root = parent <> "/management-snapshot-read-v2"
sha = fn bytes -> :crypto.hash(:sha256,bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  File.read!(path) |> String.split("\n",trim: true) |> Map.new(fn row ->
    [h,p] = String.split(row,"  ",parts: 2)
    {p,h}
  end)
end
counts = for {dir,pin} <- [
  {root,"01ccdeba3b75a58906000ac8836c6f25e3cca6a2d65f2a34a8aabb31805dab0c"},
  {parent <> "/management-snapshot-read","c4e5e67128cde8c71b4d3f968f05fc27f493aa69cea33edc206032bd035be42e"}
] do
  true = sha.(File.read!(dir <> "/manifest.sha256")) == pin
  entries = parse.(dir <> "/manifest.sha256")
  Enum.each(entries,fn {p,h} -> true = sha.(File.read!(p)) == h end)
  {:ok,sources} = :erl_tar.extract(String.to_charlist(dir <> "/source.tar"),[:memory])
  source_map = Map.new(sources,fn {p,b} -> {List.to_string(p),b} end)
  source_rows = parse.(dir <> "/source.sha256")
  true = Enum.sort(Map.keys(source_rows)) == Enum.sort(Map.keys(source_map))
  Enum.each(source_rows,fn {p,h} -> true = sha.(source_map[p]) == h end)
  rows = parse.(dir <> "/runtime.sha256")
  Enum.each(rows,fn {p,h} -> true = sha.(File.read!(p)) == h end)
  {Path.basename(dir),%{manifest_entries: map_size(entries),sources: map_size(source_map),runtime_files: map_size(rows)}}
end
new = parse.(root <> "/runtime.sha256")
base = parse.(parent <> "/management-journal-owner-alias-repair/runtime.sha256")
relative = fn rows,graph -> Map.new(rows,fn {p,h} -> {Path.relative_to(Path.expand(p),Path.expand(graph)),h} end) end
new = relative.(new,"_build/management-snapshot-read-v2-sol-20261029")
base = relative.(base,"_build/management-journal-owner-v3-sol-20261029")
true = Enum.sort(Map.keys(new)) == Enum.sort(Map.keys(base))
changed = for {p,h} <- new,base[p] != h,do: Path.basename(p)
["Elixir.Ipse.Extension.Consent.beam"] = changed
[{helper,h}] = Map.to_list(parse.(root <> "/helper.sha256"))
true = sha.(File.read!(helper)) == h
true = h == "a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995"
IO.inspect(%{cohorts: counts, changed_from_journal_v3: changed,helper_unchanged: true},label: "MANAGEMENT_SNAPSHOT_MANIFEST_OK")
