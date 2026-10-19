defmodule Ipse.EmbeddingProfiles do
  @moduledoc "Operator-only embedding profiles, immutable public selection and fresh inference runtimes."
  alias Ipse.Provider.Embedding
  @providers %{"openai" => :openai, "ollama" => :ollama}
  @credentials %{"openai" => "OPENAI_API_KEY", "ollama" => "none"}
  @required ~w(operation provider model dimensions dimension_mode)
  @optional ~w(credential base_url timeout_ms)
  @public ~w(id operation provider model billing_mode endpoint_sha256 dimensions dimension_mode timeout_ms destination)
  @error {:error, "Invalid operator embedding profile configuration."}

  def validate(registry) do
    if is_map(registry) and map_size(registry) <= 8 and
         Enum.all?(registry, fn {id, profile} -> id?(id) and validate_profile(profile) == :ok end),
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def validate_profile(profile) do
    with true <- is_map(profile),
         true <- Enum.sort(Map.keys(Map.drop(profile, @optional))) == Enum.sort(@required),
         true <-
           profile["operation"] == "embedding" and is_map_key(@providers, profile["provider"]),
         true <-
           is_binary(profile["model"]) and
             Ipse.RuntimeInfo.model_name(profile["model"]) == profile["model"],
         true <-
           dimensions?(profile["dimensions"]) and profile["dimension_mode"] in ~w(native request),
         true <-
           Map.get(profile, "credential", @credentials[profile["provider"]]) ==
             @credentials[profile["provider"]],
         timeout = Map.get(profile, "timeout_ms", 120_000),
         true <- is_integer(timeout) and timeout in 1000..120_000,
         true <- not Map.has_key?(profile, "base_url") or is_binary(profile["base_url"]),
         true <-
           Ipse.Provider.valid_base_url?(@providers[profile["provider"]], profile["base_url"]),
         :ok <- Ipse.Extension.validate(profile),
         {:ok, _} <- Embedding.destination(runtime(profile)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def resolve(sources) when is_list(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn source, {:ok, registry} ->
      data = source.data

      cond do
        Map.has_key?(data, "embedding_profiles") and source.scope != "operator" ->
          {:halt,
           {:error,
            "Embedding profiles are operator-only; project configuration cannot define them."}}

        true ->
          entries = Map.get(data, "embedding_profiles", %{})

          with :ok <- validate(entries),
               merged = Map.merge(registry, entries),
               :ok <- validate(merged) do
            {:cont, {:ok, merged}}
          else
            _ -> {:halt, @error}
          end
      end
    end)
  rescue
    _ -> @error
  end

  def resolve(_), do: @error

  def enabled?(config) do
    Enum.any?(config[:extensions] || [], fn entry ->
      "host.embedding" in entry.identity["capabilities"]
    end)
  rescue
    _ -> false
  end

  def configuration(config),
    do: if(enabled?(config), do: validate(config[:embedding_profiles] || %{}), else: :ok)

  def snapshot(config) do
    if enabled?(config) do
      registry = config[:embedding_profiles] || %{}
      :ok = validate(registry)

      Map.new(registry, fn {id, profile} ->
        {:ok, destination} = Embedding.destination(runtime(profile))

        {id,
         %{
           "id" => id,
           "operation" => "embedding",
           "provider" => profile["provider"],
           "model" => profile["model"],
           "billing_mode" => Ipse.Usage.Normalizer.billing_mode(@providers[profile["provider"]]),
           "endpoint_sha256" =>
             if(profile["base_url"], do: Ipse.Extensions.Manifest.sha256(profile["base_url"])),
           "dimensions" => profile["dimensions"],
           "dimension_mode" => profile["dimension_mode"],
           "timeout_ms" =>
             min(Map.get(profile, "timeout_ms", 120_000), config[:timeout_ms] || 120_000),
           "destination" => destination
         }}
      end)
    end
  end

  def execution(scope, request) do
    with true <- is_map(scope) and is_map(request),
         true <- id?(request["profile"]),
         true <- is_integer(request["timeout_ms"]) and request["timeout_ms"] in 1000..120_000,
         profile when is_map(profile) <- (scope["embedding_profiles"] || %{})[request["profile"]],
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
         scope = %{"embedding_profiles" => snapshot(config)},
         {:ok, execution} <- execution(scope, request),
         profile when is_map(profile) <- (config[:embedding_profiles] || %{})[request["profile"]],
         :ok <- validate_profile(profile),
         selected = %{
           id: request["profile"],
           role: "extension",
           provider: profile["provider"],
           model: profile["model"],
           credential: Map.get(profile, "credential", @credentials[profile["provider"]]),
           base_url: profile["base_url"]
         },
         private =
           config
           |> Map.take([:budget, :budget_root, :budget_checkpoint, :delegation_origin])
           |> Map.merge(runtime(profile))
           |> Map.merge(%{
             operation: :embedding,
             execution: selected,
             timeout_ms: execution["timeout_ms"]
           }),
         {:ok, destination} <- Embedding.destination(private),
         true <- destination == scope["embedding_profiles"][request["profile"]]["destination"] do
      {:ok, private, execution}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def public_profile?(profile) do
    keys?(profile, @public) and id?(profile["id"]) and profile["operation"] == "embedding" and
      is_map_key(@providers, profile["provider"]) and is_binary(profile["model"]) and
      Ipse.RuntimeInfo.model_name(profile["model"]) == profile["model"] and
      profile["billing_mode"] ==
        Ipse.Usage.Normalizer.billing_mode(@providers[profile["provider"]]) and
      (is_nil(profile["endpoint_sha256"]) or hash?(profile["endpoint_sha256"])) and
      dimensions?(profile["dimensions"]) and profile["dimension_mode"] in ~w(native request) and
      is_integer(profile["timeout_ms"]) and profile["timeout_ms"] in 1..120_000 and
      Ipse.Provider.valid_destination?(profile["destination"]) and default_destination?(profile)
  rescue
    _ -> false
  end

  defp default_destination?(%{"endpoint_sha256" => nil} = profile),
    do:
      Embedding.destination(%{provider: @providers[profile["provider"]]}) ==
        {:ok, profile["destination"]}

  defp default_destination?(_), do: true

  defp runtime(profile) do
    base = %{
      provider: @providers[profile["provider"]],
      model: profile["model"],
      dimensions: profile["dimensions"],
      dimension_mode: profile["dimension_mode"]
    }

    if profile["base_url"], do: Map.put(base, :base_url, profile["base_url"]), else: base
  end

  defp dimensions?(value), do: is_integer(value) and value in 1..4096

  defp id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, value)

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
