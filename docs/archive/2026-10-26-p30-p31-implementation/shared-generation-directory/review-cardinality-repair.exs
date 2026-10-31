path = "docs/archive/2026-10-26-p30-p31-implementation/shared-directory-cardinality/manifest.json"
m = Jason.decode!(File.read!(path))
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
true = sha.(File.read!(path)) == "223c621005fa500c6f3159dce3296d4ac651ce044319d9e9d17f24d7eb85d1c0"
check = fn file, expected ->
  bytes = File.read!(file)
  true = sha.(bytes) == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
Enum.each(m["sources"], fn {p, h} -> check.(Path.join(m["source_snapshot"], p), h) end)
Enum.each(m["logs"], fn {p, h} -> check.(Path.join(Path.dirname(path), p), h) end)
Enum.each(m["compiled_feature_beams"], fn {p, h} -> check.(Path.join(m["compiled_feature_path"], p), h) end)
true = sha.(File.read!(m["previous_manifest"])) == m["previous_manifest_sha256"]
IO.inspect(%{sources: map_size(m["sources"]), logs: map_size(m["logs"]), feature_beams: map_size(m["compiled_feature_beams"])}, label: "DIRECTORY_CARDINALITY_REPAIR_MANIFEST_OK")
code = File.read!("docs/archive/2026-10-26-p30-p31-implementation/shared-generation-directory/review-partial-groups.exs")
code = String.replace(code, "{:ok, directory} = D.pack(profile, catalog, catalog_pages, summaries, 7)", "directory = nil\n{:error, :invalid_generation_directory} = D.pack(profile, catalog, catalog_pages, summaries, 7)\nIO.puts(\"DIRECTORY_ORIGINAL_PARTIAL_GROUP_COUNTEREXAMPLE_REFUSED\")\nSystem.halt(0)")
Code.eval_string(code)
