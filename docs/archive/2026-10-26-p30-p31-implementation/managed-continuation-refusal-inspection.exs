Code.require_file("dev/knowledge/managed_storage_continuation.ex")
alias Ipse.Development.ManagedStorageContinuation, as: C
alias Ipse.Runner.Transaction, as: T
alias Ipse.JSON
[failure_path, output] = System.argv()
Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
owner = self()
spawn_link(fn -> Process.sleep(90_000); Process.exit(owner, :kill) end)
failure = Jason.decode!(File.read!(failure_path))
location = failure["context"]["location"]
last = failure["last_call"]
generation = last["before_generation"]
{snapshot, rows, operations} = C.snapshot(location, generation)
false = Map.has_key?(operations, last["operation_id"])
[change] = last["request"]["changes"]
key = change["key"]
false = Map.has_key?(rows, key)
identity = JSON.sha256(key)
shard = identity |> binary_part(0, 3) |> String.to_integer(16) |> rem(512) |> Integer.to_string(16) |> String.pad_leading(3, "0")
directory = Path.join(location["root"], location["project"])
{:ok, cap} = T.acquire(Path.join(directory, ".lock"), cwd: directory)
try do
  {:ok, bytes} = T.read(cap, ".", "root.json", 1024)
  true = JSON.sha256(bytes) == snapshot["root_sha256"]
  pages = Enum.map(0..3, fn page ->
    page_key = "host.validity.live.#{shard}.#{page}"
    row = Map.fetch!(rows, page_key)
    {:ok, bytes} = T.read(cap, "objects", row["sha256"] <> ".json", 6144)
    true = JSON.sha256(bytes) == row["sha256"]
    value = Jason.decode!(bytes)
    true = value["kind"] == "live" and value["version"] == 2 and value["shard"] == shard and value["page"] == page
    %{"key" => page_key, "sha256" => row["sha256"], "entries" => map_size(value["entries"]), "attempted_identity_absent" => not Map.has_key?(value["entries"], identity)}
  end)
  {:ok, allocation} = T.allocation(cap)
  :ok = T.check(cap)
  :ok = T.release(cap)
  marker_dir = failure["context"]["handle"]["directory"] || failure["context"]["handle"]["root"]
  report = %{read_only: true, qualification_passed: false, root_sha256: snapshot["root_sha256"], generation: generation, note_count: snapshot["note_count"], receipt_count: snapshot["receipt_count"], record_count: snapshot["record_count"], classes: snapshot["classes"], attempted_operation_id: last["operation_id"], attempted_request_sha256: JSON.digest([last["request"]]), attempted_record_key: key, attempted_operation_absent: true, attempted_record_absent: true, live_shard: shard, live_pages: pages, native_collection_allocation: allocation, managed_control_reserved_bytes: 22*1024*1024, runtime_binding_sha256: C.runtime_binding(location), pending_marker_untouched: true, marker_directory_hint: marker_dir}
  File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
  IO.puts(Jason.encode!(report, pretty: true))
after
  T.release(cap)
end
