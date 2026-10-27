# Historical read-only diagnostic for the synthetic segment-1 store.
# Reads exact retained paths; never acquires a product lock or writes a file.
base = "/tmp/ipse-storage-endurance-20261026-02"
Code.require_file(base <> "/extensions/knowledge/src/notes.ex")

for name <- ~w(storage_workload.ex storage_continuation.exs storage_annual.exs) do
  Code.require_file(base <> "/dev/knowledge/" <> name)
end

parent =
  "/home/lexlapax/projects/lexlapax/ipse/_build/storage-workloads/ipse-storage-annual-74b231d6e83d7c662c484ab600c81e9c"

project = "7641de2b464e967f50674e6983d004f343b8cf09a289c6a887120b9a464d9605"
directory = Path.join([parent, "collections", project])

read = fn path, limit ->
  {:ok, stat} = File.lstat(path)
  true = stat.type == :regular and stat.links == 1 and stat.size <= limit
  bytes = File.read!(path)
  true = byte_size(bytes) == stat.size
  bytes
end

root_bytes = read.(Path.join(directory, "root.json"), 1024)
root = Jason.decode!(root_bytes)
true = Ipse.JSON.sha256?(root["manifest"])
manifest_path = Path.join([directory, "manifests", root["manifest"] <> ".json"])
manifest_bytes = read.(manifest_path, 8 * 1024 * 1024)
true = Ipse.JSON.sha256(manifest_bytes) == root["manifest"]

{:ok, state, references} =
  Ipse.Extension.Collection.Blocks.decode(Jason.decode!(manifest_bytes), fn hash, size ->
    {:ok, read.(Path.join([directory, "manifests", hash <> ".json"]), size)}
  end)

actual =
  Map.new(state["records"], fn {key, record} ->
    bytes = read.(Path.join([directory, "objects", record["sha256"] <> ".json"]), 6144)
    true = byte_size(bytes) == record["bytes"]
    true = Ipse.JSON.sha256(bytes) == record["sha256"]
    {key, Jason.decode!(bytes)}
  end)

{_, expected, queue, _} = Ipse.Development.StorageAnnual.regenerate(56, 0, "maximum")
operations = Ipse.Extension.Collection.Migration.operations(state)

true =
  Enum.all?(operations, fn {_, receipt} ->
    Ipse.Extension.Collection.Migration.receipt?(receipt)
  end)

counts =
  Map.new(~w(objects manifests), fn name ->
    names = File.ls!(Path.join(directory, name))
    true = length(names) <= 20_000

    {name,
     %{count: length(names), pending: Enum.filter(names, &String.starts_with?(&1, ".pending-"))}}
  end)

oracle_names = File.ls!(Path.join([parent, "oracle", "segment-1"])) |> Enum.sort()

IO.puts(
  Jason.encode!(
    %{
      kind: "development_storage_annual_unclean_read_only_inspection",
      inspected_at_utc: DateTime.utc_now() |> DateTime.to_iso8601(),
      qualification_passed: false,
      outcome: "incomplete",
      termination_cause: "unknown",
      diagnostic_is_continuation: false,
      product_api_calls: 0,
      writes_or_retries: 0,
      root: root,
      root_sha256: Ipse.JSON.sha256(root_bytes),
      root_unchanged_across_read: root_bytes == read.(Path.join(directory, "root.json"), 1024),
      canonical_block_decode_passed: true,
      referenced_metadata_blocks: MapSet.size(references),
      actual_records_with_verified_object_hashes: map_size(actual),
      valid_receipts: map_size(operations),
      day56_cycle0_model_equal: actual == expected,
      offline_queue_count: length(queue),
      migration: state["migration"],
      checkpoint: state["checkpoint"],
      directory_counts: counts,
      oracle_directory_names: oracle_names,
      runtime_binding_sha256: "1ae1497bec81dd1a4c225d45d0fd810671f9a7c59a74d4d0d7671f678792fe2d",
      native_helper_sha256: "108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29",
      scope:
        "ordinary-v4 primitive and Notes policy fixture; not domain admission or Session turns"
    },
    pretty: true
  )
)
