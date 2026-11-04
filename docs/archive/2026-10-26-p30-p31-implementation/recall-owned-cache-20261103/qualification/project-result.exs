proof = File.cwd!()
root = "/dev/shm/ipse-json-recall33-cache-qualification-state-20261103-01/fixture-tmp/ipse-native-recall-9dd9f888026f35ca74760e51e7003203"
result = root |> Path.join("recall-one-shot-result.json") |> File.read!() |> :json.decode()
intent = root |> Path.join("recall-one-shot-intent.json") |> File.read!() |> :json.decode()
events = Path.join([root, "home/sessions", intent["session_id"] <> ".jsonl"]) |> File.stream!() |> Enum.map(&:json.decode/1)
allowed = ~w(completed failed ok error partial final model text delivered)
safe = fn value -> if value in allowed, do: value, else: "other" end
requests = Enum.map(Enum.filter(events, &(&1["type"] in ~w(request_measured request_finished turn_finished))), fn event ->
 Map.new(["type", "kind", "outcome", "status", "finality", "duration_ms"], fn key ->
  value = event[key]
  {key, if(key in ["type", "duration_ms"], do: value, else: safe.(value))}
 end)
end)
counts = Enum.frequencies_by(events, & &1["type"])
inputs = events |> Enum.filter(&(&1["type"] == "worker_input_result")) |> Enum.frequencies_by(& &1["status"])
projection = %{result: result, dispatch_intent_count: Map.get(counts, "inference_dispatch_intent", 0), request_admitted_count: Map.get(counts, "request_admitted", 0), worker_inputs: inputs, requests: requests}
File.write!(Path.join(proof, "result-projection.json"), :json.encode(projection), [:exclusive])
IO.inspect(projection, limit: :infinity, charlists: :as_lists)
