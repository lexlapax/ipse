base = Path.dirname(__ENV__.file)
prior = "/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-protected-workflow-20261105-02"
sdk_outer = "/home/lexlapax/projects/lexlapax/ipse/_build/verification/retained-final-runtime-d548-20261105-02"
sdk = Path.join(sdk_outer, "source")
hash = &Ipse.JSON.sha256/1
nil = Process.whereis(Ipse.Supervisor)
false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
ports = MapSet.new(Port.list())
raw_result = File.read!(Path.join([base, "owner-compile-01", "owner-qualification-result.json"]))
result = Jason.decode!(raw_result)
true = result["status"] === "passed" and result["compiled_owner_modules"] === 1 and result["reused_helpers"] === 6
true = result["sdk_rebuilt"] === false and result["artifact_rebuilt"] === false and result["app_started"] === false and result["actor_released"] === false
true = result["helper_modules"] === 7 and result["sdk_apps"] === 16 and result["ipse_modules"] === 241
"3972c9bf87fd9cb9998d0b63e729972bce04c4b7f193ae1660a96610799db92e" = result["artifact_manifest_sha256"]
inventory = Path.join(base, "helper-inventory.sha256")
true = hash.(File.read!(inventory)) === result["helper_inventory_sha256"]
source_paths = [
  Path.join(sdk, "test/support/provider_fixture.ex"),
  Path.join(sdk, "test/support/resume_assertions.exs")
] ++ Enum.map(~w(metrics decision_metrics selection_experiment protected_answer), &Path.join([prior, "candidate/dev/evaluation", &1 <> ".exs"])) ++
  Enum.map(~w(paired_session.exs entry.exs guard.exs actor-phases.sh run-OFF.sh run-bounded-OFF.sh), &Path.join(base, &1)) ++
  Enum.map(~w(answer_extension.ex build_answer.exs), &Path.join(prior, &1))
source_inventory = Enum.sort(source_paths) |> Enum.map_join("", &(hash.(File.read!(&1)) <> "  " <> &1 <> "\n"))
source_inventory_path = Path.join(base, "actor-source.sha256")
File.write!(source_inventory_path, source_inventory, [:exclusive, :sync])
File.chmod!(source_inventory_path, 0o600)
labels_path = Path.join(base, "quality-labels.UNAVAILABLE.json")
labels = %{"version" => 1, "scope" => "synthetic_protocol_only", "independent_labels" => nil,
  "quality" => "unverified", "model_quality_claim" => false}
labels_bytes = Jason.encode!(labels) <> "\n"
File.write!(labels_path, labels_bytes, [:exclusive, :sync])
File.chmod!(labels_path, 0o600)
descriptor = Path.join(base, "descriptor.UNREVIEWED.json") |> File.read!() |> Jason.decode!()
false = descriptor["reviewed"]
storage = Path.dirname(descriptor["actor_root"])
false = File.exists?(storage)
source_commitment = Ipse.JSON.digest([%{
  "sdk_source_manifest_sha256" => descriptor["sdk_source_manifest_sha256"],
  "fixture_source_inventory_sha256" => hash.(source_inventory),
  "compiled_helper_inventory_sha256" => result["helper_inventory_sha256"],
  "artifact_manifest_sha256" => result["artifact_manifest_sha256"]
}])
artifact_manifest_path = Path.join(result["artifact_path"], "extension.json")
artifact = artifact_manifest_path |> File.read!() |> Jason.decode!()
paths = source_paths ++ Enum.map(result["helper_files"], & &1["path"]) ++
  Enum.map(artifact["files"], &Path.join(result["artifact_path"], &1["path"])) ++
  [artifact_manifest_path, inventory, source_inventory_path, labels_path,
   Path.join([base, "owner-compile-01", "owner-qualification-result.json"]),
   descriptor["pty"]] ++
  Enum.map(~w(source.sha256 runtime.sha256 dependencies.sha256), &Path.join([sdk_outer, "evidence", &1]))
files = paths |> Enum.uniq() |> Enum.sort() |> Enum.map(fn path ->
  info = File.lstat!(path)
  true = info.type === :regular and info.links === 1
  %{"path" => path, "bytes" => info.size, "sha256" => hash.(File.read!(path))}
end)
filled = descriptor |> Map.merge(%{
  "source_only" => false,
  "sdk_leaves_sha256" => result["sdk_leaves_sha256"],
  "sdk_links_sha256" => result["sdk_links_sha256"],
  "helper_artifact" => result["artifact_path"],
  "compiled_helper_inventory_sha256" => result["helper_inventory_sha256"],
  "files" => files,
  "commitments" => %{"source_sha256" => source_commitment,
    "runtime_sha256" => descriptor["sdk_runtime_manifest_sha256"], "label_commitment" => hash.(labels_bytes)}
})
false = filled["reviewed"]
actor_descriptor = Path.join(base, "actor-descriptor.review-false.json")
File.write!(actor_descriptor, Jason.encode!(filled) <> "\n", [:exclusive, :sync])
File.chmod!(actor_descriptor, 0o600)
input_paths = paths ++ [actor_descriptor, Path.join(base, "fill-actor.exs")]
input_manifest = input_paths |> Enum.uniq() |> Enum.sort() |> Enum.map_join("", &(hash.(File.read!(&1)) <> "  " <> &1 <> "\n"))
File.write!(Path.join(base, "actor-inputs.sha256"), input_manifest, [:exclusive, :sync])
File.chmod!(Path.join(base, "actor-inputs.sha256"), 0o600)
File.mkdir_p!(Path.join(base, "evidence"))
File.chmod!(Path.join(base, "evidence"), 0o700)
false = File.exists?(storage)
false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
true = MapSet.new(Port.list()) === ports
IO.puts(Jason.encode!(%{status: "prepared_false", descriptor_sha256: hash.(File.read!(actor_descriptor)),
  actor_inputs_sha256: hash.(input_manifest), files: length(files), app_started: false,
  actor_released: false, storage_absent: true, retained_access: false}))
