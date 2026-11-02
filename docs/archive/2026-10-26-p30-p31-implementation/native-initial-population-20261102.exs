alias Ipse.JSON
root = "/tmp/ipse-native-seed-initial-20261102-first"
read = fn path -> path |> File.read!() |> Jason.decode!() end
fingerprint = fn path ->
  bytes = File.read!(path)
  %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
end
manifest = read.(Path.join(root, "manifest.json"))
Enum.each(manifest["files"], fn item -> true = fingerprint.(item["path"]) === item end)
reports = Enum.map(1..273, fn index ->
  marker = read.(Path.join(root, "checkpoints/closed-#{index}.json"))
  true = marker["index"] == index and marker["exit_code"] == 0
  true = fingerprint.(marker["report"]["path"]) === marker["report"]
  true = fingerprint.(marker["log"]["path"]) === marker["log"]
  report = read.(marker["report"]["path"])
  true = report["index"] == index and report["closed"] == true
  report
end)
last = List.last(reports)
true = last["public_records"] == 2000 and last["snapshot"]["generation"] == 2100
true = last["initial_seed_complete"] == true
samples = Enum.flat_map(reports, & &1["capture_elapsed_us"]) |> Enum.sort()
true = length(samples) == 2000
max_field = fn key -> Enum.max(Enum.map(reports, & &1[key])) end
actual_total = fn report ->
  report["status"]["allocated_bytes"] +
    Enum.sum(Enum.map(report["physical_allocations"], fn {_, value} -> value["allocated_bytes"] end))
end
summary = %{
  "version" => 1, "kind" => "closed_initial_population_checkpoint_summary",
  "root" => root, "manifest" => fingerprint.(Path.join(root, "manifest.json")),
  "frozen_files_verified" => length(manifest["files"]),
  "closed_segments" => length(reports), "notes" => last["public_records"],
  "operations" => last["snapshot"]["generation"],
  "final_status" => last["status"], "final_physical_allocations" => last["physical_allocations"],
  "final_actual_components_allocated_bytes" => actual_total.(last),
  "peak_post_segment_actual_components_bytes" => Enum.max(Enum.map(reports, actual_total)),
  "peak_staged_accounted_collection_bytes" => max_field.("staged_accounted_allocation_peak"),
  "max_post_segment_beam_bytes" => max_field.("beam_memory_after_segment"),
  "max_record_encoded_bytes" => max_field.("largest_new_record_encoded_bytes"),
  "capture_elapsed_sample_count" => length(samples),
  "capture_elapsed_p95_us" => Enum.at(samples, ceil(length(samples) * 0.95) - 1),
  "capture_elapsed_scope" => "whole native statement capture, including input/review; not local publication or reference-hardware qualification",
  "peak_scope" => "sampled post-segment component allocations and separate Collection staging telemetry; not full process-tree RAM or disk peak",
  "full_population_readonly_audit" => "pending",
  "maximum_payload_qualification" => false, "annual_workload_qualification" => false
}
File.write!("/tmp/ipse-native-population-metrics-20261102.json", Jason.encode!(summary, pretty: true) <> "\n", [:exclusive])
IO.puts(Jason.encode!(summary))
