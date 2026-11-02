ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{CLI, JSON, Journal, Usage}
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ManagedPages
{:ok, _} = Application.ensure_all_started(:ipse)
[root, mode] = System.argv()
assert mode in ~w(cancel reject)
home = Path.join(root, "home")
cwd = Path.join(root, "work")
System.put_env("IPSE_HOME", home)

for env <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(env)

fixture = root |> Path.join("pending-rejection.json") |> File.read!() |> Jason.decode!()
namespace = fixture["namespace"]
collection = SemanticAdmission.collection_root(home)

read = fn key ->
  assert {:ok, view} = Collection.open_view(collection, namespace)

  try do
    assert {:ok, %{"records" => [record]}} =
             Collection.view_read(view, %{"op" => "get_many", "keys" => [key]})

    record
  after
    assert :ok = Collection.close_view(view)
  end
end

target = read.(fixture["key"])
peer = read.(fixture["peer_key"])
assert target["value"]["kind"] === "proposal" and target["value"]["state"] === "pending"
[proof] = get_in(target, ["value", "evidence", "sources"])
sessions = Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})
options = ["--cwd", cwd, "--config", Path.join(home, "config.json"), "--no-project-config"]
if mode == "reject", do: assert(CLI.run(["knowledge", "disable"] ++ options) == 0)
assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)
assert {:ok, before_control} = Consent.existing_snapshot(control, binding["project_id"])
if mode == "reject", do: assert(before_control["policy"] === nil)
assert {:ok, view} = Collection.open_view(collection, namespace)

anchor_key =
  try do
    assert {:ok, selected} =
             Collection.view_neighbors(view, %{
               "version" => 1,
               "prefix" => ManagedPages.prefix(:anchor),
               "fence_bytes" => ManagedPages.width(:anchor),
               "needle" => target["value"]["lineage"]
             })

    selected["neighbors"]["selected"]["key"]
  after
    assert :ok = Collection.close_view(view)
  end

anchor = read.(anchor_key)

assert {:ok, backup} =
         Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

old_journals = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))
source = Path.join(fixture["history_dir"], proof["session_id"] <> ".jsonl")
held = source <> ".rejection-unavailable"

if mode == "reject" do
  assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
  File.rename!(source, held)
  assert :ok = Ipse.Runner.unlock(lock)
end

code =
  try do
    CLI.run(["knowledge", "reject", fixture["key"]] ++ options)
  after
    if File.exists?(held) do
      assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
      File.rename!(held, source)
      assert :ok = Ipse.Runner.unlock(lock)
    end
  end

assert code == if(mode == "reject", do: 0, else: 1)
assert read.(fixture["peer_key"]) === peer
assert read.(anchor_key) === anchor

assert sessions ===
         Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})

[journal] = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl")) -- old_journals
assert {:ok, %{events: events, tail: :none}} = Journal.read_path(journal)
assert {:ok, after_control} = Consent.existing_snapshot(control, binding["project_id"])
"pending." <> id = fixture["key"]

if mode == "cancel" do
  assert read.(fixture["key"]) === target
  assert read.("reject." <> id) === nil
  assert after_control === before_control

  assert {:ok, ^backup} =
           Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

  refute Enum.any?(events, &(&1["type"] == "managed_lifecycle_intent"))
else
  assert read.(fixture["key"]) === nil
  suppression = read.("reject." <> id)
  assert suppression["value"]["candidate_id"] === id
  [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
  assert intent["facts"]["target"] === target
  assert get_in(intent, ["facts", "target", "value", "evidence", "sources"]) === [proof]
  [operation_id] = Map.keys(after_control["operations"]) -- Map.keys(before_control["operations"])
  assert operation_id === intent["operation_id"]
  operation = after_control["operations"][operation_id]
  assert operation["status"] === "settled"
  assert operation["actual"]["operations"] === 1
  assert operation["actual"]["model_calls"] === 0 and operation["actual"]["download_bytes"] === 0
  assert operation["actual"]["cost_nanos"] === 0

  assert {:ok,
          %{"control_status" => "settled", "journal_status" => "settled", "replayed" => false}} =
           CLI.Knowledge.Management.operation(
             %{home: home},
             cwd,
             Path.basename(journal, ".jsonl")
           )

  assert {:ok, current} =
           Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

  import_request = %{
    "op" => "import",
    "project" => namespace,
    "floor" => backup["floor"],
    "expected_generation" => current["generation"],
    "advance_floor" => true,
    "changes" => [
      %{"key" => fixture["key"], "expected_revision" => 0, "value" => target["value"]}
    ]
  }

  assert {:failed, %{"code" => "collection_import_floor"}} =
           Collection.execute(collection, namespace, import_request, Usage.id())

  assert {:ok, ^current} =
           Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())
end

IO.puts("PUBLIC_SESSION_PENDING_REJECTION_#{String.upcase(mode)}_PASSED")
