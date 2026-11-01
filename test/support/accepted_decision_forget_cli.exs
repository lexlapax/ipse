ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, mode] = System.argv()
assert mode in ~w(cancel forget)
home = Path.join(root, "home")
cwd = Path.join(root, "work")
System.put_env("IPSE_HOME", home)
fixture = root |> Path.join("accepted-forget.json") |> File.read!() |> Jason.decode!()
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.{CLI, Journal, Usage}
collection = SemanticAdmission.collection_root(home)
namespace = fixture["namespace"]

read = fn key ->
  assert {:ok, result} =
           Collection.execute(collection, namespace, %{"op" => "get", "key" => key}, Usage.id())

  result["record"]
end

target = read.(fixture["key"])
link = read.(fixture["link_key"])
peer = read.(fixture["peer_key"])
assert target["value"]["kind"] == "accepted_decision"
assert peer["value"]["kind"] == "accepted_decision"
sessions = Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})
options = ["--cwd", cwd, "--config", Path.join(home, "config.json"), "--no-project-config"]
if mode == "forget", do: assert(CLI.run(["knowledge", "disable"] ++ options) == 0)
assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)
assert {:ok, before} = Consent.existing_snapshot(control, binding["project_id"])
management = Path.join(home, "knowledge-management")
old_journals = Path.wildcard(management <> "/*.jsonl")

source =
  Path.join(fixture["history_dir"], target["value"]["source_proof"]["session_id"] <> ".jsonl")

held = source <> ".forget-unavailable"

if mode == "forget" do
  assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
  File.rename!(source, held)
  assert :ok = Ipse.Runner.unlock(lock)
end

code =
  try do
    CLI.run(["knowledge", "forget", fixture["key"]] ++ options)
  after
    if File.exists?(held) do
      assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
      File.rename!(held, source)
      assert :ok = Ipse.Runner.unlock(lock)
    end
  end

assert code == if(mode == "forget", do: 0, else: 1)
assert read.(fixture["link_key"]) == link
assert read.(fixture["peer_key"]) == peer
assert {:ok, after_forget} = Consent.existing_snapshot(control, binding["project_id"])
assert [journal] = Path.wildcard(management <> "/*.jsonl") -- old_journals
assert {:ok, %{events: events, tail: :none}} = Journal.read_path(journal)

if mode == "forget" do
  assert read.(fixture["key"]) == nil
  assert [id] = Map.keys(after_forget["operations"]) -- Map.keys(before["operations"])
  operation = after_forget["operations"][id]
  assert operation["status"] == "settled" and operation["operation"] == "collection.forget"
  assert operation["actual"]["operations"] == 1

  for metric <- ~w(model_calls download_bytes cost_nanos),
      do: assert(operation["actual"][metric] == 0)

  assert [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
  assert intent["facts"]["kind"] == "managed_accepted_decision_forget"
  assert intent["facts"]["target"] == target

  assert [%{"status" => "settled"}] =
           Enum.filter(events, &(&1["type"] == "managed_lifecycle_result"))

  assert {:ok, :suppressed} =
           ProjectIdentity.with_existing_domain_auth(
             home,
             cwd,
             binding,
             %{namespace: namespace, format: "managed-metadata-v3"},
             fn cap, _ ->
               {:ok, view} = Collection.open_view(collection, namespace)

               try do
                 lineage = target["value"]["lineage"]
                 alias Ipse.Extension.Collection.ManagedPages

                 {:ok, neighbors} =
                   Collection.view_neighbors(view, %{
                     "version" => 1,
                     "prefix" => ManagedPages.prefix(:anchor),
                     "fence_bytes" => ManagedPages.width(:anchor),
                     "needle" => lineage
                   })

                 anchor_key = neighbors["neighbors"]["selected"]["key"]

                 {:ok, page} =
                   Collection.view_read(view, %{"op" => "get_many", "keys" => [anchor_key]})

                 [record] = page["records"]
                 {:ok, opened} = ManagedPages.open(cap, record, neighbors)
                 anchor = opened.entries[lineage]
                 assert anchor["choice"]["kind"] == "native_management"
                 assert anchor["choice"]["target_value_sha256"] == target["sha256"]
                 assert anchor["retirement"]["record_key"] == target["key"]
                 assert anchor["retirement"]["record_value_sha256"] == target["sha256"]

                 assert {:error, _} =
                          Ipse.Session.PendingAcceptance.retention_plan(
                            fixture["event"],
                            fixture["note_recipe"],
                            anchor,
                            nil,
                            System.system_time(:millisecond)
                          )

                 {:ok, :suppressed}
               after
                 assert :ok = Collection.close_view(view)
               end
             end
           )

  assert {:ok,
          %{"control_status" => "settled", "journal_status" => "settled", "replayed" => false}} =
           CLI.Knowledge.Management.operation(
             %{home: home},
             cwd,
             Path.basename(journal, ".jsonl")
           )
else
  assert read.(fixture["key"]) == target
  assert after_forget == before
  refute Enum.any?(events, &(&1["type"] == "managed_lifecycle_intent"))
end

assert sessions ==
         Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})

IO.puts("NATIVE_ACCEPTED_DECISION_#{String.upcase(mode)}_PASSED")
