path = "docs/archive/2026-10-26-p30-p31-implementation/shared-generation-directory/manifest.json"
m = Jason.decode!(File.read!(path))
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
check = fn file, expected ->
  bytes = File.read!(file)
  true = sha.(bytes) == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
Enum.each(m["sources"], fn {p, h} -> check.(Path.join(m["source_snapshot"], p), h) end)
Enum.each(m["logs"], fn {p, h} -> check.(Path.join(Path.dirname(path), p), h) end)
Enum.each(m["artifacts"], fn {dir, files} -> Enum.each(files, fn {p, h} -> check.(Path.join([m["artifact_root"], dir, p]), h) end) end)
Enum.each(m["host_beam_hashes"], fn {p, h} -> true = sha.(File.read!(Path.join([m["host_graph"], "lib/ipse/ebin", p]))) == h end)
for field <- ["base_manifest", "canonical_manifest"] do
  true = sha.(File.read!(m[field])) == m[field <> "_sha256"]
end
true = sha.(File.read!(Path.join(m["host_graph"], "lib/ipse/priv/ipse-runner"))) == m["native_helper_sha256"]
IO.inspect(%{sources: map_size(m["sources"]), logs: map_size(m["logs"]), artifacts: map_size(m["artifacts"]), host_beams: map_size(m["host_beam_hashes"])}, label: "DIRECTORY_REVIEW_MANIFEST_OK")
