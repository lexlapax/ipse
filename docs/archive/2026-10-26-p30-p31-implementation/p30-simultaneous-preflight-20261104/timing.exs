[root] = System.argv()
for child <- ~w(first second) do
  info = root |> Path.join(child <> "/barrier.json") |> File.read!() |> :json.decode()
  hold = root |> Path.join(child <> "/hold.json") |> File.read!() |> :json.decode()
  events = File.stream!(Path.join(root, "sessions/" <> info["session_id"] <> ".jsonl")) |> Enum.map(&:json.decode/1)
  operation = info["operation_id"]
  [finished] = Enum.filter(events, &(&1["type"] == "request_finished" and &1["request_id"] == operation))
  [preflight] = Enum.filter(events, &(&1["type"] == "managed_preflight_intent" and &1["request_id"] == operation))
  IO.puts(:json.encode(%{child: child, held_ms: hold["hold_ms"], decision_request_duration_ms: finished["duration_ms"], preflight_budget_ms: preflight["deadline_ms"] - preflight["checked_at_ms"], finality: finished["finality"], outcome: finished["outcome"], decision_dispatch_intents: Enum.count(events, &(&1["type"] == "inference_dispatch_intent" and &1["request_id"] == operation))}))
end
