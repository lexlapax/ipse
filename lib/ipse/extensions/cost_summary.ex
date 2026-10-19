defmodule Ipse.Extensions.CostSummary do
  @moduledoc "Pure request-keyed cumulative aggregation; no model, storage or budget authority."
  alias Ipse.Extensions.Costs
  alias Ipse.Usage
  alias Ipse.Usage.Normalizer

  @fields ~w(operation provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)
  @safe 9_007_199_254_740_991
  @limit 10_000

  def new(card, limit \\ @limit) when is_integer(limit) and limit in 1..40_000 do
    with :ok <- Costs.validate(card), do: {:ok, %{card: card, requests: %{}, limit: limit}}
  end

  @doc "Replace the contribution for an actual request attempt, never add cumulative observations as deltas."
  def put(state, request) do
    key = {request["session_id"], request["request_id"], request["attempt_id"]}

    admission =
      request
      |> Map.drop(~w(outcome finality duration_ms reported_model usage))
      |> then(&Ipse.Compaction.digest([&1]))

    with true <- Usage.valid_request_record?(request),
         true <- map_size(state.requests) < state.limit or Map.has_key?(state.requests, key),
         true <-
           not Map.has_key?(state.requests, key) or state.requests[key].admission == admission,
         {:ok, quote} <- Costs.estimate(state.card, Map.take(request, @fields)) do
      contribution = %{
        admission: admission,
        group:
          {request["provider"], request["billing_mode"], quote["basis"],
           request["operation"] || "text"},
        amount: quote["amount_nanos"],
        known: quote["known_amount_nanos"],
        overflow: "amount_overflow" in quote["missing"],
        final: request["outcome"] == "completed" and request["finality"] == "final",
        unknown: request["outcome"] == "unknown",
        counts: request["usage"]["counts"]
      }

      {:ok, %{state | requests: Map.put(state.requests, key, contribution)}}
    else
      _ -> {:error, :invalid_summary_request}
    end
  rescue
    _ -> {:error, :invalid_summary_request}
  end

  def report(state, snapshot, enumeration_complete) do
    report_scope(state, snapshot, enumeration_complete, snapshot["request_count"], [
      snapshot["source"]["session_id"]
    ])
  end

  def tree_report(state, snapshot, discovery, children, descriptors) do
    snapshots = for %{"snapshot" => s} <- children, s != nil, do: s
    count = if discovery, do: discovery["child_count"]
    captured = Enum.count(children, &(&1["complete"] == true))

    unknown =
      Enum.count(descriptors, &(&1["status"] != "result_recorded" or not &1["cleanup_confirmed"]))

    legacy = snapshot["legacy_unmetered"] or Enum.any?(snapshots, & &1["legacy_unmetered"])
    expected = snapshot["request_count"] + Enum.sum(Enum.map(snapshots, & &1["request_count"]))
    sessions = [snapshot["source"]["session_id"] | Enum.map(snapshots, & &1["child_id"])]
    complete = count != nil and captured == count

    report =
      report_scope(
        state,
        %{snapshot | "legacy_unmetered" => legacy},
        complete,
        expected,
        sessions
      )

    gaps =
      children
      |> Enum.reject(& &1["complete"])
      |> Enum.map(&(&1["error"] || "scan_limit"))
      |> Enum.frequencies()

    unvisited = if count, do: count - length(children), else: 0

    gaps =
      if unvisited > 0,
        do: Map.update(gaps, "scan_limit", unvisited, &(&1 + unvisited)),
        else: gaps

    Map.merge(report, %{
      "coverage" => "session_tree",
      "snapshot" => snapshot,
      "discovery_snapshot" => discovery,
      "child_count" => count,
      "captured_child_count" => captured,
      "unknown_child_outcome_count" => unknown,
      "legacy_unmetered" => legacy,
      "gap_count" => if(count, do: count - captured),
      "gap_reasons" => gaps,
      "child_manifest_sha256" => Ipse.Compaction.digest([children]),
      "cost_estimate_complete" => report["cost_estimate_complete"] and unknown == 0
    })
  end

  defp report_scope(state, snapshot, enumeration_complete, expected, sessions) do
    enumeration_complete =
      enumeration_complete and map_size(state.requests) == expected and
        Enum.all?(Map.keys(state.requests), fn {session, _, _} ->
          session in sessions
        end)

    groups =
      state.requests
      |> Map.values()
      |> Enum.group_by(& &1.group)
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map(fn {{provider, billing, basis, operation}, rows} ->
        known = sum(Enum.map(rows, & &1.known))
        amounts = Enum.map(rows, & &1.amount)
        overflow = known.overflow or Enum.any?(rows, & &1.overflow)

        group = %{
          "provider" => provider,
          "billing_mode" => billing,
          "basis" => basis,
          "request_count" => length(rows),
          "unknown_cost_count" => Enum.count(amounts, &is_nil/1),
          "unknown_outcome_count" => Enum.count(rows, & &1.unknown),
          "partial_request_count" => Enum.count(rows, &(not &1.final)),
          "amount_nanos" =>
            if(Enum.all?(amounts, &is_integer/1) and not overflow, do: known.value),
          "known_amount_nanos" => if(not overflow, do: known.value),
          "overflow" => overflow,
          "counts" =>
            Map.new(Normalizer.fields(), fn field ->
              values = Enum.map(rows, & &1.counts[field])
              subtotal = sum(values)
              complete = Enum.all?(rows, & &1.final) and Enum.all?(values, &is_integer/1)

              counters = %{
                "total" => if(complete, do: subtotal.value),
                "known_subtotal" => subtotal.value,
                "unknown_count" => Enum.count(values, &is_nil/1),
                "overflow" => subtotal.overflow
              }

              counters =
                if operation == "embedding" and field == "output_tokens",
                  do: counters |> Map.put("unknown_count", 0) |> Map.put("not_applicable", true),
                  else: counters

              {field, counters}
            end)
        }

        if operation == "embedding", do: Map.put(group, "operation", operation), else: group
      end)

    complete =
      enumeration_complete and not snapshot["legacy_unmetered"] and
        Enum.all?(groups, &is_integer(&1["amount_nanos"]))

    %{
      "status" => "summarized",
      "coverage" => "session",
      "snapshot" => snapshot,
      "request_count" => map_size(state.requests),
      "enumeration_complete" => enumeration_complete,
      "cost_estimate_complete" => complete,
      "groups" => groups,
      "rate_card" =>
        Map.take(state.card, ~w(id revision currency source published_on))
        |> Map.put("sha256", Ipse.Compaction.digest([state.card])),
      "currency_scale" => 9,
      "rounding" => "ceiling_per_request"
    }
  end

  defp sum(values) do
    known = Enum.filter(values, &is_integer/1)
    value = Enum.sum(known)
    overflow = value > @safe
    %{value: if(known != [] and not overflow, do: value), overflow: overflow}
  end
end
