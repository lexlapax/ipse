alias Ipse.Runner.Transaction, as: T
alias Ipse.Development.StorageContinuation, as: Oracle
alias Ipse.JSON
Code.require_file("dev/knowledge/storage_continuation.exs")
owner = self()
spawn_link(fn -> Process.sleep(30_000); Process.exit(owner, :kill) end)
failure = Jason.decode!(File.read!("/tmp/ipse-managed-storage-segment5-20261026-01.json.failure.json"))
context = failure["context"]
location = context["location"]
directory = Path.join(location["root"], location["project"])
{:ok, cap} = T.acquire(Path.join(directory,".lock"), cwd: directory)
{:ok, bytes} = T.read(cap,".","root.json",1024)
:ok = T.check(cap)
:ok = T.release(cap)
true = JSON.sha256(bytes) == "840fa00f9f5f78b278d4622d4ac95a551c3ba8f48c60e6316d7a6d7008b30e41"
handle = context["handle"]
marker_path = Path.join(handle["directory"],handle["marker"])
marker = File.read!(marker_path)
{:ok, oracle_cap} = T.acquire(Path.join(handle["directory"],".lock"),cwd: handle["directory"])
{:ok, oracle_allocation} = T.allocation(oracle_cap,:flat)
:ok = T.release(oracle_cap)
{:error, :continuation_unclean_or_corrupt} = Oracle.read(Path.join(handle["directory"],"root.json"),JSON.sha256("known nonexistent checkpoint"))
report = %{read_only: true, root: Jason.decode!(bytes), root_sha256: JSON.sha256(bytes), pending_marker: handle["marker"], pending_marker_sha256: JSON.sha256(marker), pending_marker_bytes: byte_size(marker), pending_marker_preserved: true, final_oracle_allocation: oracle_allocation, clean_continuation_refused: true, final_json_present: File.exists?("/tmp/ipse-managed-storage-segment5-20261026-01.json"), resource_failure_present: File.exists?("/tmp/ipse-managed-storage-segment5-20261026-01.json.resource-failure.json")}
File.write!("/tmp/ipse-managed-storage-final-root-20261026-01.json",Jason.encode!(report,pretty: true) <> "\n")
IO.puts(Jason.encode!(report,pretty: true))
