defmodule Ipse.Budget.Policy do
  @moduledoc "Closed operator policy for per-tree admission reservations, not invoice guarantees."
  alias Ipse.{MCP.Schema, Usage.Normalizer}
  @safe 9_007_199_254_740_991
  @bases ~w(api_estimate api_equivalent local_estimate)
  def bases, do: @bases

  def schema do
    count = integer(0, Normalizer.limit())
    positive = integer(1, Normalizer.limit())

    money = %{
      "type" => "object",
      "properties" => %{
        "basis" => %{"type" => "string", "enum" => @bases},
        "limit_nanos" => integer(0, @safe),
        "reserve_nanos" => integer(1, @safe)
      },
      "required" => ~w(basis limit_nanos reserve_nanos),
      "additionalProperties" => false
    }

    %{
      "type" => "object",
      "properties" => %{
        "version" => %{"type" => "integer", "enum" => [1]},
        "max_requests" => integer(0, 40_000),
        "max_input_tokens" => count,
        "max_output_tokens" => count,
        "reserve_input_tokens" => positive,
        "reserve_output_tokens" => integer(1, Ipse.Provider.Limits.maximum()),
        "money" => %{"type" => "array", "minItems" => 1, "maxItems" => 3, "items" => money},
        "rate_card" => Ipse.Extensions.Costs.schema()
      },
      "required" => ["version"],
      "additionalProperties" => false
    }
  end

  def validate(nil), do: :ok

  def validate(policy) do
    with :ok <- Schema.validate_arguments(schema(), policy),
         true <- policy["version"] === 1,
         true <-
           Enum.all?(
             Map.take(
               policy,
               ~w(max_requests max_input_tokens max_output_tokens reserve_input_tokens reserve_output_tokens)
             ),
             fn {_, value} -> is_integer(value) end
           ),
         true <-
           Enum.any?(
             ~w(max_requests max_input_tokens max_output_tokens money),
             &Map.has_key?(policy, &1)
           ),
         true <- paired?(policy, "max_input_tokens", "reserve_input_tokens"),
         true <- paired?(policy, "max_output_tokens", "reserve_output_tokens"),
         true <- paired?(policy, "money", "rate_card"),
         true <-
           length(Enum.uniq_by(policy["money"] || [], & &1["basis"])) ==
             length(policy["money"] || []),
         true <-
           Enum.all?(
             policy["money"] || [],
             &(is_integer(&1["limit_nanos"]) and is_integer(&1["reserve_nanos"]))
           ),
         :ok <-
           if(policy["rate_card"],
             do: Ipse.Extensions.Costs.validate(policy["rate_card"]),
             else: :ok
           ) do
      :ok
    else
      _ -> {:error, :invalid_budget_policy}
    end
  rescue
    _ -> {:error, :invalid_budget_policy}
  end

  def resolve(sources) do
    if Enum.any?(sources, &(&1.scope != "operator" and Map.has_key?(&1.data, "budget"))) do
      {:error, "Budget policy is operator-only; project configuration cannot replace it."}
    else
      policy = Enum.find_value(sources, & &1.data["budget"])
      with :ok <- validate(policy), do: {:ok, policy}
    end
  end

  def runtime(config) do
    with :ok <- validate(config[:budget]),
         true <- is_nil(config[:budget_root]) or is_map(config[:budget]),
         true <-
           is_nil(config[:budget]) or is_nil(config[:delegation_origin]) or
             is_map(config[:budget_root]) do
      request_config(config)
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    else
      _ -> {:error, :invalid_budget_policy}
    end
  end

  def request_config(%{operation: :embedding} = config), do: {:ok, config}

  def request_config(config) do
    case config[:budget] do
      %{"reserve_output_tokens" => reserve} ->
        capped =
          Map.put(
            config,
            :max_output_tokens,
            Ipse.Provider.Limits.narrow(config[:max_output_tokens], reserve)
          )

        with :ok <- Ipse.Provider.Limits.validate(capped), do: {:ok, capped}

      _ ->
        {:ok, config}
    end
  end

  def limits(policy) do
    ordinary =
      for {source, target} <- [
            {"max_requests", "requests"},
            {"max_input_tokens", "input_tokens"},
            {"max_output_tokens", "output_tokens"}
          ],
          Map.has_key?(policy, source),
          into: %{},
          do: {target, policy[source]}

    Enum.reduce(policy["money"] || [], ordinary, fn bucket, acc ->
      Map.put(acc, "money:" <> bucket["basis"], bucket["limit_nanos"])
    end)
  end

  def reservation(policy, admission) do
    basis = basis(admission["billing_mode"])

    for key <- Map.keys(limits(policy)), into: %{} do
      value =
        case key do
          "requests" ->
            1

          "input_tokens" ->
            policy["reserve_input_tokens"]

          "output_tokens" ->
            if Ipse.Usage.operation(admission) == "embedding",
              do: 0,
              else: policy["reserve_output_tokens"]

          "money:" <> selected ->
            if selected == basis,
              do: Enum.find(policy["money"], &(&1["basis"] == selected))["reserve_nanos"],
              else: 0
        end

      {key, value}
    end
  end

  def observed(policy, admission, usage, completion \\ nil),
    do: measure(policy, admission, usage, completion, true)

  def known(policy, admission, usage, completion),
    do: measure(policy, admission, usage, completion, false)

  defp measure(policy, admission, usage, completion, final_only) do
    record =
      Ipse.Usage.request_record(%{
        admission: admission,
        observation: usage,
        completion: completion
      })

    estimate = if policy["rate_card"], do: estimate(policy, record)

    for key <- Map.keys(limits(policy)), into: %{} do
      value =
        case key do
          "requests" ->
            1

          "input_tokens" ->
            record["usage"]["counts"]["input_tokens"]

          "output_tokens" ->
            if Ipse.Usage.operation(admission) == "embedding",
              do: 0,
              else: record["usage"]["counts"]["output_tokens"]

          "money:" <> selected ->
            cond do
              selected != basis(admission["billing_mode"]) -> 0
              is_nil(estimate) -> nil
              "amount_overflow" in estimate["missing"] -> @safe + 1
              completion && estimate["status"] == "estimated" -> estimate["amount_nanos"]
              completion && completion["outcome"] == "completed" && final_only -> nil
              true -> estimate["known_amount_nanos"]
            end
        end

      {key, value}
    end
  end

  defp estimate(policy, record) do
    fields =
      ~w(provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)

    fields = if record["version"] == 2, do: fields ++ ["operation"], else: fields

    case Ipse.Extensions.Costs.estimate(policy["rate_card"], Map.take(record, fields)) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp basis("api"), do: "api_estimate"
  defp basis("subscription"), do: "api_equivalent"
  defp basis("local"), do: "local_estimate"
  defp basis(_), do: nil
  defp paired?(map, left, right), do: Map.has_key?(map, left) == Map.has_key?(map, right)
  defp integer(low, high), do: %{"type" => "integer", "minimum" => low, "maximum" => high}
end
