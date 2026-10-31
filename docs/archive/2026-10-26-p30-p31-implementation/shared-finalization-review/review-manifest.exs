path = "docs/archive/2026-10-26-p30-p31-implementation/shared-generation-finalization/manifest.json"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
true = sha.(File.read!(path)) == "5031bab3f8e92da7af655359a236d1d12c16868de752bbca86e5b6d630e475d3"
m = Jason.decode!(File.read!(path))
check = fn p, expected ->
  bytes = File.read!(p)
  true = sha.(bytes) == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
Enum.each(m["sources"], fn {p, h} -> check.(Path.join(m["source_snapshot"], p), h) end)
Enum.each(m["logs"], fn {p, h} -> check.(Path.join(Path.dirname(path), p), h) end)
Enum.each(m["compiled_cohorts"], fn {dir, files} -> Enum.each(files, fn {p, h} -> check.(Path.join(dir, p), h) end) end)
Enum.each(m["public_artifact_files"], fn {p, h} -> check.(Path.join(m["public_artifact"], p), h) end)
true = sha.(File.read!(m["previous_manifest"])) == m["previous_manifest_sha256"]
IO.inspect(%{sources: map_size(m["sources"]), logs: map_size(m["logs"]), cohorts: map_size(m["compiled_cohorts"]), cohort_files: Enum.sum(Enum.map(m["compiled_cohorts"], fn {_, files} -> map_size(files) end)), public_artifact_files: map_size(m["public_artifact_files"]), prerequisite_manifest: true}, label: "FINALIZATION_MANIFEST_OK")
