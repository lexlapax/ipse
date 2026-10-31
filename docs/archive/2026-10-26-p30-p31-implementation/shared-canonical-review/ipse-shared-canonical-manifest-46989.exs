root = Path.expand("docs/archive/2026-10-26-p30-p31-implementation/shared-projection-canonical-fact")
Path.wildcard("_build/shared-projection-codec-20261029/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
manifest = Jason.decode!(File.read!(Path.join(root, "manifest.json")))
verify = fn path, expected ->
  bytes = File.read!(path)
  hash = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  true = hash == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
Enum.each(manifest["sources"], fn {path, expected} -> verify.(Path.join(manifest["source_snapshot"], path), expected) end)
Enum.each(manifest["artifact_files"], fn {path, expected} -> verify.(Path.join(manifest["artifact"], path), expected) end)
Enum.each(manifest["logs"], fn {path, expected} -> verify.(Path.join(root, path), expected) end)
previous = File.read!(manifest["previous_manifest"])
true = Base.encode16(:crypto.hash(:sha256, previous), case: :lower) == manifest["previous_manifest_sha256"]
IO.puts("CANONICAL_REPAIR_MANIFEST_OK sources=#{map_size(manifest["sources"])} artifact_files=#{map_size(manifest["artifact_files"])} logs=#{map_size(manifest["logs"])} previous_manifest=true")
