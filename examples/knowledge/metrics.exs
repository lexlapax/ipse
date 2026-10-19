defmodule IpseKnowledge.Metrics do
  @moduledoc """
  Pure measurements over saved, normalized predictions and explicit review verdicts.

  Inputs are scoring projections, not prediction-time schemas. `expected_refusal`
  is a scoring-only annotation added after finalized prediction hashes and label
  exposure. Never give it to a predictor or model. Independent verdicts are supplied
  by the caller; this module does not assess entailment or reviewer independence.

  Each citation_id identifies one claim/span pair. Separate claims citing the same
  span need separate pair IDs; the caller must not collapse those pairs.

  A nil score is unmeasured or not applicable, never perfect quality. Latency
  quantiles include recorded censored lower bounds and failed observations. They
  do not estimate unseen completion times. Paired failed rows score zero while
  preserving their saved values; explicit non-applicability is declared separately.
  """
  @version 1
  @statuses ~w(ok partial failed refused timeout unavailable missing cancelled)
  @source_keys ~w(project source_id generation version sha256)

  def version, do: @version

  def retrieval(prediction, qrels) do
    with true <- exact?(prediction, ~w(status ranked_sources top_k)),
         true <-
           status?(prediction["status"]) and is_integer(prediction["top_k"]) and
             prediction["top_k"] in 1..128,
         ranked when is_list(ranked) <- prediction["ranked_sources"],
         true <- length(ranked) <= prediction["top_k"] and Enum.all?(ranked, &source?/1),
         true <- is_list(qrels) and Enum.all?(qrels, &qrel?/1) do
      grades =
        Enum.reduce(qrels, %{}, fn q, acc ->
          Map.update(acc, unit(q["source"]), q["grade"], &max(&1, q["grade"]))
        end)

      relevant = Map.filter(grades, fn {_, grade} -> grade > 0 end)
      ranking = Enum.uniq_by(ranked, &unit/1)
      positive_count = map_size(relevant)

      observed_recall =
        if positive_count > 0 and prediction["top_k"] >= 5 do
          Enum.count(Enum.take(ranking, 5), &Map.has_key?(relevant, unit(&1))) / positive_count
        end

      ideal = relevant |> Map.values() |> Enum.sort(:desc) |> Enum.take(10) |> dcg()

      observed_ndcg =
        if ideal > 0 and prediction["top_k"] >= 10 do
          ranking
          |> Enum.take(10)
          |> Enum.map(&Map.get(relevant, unit(&1), 0))
          |> dcg()
          |> Kernel./(ideal)
        end

      failed = prediction["status"] != "ok"

      {:ok,
       %{
         "metric_version" => @version,
         "status" => prediction["status"],
         "failed" => failed,
         "relevant_sources" => positive_count,
         "retrieved_sources" => length(ranking),
         "recall_at_5" => scored(observed_recall, failed),
         "ndcg_at_10" => scored(observed_ndcg, failed),
         "observed_recall_at_5" => observed_recall,
         "observed_ndcg_at_10" => observed_ndcg,
         "recall_reason" => metric_reason(positive_count, prediction["top_k"], 5),
         "ndcg_reason" => metric_reason(positive_count, prediction["top_k"], 10)
       }}
    else
      _ -> {:error, :invalid_retrieval_input}
    end
  rescue
    _ -> {:error, :invalid_retrieval_input}
  end

  def nearest_rank(values, percentile) do
    if is_list(values) and Enum.all?(values, &finite?/1) and finite?(percentile) and
         percentile > 0 and percentile <= 1 do
      value =
        if values != [],
          do: values |> Enum.sort() |> Enum.at(max(ceil(percentile * length(values)), 1) - 1)

      {:ok, value}
    else
      {:error, :invalid_percentile_input}
    end
  rescue
    _ -> {:error, :invalid_percentile_input}
  end

  def latency(samples) do
    if is_list(samples) and Enum.all?(samples, &latency_sample?/1) do
      elapsed =
        Enum.flat_map(samples, fn s ->
          if is_nil(s["elapsed_ms"]), do: [], else: [s["elapsed_ms"]]
        end)

      {:ok, p50} = nearest_rank(elapsed, 0.50)
      {:ok, p95} = nearest_rank(elapsed, 0.95)

      {:ok,
       %{
         "metric_version" => @version,
         "p50_ms" => p50,
         "p95_ms" => p95,
         "quantile_basis" => "observed_elapsed_including_censored_lower_bounds",
         "total_n" => length(samples),
         "measured_n" => length(elapsed),
         "censored_n" => Enum.count(samples, & &1["censored"]),
         "missing_n" => length(samples) - length(elapsed),
         "failed_n" => Enum.count(samples, &(&1["status"] != "ok"))
       }}
    else
      {:error, :invalid_latency_input}
    end
  rescue
    _ -> {:error, :invalid_latency_input}
  end

  def paired(queries, baseline, variant) do
    with true <-
           is_list(queries) and Enum.all?(queries, &query?/1) and unique?(queries, "query_id"),
         ids <- MapSet.new(Enum.map(queries, & &1["query_id"])),
         true <- rows?(baseline, ids) and rows?(variant, ids) do
      left = Map.new(baseline, &{&1["query_id"], &1})
      right = Map.new(variant, &{&1["query_id"], &1})

      rows =
        Enum.map(queries, fn q ->
          a = Map.get(left, q["query_id"], missing(q["query_id"]))
          b = Map.get(right, q["query_id"], missing(q["query_id"]))
          av = paired_value(a, q["applicable"])
          bv = paired_value(b, q["applicable"])
          delta = if is_number(av) and is_number(bv), do: bv - av

          %{
            "query_id" => q["query_id"],
            "applicable" => q["applicable"],
            "baseline" => Map.put(a, "scored_value", av),
            "variant" => Map.put(b, "scored_value", bv),
            "delta" => delta,
            "reason" =>
              cond do
                not q["applicable"] -> "not_applicable"
                is_nil(delta) -> "unmeasured"
                true -> nil
              end
          }
        end)

      deltas = Enum.flat_map(rows, fn r -> if is_nil(r["delta"]), do: [], else: [r["delta"]] end)
      eligible = Enum.count(queries, & &1["applicable"])
      complete = length(deltas) == eligible
      average = mean(deltas)

      {:ok,
       %{
         "metric_version" => @version,
         "rows" => rows,
         "total_n" => length(queries),
         "eligible_n" => eligible,
         "not_applicable_n" => length(queries) - eligible,
         "measured_pairs_n" => length(deltas),
         "unmeasured_pairs_n" => eligible - length(deltas),
         "failed_pairs_n" =>
           Enum.count(
             rows,
             &(&1["baseline"]["status"] != "ok" or &1["variant"]["status"] != "ok")
           ),
         "missing_pairs_n" =>
           Enum.count(
             rows,
             &(&1["baseline"]["status"] == "missing" or &1["variant"]["status"] == "missing")
           ),
         "complete" => complete,
         "mean_delta" => if(complete, do: average),
         "observed_mean_delta" => average
       }}
    else
      _ -> {:error, :invalid_paired_input}
    end
  rescue
    _ -> {:error, :invalid_paired_input}
  end

  def semantic(predictions, reviews) do
    with true <-
           is_list(predictions) and Enum.all?(predictions, &prediction?/1) and
             unique?(predictions, "prediction_id"),
         true <-
           is_list(reviews) and Enum.all?(reviews, &review?/1) and
             unique?(reviews, "prediction_id"),
         by_id <- Map.new(predictions, &{&1["prediction_id"], &1}),
         true <- Enum.all?(reviews, &review_matches?(&1, by_id)) do
      review_map = Map.new(reviews, &{&1["prediction_id"], &1})
      rows = Enum.map(predictions, &semantic_row(&1, review_map[&1["prediction_id"]]))
      pairs = Enum.flat_map(rows, & &1["citations"])
      support_measured = Enum.count(rows, & &1["support_measured"])
      support_correct = Enum.count(rows, & &1["support_correct"])
      citation_measured = Enum.count(pairs, & &1["measured"])
      citation_supported = Enum.count(pairs, & &1["supported"])
      support_complete = length(rows) > 0 and support_measured == length(rows)
      citation_complete = length(pairs) > 0 and citation_measured == length(pairs)

      {:ok,
       %{
         "metric_version" => @version,
         "rows" => rows,
         "review_complete" => Enum.all?(rows, & &1["review_complete"]),
         "support" => %{
           "total_n" => length(rows),
           "measured_n" => support_measured,
           "unmeasured_n" => length(rows) - support_measured,
           "correct_n" => support_correct,
           "failed_n" => Enum.count(predictions, &(&1["status"] != "ok")),
           "retrieval_only_n" =>
             Enum.count(predictions, &(&1["response_kind"] == "retrieval_only")),
           "complete" => support_complete,
           "accuracy" => if(support_complete, do: ratio(support_correct, length(rows))),
           "measured_accuracy" => ratio(support_correct, support_measured),
           "reason" =>
             cond do
               rows == [] -> "no_predictions"
               not support_complete -> "unmeasured_predictions"
               true -> nil
             end
         },
         "citation" => %{
           "total_n" => length(pairs),
           "measured_n" => citation_measured,
           "unmeasured_n" => length(pairs) - citation_measured,
           "supported_n" => citation_supported,
           "invalid_n" =>
             Enum.count(pairs, &(&1["integrity"] == "invalid" or &1["verdict"] == "invalid")),
           "complete" => citation_complete,
           "precision" => if(citation_complete, do: ratio(citation_supported, length(pairs))),
           "measured_precision" => ratio(citation_supported, citation_measured),
           "reason" =>
             cond do
               pairs == [] -> "no_citation_pairs"
               not citation_complete -> "unmeasured_pairs"
               true -> nil
             end
         }
       }}
    else
      _ -> {:error, :invalid_semantic_input}
    end
  rescue
    _ -> {:error, :invalid_semantic_input}
  end

  defp semantic_row(p, review) do
    independent = is_map(review) and review["independent"]
    verdict = if is_map(review), do: review["verdict"], else: "unmeasured"
    judged = independent and verdict != "unmeasured"
    support_measured = judged and p["response_kind"] != "retrieval_only"

    outcome_ok =
      p["status"] == "ok" or
        (p["status"] == "refused" and p["expected_refusal"] and verdict == "correct_abstention")

    correct = support_measured and outcome_ok and verdict in ~w(supported correct_abstention)

    citation_reviews =
      if is_map(review), do: Map.new(review["citations"], &{&1["citation_id"], &1}), else: %{}

    pairs =
      Enum.map(p["citations"], fn c ->
        cr = citation_reviews[c["citation_id"]]
        cv = if is_map(cr), do: cr["verdict"], else: "unmeasured"
        measured = independent and cv != "unmeasured" and c["integrity"] != "unmeasured"

        %{
          "prediction_id" => p["prediction_id"],
          "citation_id" => c["citation_id"],
          "integrity" => c["integrity"],
          "verdict" => cv,
          "measured" => measured,
          "supported" => measured and c["integrity"] == "valid" and cv == "supported",
          "review_present" => is_map(cr)
        }
      end)

    review_complete = is_map(review) and independent and Enum.all?(pairs, & &1["review_present"])

    %{
      "prediction_id" => p["prediction_id"],
      "query_id" => p["query_id"],
      "status" => p["status"],
      "response_kind" => p["response_kind"],
      "verdict" => verdict,
      "reviewer_id" => if(is_map(review), do: review["reviewer_id"]),
      "independent" => independent,
      "review_complete" => review_complete,
      "support_measured" => support_measured,
      "support_correct" => correct,
      "citations" => pairs
    }
  end

  defp prediction?(p) do
    exact?(p, ~w(prediction_id query_id status response_kind expected_refusal citations)) and
      id?(p["prediction_id"]) and id?(p["query_id"]) and status?(p["status"]) and
      p["response_kind"] in ~w(answer abstention retrieval_only) and
      is_boolean(p["expected_refusal"]) and
      is_list(p["citations"]) and Enum.all?(p["citations"], &saved_citation?/1) and
      unique?(p["citations"], "citation_id")
  end

  defp saved_citation?(c),
    do:
      exact?(c, ~w(citation_id integrity)) and id?(c["citation_id"]) and
        c["integrity"] in ~w(valid invalid unmeasured)

  defp review?(r) do
    exact?(r, ~w(prediction_id verdict reviewer_id independent citations)) and
      id?(r["prediction_id"]) and
      id?(r["reviewer_id"]) and is_boolean(r["independent"]) and
      r["verdict"] in ~w(supported correct_abstention unsupported incorrect_abstention unmeasured) and
      is_list(r["citations"]) and
      Enum.all?(r["citations"], fn c ->
        exact?(c, ~w(citation_id verdict)) and id?(c["citation_id"]) and
          c["verdict"] in ~w(supported unsupported invalid unmeasured)
      end) and unique?(r["citations"], "citation_id")
  end

  defp review_matches?(r, by_id) do
    case by_id[r["prediction_id"]] do
      nil ->
        false

      p ->
        ids = MapSet.new(Enum.map(p["citations"], & &1["citation_id"]))

        Enum.all?(r["citations"], &MapSet.member?(ids, &1["citation_id"])) and
          case {p["response_kind"], r["verdict"]} do
            {"retrieval_only", verdict} -> verdict == "unmeasured"
            {"answer", "correct_abstention"} -> false
            {"answer", "incorrect_abstention"} -> false
            {"abstention", "supported"} -> false
            {"abstention", "unsupported"} -> false
            _ -> true
          end
    end
  end

  defp query?(q),
    do: exact?(q, ~w(query_id applicable)) and id?(q["query_id"]) and is_boolean(q["applicable"])

  defp rows?(rows, ids),
    do:
      is_list(rows) and unique?(rows, "query_id") and
        Enum.all?(rows, fn r ->
          exact?(r, ~w(query_id status value)) and MapSet.member?(ids, r["query_id"]) and
            status?(r["status"]) and (is_nil(r["value"]) or finite?(r["value"]))
        end)

  defp missing(id), do: %{"query_id" => id, "status" => "missing", "value" => nil}
  defp paired_value(_, false), do: nil
  defp paired_value(%{"status" => "ok", "value" => value}, true), do: value
  defp paired_value(_, true), do: 0.0

  defp latency_sample?(s),
    do:
      exact?(s, ~w(status elapsed_ms censored)) and status?(s["status"]) and
        is_boolean(s["censored"]) and
        (is_nil(s["elapsed_ms"]) or (finite?(s["elapsed_ms"]) and s["elapsed_ms"] >= 0))

  defp metric_reason(0, _, _), do: "no_relevant_sources"
  defp metric_reason(_, k, cutoff) when k < cutoff, do: "insufficient_rank_capacity"
  defp metric_reason(_, _, _), do: nil
  defp scored(nil, _), do: nil
  defp scored(_, true), do: 0.0
  defp scored(value, false), do: value

  defp source?(s),
    do:
      exact?(s, @source_keys) and id?(s["project"]) and id?(s["source_id"]) and
        is_integer(s["generation"]) and s["generation"] > 0 and
        ((is_integer(s["version"]) and s["version"] > 0) or id?(s["version"])) and
        is_binary(s["sha256"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, s["sha256"])

  defp qrel?(q),
    do:
      exact?(q, ~w(source grade)) and source?(q["source"]) and is_integer(q["grade"]) and
        q["grade"] in 0..30

  defp unit(s), do: Enum.map(@source_keys, &s[&1])

  defp dcg(grades),
    do:
      grades
      |> Enum.with_index(1)
      |> Enum.reduce(0.0, fn {grade, rank}, sum ->
        sum + (Integer.pow(2, grade) - 1) / :math.log2(rank + 1)
      end)

  defp mean([]), do: nil

  defp mean(values) do
    count = length(values)
    Enum.reduce(values, 0.0, &(&1 / count + &2))
  end

  defp ratio(_, 0), do: nil
  defp ratio(n, d), do: n / d
  defp status?(s), do: s in @statuses
  defp id?(s), do: is_binary(s) and byte_size(s) > 0 and String.valid?(s)
  defp finite?(n), do: is_number(n) and n == n and abs(n) <= 1.7976931348623157e308

  defp exact?(m, keys),
    do: is_map(m) and map_size(m) == length(keys) and Enum.all?(keys, &Map.has_key?(m, &1))

  defp unique?(rows, key),
    do:
      length(rows) ==
        length(Enum.uniq_by(rows, fn row -> if is_map(row), do: row[key], else: nil end))
end
