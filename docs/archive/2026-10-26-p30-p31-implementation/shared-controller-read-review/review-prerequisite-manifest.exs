path = "docs/archive/2026-10-26-p30-p31-implementation/shared-job-prerequisites/manifest.json"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
true = sha.(File.read!(path)) == "1945be650522a3d6d06317f834640c4de5112981d72e3f54f82980e1f6d3cffd"
m = Jason.decode!(File.read!(path))
check = fn p, expected ->
  bytes = File.read!(p)
  true = sha.(bytes) == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
Enum.each(m["sources"], fn {p, h} -> check.(Path.join(m["source_snapshot"], p), h) end)
Enum.each(m["logs"], fn {p, h} -> check.(Path.join(Path.dirname(path), p), h) end)
Enum.each(m["compiled_feature_beams"], fn {p, h} -> check.(Path.join(m["compiled_feature_path"], p), h) end)
for {field, hash_field} <- [{"previous_manifest", "previous_manifest_sha256"}, {"review_counterexample", "review_counterexample_sha256"}, {"review_counterexample_log", "review_counterexample_log_sha256"}] do
  true = sha.(File.read!(m[field])) == m[hash_field]
end
old = Jason.decode!(File.read!(m["previous_manifest"]))
true = sha.(File.read!(Path.join(old["source_snapshot"], m["fixture_factory"]))) == m["fixture_factory_sha256"]
IO.inspect(%{sources: map_size(m["sources"]), logs: map_size(m["logs"]), feature_beams: map_size(m["compiled_feature_beams"]), ancestor: true, original_counterexample: true, frozen_fixture_factory: true}, label: "PREREQUISITE_REPAIR_MANIFEST_OK")
