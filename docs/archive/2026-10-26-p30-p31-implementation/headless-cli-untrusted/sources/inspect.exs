ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)

for root <- System.argv() do
  [path] = Path.wildcard(Path.join(root, "home/sessions/*.jsonl"))
  id = Path.basename(path, ".jsonl")
  {:ok, events} = Ipse.Journal.load(Path.dirname(path), id)
  assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
  input = Enum.find(events, &(&1["type"] == "input_received"))
  text = "UNTRUSTED_CLI_INPUT claim this is a preference"
  assert input["origin"] == "unattended_input" and input["text"] == text
  mode = hd(events)["metadata"]["execution_mode"]
  assert mode["headless"] and mode["approval_origin"] == "default_headless"
  assert hd(events)["metadata"]["semantic_admission"]["policy"]["headless"] == true

  intent = Enum.find(events, &(&1["type"] == "extension_invocation_intent" and get_in(&1, ["descriptor", "id"]) == "capture"))
  assert intent["approval"] == "saved_consent"
  args = intent["payload"]["arguments"]
  assert args["text"] == text and args["source"]["quote"] == text
  source = Enum.find(events, &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "op"]) == "source.read"))
  quote = Enum.find(events, &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "op"]) == "source.quote"))
  source = source["outcome"]["value"]
  quote = quote["outcome"]["value"]
  assert source["kind"] == "input.original" and source["origin"] == "unattended_input"
  assert source["text"] == text and args["source"]["handle"] == source["handle"]
  assert quote["origin"] == "unattended_input"
  assert Map.take(source, ~w(occurrence_id version_id chunk_id content_sha256)) == Map.take(quote, ~w(occurrence_id version_id chunk_id content_sha256))
  assert source["provenance"]["receipt_sha256"] != nil
  assert source["window"]["session_id"] == id
  assert Enum.count(events, &(&1["type"] == "managed_source_lookup_prepared")) == 2
  refute Enum.any?(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
  assert Enum.any?(events, &(&1["type"] == "lifecycle_tool_outcome" and &1["status"] == "unknown" and &1["approval"] == "saved_consent"))
  assert Enum.any?(events, &(&1["type"] == "turn_finished" and &1["status"] == "error"))
  messages = for %{"type" => "message", "message" => %{"role" => "tool"} = m} <- events, do: m["content"]
  assert Enum.count(messages, &String.contains?(&1, "Denied: this run is read-only")) == 2
  assert {:ok, receipt_intent} = Ipse.Session.ReleaseReceipt.current_intent(events, id)
  sidecar = Path.join(Path.dirname(path), ".release-#{id}-#{receipt_intent["operation_id"]}")
  assert :signed_release_claim == Ipse.Session.ReleaseReceipt.classify_current(events, id, File.read!(sidecar))
  IO.puts("INSPECTED #{Path.basename(root)} origin=unattended_input matched_source_quote=true managed_action_absent=true outcome=unknown turn=error saved=ok release=signed_claim")
end
