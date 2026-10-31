root = "docs/archive/2026-10-26-p30-p31-implementation/management-journal-owner"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "eaed2cef565540363d09c58bb5162bbb030245ed14f95367f59a4a066ead38c4"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {path, hash} -> true = sha.(File.read!(path)) == hash end)
{:ok, sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
source_map = Map.new(sources, fn {path, bytes} -> {List.to_string(path), bytes} end)
source_rows = parse.(root <> "/source.sha256")
true = length(source_rows) == map_size(source_map)
Enum.each(source_rows, fn {path, hash} -> true = sha.(Map.fetch!(source_map, path)) == hash end)
counts = for suffix <- ["standard", "hook", "old"] do
  rows = parse.(root <> "/runtime-" <> suffix <> ".sha256")
  Enum.each(rows, fn {path, hash} -> true = sha.(File.read!(path)) == hash end)
  [{helper, helper_sha}] = parse.(root <> "/helper-" <> suffix <> ".sha256")
  true = sha.(File.read!(helper)) == helper_sha
  true = Enum.member?(rows, {helper, helper_sha})
  {suffix, length(rows), helper_sha}
end
IO.inspect(%{manifest_entries: length(entries), source_files: length(source_rows), runtimes: counts}, label: "MANAGEMENT_OWNER_MANIFEST_OK")
