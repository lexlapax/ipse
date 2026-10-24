defmodule Ipse.Test.ProviderRegistryFixture do
  @moduledoc false
  @providers ~w(chatgpt openai ollama anthropic demo)

  def portable(%MapSet{} = set), do: set |> Enum.map(&portable/1) |> Enum.sort()
  def portable(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&portable/1)
  def portable(value) when is_list(value), do: Enum.map(value, &portable/1)

  def portable(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, portable(item)} end)

  def portable(value), do: value

  def facts(cwd, home) do
    Map.new(@providers, fn id ->
      provider = String.to_existing_atom(id)

      {:ok, effective} =
        Ipse.Config.resolve(cwd, home, [provider: id, project_config: false], %{})

      model = effective.settings["model"]
      config = %{provider: provider, model: model}

      destination =
        case Ipse.Provider.destination(config) do
          {:ok, value} -> value
          {:error, reason} -> %{"error" => to_string(reason)}
        end

      raw = raw(provider)
      usage = Ipse.Usage.normalize(provider, raw)

      row = %{
        "id" => id,
        "provider" => id,
        "billing_mode" => Ipse.Usage.billing_mode(provider),
        "basis" => basis(provider),
        "model" => model,
        "endpoint_sha256" => nil,
        "from" => "2026-01-01",
        "until" => nil,
        "input_min" => 0,
        "input_max" => nil,
        "input_mode" => "flat",
        "rates" => %{"input" => "2", "output" => "10"}
      }

      card = %{
        "version" => 1,
        "id" => "registry-fixture",
        "revision" => "synthetic-1",
        "currency" => "USD",
        "source" => "operator:registry-fixture",
        "published_on" => "2026-10-23",
        "rows" => if(provider == :demo, do: [], else: [row])
      }

      request = %{
        "provider" => id,
        "billing_mode" => Ipse.Usage.billing_mode(provider),
        "model" => model,
        "reported_model" => nil,
        "endpoint_sha256" => nil,
        "admitted_at_ms" => 1_792_713_600_000,
        "outcome" => "completed",
        "finality" => "final",
        "usage" => usage
      }

      {:ok, cost} = Ipse.Usage.Costs.estimate(card, request)

      {id,
       %{
         "manifest" => Ipse.Config.manifest(effective),
         "destination" => destination,
         "usage" =>
           Enum.map([raw, %{}, nil, %{"input_tokens" => -1}], &Ipse.Usage.normalize(provider, &1)),
         "cost" => cost
       }}
    end)
    |> Jason.encode!()
    |> Jason.decode!()
  end

  def raw(p) when p in [:chatgpt, :openai],
    do: %{
      "input_tokens" => 12,
      "output_tokens" => 8,
      "total_tokens" => 20,
      "input_tokens_details" => %{"cached_tokens" => 2},
      "output_tokens_details" => %{"reasoning_tokens" => 3}
    }

  def raw(:anthropic),
    do: %{
      "input_tokens" => 10,
      "cache_read_input_tokens" => 2,
      "cache_creation_input_tokens" => 0,
      "output_tokens" => 8
    }

  def raw(:ollama),
    do: %{
      "input_tokens" => 12,
      "output_tokens" => 8,
      "input_cached_tokens" => 2,
      "provider_duration_ns" => 1_000_000_000
    }

  def raw(:demo), do: %{}
  defp basis(:chatgpt), do: "api_equivalent"
  defp basis(:ollama), do: "local_estimate"
  defp basis(_), do: "api_estimate"
end
