Path.wildcard("_build/literal-v4-ab-current2-sol-20261029/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
root = "docs/archive/2026-10-26-p30-p31-implementation/literal-v4-source-union"
manifest = Jason.decode!(File.read!(Path.join(root, "manifest.json")))
Enum.each(manifest["files"], fn {path, expected} ->
  bytes = File.read!(Path.join(root, path))
  true = byte_size(bytes) == expected["bytes"]
  true = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == expected["sha256"]
end)
runtime = Jason.decode!(File.read!(Path.join(root, "runtime.json")))
IO.puts("LITERAL_MANIFEST_REVIEW_OK artifacts=#{map_size(manifest["files"])}")
IO.inspect(Map.keys(runtime), label: "INVENTORY_FIELDS")
