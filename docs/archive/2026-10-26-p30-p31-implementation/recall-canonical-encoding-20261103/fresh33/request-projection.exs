root = "/dev/shm/ipse-json-recall33-20261103-01/fixture-tmp/ipse-native-recall-d3cb1f500d36011a3c2021bb37f5cfc5"
intent = root |> Path.join("recall-one-shot-intent.json") |> File.read!() |> :json.decode()
events = Path.join([root, "home/sessions", intent["session_id"] <> ".jsonl"]) |> File.stream!() |> Enum.map(&:json.decode/1)
header = List.first(events)
IO.inspect(Map.keys(header["metadata"]) |> Enum.sort(), label: "header_metadata_keys")
for {event, index} <- Enum.with_index(events), event["type"] in ~w(request_admitted managed_preflight_intent inference_dispatch_intent request_measured request_finished) do
  numbers = Map.filter(event, fn {_, value} -> is_number(value) or is_boolean(value) or is_nil(value) end)
  IO.inspect(%{index: index, type: event["type"], keys: Enum.sort(Map.keys(event)), numeric_fields: numbers}, limit: :infinity)
end
config = root |> Path.join("home/config.json") |> File.read!() |> :json.decode()
IO.inspect(%{provider_timeout_ms: get_in(config, ["profiles", "recall", "timeout_ms"]), provider: get_in(config, ["profiles", "recall", "provider"])}, label: "fixture_selected_profile")
