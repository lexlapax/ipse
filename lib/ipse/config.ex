defmodule Ipse.Config do
  @moduledoc "Bounded configuration resolution and admitted session runtime policy."
  alias Ipse.Workspace
  alias Ipse.JSON, as: Schema

  @file_bytes 16_384
  @max_sources 17
  @defaults %{
    "provider" => "chatgpt",
    "sandbox" => "off",
    "max_steps" => 30,
    "context_bytes" => 400_000,
    "compact" => true,
    "subagents" => false,
    "subagent_concurrency" => 1,
    "timeout_ms" => 120_000
  }
  @providers %{
    "chatgpt" => {:chatgpt, "gpt-6.1-sol"},
    "openai" => {:openai, "gpt-6.1-sol"},
    "ollama" => {:ollama, "qwen3:8b"},
    "anthropic" => {:anthropic, "claude-sonnet-4-5"},
    "demo" => {:demo, "scripted"}
  }
  @sandboxes %{"off" => :off, "native" => :native}
  @fields ~w(provider model sandbox max_steps context_bytes compact subagents subagent_concurrency timeout_ms max_output_tokens)
  @option_keys Map.new(@fields, fn key -> {key, String.to_atom(key)} end)
  @env_keys Map.new(@fields, &{&1, "IPSE_" <> String.upcase(&1)})

  def resolve(cwd, home, opts \\ [], environment \\ System.get_env()) do
    with {:ok, cwd} <- Workspace.canonical_path(cwd),
         true <- File.dir?(cwd),
         {:ok, dirs} <- project_dirs(cwd),
         {:ok, sources} <- sources(dirs, home, opts, environment),
         {:ok, loaded} <- load_sources(sources),
         :ok <- project_trust(loaded, opts),
         :ok <- profile_authority(loaded),
         {:ok, env} <- environment_settings(environment) do
      initial = %{
        settings: @defaults,
        provenance: Map.new(@defaults, fn {key, _} -> {key, "built-in"} end),
        sources: [],
        profiles: %{},
        roles: %{}
      }

      effective =
        Enum.reduce(loaded, initial, fn source, acc ->
          values = source.data["settings"] || %{}

          values =
            if source.scope == "project" and acc.settings["sandbox"] == "native" and
                 values["sandbox"] == "off",
               do: Map.delete(values, "sandbox"),
               else: values

          %{
            acc
            | settings: Map.merge(acc.settings, values),
              provenance:
                Map.merge(acc.provenance, Map.new(values, fn {key, _} -> {key, source.path} end)),
              sources: acc.sources ++ [Map.drop(source, [:data])],
              profiles: Map.merge(acc.profiles, source.data["profiles"] || %{}),
              roles: Map.merge(acc.roles, source.data["roles"] || %{})
          }
        end)

      with {:ok, extensions} <- Ipse.Extension.Config.resolve(loaded, opts),
           {:ok, embedding_profiles} <- Ipse.Config.Profiles.resolve_embeddings(loaded),
           {:ok, budget} <- Ipse.Usage.Budget.resolve_policy(loaded),
           {:ok, journal} <- Ipse.Journal.resolve_limits(loaded),
           {:ok, observation} <- Ipse.Observability.resolve(loaded, opts, environment),
           :ok <- Ipse.Config.Profiles.validate(effective.profiles, effective.roles),
           {:ok, profile_id, profile} <-
             Ipse.Config.Profiles.select(
               effective.profiles,
               effective.roles,
               opts[:profile] || environment["IPSE_PROFILE"]
             ) do
        effective =
          overlay(effective, Ipse.Config.Profiles.settings(profile), "profile #{profile_id}")

        effective = overlay(effective, env, "environment")

        cli =
          for {field, key} <- @option_keys,
              Keyword.has_key?(opts, key),
              into: %{},
              do: {field, opts[key]}

        effective = overlay(effective, cli, "CLI")

        settings =
          Map.put_new_lazy(effective.settings, "model", fn ->
            case @providers[effective.settings["provider"]] do
              {_, model} -> model
              nil -> nil
            end
          end)

        provenance = Map.put_new(effective.provenance, "model", "provider default")

        execution = Ipse.Config.Profiles.manifest(profile_id, profile)

        with :ok <- validate_settings(settings),
             :ok <-
               Ipse.Config.Profiles.reasoning(
                 settings["provider"],
                 settings["model"],
                 profile["reasoning_effort"]
               ),
             :ok <-
               Ipse.Provider.validate_output_limit(%{
                 provider: elem(@providers[settings["provider"]], 0),
                 max_output_tokens: settings["max_output_tokens"]
               }),
             :ok <-
               Ipse.Usage.Budget.validate_configuration(%{
                 budget: budget,
                 provider: elem(@providers[settings["provider"]], 0),
                 max_output_tokens: settings["max_output_tokens"]
               }),
             true <-
               is_nil(profile_id) or
                 (settings["provider"] == profile["provider"] and
                    settings["model"] == profile["model"] and is_nil(opts[:base_url])),
             true <- settings["subagent_concurrency"] == 1 or settings["subagents"] do
          identity = %{
            "settings" => settings,
            "sources" => effective.sources,
            "profiles" => effective.profiles,
            "roles" => effective.roles,
            "execution" => execution
          }

          identity =
            if extensions == %{"instances" => [], "trust" => []},
              do: identity,
              else: Map.put(identity, "extensions", extensions)

          identity = if budget, do: Map.put(identity, "budget", budget), else: identity

          identity =
            if embedding_profiles == %{},
              do: identity,
              else: Map.put(identity, "embedding_profiles", embedding_profiles)

          fingerprint = Ipse.JSON.digest([identity])

          {:ok,
           %{effective | settings: settings, provenance: provenance}
           |> Map.put(:fingerprint, fingerprint)
           |> Map.put(:extensions, extensions)
           |> Map.put(:embedding_profiles, embedding_profiles)
           |> Map.put(:budget, budget)
           |> Map.put(:journal, journal)
           |> Map.put(:observability, observation)
           |> Map.put(:execution, execution)}
        else
          {:error, message} when is_binary(message) ->
            {:error, message}

          _ ->
            {:error,
             "Invalid effective configuration or subagent concurrency; inspect ipse config."}
        end
      end
    else
      false -> {:error, "Invalid configuration workspace."}
      {:error, _} = error -> error
    end
  end

  @doc "Admit runtime resources after resolve/4; client supplies paths and interaction policy."
  def runtime(effective, client) do
    settings = effective.settings
    {provider, _} = Map.fetch!(@providers, settings["provider"])
    sandbox = Map.fetch!(@sandboxes, settings["sandbox"])

    cond do
      provider == :chatgpt && client.base_url ->
        {:error, "Subscription credentials only go to the official OpenAI endpoint."}

      not Ipse.Provider.valid_base_url?(provider, client.base_url) ->
        {:error,
         "Provider endpoint requires HTTPS or explicit HTTP loopback, without credentials, query or fragment."}

      true ->
        with {:ok, extensions} <-
               Ipse.Extension.Registry.prepare(effective.extensions, client.home),
             {:ok, servers} <- Ipse.MCP.Config.load(client.mcp_config),
             {:ok, _policy} <- Ipse.Tools.Sandbox.resolve(sandbox, client.workspace) do
          {:ok,
           Map.merge(
             %{
               provider: provider,
               model: settings["model"],
               auth_dir: client.auth_dir,
               home: client.home,
               operator_home: client.operator_home,
               configuration: manifest(effective),
               extensions: extensions,
               embedding_profiles: effective.embedding_profiles,
               observability: effective.observability.policy,
               timeout_ms: settings["timeout_ms"],
               max_output_tokens: settings["max_output_tokens"],
               budget: effective.budget,
               journal: effective.journal,
               sandbox: sandbox,
               base_url: client.base_url,
               max_steps: settings["max_steps"],
               context_bytes: settings["context_bytes"],
               compact: settings["compact"],
               mcp_servers: servers,
               subagents: settings["subagents"],
               subagent_concurrency: settings["subagent_concurrency"],
               operator_questions: client.operator_questions,
               approval: client.approval
             },
             Ipse.Config.Profiles.runtime(effective)
           )}
        end
    end
  end

  def manifest(effective),
    do:
      Map.take(effective, [
        :settings,
        :sources,
        :provenance,
        :fingerprint,
        :profiles,
        :roles,
        :execution
      ])
      |> Map.put(:extensions, Ipse.Extension.Config.inspect_config(effective.extensions))
      |> Map.put(:observability, effective.observability)
      |> Map.put(:budget, effective.budget)
      |> Map.put(:journal, effective.journal)
      |> Map.merge(
        if(effective.embedding_profiles == %{},
          do: %{},
          else: %{embedding_profiles: effective.embedding_profiles}
        )
      )

  def legacy_compatible?(effective), do: effective.sources == []

  def settings_schema do
    %{
      "type" => "object",
      "properties" => %{
        "provider" => %{"type" => "string", "enum" => Map.keys(@providers)},
        "model" => %{"type" => "string", "minLength" => 1, "maxLength" => 200},
        "sandbox" => %{"type" => "string", "enum" => ["off", "native"]},
        "max_steps" => integer(1, 100_000),
        "context_bytes" => integer(8192, 16_000_000),
        "compact" => %{"type" => "boolean"},
        "subagents" => %{"type" => "boolean"},
        "subagent_concurrency" => integer(1, 2),
        "timeout_ms" => integer(1000, 600_000),
        "max_output_tokens" => integer(1, Ipse.Provider.max_output_tokens())
      },
      "additionalProperties" => false
    }
  end

  defp schema do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(
          %{
            "version" => %{"type" => "integer", "enum" => [1]},
            "settings" => settings_schema(),
            "profiles" => %{"type" => "object"},
            "embedding_profiles" => %{"type" => "object"},
            "roles" => %{"type" => "object"},
            "observability" => Ipse.Observability.schema(),
            "budget" => Ipse.Usage.Budget.schema(),
            "journal" => Ipse.Journal.limit_schema()
          },
          Ipse.Extension.Config.schema()
        ),
      "required" => ["version"],
      "additionalProperties" => false
    }
  end

  defp validate_settings(settings) do
    with :ok <- Schema.validate_arguments(settings_schema(), settings),
         true <-
           not Map.has_key?(settings, "model") or
             not is_nil(Ipse.Provider.model_name(settings["model"])) do
      :ok
    else
      _ -> {:error, "Invalid configuration settings."}
    end
  end

  defp sources(dirs, home, opts, env) do
    explicit = opts[:config] || env["IPSE_CONFIG"]

    operator = %{
      path: Path.expand(explicit || Path.join(home, "config.json")),
      scope: "operator",
      required: not is_nil(explicit),
      boundary: nil
    }

    project =
      if opts[:project_config] == false,
        do: [],
        else:
          Enum.map(
            dirs,
            &%{
              path: Path.join(&1, ".ipse/config.json"),
              scope: "project",
              required: false,
              boundary: hd(dirs)
            }
          )

    if length(project) + 1 <= @max_sources,
      do: {:ok, [operator | project]},
      else: {:error, "Too many project configuration scopes."}
  end

  defp load_sources(sources) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, loaded} ->
      case read_source(source) do
        :missing -> {:cont, {:ok, loaded}}
        {:ok, value} -> {:cont, {:ok, loaded ++ [value]}}
        error -> {:halt, error}
      end
    end)
  end

  defp read_source(source) do
    with {:ok, stat} <- File.lstat(source.path) do
      with true <- stat.type in [:regular, :symlink],
           {:ok, canonical} <- Workspace.canonical_path(source.path),
           true <- is_nil(source.boundary) or within?(canonical, source.boundary),
           {:ok, raw} <- read_bounded(canonical),
           {:ok, data} <- Ipse.JSON.decode_bounded(raw),
           :ok <- Schema.validate_arguments(schema(), data),
           :ok <- Ipse.Config.Profiles.validate(data["profiles"] || %{}, %{}),
           :ok <- Ipse.Config.Profiles.validate_embeddings(data["embedding_profiles"] || %{}),
           :ok <- Ipse.Extension.Config.validate(data),
           :ok <- validate_settings(data["settings"] || %{}) do
        {:ok,
         %{
           path: source.path,
           canonical_path: canonical,
           scope: source.scope,
           sha256: Ipse.JSON.sha256(raw),
           data: data
         }}
      else
        _ -> {:error, "Invalid, oversized or unsafe configuration: #{source.path}"}
      end
    else
      {:error, :enoent} ->
        if(source.required,
          do: {:error, "Configuration file not found: #{source.path}"},
          else: :missing
        )

      _ ->
        {:error, "Could not read configuration: #{source.path}"}
    end
  end

  defp read_bounded(path) do
    with {:ok, %{type: :regular}} <- File.stat(path),
         {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(file, @file_bytes + 1) do
          raw when is_binary(raw) and byte_size(raw) <= @file_bytes -> {:ok, raw}
          _ -> {:error, :invalid}
        end
      after
        File.close(file)
      end
    end
  end

  defp profile_authority(loaded) do
    operator_ids =
      loaded
      |> Enum.filter(&(&1.scope == "operator"))
      |> Enum.flat_map(&Map.keys(&1.data["profiles"] || %{}))
      |> MapSet.new()

    invalid =
      Enum.find(loaded, fn source ->
        source.scope == "project" and
          Enum.any?(source.data["profiles"] || %{}, fn {id, profile} ->
            MapSet.member?(operator_ids, id) or
              Enum.any?(~w(base_url model_call_timeout_ms), &Map.has_key?(profile, &1))
          end)
      end)

    if invalid,
      do:
        {:error,
         "Project configuration cannot define provider endpoints, extend model-call timeouts or replace operator profiles: #{invalid.path}"},
      else: :ok
  end

  defp project_trust(loaded, opts) do
    if Enum.any?(loaded, &(&1.scope == "project")) and opts[:trust_project_config] != true,
      do:
        {:error,
         "Project configuration requires explicit --trust-project-config; use ipse config --no-project-config to inspect operator defaults."},
      else: :ok
  end

  defp environment_settings(environment) do
    Enum.reduce_while(@env_keys, {:ok, %{}}, fn {field, key}, {:ok, values} ->
      case Map.fetch(environment, key) do
        :error ->
          {:cont, {:ok, values}}

        {:ok, value} ->
          case parse_environment(field, value) do
            {:ok, value} -> {:cont, {:ok, Map.put(values, field, value)}}
            _ -> {:halt, {:error, "Invalid #{key} configuration value."}}
          end
      end
    end)
  end

  defp parse_environment(field, value) when field in ["compact", "subagents"] do
    case value do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, :invalid}
    end
  end

  defp parse_environment(field, value)
       when field in [
              "max_steps",
              "context_bytes",
              "subagent_concurrency",
              "timeout_ms",
              "max_output_tokens"
            ] do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :invalid}
    end
  end

  defp parse_environment(_, value), do: {:ok, value}

  defp overlay(effective, values, source),
    do: %{
      effective
      | settings: Map.merge(effective.settings, values),
        provenance:
          Map.merge(effective.provenance, Map.new(values, fn {key, _} -> {key, source} end))
    }

  defp integer(min, max), do: %{"type" => "integer", "minimum" => min, "maximum" => max}
  defp within?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp project_dirs(cwd) do
    ancestors =
      Stream.unfold(cwd, fn
        nil -> nil
        dir -> {dir, if(Path.dirname(dir) == dir, do: nil, else: Path.dirname(dir))}
      end)
      |> Enum.to_list()

    root =
      Enum.find(ancestors, cwd, fn dir ->
        case File.lstat(Path.join(dir, ".git")) do
          {:ok, %{type: type}} when type in [:regular, :directory] -> true
          _ -> false
        end
      end)

    {:ok, ancestors |> Enum.take_while(&(&1 != root)) |> Kernel.++([root]) |> Enum.reverse()}
  end
end
