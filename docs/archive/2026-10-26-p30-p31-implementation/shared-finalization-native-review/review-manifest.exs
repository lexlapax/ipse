path = "docs/archive/2026-10-26-p30-p31-implementation/shared-finalization-native/manifest.json"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
true = sha.(File.read!(path)) == "3aca9d4bffb7cc7385587e48e54e4f37680e7d45f53ecbc1558419b25cfa0876"
m = Jason.decode!(File.read!(path))
check = fn p, expected ->
  bytes = File.read!(p)
  true = sha.(bytes) == expected["sha256"]
  true = byte_size(bytes) == expected["byte_count"]
end
Enum.each(m["sources"], fn {p, h} -> check.(Path.join(m["source_snapshot"], p), h) end)
Enum.each(m["logs"], fn {p, h} -> check.(Path.join(Path.dirname(path), p), h) end)
Enum.each(m["runtime_files"], fn {p, h} -> check.(p, h) end)
Enum.each(m["public_and_fixture_artifacts"], fn {dir, files} -> Enum.each(files, fn {p, h} -> check.(Path.join(dir, p), h) end) end)
true = sha.(File.read!(m["previous_manifest"])) == m["previous_manifest_sha256"]
true = sha.(File.read!(m["host_restoration_manifest"])) == m["host_restoration_manifest_sha256"]
base = Path.join(Path.dirname(m["host_restoration_manifest"]), "runtime-final.sha256")
true = sha.(File.read!(base)) == m["base_inventory_sha256"]
verify_inventory = fn file, rewrite ->
  rows = File.read!(file) |> String.split("\n", trim: true)
  Enum.each(rows, fn row ->
    [hash, p] = String.split(row, "  ", parts: 2)
    p = rewrite.(p)
    true = m["runtime_files"][p]["sha256"] == hash
    true = sha.(File.read!(p)) == hash
  end)
  length(rows)
end
base_count = verify_inventory.(base, &String.replace_prefix(&1, "_build/document-decision-sol-20261029/", "_build/shared-finalization-native-20261029/"))
copy_count = verify_inventory.(Path.join(Path.dirname(path), "runtime.sha256"), & &1)
true = copy_count == map_size(m["runtime_files"])
helper = "_build/shared-finalization-native-20261029/lib/ipse/priv/ipse-runner"
true = sha.(File.read!(helper)) == m["helper_sha256"]
previous = Jason.decode!(File.read!(m["previous_manifest"]))
features = ~w(extensions/knowledge/build.exs extensions/knowledge/src/corpus.ex extensions/knowledge/src/store/collection/directory.ex extensions/knowledge/src/store/collection/finalization.ex extensions/knowledge/src/store/collection/job.ex extensions/knowledge/src/store/collection/reduction.ex)
Enum.each(features, fn p -> true = m["sources"][p] == previous["sources"][p] end)
IO.inspect(%{sources: map_size(m["sources"]), logs: map_size(m["logs"]), runtime_files: map_size(m["runtime_files"]), inherited_runtime_inventory_files: base_count, additional_pinned_runtime_files: copy_count - base_count, artifact_inventories: map_size(m["public_and_fixture_artifacts"]), artifact_files: Enum.sum(Enum.map(m["public_and_fixture_artifacts"], fn {_, files} -> map_size(files) end)), unchanged_feature_sources: length(features), copied_runtime_matches_base: true, helper: m["helper_sha256"]}, label: "NATIVE_FINALIZATION_MANIFEST_OK")
