path = "docs/archive/2026-10-26-p30-p31-implementation/shared-directory-v2-implementation/manifest.json"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
true = sha.(File.read!(path)) == "382d9cf81e29259611cc9481363da54437cbe82cbeee92f70495d3498b0529dd"
m = Jason.decode!(File.read!(path))
check = fn p, expected ->
  bytes = File.read!(p)
  true = sha.(bytes) == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
Enum.each(m["sources"], fn {p, h} -> check.(Path.join(m["source_snapshot"], p), h) end)
Enum.each(m["logs"], fn {p, h} -> check.(Path.join(Path.dirname(path), p), h) end)
Enum.each(m["runtime_files"], fn {p, h} -> check.(p, h) end)
for field <- ["compiled_feature_cohorts", "actual_public_and_fixture_artifacts"] do
  Enum.each(m[field], fn {dir, files} -> Enum.each(files, fn {p, h} -> check.(Path.join(dir, p), h) end) end)
end
Enum.each(m["ancestors"], fn {p, hash} -> true = sha.(File.read!(p)) == hash end)
helper = "_build/shared-finalization-native-20261029/lib/ipse/priv/ipse-runner"
true = sha.(File.read!(helper)) == m["helper_sha256"]
true = m["sources"]["extensions/knowledge/src/store/collection.ex"]["sha256"] == "2811dc2be11955495b43e853371385f3148d3052485bac5ae5fc4969174ff599"
previous = Jason.decode!(File.read!("docs/archive/2026-10-26-p30-p31-implementation/shared-finalization-native/manifest.json"))
true = previous["runtime_files"] == m["runtime_files"]
IO.inspect(%{sources: map_size(m["sources"]), logs: map_size(m["logs"]), runtime_files: map_size(m["runtime_files"]), ancestors: map_size(m["ancestors"]), feature_cohorts: map_size(m["compiled_feature_cohorts"]), feature_files: Enum.sum(Enum.map(m["compiled_feature_cohorts"], fn {_, files} -> map_size(files) end)), artifact_inventories: map_size(m["actual_public_and_fixture_artifacts"]), artifact_files: Enum.sum(Enum.map(m["actual_public_and_fixture_artifacts"], fn {_, files} -> map_size(files) end)), runtime_unchanged_from_native_finalization: true, client_writer_unchanged: true, helper: m["helper_sha256"]}, label: "ROOT2_IMPLEMENTATION_MANIFEST_OK")
