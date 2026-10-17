defmodule Ipse.Extensions.CostSummary do
  @moduledoc "Pure request-keyed cumulative aggregation; no model, storage or budget authority."
  alias Ipse.Extensions.Costs
  alias Ipse.Usage
  alias Ipse.Usage.Normalizer

  @fields ~w(provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)
  @safe 9_007_199_254_740_991
  @limit 10_000

  def new(card) do
    with :ok <- Costs.validate(card), do: {:ok, %{card: card, requests: %{}}}
  end

  @doc "Replace the contribution for an actual request attempt, never add cumulative observations as deltas."
  def put(state, request) do
    key = {request["session_id"], request["request_id"], request["attempt_id"]}

    admission =
      request
      |> Map.drop(~w(outcome finality duration_ms reported_model usage))
      |> then(&Ipse.Compaction.digest([&1]))

    with true <- Usage.valid_request_record?(request),
         true <- map_size(state.requests) < @limit or Map.has_key?(state.requests, key),
         true <-
           not Map.has_key?(state.requests, key) or state.requests[key].admission == admission,
         {:ok, quote} <- Costs.estimate(state.card, Map.take(request, @fields)) do
      contribution = %{
        admission: admission,
        group: {request["provider"], request["billing_mode"], quote["basis"]},
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
    enumeration_complete =
      enumeration_complete and map_size(state.requests) == snapshot["request_count"] and
        Enum.all?(Map.keys(state.requests), fn {session, _, _} ->
          session == snapshot["source"]["session_id"]
        end)

    groups =
      state.requests
      |> Map.values()
      |> Enum.group_by(& &1.group)
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map(fn {{provider, billing, basis}, rows} ->
        known = sum(Enum.map(rows, & &1.known))
        amounts = Enum.map(rows, & &1.amount)
        overflow = known.overflow or Enum.any?(rows, & &1.overflow)

        %{
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

              {field,
               %{
                 "total" => if(complete, do: subtotal.value),
                 "known_subtotal" => subtotal.value,
                 "unknown_count" => Enum.count(values, &is_nil/1),
                 "overflow" => subtotal.overflow
               }}
            end)
        }
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
