Code.require_file("metrics.exs", __DIR__)

defmodule Ipse.Development.Evaluation.DecisionMetrics do
  @moduledoc """
  Pure comparison of bounded aggregate decision-consumer measurements.

  This does not run an experiment or verify labels, matching, reviewer
  independence, latency instrumentation, cost accounting, or any hard gate.
  The caller must establish those facts separately. Unknown measurements stay
  unverified; all comparisons use integer arithmetic.
  """

  @error {:error, :invalid_decision_metrics}
  @max 9_007_199_254_740_991
  @fields ~w(cases supported abstentions critical_total critical_recalled citation_total citation_supported cost_nanos p95_ms)
  @gate_fields ~w(protocol quality_bars citation_integrity matched_workload finite_resources paired_critical)
  @assessment_fields ~w(candidates abstentions false_total false_durable useful_total useful_kept critical_total critical_kept cost_nanos p95_ms)
  @assessment_gates ~w(protocol matched_workload finite_cost_cap)

  @doc "Compare the frozen P30 selection thresholds over independently supplied aggregates."
  def selection(baseline, candidate, gates) do
    with true <- aggregate?(baseline) and aggregate?(candidate) and gates?(gates),
         true <- baseline["cases"] == candidate["cases"],
         true <- baseline["critical_total"] == candidate["critical_total"] do
      criteria = %{
        "hard_gates" => gate_status(gates),
        "critical_recall" => compare_critical(baseline, candidate),
        "citation_precision" => compare_citations(baseline, candidate),
        "latency" => compare_latency(baseline, candidate),
        "benefit" => compare_benefit(baseline, candidate),
        "abstention" => compare_abstention(baseline, candidate, "cases")
      }

      {:ok, result(criteria, gates, baseline, candidate, "cases")}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Compare the frozen candidate-assessment thresholds over supplied aggregates."
  def assessment(baseline, candidate, gates) do
    with true <- assessment?(baseline) and assessment?(candidate),
         true <- gate_values?(gates, @assessment_gates),
         true <-
           Enum.all?(
             ~w(candidates false_total useful_total critical_total),
             &(baseline[&1] == candidate[&1])
           ) do
      criteria = %{
        "hard_gates" => gate_status(gates),
        "false_durable_reduction" => false_reduction(baseline, candidate),
        "useful_capture" => capture_nonregression(baseline, candidate, "useful"),
        "critical_capture" => capture_nonregression(baseline, candidate, "critical"),
        "latency" => compare_latency(baseline, candidate),
        "cost" => compare_cost(baseline, candidate)
      }

      {:ok, result(criteria, gates, baseline, candidate, "candidates")}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Compare paired critical-case outcomes without treating missing work as a pass."
  def critical_pairs(queries, baseline, candidate) do
    with true <- is_list(queries) and length(queries) in 1..1024,
         true <- binary_pair_values?(baseline) and binary_pair_values?(candidate),
         {:ok, paired} <- Ipse.Development.Evaluation.Metrics.paired(queries, baseline, candidate) do
      eligible = Enum.filter(paired["rows"], & &1["applicable"])

      unknown =
        Enum.count(eligible, fn row ->
          row["baseline"]["status"] != "ok" or row["variant"]["status"] != "ok" or
            is_nil(row["baseline"]["value"]) or is_nil(row["variant"]["value"])
        end)

      losses =
        for row <- eligible,
            row["baseline"]["status"] == "ok",
            row["variant"]["status"] == "ok",
            row["baseline"]["value"] == 1,
            row["variant"]["value"] == 0,
            do: row["query_id"]

      gate =
        cond do
          eligible == [] or unknown > 0 -> "unverified"
          losses != [] -> "fail"
          true -> "pass"
        end

      {:ok,
       %{
         "status" => gate,
         "eligible" => length(eligible),
         "unverified" => unknown,
         "regressed_query_ids" => losses
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp binary_pair_values?(rows),
    do:
      is_list(rows) and length(rows) <= 1024 and
        Enum.all?(rows, fn row -> is_map(row) and row["value"] in [nil, 0, 1] end)

  defp result(criteria, gates, baseline, candidate, denominator) do
    disposition =
      cond do
        Enum.any?(criteria, fn {_, status} -> status == "unverified" end) -> "unverified"
        Enum.any?(criteria, fn {_, status} -> status == "fail" end) -> "evaluated_rejected"
        true -> "useful_candidate"
      end

    %{
      "disposition" => disposition,
      "criteria" => criteria,
      "gate_details" => gates,
      "abstentions" => %{
        "denominator" => baseline[denominator],
        "baseline" => baseline["abstentions"],
        "candidate" => candidate["abstentions"]
      }
    }
  end

  defp aggregate?(row) do
    keys?(row, @fields) and uint?(row["cases"]) and row["cases"] > 0 and
      count?(row["supported"], row["cases"]) and count?(row["abstentions"], row["cases"]) and
      uint?(row["critical_total"]) and
      row["critical_total"] <= row["cases"] and
      count?(row["critical_recalled"], row["critical_total"]) and
      uint?(row["citation_total"]) and count?(row["citation_supported"], row["citation_total"]) and
      nullable_uint?(row["cost_nanos"]) and nullable_uint?(row["p95_ms"])
  end

  defp assessment?(row) do
    keys?(row, @assessment_fields) and uint?(row["candidates"]) and row["candidates"] > 0 and
      count?(row["abstentions"], row["candidates"]) and
      Enum.all?(~w(false useful critical), fn kind ->
        count?(row[kind <> "_total"], row["candidates"]) and
          count?(
            row[kind <> if(kind == "false", do: "_durable", else: "_kept")],
            row[kind <> "_total"]
          )
      end) and nullable_uint?(row["cost_nanos"]) and nullable_uint?(row["p95_ms"])
  end

  defp gates?(gates), do: gate_values?(gates, @gate_fields)

  defp gate_values?(gates, fields),
    do: keys?(gates, fields) and Enum.all?(fields, &(gates[&1] in ~w(pass fail unverified)))

  defp gate_status(gates) do
    cond do
      Enum.any?(Map.values(gates), &(&1 == "unverified")) -> "unverified"
      Enum.any?(Map.values(gates), &(&1 == "fail")) -> "fail"
      true -> "pass"
    end
  end

  defp compare_critical(%{"critical_total" => 0}, _), do: "unverified"
  defp compare_critical(b, c), do: status(c["critical_recalled"] >= b["critical_recalled"])

  defp compare_citations(%{"citation_total" => 0}, _), do: "unverified"
  defp compare_citations(_, %{"citation_total" => 0}), do: "unverified"

  defp compare_citations(b, c),
    do:
      status(
        c["citation_supported"] * b["citation_total"] >=
          b["citation_supported"] * c["citation_total"]
      )

  defp compare_latency(%{"p95_ms" => base}, %{"p95_ms" => candidate})
       when is_integer(base) and base > 0 and is_integer(candidate),
       do: status(candidate * 5 <= base * 6)

  defp compare_latency(_, _), do: "unverified"

  # Abstaining more often than the baseline by over five percentage points fails.
  defp compare_abstention(b, c, denominator),
    do: status(100 * (c["abstentions"] - b["abstentions"]) <= 5 * b[denominator])

  # Whole-task cost, including the decision call, may exceed the baseline by at most a fifth.
  defp compare_cost(%{"cost_nanos" => base}, %{"cost_nanos" => candidate})
       when is_integer(base) and base > 0 and is_integer(candidate),
       do: status(candidate * 5 <= base * 6)

  defp compare_cost(_, _), do: "unverified"

  defp false_reduction(%{"false_durable" => 0}, _), do: "unverified"
  defp false_reduction(b, c), do: status(c["false_durable"] * 5 <= b["false_durable"] * 4)

  defp capture_nonregression(b, c, kind) do
    total = b[kind <> "_total"]

    if total == 0,
      do: "unverified",
      else: status(100 * (b[kind <> "_kept"] - c[kind <> "_kept"]) <= 2 * total)
  end

  defp compare_benefit(b, c) do
    improvement = 100 * (c["supported"] - b["supported"]) >= 5 * b["cases"]

    cost =
      case {b["cost_nanos"], c["cost_nanos"]} do
        {base, candidate} when is_integer(base) and base > 0 and is_integer(candidate) ->
          status(candidate * 5 <= base * 4)

        _ ->
          "unverified"
      end

    cond do
      improvement or cost == "pass" -> "pass"
      cost == "unverified" -> "unverified"
      true -> "fail"
    end
  end

  defp status(true), do: "pass"
  defp status(false), do: "fail"
  defp count?(value, total), do: uint?(value) and value <= total
  defp nullable_uint?(value), do: is_nil(value) or uint?(value)
  defp uint?(value), do: is_integer(value) and value in 0..@max
  defp keys?(map, fields), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(fields)
end
