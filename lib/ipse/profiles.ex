defmodule Ipse.Profiles do
  @moduledoc "Operator-defined execution profiles and explicit bounded child routing."
  alias Ipse.{MCP.Schema, RuntimeInfo}

  @providers %{
    "chatgpt" => :chatgpt,
    "openai" => :openai,
    "ollama" => :ollama,
    "anthropic" => :anthropic,
    "demo" => :demo
  }
  @credentials %{
    "chatgpt" => "ipse-auth",
    "openai" => "OPENAI_API_KEY",
    "anthropic" => "ANTHROPIC_API_KEY",
    "ollama" => "none",
    "demo" => "none"
  }
  @settings ~w(provider model max_steps context_bytes timeout_ms max_output_tokens)

  def validate(profiles, roles)
      when is_map(profiles) and is_map(roles) and map_size(profiles) <= 8 do
    if Enum.all?(profiles, fn {id, profile} -> id?(id) and validate_profile(profile) == :ok end) and
         Enum.all?(roles, fn {role, id} ->
           role in ~w(main routine review) and Map.has_key?(profiles, id)
         end) do
      :ok
    else
      {:error, "Invalid profile or role configuration."}
    end
  end

  def validate(_, _), do: {:error, "Invalid profile or role configuration."}

  def validate_profile(profile) do
    schema = %{
      "type" => "object",
      "properties" =>
        Map.merge(Map.take(Ipse.Config.settings_schema()["properties"], @settings), %{
          "credential" => %{"type" => "string", "enum" => Map.values(@credentials) |> Enum.uniq()},
          "base_url" => %{"type" => "string", "minLength" => 1, "maxLength" => 512},
          "reasoning_effort" => %{"type" => "string", "enum" => ~w(low medium high xhigh max)}
        }),
      "required" => ["provider", "model"],
      "additionalProperties" => false
    }

    with :ok <- Schema.validate_arguments(schema, profile),
         true <- not is_nil(RuntimeInfo.model_name(profile["model"])),
         true <-
           Map.get(profile, "credential", @credentials[profile["provider"]]) ==
             @credentials[profile["provider"]],
         :ok <- reasoning(profile["provider"], profile["model"], profile["reasoning_effort"]),
         :ok <-
           Ipse.Provider.Limits.validate(%{
             provider: @providers[profile["provider"]],
             max_output_tokens: profile["max_output_tokens"]
           }),
         true <- endpoint?(profile["provider"], profile["base_url"]) do
      :ok
    else
      _ -> {:error, "Unsupported profile settings, model or credential reference."}
    end
  end

  def reasoning(_provider, _model, nil), do: :ok

  def reasoning(provider, "gpt-6.1-sol", effort)
      when provider in ["chatgpt", "openai"] and effort in ~w(low medium high xhigh max) do
    :ok
  end

  def reasoning(_, _, _),
    do: {:error, "Reasoning effort is supported only for documented gpt-6.1-sol profiles."}

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
    do: %{
      id: id,
      role: "main",
      provider: profile["provider"],
      model: profile["model"],
      credential: Map.get(profile, "credential", @credentials[profile["provider"]]),
      reasoning_effort: profile["reasoning_effort"],
      base_url: profile["base_url"]
    }

  def runtime(effective) do
    selected = effective.execution

    runtime = %{
      profiles: effective.profiles,
      roles: effective.roles,
      execution: selected,
      reasoning_effort: if(selected, do: selected.reasoning_effort)
    }

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
              Ipse.Provider.Limits.narrow(
                config[:max_output_tokens],
                profile["max_output_tokens"]
              )
          }

          with :ok <- Ipse.Provider.Limits.validate(effective),
               do: Ipse.Budget.Policy.runtime(Map.put(effective, :budget, config[:budget]))
        end

      true ->
        {:error, "Delegation profile is not configured; no provider fallback was attempted."}
    end
  end

  def child_config(config, origin, args) do
    with :ok <- validate_route(config, args) do
      id = route_id(config, args)
      child = Ipse.Delegation.child_config(config, origin)

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
            :budget_root,
            :budget_checkpoint,
            :approval,
            :delegation_origin
          ])

        policy =
          if profile["provider"] == "chatgpt",
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
           max_steps: min(profile["max_steps"] || 6, Ipse.Delegation.max_steps()),
           context_bytes:
             min(profile["context_bytes"] || 400_000, Map.get(config, :context_bytes, 400_000)),
           timeout_ms: min(profile["timeout_ms"] || 120_000, Ipse.Delegation.timeout_ms())
         })
         |> Map.put(
           :max_output_tokens,
           Ipse.Provider.Limits.narrow(config[:max_output_tokens], runtime[:max_output_tokens])
         )}
      end
    end
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, id)

  defp route_id(config, args),
    do: args["profile"] || Map.get(config, :roles, %{})[args["role"] || "routine"]

  defp endpoint?(_, nil), do: true
  defp endpoint?("chatgpt", url), do: url == "https://api.openai.com/v1"

  defp endpoint?(_, url) do
    uri = URI.parse(url)

    is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and is_nil(uri.query) and
      is_nil(uri.fragment) and
      (uri.scheme == "https" or
         (uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"]))
  end
end
