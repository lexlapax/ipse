ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{JSON, Journal, Session, Usage}
alias Ipse.CLI.Knowledge.Management
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ObservedRead
[root, output] = System.argv()
read = fn p -> p |> File.read!() |> Jason.decode!() end
fingerprint = fn p -> %{"path" => p, "bytes" => File.stat!(p).size, "sha256" => JSON.sha256(File.read!(p))} end
m = read.(Path.join(root, "turnover-pilot/manifest.json"))
assert m["root"] == root and length(m["actions"]) == 7 and length(m["segments"]) == 3
assert not File.exists?(Path.join(root, "turnover-pilot/inflight.json"))
for f <- m["files"] ++ m["seed_sources"], do: assert(fingerprint.(f["path"]) === f)
reports = for i <- 1..3 do
  closed = read.(Path.join(root, "turnover-pilot/closed-#{i}.json"))
  assert closed["index"] == i and closed["exit_code"] == 0
  assert fingerprint.(closed["input"]["path"]) === closed["input"]
  assert fingerprint.(closed["report"]["path"]) === closed["report"]
  assert fingerprint.(closed["log"]["path"]) === closed["log"]
  read.(closed["report"]["path"])
end
records = Enum.reduce(reports, m["records"], fn r, acc -> Map.merge(acc, r["new_records"]) end)
Code.require_file(Path.join(root, "runtime/managed_clock_lifecycle.exs"))
{:ok, _} = Application.ensure_all_started(:ipse)
apply(Ipse.Test.ManagedClockLifecycle, :check_stdio_clock, [root])
home = Path.join(root,"home")
cwd = Path.join(root,"work")
{:ok, binding} = ProjectIdentity.existing(home,cwd)
{:ok, ns} = Ipse.Extension.SemanticConsent.namespace(binding["project_id"],"knowledge")
collection = SemanticAdmission.collection_root(home)
{:ok, selected} = Management.selection(home)
{:ok, before} = ObservedRead.read(collection, ns, %{"op" => "snapshot"})
assert before["value"] === List.last(reports)["snapshot"]
assert before["witness"]["root_sha256"] == List.last(reports)["root_sha256"]
{:ok, control} = Consent.existing_snapshot(SemanticAdmission.control_root(home),binding["project_id"])
assert JSON.digest([control]) == List.last(reports)["control_sha256"]
assert before["value"]["generation"] == 15 and control["sequence"] == 15
now = System.system_time(:millisecond)
for id <- ~w(seed/3 seed/4 seed/5 pilot/correct) do
  {:ok, value} = Collection.execute(collection, ns, %{"op" => "get", "key" => records[id]["key"]}, Usage.id())
  assert value["record"] == nil
end
verified = for {id, category, expired} <- [{"seed/1","pin",false},{"seed/2","preference",false},{"seed/6","ordinary",true},{"seed/7","ordinary",true},{"pilot/capture","ordinary",true},{"pilot/current","current",false}] do
  expected = records[id]
  {:ok, observed} = ProjectIdentity.with_existing_domain_auth(home,cwd,binding,%{namespace: ns,format: "managed-metadata-v3"},fn cap,catalog ->
    ObservedRead.managed_record(collection,ns,%{"op" => "get_record","key" => expected["key"]},cap,catalog,selected.recipe)
  end)
  record = observed["observation"]["value"]["record"]
  assert record["value"] === expected["value"]
  metadata = observed["metadata"]
  assert metadata["category"] == category
  assert if(expired, do: is_integer(metadata["valid_until_ms"]) and metadata["valid_until_ms"] < now, else: is_nil(metadata["valid_until_ms"]))
  %{"id" => id,"category" => category,"expired" => expired,"value_sha256" => record["sha256"]}
end
sessions = Path.wildcard(Path.join(home,"sessions/*.jsonl"))
for path <- sessions do
  id = Path.basename(path,".jsonl")
  {:ok, events} = Journal.load(Path.dirname(path),id)
  {:ok, _} = Session.Saved.restore(events,id)
  {:ok, %{"release_claim" => "signed_release_claim"}} = Session.Saved.inspect_saved(Path.dirname(path),id)
end
for {_, op} <- control["operations"], do: assert(op["status"] == "settled" and op["actual"]["model_calls"] == 0)
assert not File.exists?(Path.join(root,"unexpected-model"))
{:ok, after_snapshot} = ObservedRead.read(collection,ns,%{"op" => "snapshot"})
assert after_snapshot === before
{:ok, after_control} = Consent.existing_snapshot(SemanticAdmission.control_root(home),binding["project_id"])
assert after_control === control
for f <- m["files"] ++ m["seed_sources"], do: assert(fingerprint.(f["path"]) === f)
{:ok, status} = Collection.execute(collection,ns,%{"op" => "status"},Usage.id())
physical = Map.new([{"control", SemanticAdmission.control_root(home)}, {"identity", Path.join(home,"project-identities")}, {"management", Path.join(home,"knowledge-management")}, {"sessions", Path.join(home,"sessions")}], fn {name,path} ->
  {:ok, allocation} = Ipse.Runner.storage_allocation(path)
  {name, allocation}
end)
measured = status["allocated_bytes"] + Enum.sum(Enum.map(physical, fn {_, allocation} -> allocation["allocated_bytes"] end))
File.write!(output, Jason.encode!(%{"verified" => verified, "absent_aliases" => ~w(seed/3 seed/4 seed/5 pilot/correct), "generation" => 15,"settled_control_sequence" => 15,"saved_sessions" => length(sessions),"root_sha256" => before["witness"]["root_sha256"], "collection_status" => status, "physical_allocations" => physical, "measured_components_allocated_bytes" => measured, "qualification" => false}) <> "\n", [:exclusive])
IO.puts("NATIVE_TURNOVER_PILOT_AUDIT_PASSED")
