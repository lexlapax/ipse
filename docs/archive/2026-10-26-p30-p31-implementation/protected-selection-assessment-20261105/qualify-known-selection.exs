import ExUnit.Assertions
alias Ipse.{Session,Journal,JSON}
alias Ipse.Extension.{ResultSource,Consent,Collection,ProjectIdentity,SemanticAdmission}
base=Path.dirname(__ENV__.file)
root="/dev/shm/ipse-selection-assessment-phased-20261105-03/actor"
dir=Path.join(root,"sessions")
read=fn path->path |> File.read!() |> Jason.decode!()end
p=read.(Path.join(root,"setup-checkpoint.json"))
terminal=read.(Path.join(root,"selection-terminal.json"))
assert terminal["terminal_status"]===0
id=terminal["session_id"]
{:ok,events}=Journal.load(dir,id)
assert {:ok,_}=Session.Saved.restore(events,id)
receipt=read.(Path.join(root,"selection-observed.json"))["output"]
true=ResultSource.valid_descriptor?(receipt)
{:ok,index}=ResultSource.restore(events)
{:ok,source}=ResultSource.readable_source(index,receipt)
true=source.intent["descriptor"]["id"]==="select_shadow"
true=source.intent["payload"]["arguments"]===p["arguments"]
{:ok,result}=ResultSource.read_saved(dir,id,receipt["output_id"])
true=byte_size(result.bytes)===receipt["byte_count"]
true=JSON.sha256(result.bytes)===receipt["sha256"]
[final]=Enum.filter(events,&(&1["type"]=="extension_invocation_result" and &1["invocation_id"]==source.intent["invocation_id"]))
true=final["delivery"]===receipt
true=ResultSource.published?(index,final)
[release_intent]=Enum.filter(events,&(&1["type"]=="managed_output_release_intent" and &1["parent_invocation_id"]==source.intent["invocation_id"]))
[release]=Enum.filter(events,&(&1["type"]=="managed_output_release_result" and &1["release_id"]==release_intent["release_id"]))
[cleanup]=Enum.filter(events,&(&1["type"]=="managed_output_release_cleanup" and &1["release_id"]==release_intent["release_id"]))
true=Session.ManagedOutput.bound_result?(release_intent,final)
true=Session.ManagedOutput.valid_admission?(release,release_intent,final,[])
true=Session.ManagedOutput.valid_cleanup?(cleanup,release_intent,release)
true=release["decision"]==="current" and cleanup["status"]==="confirmed"
ast=Code.string_to_quoted!(File.read!(Path.join(base,"selection_assessment_phased.exs")))
ast=Macro.prewalk(ast,fn
 {:defmodule,meta,[_,body]}->{:defmodule,meta,[{:__aliases__,[],[:Ipse,:Test,:KnownSelectionAssertions]},body]}
 {:defp,meta,[{name,m,args},body]} when name in [:assert_selection,:assert_checkpoint]->{:def,meta,[{name,m,args},body]}
 node->node
end)
{_,[]}=Code.with_diagnostics(fn->Code.compile_quoted(ast,"verification-only-known-selection.exs")end)
Ipse.Test.KnownSelectionAssertions.assert_selection(%{output: result.value,events: events},p["keys"])
# Fresh read-only owners; no Session/provider/decision/publication is started.
{:ok,_}=Application.ensure_all_started(:ipse)
true=:sys.get_state(Session.Input).entries===%{}
home=Path.join(root,"home")
cwd=Path.join(root,"project")
{:ok,project}=ProjectIdentity.existing(home,cwd)
{:ok,calls}=Agent.start_link(fn->[]end)
c=%{root: root,dir: dir,path: Path.join(home,"config.json"),collection: SemanticAdmission.collection_root(home),control: SemanticAdmission.control_root(home),project: project,calls: calls}
Ipse.Test.KnownSelectionAssertions.assert_checkpoint(c,p,1)
{:ok,policy}=Consent.existing_snapshot(c.control,project["project_id"])
new=Map.drop(policy["operations"],Map.keys(p["policy"]["operations"])) |> Map.values()
true=length(new)===1
true=Enum.all?(new,&(&1["status"]==="settled" and &1["actual"]["model_calls"]===1))
true=Enum.all?(Map.values(p["policy"]["operations"]),&(get_in(&1,["actual","model_calls"])===0))
remaining=policy["policy"]["limits"]["model_calls"]-Enum.sum(Enum.map(new,& &1["actual"]["model_calls"]))
true=remaining===1
beforecontrol=policy
{:ok,snapshot}=Collection.execute(c.collection,p["namespace"],%{"op"=>"snapshot"},Ipse.Usage.id())
true=snapshot===p["snapshot"]
for key<-p["keys"] do
 {:ok,%{"record"=>record}}=Collection.execute(c.collection,p["namespace"],%{"op"=>"get","key"=>key},Ipse.Usage.id())
 true=is_map(record)
end
{:ok,aftercontrol}=Consent.existing_snapshot(c.control,project["project_id"])
true=aftercontrol===beforecontrol
true=:sys.get_state(Session.Input).entries===%{}
checkpoint=%{"status"=>"known_closed","output"=>result.value,"main_wire_calls"=>2,"decision_wire_calls"=>1,"qualification"=>"exact_saved_result_materialized_after_original_failed_pipeline","selection_journal_sha256"=>JSON.sha256(File.read!(Path.join(dir,id<>".jsonl"))),"delivery_sha256"=>receipt["sha256"]}
File.write!(Path.join(root,"selection-checkpoint.json"),Jason.encode!(checkpoint)<>"\n",[:exclusive])
report=%{status: "known_selection_qualified",original_pipeline: "failed_preserved",materialized_bytes: byte_size(result.bytes),descriptor_and_value_hash_match: true,actual_current_release_and_confirmed_cleanup: true,saved: true,all_selection_assertions: true,baseline_included: result.value["baseline"]["included"],candidate_included: result.value["candidate"]["included"],eligible_count: result.value["eligible_count"],allocation_bytes: result.value["allocation_bytes"],eligible_rendered_bytes: result.value["eligible_rendered_bytes"],read_bindings: length(result.value["reads"]),original_fingerprints: "unchanged_named_lock_ctime_allowance",native_snapshot_unchanged: true,all_original_note_keys_present: true,policy_unchanged: true,new_settled_model_calls: 1,remaining_model_calls: remaining,selection_checkpoint_sha256: JSON.sha256(File.read!(Path.join(root,"selection-checkpoint.json"))),no_model_or_decision_or_publication_during_qualification: true}
File.write!(Path.join(base,"evidence/known-selection-qualified.json"),Jason.encode!(report)<>"\n",[:exclusive])
Agent.stop(calls)
IO.puts(Jason.encode!(report))
