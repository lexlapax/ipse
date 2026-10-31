Code.require_file("extensions/knowledge/src/knowledge/decision_policy.ex")
alias IpseKnowledge.Knowledge.DecisionPolicy, as: Policy

rows = [%{"id" => "a", "rendered" => "A!"}, %{"id" => "b", "rendered" => "雪"}]
packs = [%{"id" => "left", "members" => ["a"]}, %{"id" => "right", "members" => ["b"]}]
policies = [Policy.default("notes.select"), Map.merge(Policy.default("notes.select"), %{"strategy" => "decision", "profile" => "audit"})]

for availability <- ~w(available unavailable unknown),
    coverage <- ~w(complete partial unknown),
    {count, bytes} <- [{2, 5}, {3, 5}, {3, 6}, {3, 9}, {0, 0}, {nil, nil}],
    allocation <- [0, 2, 3, 4, 5, 9],
    budget <- [true, false],
    policy <- policies,
    mode <- [:production, :development_experiment],
    reduce: %{accepted: 0, rejected: 0, requests: 0} do
  stats ->
    f = %{"version" => 1, "availability" => availability, "coverage" => coverage,
      "allocation_bytes" => allocation, "eligible_count" => count, "eligible_rendered_bytes" => bytes,
      "budget_available" => budget, "query" => "synthetic", "candidates" => rows,
      "alternatives" => packs, "baseline_id" => "left"}
    case Policy.plan(policy, f, mode) do
      {:error, :invalid_decision_policy} ->
        %{stats | rejected: stats.rejected + 1}
      {:ok, p} ->
        if coverage == "complete" and (not is_integer(count) or not is_integer(bytes) or count < 2 or bytes < 5 + count - 2 or (count == 2 and bytes != 5)), do: raise "contradictory total accepted"
        if mode == :production and p.request != nil, do: raise "production request"
        if policy["strategy"] == "none" and p.request != nil, do: raise "none request"
        if (availability != "available" or coverage != "complete") and (p.request != nil or p.baseline != nil), do: raise "unknown coverage baseline or request"
        if availability == "available" and coverage == "complete" and is_integer(bytes) and bytes <= allocation and count != 2 and (p.request != nil or p.baseline != nil), do: raise "missing fitting rows selected"
        if p.request != nil and (mode != :development_experiment or availability != "available" or coverage != "complete" or not budget or bytes <= allocation or length(p.mapping) < 2), do: raise "request outside eligible stratum"
        if is_map(p.baseline) do
          selected = p.baseline["members"]
          if Enum.any?(selected, &(&1 not in ~w(a b))), do: raise "foreign baseline"
          if Enum.sum(for row <- rows, row["id"] in selected, do: byte_size(row["rendered"])) > allocation, do: raise "oversized baseline"
          if availability == "available" and coverage == "complete" and count == 2 and bytes <= allocation and selected != ~w(a b), do: raise "fitting set omitted"
        end
        if p.request == nil do
          case Policy.apply(p, nil) do
            {:ok, %{"action" => action}} when action == p.baseline -> :ok
            other -> raise "bad zero-call action #{inspect(other)}"
          end
        else
          question = hd(p.request["questions"])
          choices = question["choices"]
          first = hd(choices)
          reply = %{"version" => 1, "answers" => [%{"id" => "pack", "type" => "choice", "choice" => first, "confidence" => 0.1,
            "probabilities" => Enum.map(choices, fn c -> %{"id" => c, "probability" => if(c == first, do: 0.9, else: 0.1 / (length(choices) - 1))} end)}]}
          {:ok, %{"action" => action}} = Policy.apply(p, reply)
          expected = Enum.find(p.mapping, &(&1["id"] == first))
          if action != %{"pack" => first, "members" => expected["members"]}, do: raise "choice mapping mismatch"
          case Policy.apply(p, %{"version" => 1, "answers" => []}) do
            {:ok, %{"action" => action, "receipt" => %{"reason" => "malformed_advice"}}} when action == p.baseline -> :ok
            _ -> raise "bad malformed fallback"
          end
        end
        %{stats | accepted: stats.accepted + 1, requests: stats.requests + if(p.request, do: 1, else: 0)}
    end
end
|> IO.inspect(label: "coverage-grid")
