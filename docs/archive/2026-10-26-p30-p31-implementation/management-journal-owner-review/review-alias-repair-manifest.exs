root = "docs/archive/2026-10-26-p30-p31-implementation/management-journal-owner-alias-repair"
previous = "docs/archive/2026-10-26-p30-p31-implementation/management-journal-owner"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "65284e7da1568b68bb3ef18f08b72fa6b0ca6020d1e274cf8a5225721884d412"
true = sha.(File.read!(previous <> "/manifest.sha256")) == "eaed2cef565540363d09c58bb5162bbb030245ed14f95367f59a4a066ead38c4"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {path, hash} -> true = sha.(File.read!(path)) == hash end)
{:ok, sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
source_map = Map.new(sources, fn {path, bytes} -> {List.to_string(path), bytes} end)
source_rows = parse.(root <> "/source.sha256")
true = length(source_rows) == map_size(source_map)
Enum.each(source_rows, fn {path, hash} -> true = sha.(Map.fetch!(source_map, path)) == hash end)
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows, fn {path, hash} -> true = sha.(File.read!(path)) == hash end)
old_graph = Path.expand("_build/management-journal-owner-v2-sol-20261029")
new_graph = Path.expand("_build/management-journal-owner-v3-sol-20261029")
relative = fn entries, graph -> Map.new(entries, fn {path, hash} -> {Path.relative_to(path, graph), hash} end) end
old_rows = relative.(parse.(previous <> "/runtime-standard.sha256"), old_graph)
new_rows = relative.(rows, new_graph)
true = Map.keys(old_rows) |> Enum.sort() == Enum.sort(Map.keys(new_rows))
changed = Enum.filter(new_rows, fn {p, hash} -> old_rows[p] != hash end) |> Enum.map(&elem(&1, 0))
["lib/ipse/ebin/Elixir.Ipse.Journal.beam"] = changed
[{helper, helper_sha}] = parse.(root <> "/helper.sha256")
true = sha.(File.read!(helper)) == helper_sha
true = helper_sha == "a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995"
IO.inspect(%{manifest_entries: length(entries), source_files: length(source_rows), runtime_files: length(rows), changed_runtime_files: changed, helper_unchanged: true}, label: "ALIAS_REPAIR_MANIFEST_OK")
