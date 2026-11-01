ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root] = System.argv()
alias Ipse.{CLI, Journal, Usage}
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
home = Path.join(root, "home")
cwd = Path.join(root, "work")
System.put_env("IPSE_HOME", home)
fixture = root |> Path.join("accepted-expiry.json") |> File.read!() |> Jason.decode!()
collection = SemanticAdmission.collection_root(home)
namespace = fixture["namespace"]
options = ["--cwd", cwd, "--config", Path.join(home, "config.json"), "--no-project-config"]

read = fn key ->
  assert {:ok, value} =
           Collection.execute(collection, namespace, %{"op" => "get", "key" => key}, Usage.id())

  value["record"]
end

target = read.(fixture["key"])
link = read.(fixture["link_key"])
peer = read.(fixture["peer_key"])
deadline = target["value"]["valid_until_ms"]
assert target["value"]["kind"] == "accepted_decision"
assert is_integer(deadline) and deadline > System.system_time(:millisecond)
assert deadline - System.system_time(:millisecond) < 15_000
assert {:ok, binding} = ProjectIdentity.existing(home, cwd)

row = fn family, needle ->
  assert {:ok, %{"entry" => value}} =
           ProjectIdentity.with_existing_domain_auth(
             home,
             cwd,
             binding,
             %{namespace: namespace, format: "managed-metadata-v3"},
             fn cap, _ ->
               assert {:ok, view} = Collection.open_view(collection, namespace)

               try do
                 alias Ipse.Extension.Collection.ManagedPages

                 assert {:ok, neighbors} =
                          Collection.view_neighbors(view, %{
                            "version" => 1,
                            "prefix" => ManagedPages.prefix(family),
                            "fence_bytes" => ManagedPages.width(family),
                            "needle" => needle
                          })

                 key = neighbors["neighbors"]["selected"]["key"]

                 assert {:ok, page} =
                          Collection.view_read(view, %{"op" => "get_many", "keys" => [key]})

                 assert page["witness"] == neighbors["witness"]
                 [record] = page["records"]
                 assert {:ok, opened} = ManagedPages.open(cap, record, neighbors)
                 {:ok, %{"entry" => opened.entries[needle]}}
               after
                 assert :ok = Collection.close_view(view)
               end
             end
           )

  value
end

lineage = target["value"]["lineage"]
live_id = Ipse.Extension.Collection.ManagedPages.live_identity(fixture["key"])
anchor = row.(:anchor, lineage)
live = row.(:live, live_id)

assert {:ok, metadata} =
         Ipse.Session.PendingAcceptance.retained_decision_metadata(
           fixture["recipe"],
           target,
           link,
           anchor,
           live
         )

assert metadata["valid_until_ms"] == deadline
control = SemanticAdmission.control_root(home)
sessions = Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})
assert CLI.run(["knowledge", "disable"] ++ options) == 0
assert {:ok, before} = Consent.existing_snapshot(control, binding["project_id"])
assert CLI.run(["knowledge", "expire", fixture["key"]] ++ options) == 1
assert read.(fixture["key"]) == target
assert {:ok, ^before} = Consent.existing_snapshot(control, binding["project_id"])
assert System.system_time(:millisecond) < deadline
wait = deadline - System.system_time(:millisecond) + 10
assert wait in 1..15_010
Process.sleep(wait)
assert System.system_time(:millisecond) >= deadline

source =
  Path.join(fixture["history_dir"], target["value"]["source_proof"]["session_id"] <> ".jsonl")

held = source <> ".expiry-unavailable"
assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
File.rename!(source, held)
assert :ok = Ipse.Runner.unlock(lock)
old_journals = Path.wildcard(home <> "/knowledge-management/*.jsonl")

code =
  try do
    CLI.run(["knowledge", "expire", fixture["key"]] ++ options)
  after
    assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
    File.rename!(held, source)
    assert :ok = Ipse.Runner.unlock(lock)
  end

assert code == 0
assert read.(fixture["key"]) == nil
assert read.(fixture["link_key"]) == link
assert read.(fixture["peer_key"]) == peer
assert row.(:anchor, lineage) == anchor
assert row.(:live, live_id) == nil
assert {:ok, after_expiry} = Consent.existing_snapshot(control, binding["project_id"])
assert [operation_id] = Map.keys(after_expiry["operations"]) -- Map.keys(before["operations"])
operation = after_expiry["operations"][operation_id]
assert operation["status"] == "settled" and operation["operation"] == "collection.expire"
assert operation["actual"]["operations"] == 1

for metric <- ~w(model_calls download_bytes cost_nanos),
    do: assert(operation["actual"][metric] == 0)

assert [journal] = Path.wildcard(home <> "/knowledge-management/*.jsonl") -- old_journals
assert {:ok, %{events: events, tail: :none}} = Journal.read_path(journal)
assert [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
assert intent["facts"]["kind"] == "managed_accepted_decision_expiry"
assert intent["facts"]["target"] == target
assert intent["facts"]["expired_at_ms"] == deadline

assert [%{"status" => "settled"}] =
         Enum.filter(events, &(&1["type"] == "managed_lifecycle_result"))

assert {:ok, %{"journal_status" => "settled", "control_status" => "settled", "replayed" => false}} =
         CLI.Knowledge.Management.operation(%{home: home}, cwd, Path.basename(journal, ".jsonl"))

assert sessions ==
         Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})

IO.puts("NATIVE_ACCEPTED_DECISION_EXPIRY_PASSED")
