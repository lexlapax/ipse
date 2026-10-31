ExUnit.start(autorun: false)
import ExUnit.Assertions
lines = File.stream!("/tmp/ipse-remember-absence-integration-20261029.log") |> Enum.to_list()
get = fn tag ->
  line = Enum.find(lines, &String.starts_with?(&1, tag))
  {:ok, value} = Jason.decode(String.replace_prefix(line, tag, ""))
  value
end
events = get.("REMEMBER_EVENTS ")
root = get.("REMEMBER_ROOT ")
consent = get.("REMEMBER_CONSENT ")
assertion_index = Enum.find_index(events, &(&1["type"] == "operator_assertion"))
intent_index = Enum.find_index(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
assert is_integer(assertion_index) and is_integer(intent_index) and assertion_index < intent_index
intent = Enum.at(events, intent_index)
result = Enum.find(events, &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"]))
assert result["outcome"]["status"] == "ok"
operation = consent["operations"][intent["operation_id"]]
assert operation["status"] == "settled" and operation["receipt"] == result["outcome"]
assert operation["actual"]["operations"] == 1 and operation["actual"]["input_bytes"] > 0 and operation["actual"]["model_calls"] == 0
assert root["snapshot"]["generation"] == 1 and root["snapshot"]["floor_anchor"] == intent["operation_id"]
[record] = root["page"]["records"]
assert record["operation_id"] == intent["operation_id"]
normalization = operation["receipt"]["value"]["normalization"]
assert normalization["record_key"] == record["key"] and normalization["version"] == 3
assert normalization["valid_until_ms"] - normalization["first_admitted_ms"] == 90 * 86_400_000
assert length(normalization["metadata_changes"]) == 3
IO.puts("EXACT_SETTLED_OPERATION_MATCHED actual_input_bytes=#{operation["actual"]["input_bytes"]} actual_output_bytes=#{operation["actual"]["output_bytes"]} generation=1 floor=1")
