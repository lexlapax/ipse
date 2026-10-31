root = "docs/archive/2026-10-26-p30-p31-implementation"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
check = fn file, expected ->
  bytes = File.read!(file)
  true = sha.(bytes) == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
controller = root <> "/shared-generation-controller-read/manifest.json"
true = sha.(File.read!(controller)) == "e24c54dba3017d8d278715e984660b0d0d9dc9bd6db306baa637196572df733a"
m = Jason.decode!(File.read!(controller))
Enum.each(m["sources"], fn {p, h} -> check.(Path.join(m["source_snapshot"], p), h) end)
Enum.each(m["logs"], fn {p, h} -> check.(Path.join(Path.dirname(controller), p), h) end)
Enum.each(m["artifacts"], fn {dir, files} -> Enum.each(files, fn {p, h} -> check.(Path.join([m["artifact_root"], dir, p]), h) end) end)
Enum.each(m["host_beam_hashes"], fn {p, h} -> true = sha.(File.read!(Path.join([m["host_graph"], "lib/ipse/ebin", p]))) == h end)
Enum.each(m["ancestors"], fn {p, h} -> true = sha.(File.read!(p)) == h end)
true = sha.(File.read!(Path.join(m["host_graph"], "lib/ipse/priv/ipse-runner"))) == m["native_helper_sha256"]
IO.inspect(%{sources: map_size(m["sources"]), logs: map_size(m["logs"]), artifact_inventories: map_size(m["artifacts"]), artifact_files: Enum.sum(Enum.map(m["artifacts"], fn {_, files} -> map_size(files) end)), host_beams: map_size(m["host_beam_hashes"]), ancestors: map_size(m["ancestors"])}, label: "CONTROLLER_READ_MANIFEST_OK")
origin = root <> "/shared-citation-origin-canonical/manifest.json"
true = sha.(File.read!(origin)) == "57b9d3d6b83c7021e728dd59eb5b9770a81ac745791af6231a9aac49e3c0e11a"
o = Jason.decode!(File.read!(origin))
true = sha.(File.read!(o["controller_read_manifest"])) == o["controller_read_manifest_sha256"]
true = sha.(File.read!(o["pre_repair_generation_beam"])) == o["pre_repair_generation_beam_sha256"]
Enum.each(o["sources"], fn {p, h} -> check.(Path.join(o["source_snapshot"], p), h) end)
Enum.each(o["logs"], fn {p, h} -> check.(Path.join(Path.dirname(origin), p), h) end)
Enum.each(o["repaired_feature_beams"], fn {p, h} -> check.(Path.join(o["repaired_feature_path"], p), h) end)
check.(Path.join(Path.dirname(origin), "origin-alias-probe.exs"), o["probe_source"])
IO.inspect(%{sources: map_size(o["sources"]), logs: map_size(o["logs"]), repaired_beams: map_size(o["repaired_feature_beams"])}, label: "CITATION_ORIGIN_MANIFEST_OK")
