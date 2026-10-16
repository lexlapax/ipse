defmodule Ipse.Config do
  @moduledoc "Bounded data-only operator and scoped project configuration."
  alias Ipse.{MCP.Schema, WorkspaceContext, RuntimeInfo, Compaction}

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
  @models %{
    "chatgpt" => "gpt-6.1-sol",
    "openai" => "gpt-6.1-sol",
    "ollama" => "qwen3:8b",
    "anthropic" => "claude-sonnet-4-5",
    "demo" => "scripted"
  }
  @fields ~w(provider model sandbox max_steps context_bytes compact subagents subagent_concurrency timeout_ms)
  @option_keys Map.new(@fields, fn key -> {key, String.to_atom(key)} end)
  @env_keys Map.new(@fields, &{&1, "IPSE_" <> String.upcase(&1)})

  def resolve(cwd, home, opts \\ [], environment \\ System.get_env()) do
    with {:ok, cwd} <- WorkspaceContext.canonical_path(cwd),
         true <- File.dir?(cwd),
         {:ok, dirs} <- project_dirs(cwd),
         {:ok, sources} <- sources(dirs, home, opts, environment),
         {:ok, loaded} <- load_sources(sources),
         :ok <- project_trust(loaded, opts),
         {:ok, env} <- environment_settings(environment) do
      initial = %{
        settings: @defaults,
        provenance: Map.new(@defaults, fn {key, _} -> {key, "built-in"} end),
        sources: []
      }

      effective =
        Enum.reduce(loaded, initial, fn source, acc ->
          values = source.data["settings"] || %{}

          %{
            acc
            | settings: Map.merge(acc.settings, values),
              provenance:
                Map.merge(acc.provenance, Map.new(values, fn {key, _} -> {key, source.path} end)),
              sources: acc.sources ++ [Map.drop(source, [:data])]
          }
        end)

      effective = overlay(effective, env, "environment")

      cli =
        for {field, key} <- @option_keys,
            Keyword.has_key?(opts, key),
            into: %{},
            do: {field, opts[key]}

      effective = overlay(effective, cli, "CLI")
      settings = Map.put_new(effective.settings, "model", @models[effective.settings["provider"]])
      provenance = Map.put_new(effective.provenance, "model", "provider default")

      with :ok <- validate_settings(settings),
           true <- settings["subagent_concurrency"] == 1 or settings["subagents"] do
        fingerprint =
          Compaction.digest([%{"settings" => settings, "sources" => effective.sources}])

        {:ok,
         %{effective | settings: settings, provenance: provenance}
         |> Map.put(:fingerprint, fingerprint)}
      else
        _ ->
          {:error,
           "Invalid effective configuration or subagent concurrency; inspect ipse config."}
      end
    else
      false -> {:error, "Invalid configuration workspace."}
      {:error, _} = error -> error
    end
  end

  def runtime_settings(effective),
    do: Map.new(effective.settings, fn {key, value} -> {@option_keys[key], value} end)

  def manifest(effective),
    do: Map.take(effective, [:settings, :sources, :provenance, :fingerprint])

  def legacy_compatible?(effective), do: effective.sources == []

  def settings_schema do
    %{
      "type" => "object",
      "properties" => %{
        "provider" => %{"type" => "string", "enum" => Map.keys(@models)},
        "model" => %{"type" => "string", "minLength" => 1, "maxLength" => 200},
        "sandbox" => %{"type" => "string", "enum" => ["off", "native"]},
        "max_steps" => integer(1, 100_000),
        "context_bytes" => integer(8192, 16_000_000),
        "compact" => %{"type" => "boolean"},
        "subagents" => %{"type" => "boolean"},
        "subagent_concurrency" => integer(1, 2),
        "timeout_ms" => integer(1000, 600_000)
      },
      "additionalProperties" => false
    }
  end

  defp schema do
    %{
      "type" => "object",
      "properties" => %{
        "version" => %{"type" => "integer", "enum" => [1]},
        "settings" => settings_schema()
      },
      "required" => ["version"],
      "additionalProperties" => false
    }
  end

  defp validate_settings(settings) do
    with :ok <- Schema.validate_arguments(settings_schema(), settings),
         true <-
           not Map.has_key?(settings, "model") or
             not is_nil(RuntimeInfo.model_name(settings["model"])) do
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
           {:ok, canonical} <- WorkspaceContext.canonical_path(source.path),
           true <- is_nil(source.boundary) or within?(canonical, source.boundary),
           {:ok, raw} <- read_bounded(canonical),
           {:ok, data} <- Jason.decode(raw),
           :ok <- Schema.validate_arguments(schema(), data),
           :ok <- validate_settings(data["settings"] || %{}) do
        {:ok,
         %{
           path: source.path,
           canonical_path: canonical,
           scope: source.scope,
           sha256: Base.encode16(:crypto.hash(:sha256, raw), case: :lower),
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
       when field in ["max_steps", "context_bytes", "subagent_concurrency", "timeout_ms"] do
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
