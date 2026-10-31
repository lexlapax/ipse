ExUnit.start(autorun: false)
import ExUnit.Assertions
lines = File.stream!("/tmp/ipse-headless-typed-root-cache-20261029.log") |> Enum.to_list()
get = fn tag ->
  line = Enum.find(lines, &String.starts_with?(&1, tag))
  Jason.decode!(String.replace_prefix(line, tag, ""))
end
events = get.("HEADLESS_CAPTURE_EVENTS ")
consent = get.("HEADLESS_CONSENT ")
root = get.("HEADLESS_ROOT ")
intent = Enum.find(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
result = Enum.find(events, &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"]))
operation = consent["operations"][intent["operation_id"]]
assert operation["status"] == "settled" and operation["headless"] == true
assert operation["receipt"] === result["outcome"] and result["outcome"]["status"] == "ok"
assert operation["actual"]["operations"] == 1 and operation["actual"]["model_calls"] == 0
assert root["snapshot"]["generation"] == 1 and root["snapshot"]["floor_anchor"] == intent["operation_id"]
[record] = root["page"]["records"]
[proof] = record["value"]["evidence"]["sources"]
assert proof["origin"] == "typed_host_outcome" and proof["kind"] == "tool.outcome"
calls = for event <- events, call <- get_in(event, ["message", "tool_calls"]) || [], do: call
for name <- ~w(write shell) do
  call = Enum.find(calls, &(get_in(&1, ["function", "name"]) == name))
  message = Enum.find(events, &(get_in(&1, ["message", "tool_call_id"]) == call["id"]))
  assert get_in(message, ["message", "ipse_tool_outcome", "status"]) == "denied"
end
IO.puts("HEADLESS_SETTLED_EXACT_RESULT input_bytes=#{operation["actual"]["input_bytes"]} output_bytes=#{operation["actual"]["output_bytes"]} generation=1 write_and_shell=denied")
