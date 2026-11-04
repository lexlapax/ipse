roots = Path.wildcard("task-runtime/tmp/ipse-shadow-session-*") |> Enum.sort()
true = length(roots) == 11
summary =
  Enum.map(roots, fn root ->
    events =
      Path.wildcard(Path.join(root, "sessions/*.jsonl"))
      |> Enum.flat_map(fn path -> File.stream!(path) |> Enum.map(&Jason.decode!/1) end)

    intents = Enum.filter(events, &(&1["type"] == "extension_action_intent"))
    results = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    result_ids = MapSet.new(results, & &1["operation_id"])
    unmatched = Enum.count(intents, &(not MapSet.member?(result_ids, &1["operation_id"])))

    controls =
      Path.wildcard(Path.join(root, "home/**/control.json"), match_dot: true)
      |> Enum.flat_map(fn path ->
        case path |> File.read!() |> Jason.decode() do
          {:ok, %{"operations" => operations}} when is_map(operations) -> [operations]
          _ -> []
        end
      end)

    [operations] = controls
    statuses = operations |> Map.values() |> Enum.map(& &1["status"])
    true = Enum.all?(statuses, &(&1 in ~w(settled unknown)))

    advice =
      events
      |> Enum.filter(&(&1["type"] == "extension_invocation_result" and get_in(&1, ["value", "status"]) == "assessed"))
      |> Enum.map(fn event ->
        a = event["value"]["advice"] || %{}
        {a["choice"], a["reason"]}
      end)

    true = Enum.all?(advice, &(&1 in [{"defer_candidate", "selected"}, {"keep_baseline", "selected"}, {nil, "low_probability"}]))
    %{unmatched: unmatched, statuses: statuses, advice: advice}
  end)

unknown_count = Enum.count(summary, &("unknown" in &1.statuses))
true = unknown_count == 2
true = Enum.all?(summary, &(&1.unmatched == 0))
advice = summary |> Enum.flat_map(& &1.advice) |> Enum.frequencies()
true = advice[{"defer_candidate", "selected"}] == 1
IO.puts("synthetic_fixture_roots=11")
IO.puts("roots_with_unmatched_extension_action_intents=0")
IO.puts("roots_with_unknown_consent_operations=2")
IO.puts("defer_candidate_selected_results=1")
IO.puts("keep_baseline_selected_results=#{Map.get(advice, {"keep_baseline", "selected"}, 0)}")
IO.puts("low_probability_results=#{Map.get(advice, {nil, "low_probability"}, 0)}")
