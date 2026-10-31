root = "docs/archive/2026-10-26-p30-p31-implementation/document-packed-layout"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
check = fn path, metadata ->
  bytes = File.read!(path)
  true = byte_size(bytes) == (metadata["bytes"] || metadata["byte_count"])
  true = sha.(bytes) == metadata["sha256"]
end
bytes = File.read!(root <> "/manifest.json")
true = sha.(bytes) == "a95dd90c4430b68766dda279598bc327cc61b4534b3e324e9ebd13e8d90c3607"
m = :json.decode(bytes)
for section <- ["sources", "logs", "runtime"], {path, metadata} <- m[section], do: check.(path, metadata)
check.(m["helper"]["path"], m["helper"]["hash"])
check.(m["ancestor"]["path"], m["ancestor"]["hash"])
ancestor = File.read!(m["ancestor"]["path"]) |> :json.decode()
current_root = Path.expand("_build/document-layout-inventory-sol-20261029/lib")
old_root = Path.expand("_build/document-inventory-sol-20261029/lib")
current = Map.new(m["runtime"], fn {p,v} -> {Path.relative_to(p,current_root),v} end)
old = Map.new(ancestor["runtime"], fn {p,v} -> {Path.relative_to(p,old_root),v} end)
true = Enum.sort(Map.keys(current)) == Enum.sort(Map.keys(old))
changed = for {p,v} <- current, old[p]["sha256"] != v["sha256"], do: p
true = Enum.sort(changed) == ["ipse/ebin/Elixir.Ipse.Extension.Collection.DocumentStage.beam", "ipse/ebin/Elixir.Ipse.Extension.CollectionStore.beam"]
physical = fn walk, path ->
  case File.lstat!(path).type do
    :regular -> [Path.relative_to(path,current_root)]
    :directory -> Enum.flat_map(File.ls!(path), fn name -> walk.(walk,Path.join(path,name)) end)
    :symlink -> []
  end
end
regulars = physical.(physical,current_root)
true = Enum.all?(regulars, &Map.has_key?(current,&1))
resolved_extra = Map.keys(current) -- regulars
true = length(resolved_extra) == 9 and Enum.all?(resolved_extra, &String.starts_with?(&1,"telemetry/src/"))
true = m["helper"]["hash"]["sha256"] == "7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067"
IO.inspect(%{source_files: map_size(m["sources"]), log_files: map_size(m["logs"]), resolved_runtime_paths: map_size(current), physical_regular_files: length(regulars), inherited_symlink_source_paths: length(resolved_extra), changed_beams: Enum.sort(changed), inherited_unchanged_paths: map_size(current)-length(changed), helper_unchanged: true}, label: "DOCUMENT_PACKED_LAYOUT_MANIFEST_OK")
