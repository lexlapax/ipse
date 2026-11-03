ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{JSON, Journal, Session, Usage}
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ObservedRead
[root, audit_path, output] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)
home = Path.join(root,"home")
cwd = Path.join(root,"work")
audit = audit_path |> File.read!() |> Jason.decode!()
seed_rows = audit["verified_rows"]["path"] |> File.read!() |> Jason.decode!()
{:ok, binding} = ProjectIdentity.existing(home,cwd)
{:ok, ns} = Ipse.Extension.SemanticConsent.namespace(binding["project_id"],"knowledge")
collection = SemanticAdmission.collection_root(home)
{:ok, before} = ObservedRead.read(collection,ns,%{"op" => "snapshot"})
{:ok, control} = Consent.existing_snapshot(SemanticAdmission.control_root(home),binding["project_id"])
assert before["value"]["generation"] == 9 and control["sequence"] == 9
assert File.exists?(Path.join(root,"turnover-pilot/inflight.json"))
refute File.exists?(Path.join(root,"turnover-pilot/closed-1.json"))
refute File.exists?(Path.join(root,"turnover-pilot/report-1.json"))
{:ok, page} = Collection.scan_visible(collection,ns,%{"op" => "scan", "after" => nil,"generation" => 9,"limit" => 32},Usage.id())
assert length(page["records"]) == 8
old = MapSet.new(seed_rows, & &1["key"])
assert [new] = Enum.reject(page["records"], &MapSet.member?(old, &1["key"]))
assert new["value"]["text"] == "Pilot continuation statement"
sessions = Path.wildcard(Path.join(home,"sessions/*.jsonl"))
for p <- sessions do
  id=Path.basename(p,".jsonl")
  {:ok, events}=Journal.load(Path.dirname(p),id)
  {:ok,_}=Session.Saved.restore(events,id)
  {:ok,%{"release_claim" => "signed_release_claim"}}=Session.Saved.inspect_saved(Path.dirname(p),id)
end
assert Enum.all?(control["operations"], fn {_,op} -> op["status"] == "settled" end)
{:ok, after_snapshot}=ObservedRead.read(collection,ns,%{"op" => "snapshot"})
assert before === after_snapshot
{:ok, ^control}=Consent.existing_snapshot(SemanticAdmission.control_root(home),binding["project_id"])
report=%{"generation"=>9,"control_sequence"=>9,"marker_present"=>true,"new_record_count"=>1,"new_record_sha256"=>new["sha256"],"saved_sessions"=>length(sessions),"root_sha256"=>before["witness"]["root_sha256"],"qualification"=>false}
File.write!(output,Jason.encode!(report)<>"\n",[:exclusive])
IO.puts("NATIVE_LOCK_FAULT_INSPECTION_PASSED")
