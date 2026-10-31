ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root] = System.argv()
home = Path.join(root, "home")
[filename] = Path.wildcard(Path.join(home, "sessions/*.jsonl"))
id = Path.basename(filename, ".jsonl")
{:ok, events} = Ipse.Journal.load(Path.dirname(filename), id)
{:ok, saved} = Ipse.Session.Saved.restore(events, id)
admission = hd(events)["metadata"]["semantic_admission"]
assert Enum.any?(events, &(&1["type"] == "turn_finished" and &1["status"] == "ok"))
assert Enum.count(events, &(&1["type"] == "input_received")) == 1
assert Enum.count(events, &(&1["type"] == "managed_source_lookup_prepared")) == 4
assert Enum.any?(saved.messages, &Map.has_key?(&1, "ipse_root_history"))

action =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "collection.managed")
  )

assert Ipse.Extension.Actions.valid_result?(action) and action["outcome"]["status"] == "ok"
receipt = get_in(action, ["outcome", "value", "receipt"])
namespace = admission["pin"]["namespace"]
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

{:ok, inspected} =
  Ipse.Extension.Collection.execute(
    collection,
    namespace,
    %{"op" => "inspect", "operation_id" => action["operation_id"]},
    Ipse.Usage.id()
  )

assert inspected["operation"] === receipt

assert inspected["generation"] === receipt["generation"] and
         inspected["floor_anchor"] === action["operation_id"]

{:ok, consent} =
  Ipse.Extension.Consent.snapshot(
    Ipse.Extension.SemanticAdmission.control_root(home),
    admission["pin"]["project_id"]
  )

assert consent["operations"][action["operation_id"]]["status"] == "settled"
{:ok, intent} = Ipse.Session.ReleaseReceipt.current_intent(events, id)
sidecar = Path.join(Path.dirname(filename), ".release-#{id}-#{intent["operation_id"]}")

assert :signed_release_claim ==
         Ipse.Session.ReleaseReceipt.classify_current(events, id, File.read!(sidecar))

IO.puts(
  "INSPECTED turn=ok saved=ok root=exact receipt=matched floor_anchor=matched consent=settled subsequent_source_calls=2 input_events=1 release=signed_claim"
)
