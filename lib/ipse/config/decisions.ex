defmodule Ipse.Config.Decisions do
  @moduledoc "Operator-only decision profiles with explicit service identity and nullable service disclosures."
  alias Ipse.Provider.Decision.Transport

  @providers %{
    "openai" => :openai,
    "system_one" => :system_one,
    "system_one_compatible" => :system_one_compatible
  }
  @required ~w(operation provider model service_id)
  @optional ~w(expected_model credential base_url timeout_ms pricing processing_region storage_region cache_retention account_controls)
  @disclosures ~w(pricing processing_region storage_region cache_retention account_controls)
  @public ~w(id operation provider model expected_model service_id billing_mode endpoint_sha256 timeout_ms destination subset pricing processing_region storage_region cache_retention account_controls)
  @error {:error, "Invalid operator decision profile configuration."}

  def validate(registry) do
    if is_map(registry) and map_size(registry) <= 8 and
         Enum.all?(registry, fn {id, profile} -> id?(id) and validate_profile(profile) == :ok end),
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def validate_profile(profile) do
    with true <- is_map(profile) and keys?(Map.drop(profile, @optional), @required),
         true <-
           profile["operation"] == "decision" and is_map_key(@providers, profile["provider"]),
         true <-
           model?(profile["model"]) and
             model?(Map.get(profile, "expected_model", profile["model"])),
         true <-
           profile["provider"] != "openai" or
             (profile["model"] == "gpt-6-luna" and
                Map.get(profile, "expected_model", profile["model"]) == "gpt-6-luna"),
         true <- id?(profile["service_id"]),
         true <-
           Map.get(profile, "credential", credential(profile["provider"])) ==
             credential(profile["provider"]),
         timeout = Map.get(profile, "timeout_ms", 120_000),
         true <- is_integer(timeout) and timeout in 1000..120_000,
         true <- not Map.has_key?(profile, "base_url") or is_binary(profile["base_url"]),
         true <- disclosures?(profile),
         {:ok, _} <- Transport.destination(runtime(profile)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def resolve(sources) when is_list(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn source, {:ok, registry} ->
      entries = Map.get(source.data, "decision_profiles", %{})

      if Map.has_key?(source.data, "decision_profiles") and source.scope != "operator" do
        {:halt,
         {:error,
          "Decision profiles are operator-only; project configuration cannot define them."}}
      else
        merged = Map.merge(registry, entries)

        if validate(entries) == :ok and validate(merged) == :ok,
          do: {:cont, {:ok, merged}},
          else: {:halt, @error}
      end
    end)
  rescue
    _ -> @error
  end

  def resolve(_), do: @error

  def enabled?(config),
    do: Enum.any?(config[:extensions] || [], &("host.decision" in &1.identity["capabilities"]))

  def configuration(config),
    do: if(enabled?(config), do: validate(config[:decision_profiles] || %{}), else: :ok)

  def snapshot(config) do
    if enabled?(config) do
      registry = config[:decision_profiles] || %{}
      :ok = validate(registry)

      Map.new(registry, fn {id, profile} ->
        {:ok, destination} = Transport.destination(runtime(profile))

        {id,
         Map.merge(Map.new(@disclosures, &{&1, profile[&1]}), %{
           "id" => id,
           "operation" => "decision",
           "provider" => profile["provider"],
           "model" => profile["model"],
           "expected_model" => Map.get(profile, "expected_model", profile["model"]),
           "service_id" => profile["service_id"],
           "billing_mode" => billing(profile["provider"]),
           "endpoint_sha256" =>
             if(profile["base_url"], do: Ipse.JSON.sha256(profile["base_url"])),
           "timeout_ms" => min(profile["timeout_ms"] || 120_000, config[:timeout_ms] || 120_000),
           "destination" => destination,
           "subset" =>
             Ipse.Provider.Decision.subset(Transport.engine(@providers[profile["provider"]]))
         })}
      end)
    end
  end

  def execution(scope, request) do
    with true <- is_map(request) and id?(request["profile"]),
         true <- is_integer(request["timeout_ms"]) and request["timeout_ms"] in 1000..120_000,
         profile when is_map(profile) <- (scope["decision_profiles"] || %{})[request["profile"]],
         true <- public_profile?(profile) and profile["id"] == request["profile"] do
      {:ok,
       profile
       |> Map.delete("destination")
       |> Map.put("timeout_ms", min(profile["timeout_ms"], request["timeout_ms"]))}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def prepare(config, request) do
    with :ok <- configuration(config),
         scope = %{"decision_profiles" => snapshot(config)},
         {:ok, execution} <- execution(scope, request),
         profile when is_map(profile) <- (config[:decision_profiles] || %{})[request["profile"]],
         :ok <- validate_profile(profile),
         selected = %{
           id: request["profile"],
           role: "extension",
           provider: profile["provider"],
           model: profile["model"],
           credential: credential(profile["provider"]),
           base_url: profile["base_url"]
         },
         private =
           config
           |> Map.take([:budget, :budget_root, :budget_checkpoint, :delegation_origin])
           |> Map.merge(runtime(profile))
           |> Map.merge(%{
             operation: :decision,
             execution: selected,
             timeout_ms: execution["timeout_ms"]
           }),
         {:ok, destination} <- Transport.destination(private),
         true <- destination == scope["decision_profiles"][request["profile"]]["destination"] do
      {:ok, private, execution}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def public_profile?(profile) do
    keys?(profile, @public) and id?(profile["id"]) and profile["operation"] == "decision" and
      is_map_key(@providers, profile["provider"]) and model?(profile["model"]) and
      model?(profile["expected_model"]) and
      (profile["provider"] != "openai" or
         (profile["model"] == "gpt-6-luna" and profile["expected_model"] == "gpt-6-luna")) and
      id?(profile["service_id"]) and profile["billing_mode"] == billing(profile["provider"]) and
      (is_nil(profile["endpoint_sha256"]) or Ipse.JSON.sha256?(profile["endpoint_sha256"])) and
      is_integer(profile["timeout_ms"]) and profile["timeout_ms"] in 1..120_000 and
      disclosures?(profile) and
      profile["subset"] ==
        Ipse.Provider.Decision.subset(Transport.engine(@providers[profile["provider"]])) and
      Ipse.Provider.valid_destination?(profile["destination"]) and valid_destination?(profile)
  rescue
    _ -> false
  end

  def selection_sha256(execution, destination) do
    if is_map(execution) and not Map.has_key?(execution, "destination") and
         public_profile?(Map.put(execution, "destination", destination)),
       do:
         {:ok,
          Ipse.JSON.digest([
            "ipse.decision.selection",
            1,
            Map.delete(execution, "timeout_ms"),
            destination
          ])},
       else: @error
  rescue
    _ -> @error
  end

  def provider(id), do: @providers[id]
  def billing("system_one_compatible"), do: "local"
  def billing(provider) when provider in ["openai", "system_one"], do: "api"
  def billing(_), do: nil
  defp credential("openai"), do: "openai_api_key"
  defp credential("system_one"), do: "typesafe_api_key"
  defp credential("system_one_compatible"), do: "none"
  defp credential(_), do: nil

  defp runtime(profile),
    do:
      %{
        provider: @providers[profile["provider"]],
        model: profile["model"],
        expected_model: Map.get(profile, "expected_model", profile["model"]),
        service_id: profile["service_id"]
      }
      |> maybe_base(profile)

  defp maybe_base(runtime, %{"base_url" => base}), do: Map.put(runtime, :base_url, base)
  defp maybe_base(runtime, _), do: runtime

  defp disclosures?(profile),
    do:
      Enum.all?(@disclosures, fn key ->
        is_nil(profile[key]) or
          (is_binary(profile[key]) and String.valid?(profile[key]) and
             byte_size(profile[key]) in 1..1024)
      end)

  defp valid_destination?(%{"endpoint_sha256" => nil} = profile),
    do:
      Transport.destination(%{provider: @providers[profile["provider"]]}) ==
        {:ok, profile["destination"]}

  defp valid_destination?(%{"provider" => "system_one_compatible"} = profile),
    do: URI.parse(profile["destination"]["origin"]).host in ["127.0.0.1", "localhost", "::1"]

  defp valid_destination?(_), do: true
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, id)
  defp model?(model), do: is_binary(model) and Ipse.Provider.model_name(model) == model
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
