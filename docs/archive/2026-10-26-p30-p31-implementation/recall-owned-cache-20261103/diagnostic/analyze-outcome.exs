proof = Path.expand(__DIR__)
root = "/dev/shm/ipse-json-recall33-diagnostic-state-20261103-01/fixture-tmp/ipse-native-recall-77a8460b49e6a4981a046200e867a84b"
outcome = root |> Path.join("diagnostic-outcome.json") |> File.read!() |> :json.decode()
rows = outcome["trace"]["records"]
completed = fn calls ->
 Enum.map(calls, fn call ->
  returned = Enum.find(rows, &(&1["event"] == "return" and &1["call_id"] == call["call_id"]))
  %{call_id: call["call_id"], at_us: call["at_us"], returned_at_us: returned && returned["at_us"], duration_us: returned && returned["at_us"] - call["at_us"], outcome: returned && returned["outcome"]}
 end)
end
cache = rows |> Enum.filter(&(&1["event"] == "call" and String.starts_with?(&1["mfa"], "Elixir.Ipse.Session.SourceReplayCache."))) |> Enum.group_by(&{&1["pid"], &1["mfa"]}) |> Enum.map(fn {{actor, mfa}, calls} ->
 spans = completed.(calls)
 durations = spans |> Enum.map(& &1.duration_us) |> Enum.reject(&is_nil/1)
 %{actor: actor, mfa: mfa, calls: length(calls), completed: length(durations), sum_us: Enum.sum(durations), first_at_us: hd(calls)["at_us"], last_call_at_us: List.last(calls)["at_us"], last_return_at_us: spans |> Enum.map(& &1.returned_at_us) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> nil end), open_call_ids: for(span <- spans, is_nil(span.returned_at_us), do: span.call_id)}
end)
boundaries = rows |> Enum.filter(&(&1["event"] in ["call", "return", "kill"] and not String.starts_with?(Map.get(&1, "mfa", ""), "Elixir.Ipse.Session.SourceReplayCache.")))
intent = root |> Path.join("recall-one-shot-intent.json") |> File.read!() |> :json.decode()
events = Path.join([root, "home/sessions", intent["session_id"] <> ".jsonl"]) |> File.stream!() |> Enum.map(&:json.decode/1)
dispatch = Enum.find(events, &(&1["type"] == "inference_dispatch_intent"))
fixed_unknown = "Inference service #{dispatch["service_id"]} has an unknown outcome. Inspect and reconcile its exact reservation before continuing; no request was replayed."
unknown_sha = :crypto.hash(:sha256, fixed_unknown) |> Base.encode16(case: :lower)
error_match = Enum.any?(outcome["errors"], &(get_in(&1, ["reason", "sha256"]) == unknown_sha and get_in(&1, ["reason", "bytes"]) == byte_size(fixed_unknown)))
summary = %{errors: outcome["errors"], error_matches_exact_fixed_unknown_service_summary_without_detail: error_match, prompt_started_at_us: outcome["prompt_started_at_us"], done_observed_at_us: outcome["done_observed_at_us"], listener: outcome["listener"], listener_task: outcome["listener_task"], collector_overflow: outcome["collector_overflow"], record_count: outcome["trace"]["record_count"], truncated: outcome["trace"]["truncated"], ancestry_overflow: outcome["trace"]["ancestry_overflow"], ancestry: outcome["trace"]["ancestry"], exits: outcome["trace"]["exits"], open_spans: outcome["trace"]["open_spans"], cache: cache, boundaries: boundaries}
File.write!(Path.join(proof, "decoded-outcome.json"), :json.encode(summary), [:exclusive])
IO.inspect(summary, charlists: :as_lists, limit: :infinity, printable_limit: :infinity)
