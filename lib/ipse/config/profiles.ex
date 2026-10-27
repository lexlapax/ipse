defmodule Ipse.Config.Profiles do
  @moduledoc "Operator-defined execution profiles and explicit bounded child routing."
  alias Ipse.JSON, as: Schema

  @providers Ipse.Provider.Registry.atoms()
  @credentials Ipse.Provider.Registry.credentials()
  @settings ~w(provider model max_steps context_bytes timeout_ms max_output_tokens)

  def validate(profiles, roles)
      when is_map(profiles) and is_map(roles) and map_size(profiles) <= 8 do
    Enum.reduce_while(Enum.sort(profiles), :ok, fn {id, profile}, :ok ->
      if id?(id) do
        case validate_profile(profile) do
          :ok -> {:cont, :ok}
          {:error, message} -> {:halt, {:error, "Profile #{id}: " <> message}}
        end
      else
        {:halt,
         {:error,
          "Invalid profile ID; use a letter followed by at most 63 letters, digits, underscores or hyphens. See docs/operator/configuration.md#reuse-a-named-model-profile."}}
      end
    end)
    |> case do
      :ok ->
        if Enum.all?(roles, fn {role, id} ->
             role in ~w(main routine review) and Map.has_key?(profiles, id)
           end),
           do: :ok,
           else:
             {:error,
              "Invalid role reference; main, routine and review must name configured profiles. See docs/operator/configuration.md#reuse-a-named-model-profile."}

      error ->
        error
    end
  end

  def validate(_, _),
    do:
      {:error,
       "Profiles and roles must be objects with at most eight profiles. See docs/operator/configuration.md#reuse-a-named-model-profile."}

  def validate_profile(profile) do
    schema = %{
      "type" => "object",
      "properties" =>
        Map.merge(Map.take(Ipse.Config.settings_schema()["properties"], @settings), %{
          "credential" => %{"type" => "string", "enum" => Map.values(@credentials) |> Enum.uniq()},
          "base_url" => %{"type" => "string", "minLength" => 1, "maxLength" => 512},
          "model_call_timeout_ms" => Ipse.Config.settings_schema()["properties"]["timeout_ms"],
          "reasoning_effort" => %{
            "type" => "string",
            "enum" => ~w(none low medium high xhigh max)
          }
        }),
      "required" => ["provider", "model"],
      "additionalProperties" => false
    }

    schema =
      update_in(schema, ["properties"], &Map.merge(&1, Ipse.Provider.Registry.profile_schema()))

    with :ok <- Schema.validate_arguments(schema, profile),
         true <- not is_nil(Ipse.Provider.model_name(profile["model"])),
         :ok <-
           (case Ipse.Provider.Registry.validate_profile(profile) do
              :ok -> :ok
              {:error, message} -> {:error, {:provider_profile, message}}
            end),
         true <-
           Map.get(profile, "credential", @credentials[profile["provider"]]) ==
             @credentials[profile["provider"]],
         :ok <-
           (case reasoning(profile["provider"], profile["model"], profile["reasoning_effort"]) do
              :ok ->
                :ok

              {:error, message} ->
                if profile["provider"] == "gemini",
                  do: {:error, {:provider_profile, message}},
                  else: {:error, :invalid_reasoning}

              _ ->
                {:error, :invalid_reasoning}
            end),
         :ok <-
           Ipse.Provider.validate_output_limit(%{
             provider: @providers[profile["provider"]],
             max_output_tokens: profile["max_output_tokens"]
           }),
         true <- Ipse.Provider.valid_base_url?(profile["provider"], profile["base_url"]) do
      :ok
    else
      {:error, {:provider_profile, message}} ->
        {:error, message}

      _ ->
        {:error,
         "Invalid profile field #{invalid_field(profile, schema)}. No model request was sent; see docs/operator/configuration.md#reuse-a-named-model-profile."}
    end
  end

  defp invalid_field(profile, schema) when is_map(profile) do
    properties = schema["properties"]

    field =
      properties
      |> Enum.sort()
      |> Enum.find_value(fn {field, rule} ->
        if Map.has_key?(profile, field) do
          single = %{"type" => "object", "properties" => %{field => rule}}
          if Schema.validate_arguments(single, Map.take(profile, [field])) != :ok, do: field
        else
          if field in schema["required"], do: field
        end
      end)

    cond do
      Enum.any?(Map.keys(profile), &(not Map.has_key?(properties, &1))) ->
        "fields"

      field ->
        field

      is_nil(Ipse.Provider.model_name(profile["model"])) ->
        "model"

      Map.get(profile, "credential", @credentials[profile["provider"]]) !=
          @credentials[profile["provider"]] ->
        "credential"

      reasoning(profile["provider"], profile["model"], profile["reasoning_effort"]) != :ok ->
        "reasoning_effort"

      Ipse.Provider.validate_output_limit(%{
        provider: @providers[profile["provider"]],
        max_output_tokens: profile["max_output_tokens"]
      }) != :ok ->
        "max_output_tokens"

      not Ipse.Provider.valid_base_url?(profile["provider"], profile["base_url"]) ->
        "base_url"

      true ->
        "settings"
    end
  end

  defp invalid_field(_, _), do: "record"

  defdelegate reasoning(provider, model, effort), to: Ipse.Provider.Registry

  def select(profiles, roles, requested) do
    id = requested || roles["main"]

    case id do
      nil ->
        {:ok, nil, %{}}

      id ->
        case profiles[id] do
          nil -> {:error, "Selected profile is not configured."}
          profile -> {:ok, id, profile}
        end
    end
  end

  def settings(profile), do: Map.take(profile, @settings)
  def manifest(nil, _), do: nil

  def manifest(id, profile),
    do:
      %{
        id: id,
        role: "main",
        provider: profile["provider"],
        model: profile["model"],
        credential: Map.get(profile, "credential", @credentials[profile["provider"]]),
        reasoning_effort: profile["reasoning_effort"],
        base_url: profile["base_url"]
      }
      |> Map.merge(Ipse.Provider.Registry.profile_runtime(profile))

  def runtime(effective) do
    selected = effective.execution

    runtime =
      %{
        profiles: effective.profiles,
        roles: effective.roles,
        execution: selected,
        reasoning_effort: if(selected, do: selected.reasoning_effort)
      }
      |> Map.merge(Ipse.Provider.Registry.runtime_fields(selected))

    if selected && selected.base_url,
      do: Map.put(runtime, :base_url, selected.base_url),
      else: runtime
  end

  def ids(config), do: config |> Map.get(:profiles, %{}) |> Map.keys() |> Enum.sort()

  def validate_route(config, args) do
    id = route_id(config, args)

    cond do
      args["role"] && is_nil(Map.get(config, :roles, %{})[args["role"]]) ->
        {:error, "Delegation role is not configured; no provider fallback was attempted."}

      is_nil(id) ->
        :ok

      id in ids(config) ->
        profile = config.profiles[id]

        with :ok <- validate_profile(profile) do
          effective = %{
            provider: @providers[profile["provider"]],
            max_output_tokens:
              Ipse.Provider.narrow_output_tokens(
                config[:max_output_tokens],
                profile["max_output_tokens"]
              )
          }

          with :ok <- Ipse.Provider.validate_output_limit(effective),
               do:
                 Ipse.Usage.Budget.validate_configuration(
                   Map.put(effective, :budget, config[:budget])
                 )
        end

      true ->
        {:error, "Delegation profile is not configured; no provider fallback was attempted."}
    end
  end

  def child_config(config, origin, args) do
    with :ok <- validate_route(config, args) do
      id = route_id(config, args)
      child = Ipse.Tools.Delegation.child_config(config, origin)

      if is_nil(id) do
        child =
          if is_map(child[:execution]),
            do: Map.update!(child, :execution, &Map.put(&1, :role, "inherited")),
            else: child

        {:ok, child}
      else
        profile = config.profiles[id]

        policy =
          Map.take(child, [
            :sandbox,
            :home,
            :operator_home,
            :shared_root,
            :extensions,
            :parallel_child,
            :max_output_tokens,
            :budget,
            :journal,
            :budget_root,
            :budget_checkpoint,
            :model_profiles,
            :embedding_profiles,
            :decision_profiles,
            :model_auth_dir,
            :approval,
            :approval_origin,
            :headless,
            :execution_mode,
            :enclosing_mode,
            :knowledge_ceiling,
            :inference_services,
            :semantic_selections,
            :delegation_origin
          ])

        policy =
          if Ipse.Provider.Registry.auth?(profile["provider"]),
            do: Map.put(policy, :auth_dir, config[:auth_dir]),
            else: policy

        selected =
          manifest(id, profile)
          |> Map.put(
            :role,
            args["role"] ||
              if(id == Map.get(config, :roles, %{})["routine"], do: "routine", else: "selected")
          )

        runtime =
          Map.new(settings(profile), fn {key, value} -> {String.to_existing_atom(key), value} end)

        runtime = Map.put(runtime, :provider, @providers[profile["provider"]])
        runtime = Map.merge(runtime, Ipse.Provider.Registry.profile_runtime(profile))

        runtime =
          if profile["base_url"],
            do: Map.put(runtime, :base_url, profile["base_url"]),
            else: runtime

        {:ok,
         Map.merge(policy, runtime)
         |> Map.merge(%{
           execution: selected,
           reasoning_effort: profile["reasoning_effort"],
           subagents: false,
           subagent_concurrency: 1,
           mcp_servers: [],
           compact: false,
           operator_questions: false,
           max_steps: min(profile["max_steps"] || 6, Ipse.Tools.Delegation.max_steps()),
           context_bytes:
             min(profile["context_bytes"] || 400_000, Map.get(config, :context_bytes, 400_000)),
           timeout_ms: min(profile["timeout_ms"] || 120_000, Ipse.Tools.Delegation.timeout_ms())
         })
         |> Map.put(
           :max_output_tokens,
           Ipse.Provider.narrow_output_tokens(
             config[:max_output_tokens],
             runtime[:max_output_tokens]
           )
         )}
      end
    end
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, id)

  defp route_id(config, args),
    do: args["profile"] || Map.get(config, :roles, %{})[args["role"] || "routine"]

  alias Ipse.Provider.Embedding
  @embedding_providers Map.take(@providers, Ipse.Provider.Registry.embedding_ids())
  @embedding_credentials Map.take(@credentials, Ipse.Provider.Registry.embedding_ids())
  @required ~w(operation provider model dimensions dimension_mode)
  @optional ~w(credential base_url timeout_ms)
  @public ~w(id operation provider model billing_mode endpoint_sha256 dimensions dimension_mode timeout_ms destination)
  @error {:error, "Invalid operator embedding profile configuration."}

  def validate_embeddings(registry) do
    if is_map(registry) and map_size(registry) <= 8 and
         Enum.all?(registry, fn {id, profile} ->
           id?(id) and validate_embedding_profile(profile) == :ok
         end),
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def validate_embedding_profile(profile) do
    with true <- is_map(profile),
         true <- Enum.sort(Map.keys(Map.drop(profile, @optional))) == Enum.sort(@required),
         true <-
           profile["operation"] == "embedding" and
             is_map_key(@embedding_providers, profile["provider"]),
         true <-
           is_binary(profile["model"]) and
             Ipse.Provider.model_name(profile["model"]) == profile["model"],
         true <-
           dimensions?(profile["dimensions"]) and profile["dimension_mode"] in ~w(native request),
         true <-
           Map.get(profile, "credential", @embedding_credentials[profile["provider"]]) ==
             @embedding_credentials[profile["provider"]],
         timeout = Map.get(profile, "timeout_ms", 120_000),
         true <- is_integer(timeout) and timeout in 1000..120_000,
         true <- not Map.has_key?(profile, "base_url") or is_binary(profile["base_url"]),
         true <-
           Ipse.Provider.valid_base_url?(
             @embedding_providers[profile["provider"]],
             profile["base_url"]
           ),
         :ok <- Ipse.Extension.validate(profile),
         {:ok, _} <- Embedding.destination(embedding_runtime(profile)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def resolve_embeddings(sources) when is_list(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn source, {:ok, registry} ->
      data = source.data

      cond do
        Map.has_key?(data, "embedding_profiles") and source.scope != "operator" ->
          {:halt,
           {:error,
            "Embedding profiles are operator-only; project configuration cannot define them."}}

        true ->
          entries = Map.get(data, "embedding_profiles", %{})

          with :ok <- validate_embeddings(entries),
               merged = Map.merge(registry, entries),
               :ok <- validate_embeddings(merged) do
            {:cont, {:ok, merged}}
          else
            _ -> {:halt, @error}
          end
      end
    end)
  rescue
    _ -> @error
  end

  def resolve_embeddings(_), do: @error

  def embeddings_enabled?(config) do
    Enum.any?(config[:extensions] || [], fn entry ->
      "host.embedding" in entry.identity["capabilities"]
    end)
  rescue
    _ -> false
  end

  def embedding_configuration(config),
    do:
      if(embeddings_enabled?(config),
        do: validate_embeddings(config[:embedding_profiles] || %{}),
        else: :ok
      )

  def embedding_snapshot(config) do
    if embeddings_enabled?(config) do
      registry = config[:embedding_profiles] || %{}
      :ok = validate_embeddings(registry)

      Map.new(registry, fn {id, profile} ->
        {:ok, destination} = Embedding.destination(embedding_runtime(profile))

        {id,
         %{
           "id" => id,
           "operation" => "embedding",
           "provider" => profile["provider"],
           "model" => profile["model"],
           "billing_mode" => Ipse.Usage.billing_mode(@embedding_providers[profile["provider"]]),
           "endpoint_sha256" =>
             if(profile["base_url"], do: Ipse.JSON.sha256(profile["base_url"])),
           "dimensions" => profile["dimensions"],
           "dimension_mode" => profile["dimension_mode"],
           "timeout_ms" =>
             min(Map.get(profile, "timeout_ms", 120_000), config[:timeout_ms] || 120_000),
           "destination" => destination
         }}
      end)
    end
  end

  def embedding_execution(scope, request) do
    with true <- is_map(scope) and is_map(request),
         true <- id?(request["profile"]),
         true <- is_integer(request["timeout_ms"]) and request["timeout_ms"] in 1000..120_000,
         profile when is_map(profile) <- (scope["embedding_profiles"] || %{})[request["profile"]],
         true <- public_embedding_profile?(profile) and profile["id"] == request["profile"] do
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

  def prepare_embedding(config, request) do
    with :ok <- embedding_configuration(config),
         scope = %{"embedding_profiles" => embedding_snapshot(config)},
         {:ok, execution} <- embedding_execution(scope, request),
         profile when is_map(profile) <- (config[:embedding_profiles] || %{})[request["profile"]],
         :ok <- validate_embedding_profile(profile),
         selected = %{
           id: request["profile"],
           role: "extension",
           provider: profile["provider"],
           model: profile["model"],
           credential:
             Map.get(profile, "credential", @embedding_credentials[profile["provider"]]),
           base_url: profile["base_url"]
         },
         private =
           config
           |> Map.take([:budget, :budget_root, :budget_checkpoint, :delegation_origin])
           |> Map.merge(embedding_runtime(profile))
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

  def public_embedding_profile?(profile) do
    keys?(profile, @public) and id?(profile["id"]) and profile["operation"] == "embedding" and
      is_map_key(@embedding_providers, profile["provider"]) and is_binary(profile["model"]) and
      Ipse.Provider.model_name(profile["model"]) == profile["model"] and
      profile["billing_mode"] ==
        Ipse.Usage.billing_mode(@embedding_providers[profile["provider"]]) and
      (is_nil(profile["endpoint_sha256"]) or Ipse.JSON.sha256?(profile["endpoint_sha256"])) and
      dimensions?(profile["dimensions"]) and profile["dimension_mode"] in ~w(native request) and
      is_integer(profile["timeout_ms"]) and profile["timeout_ms"] in 1..120_000 and
      Ipse.Provider.valid_destination?(profile["destination"]) and default_destination?(profile)
  rescue
    _ -> false
  end

  def embedding_selection_sha256(execution, destination) do
    if is_map(execution) and not Map.has_key?(execution, "destination") and
         public_embedding_profile?(Map.put(execution, "destination", destination)) do
      {:ok,
       Ipse.JSON.digest([
         "ipse.embedding.selection",
         1,
         execution["id"],
         execution["operation"],
         execution["provider"],
         execution["model"],
         execution["billing_mode"],
         destination["origin"],
         destination["target_sha256"],
         execution["dimensions"],
         execution["dimension_mode"]
       ])}
    else
      @error
    end
  rescue
    _ -> @error
  end

  defp default_destination?(%{"endpoint_sha256" => nil} = profile),
    do:
      Embedding.destination(%{provider: @embedding_providers[profile["provider"]]}) ==
        {:ok, profile["destination"]}

  defp default_destination?(_), do: true

  defp embedding_runtime(profile) do
    base = %{
      provider: @embedding_providers[profile["provider"]],
      model: profile["model"],
      dimensions: profile["dimensions"],
      dimension_mode: profile["dimension_mode"]
    }

    if profile["base_url"], do: Map.put(base, :base_url, profile["base_url"]), else: base
  end

  defp dimensions?(value), do: is_integer(value) and value in 1..4096

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
