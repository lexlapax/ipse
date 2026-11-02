alias Ipse.JSON

fp = fn path ->
  bytes = File.read!(path)
  %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
end

output = "/tmp/ipse-native-seed-audit-initial-20261102-first.json"
audit = output |> File.read!() |> Jason.decode!()
rows = audit["verified_rows"]["path"] |> File.read!() |> Jason.decode!()
true = fp.(audit["verified_rows"]["path"]) === audit["verified_rows"]
true = JSON.digest([rows]) === audit["rows_sha256"]
true = length(rows) == 2000 and audit["verified_records"] == 2000

true =
  audit["verified_categories"] == %{
    "ordinary" => 1800,
    "pin" => 100,
    "preference" => 50,
    "current" => 50
  }

true = Enum.frequencies_by(rows, & &1["metadata"]["category"]) == audit["verified_categories"]

true =
  audit["unchanged_sources"] == 373 and audit["unchanged_control"] and audit["unchanged_root"]

true = audit["measured_components_allocated_bytes"] == 134_131_712

true =
  audit["full_6_kib_record_payload_qualification"] == false and
    audit["annual_workload_qualification"] == false

receipt = %{
  "version" => 1,
  "date" => "2026-11-02",
  "kind" => "closed_native_initial_population_signed_audit",
  "publisher_source_commit" => "5331e60b9772c44131c054978c8f0d4428cbc2d6",
  "audit_caller_commit" => "d1863c7bb0656635ce72612f88190f0939441fa6",
  "audit_exit_code" => 0,
  "verified_records" => audit["verified_records"],
  "verified_categories" => audit["verified_categories"],
  "unchanged_sources" => audit["unchanged_sources"],
  "unchanged_control" => true,
  "unchanged_root" => true,
  "root_sha256" => audit["root_sha256"],
  "rows_sha256" => audit["rows_sha256"],
  "verified_rows" => audit["verified_rows"],
  "largest_record_encoded_bytes" => audit["largest_record_encoded_bytes"],
  "measured_components_allocated_bytes" => audit["measured_components_allocated_bytes"],
  "allocation_scope" => audit["allocation_scope"],
  "physical_allocations" => audit["physical_allocations"],
  "status" => audit["status"],
  "snapshot" => audit["snapshot"],
  "full_6_kib_record_payload_qualification" => false,
  "annual_workload_qualification" => false,
  "audit_output" => fp.(output),
  "audit_caller" => audit["audit_source"],
  "manifest" => audit["manifest"],
  "parent_log" => fp.("/tmp/ipse-native-seed-audit-initial-parent-20261102-first.log"),
  "child_log" => fp.(output <> ".log"),
  "seed_metrics" => fp.("/tmp/ipse-native-population-metrics-20261102.json"),
  "receipt_generator" =>
    fp.(
      "docs/archive/2026-10-26-p30-p31-implementation/native-full-population-audit-20261102.exs"
    )
}

File.write!(
  "docs/archive/2026-10-26-p30-p31-implementation/native-full-population-audit-20261102.json",
  Jason.encode!(receipt, pretty: true) <> "\n"
)
