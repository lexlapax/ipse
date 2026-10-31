ExUnit.start(autorun: false)
import ExUnit.Assertions
for {name, logfile, expected} <- [
  {"model", "/tmp/ipse-headless-model-selected-v3-20261029.log", 2},
  {"quote", "/tmp/ipse-headless-model-quote-20261029.log", 3}
] do
  lines = File.stream!(logfile) |> Enum.to_list()
  get = fn tag ->
    line = Enum.find(lines, &String.starts_with?(&1, tag))
    Jason.decode!(String.replace_prefix(line, tag, ""))
  end
  assert Enum.any?(lines, &String.starts_with?(&1, "HEADLESS_DONE :error"))
  assert Enum.any?(lines, &String.starts_with?(&1, "HEADLESS_SOURCE_PREVIEWS_STATUS_ONLY"))
  events = get.("HEADLESS_EVENTS ")
  assert Enum.any?(events, &(&1["type"] == "managed_output_release_result" and &1["decision"] == "historical_write"))
  assert Enum.any?(events, &(&1["type"] == "managed_preflight_refused"))
  root = get.("HEADLESS_ROOT ")
  consent = get.("HEADLESS_CONSENT ")
  prepared = Enum.filter(events, &(&1["type"] == "managed_source_lookup_prepared"))
  observed = Enum.filter(events, &(&1["type"] == "managed_tool_result_observed" and &1["version"] == 2))
  assert length(prepared) == expected and length(observed) == expected
  for p <- prepared do
    result = Enum.find(observed, &(&1["call_id"] == p["call_id"]))
    assert result["source_selection_sha256"] == p["selection_sha256"]
  end
  intent = Enum.find(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
  result = Enum.find(events, &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"]))
  operation = consent["operations"][intent["operation_id"]]
  assert operation["status"] == "settled" and operation["headless"] == true
  assert operation["receipt"] == result["outcome"] and result["outcome"]["status"] == "ok"
  assert root["snapshot"]["generation"] == 1 and root["snapshot"]["floor_anchor"] == intent["operation_id"]
  [record] = root["page"]["records"]
  [proof] = record["value"]["evidence"]["sources"]
  assert proof["origin"] == "typed_host_outcome" and proof["kind"] == "tool.outcome"
  calls = for event <- events, call <- get_in(event, ["message", "tool_calls"]) || [], do: call
  for tool <- ~w(write shell) do
    call = Enum.find(calls, &(get_in(&1, ["function", "name"]) == tool))
    result_message = Enum.find(events, &(get_in(&1, ["message", "tool_call_id"]) == call["id"]))
    assert get_in(result_message, ["message", "ipse_tool_outcome", "status"]) == "denied"
  end
  IO.puts("#{name}: #{expected} source lookups, settled receipt/floor, typed proof, write/shell denied, continuation refused")
end
