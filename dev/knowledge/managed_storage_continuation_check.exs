Code.require_file("managed_storage_continuation.ex", __DIR__)
alias Ipse.Development.ManagedStorageContinuation, as: C
alias Ipse.Development.StorageContinuation, as: Oracle
alias Ipse.Runner.Transaction, as: T
alias Ipse.{JSON, Usage}

driver = self()

timer =
  spawn_link(fn ->
    Process.sleep(90_000)
    Process.exit(driver, :kill)
  end)

try do
  [report_path, wire_path, output] = System.argv()
  report = Jason.decode!(File.read!(report_path))
  wire = Jason.decode!(File.read!(wire_path))
  location = report["location"]
  {before, _, _} = C.snapshot(location, 1000)
  true = before["root_sha256"] == wire["root_sha256"]
  true = before["classes"] == report["terminal_verification"]
  binding = C.runtime_binding(location)
  source = Path.join(__DIR__, "managed_storage_continuation.ex")
  original_source = File.read!(source)

  drift =
    try do
      File.write!(source, original_source <> "\n")
      C.runtime_binding(location) != binding
    after
      File.write!(source, original_source)
    end

  true = drift and C.runtime_binding(location) == binding
  parent = Path.join(Path.dirname(location["root"]), "oracle-controls-" <> Usage.id())
  File.mkdir!(parent)
  File.chmod!(parent, 0o700)
  directory = Path.join(parent, "known-fault-fixture")
  {:ok, handle} = Oracle.start(directory, %{"fixture" => true})
  root = Path.join(directory, "root.json")
  {:error, _} = Oracle.read(root, JSON.sha256("absent root"))
  {:error, _} = Oracle.start(directory, %{"fixture" => true})
  {:ok, reference} = Oracle.finish(handle, %{"fixture" => true}, %{"fixture" => true})
  {:ok, _, _} = Oracle.read(root, reference["sha256"])
  {:error, _} = Oracle.read(root, JSON.sha256("incorrect checksum"))

  {:ok, cap} = T.acquire(Path.join(directory, ".lock"), cwd: directory)
  :ok = T.quota(cap, :flat, 8 * 1024 * 1024)
  pending = ".pending-" <> Usage.id()
  :ok = T.stage(cap, ".", [{pending, "known test-injected pending marker"}])
  :ok = T.release(cap)
  {:error, _} = Oracle.read(root, reference["sha256"])

  # This is a known, isolated fault fixture. The actual baseline and its future
  # oracle are never repaired or rewritten by a control.
  {:ok, cap} = T.acquire(Path.join(directory, ".lock"), cwd: directory)
  :ok = T.quota(cap, :flat, 8 * 1024 * 1024)
  :ok = T.reclaim(cap, ".", [pending])
  changed = ".pending-" <> Usage.id()
  :ok = T.stage(cap, ".", [{changed, "{}"}])
  :ok = T.switch(cap, changed, "root.json")
  :ok = T.release(cap)
  {:error, _} = Oracle.read(root, reference["sha256"])

  {unchanged, _, _} = C.snapshot(location, 1000)
  true = before == unchanged

  result = %{
    kind: "managed_continuation_prebootstrap_controls",
    qualification_passed: false,
    source_drift_detected_and_known_fixture_restored: drift,
    pending_refused: true,
    existing_segment_refused: true,
    checksum_refused: true,
    corrupt_checkpoint_refused: true,
    clean_native_oracle_read_passed: true,
    actual_collection_root_unchanged: true,
    actual_generation: 1000,
    actual_root_sha256: before["root_sha256"],
    binding_sha256: binding,
    baseline_publications_added: 0,
    oracle_controls_directory: directory
  }

  File.write!(output, Jason.encode!(result, pretty: true) <> "\n")
  IO.puts(Jason.encode!(result, pretty: true))
after
  Process.unlink(timer)
  Process.exit(timer, :kill)
end
