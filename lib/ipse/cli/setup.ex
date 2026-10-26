defmodule Ipse.CLI.Setup do
  @moduledoc "Explicit first-run provider choice, review and private configuration writes."
  alias Ipse.CLI.{Doctor, Errors, Terminal}
  @providers Ipse.Provider.Registry.ids()
  @options ~w(provider model sandbox config cwd write replace base_url upstream data_collection)a
  @limit 16_384

  def run(opts, home, cwd) do
    path =
      Path.expand(
        opts[:config] || System.get_env("IPSE_CONFIG") || Path.join(home, "config.json")
      )

    with true <-
           Enum.all?(Keyword.keys(opts), &(&1 in @options)) ||
             {:error,
              "Unsupported setup options. See ipse --help for provider/model, route, shell, preview and save options."},
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         true <- File.dir?(cwd) || {:error, :workspace_not_found},
         {:ok, original} <- read_existing(path),
         :ok <- replacement(original, opts, path, cwd, home),
         {:ok, selection, route, interactive?} <- select(opts, original, cwd, home),
         {:ok, document} <- document(original.document, selection, route),
         :ok <- validate(document),
         bytes = Jason.encode!(document, pretty: true) <> "\n",
         true <-
           byte_size(bytes) <= @limit ||
             {:error,
              "Setup output exceeds 16 KiB; reduce the operator configuration before saving."},
         {:ok, effective} <-
           Ipse.Config.preview(cwd, home, [config: path, project_config: false], bytes),
         true <-
           Enum.all?(selection, fn {key, value} -> effective.settings[key] == value end) ||
             {:error,
              "Environment or profile settings override the proposed route or shell policy. Inspect ipse config and remove that conflict before saving setup."},
         :ok <- credential_step(selection["provider"], interactive?, home) do
      Terminal.puts("Operator configuration: #{path}")

      Terminal.puts(
        "Provider #{selection["provider"]}; #{billing(selection["provider"])} billing; model #{selection["model"]}."
      )

      Terminal.puts(bytes)

      cond do
        not interactive? and opts[:write] != true ->
          Terminal.puts("Dry run; add --write to save this configuration.")
          0

        interactive? and
            read_line("Type write to save, or anything else to cancel: ") != {:ok, "write"} ->
          Terminal.puts("Setup cancelled; no configuration was written.")
          0

        true ->
          case write_configuration(path, bytes, original) do
            :ok ->
              Terminal.puts("Saved private operator configuration.")
              {code, report} = Doctor.run([config: path, project_config: false], home, cwd)
              Doctor.print(report, false)

              command = if selection["provider"] == "demo", do: "ipse demo", else: "ipse chat"
              Terminal.puts("Next: " <> command <> " --config " <> quote_arg(path))

              code

            {:error, reason} ->
              fail(reason)
          end
      end
    else
      {:error, reason} ->
        fail(reason)

      _ ->
        fail(
          "Setup refused before writing. Inspect ipse config and the operator configuration manual."
        )
    end
  end

  defp replacement(%{bytes: nil}, _, _, _, _), do: :ok

  defp replacement(_original, opts, path, cwd, home) do
    if opts[:replace] do
      :ok
    else
      provider =
        case Ipse.Config.resolve(cwd, home, config: path, project_config: false) do
          {:ok, effective} -> effective.settings["provider"]
          _ -> "unresolved; inspect ipse config"
        end

      Terminal.puts("Existing operator configuration: #{path}; provider #{provider}.")

      {:error,
       "Configuration already exists. Review ipse config, then use setup --replace to retain a private timestamped backup."}
    end
  end

  defp select(opts, original, cwd, home) do
    interactive? = is_nil(opts[:provider]) and is_nil(opts[:model])

    cond do
      interactive? and not match?({:ok, _}, :io.columns()) ->
        {:error,
         "Interactive setup requires a TTY. Use ipse setup --provider PROVIDER --model MODEL for a dry run, then add --write."}

      not interactive? and (is_nil(opts[:provider]) or is_nil(opts[:model])) ->
        {:error,
         "Non-interactive setup requires both --provider and --model. Use ipse setup --help to review options."}

      true ->
        with {:ok, provider} <- choose_provider(opts[:provider]),
             {:ok, model} <- choose_model(provider, opts[:model], interactive?),
             {:ok, route} <- choose_route(provider, model, opts, interactive?),
             {:ok, sandbox} <-
               choose_sandbox(opts[:sandbox], original.document, cwd, home, interactive?) do
          {:ok, %{"provider" => provider, "model" => model, "sandbox" => sandbox}, route,
           interactive?}
        end
    end
  end

  defp choose_provider(nil) do
    for {provider, index} <- Enum.with_index(@providers, 1),
        do: Terminal.puts("#{index}. #{provider_label(provider)} [#{provider}]")

    ask_provider()
  end

  defp choose_provider(provider) when provider in @providers, do: {:ok, provider}

  defp choose_provider(_),
    do: {:error, "Unknown setup provider; choose one listed by ipse --help."}

  defp ask_provider do
    case read_line("Provider (no default): ") do
      {:ok, answer} ->
        provider =
          case Integer.parse(answer) do
            {index, ""} when index >= 1 and index <= length(@providers) ->
              Enum.at(@providers, index - 1)

            _ ->
              answer
          end

        if provider in @providers do
          {:ok, provider}
        else
          Terminal.puts("Choose a listed provider; no default was selected.")
          ask_provider()
        end

      _ ->
        {:error, "Setup cancelled at end of input; no configuration was written."}
    end
  end

  defp choose_model(provider, nil, true) do
    default = Ipse.Config.default_model(provider)

    prompt =
      if default, do: "Model (default #{default}): ", else: "Model (required; no default): "

    case read_line(prompt) do
      {:ok, answer} ->
        case choose_model(provider, if(answer == "", do: default, else: answer), false) do
          {:ok, model} ->
            {:ok, model}

          _ ->
            Terminal.puts(
              "Invalid model name; use a supported model identifier without spaces or query characters."
            )

            choose_model(provider, nil, true)
        end

      _ ->
        {:error, "Setup cancelled at end of input; no configuration was written."}
    end
  end

  defp choose_model(_, model, _) do
    case Ipse.Provider.model_name(model) do
      nil -> {:error, "Invalid setup model; supply a valid --model identifier."}
      model -> {:ok, model}
    end
  end

  defp choose_route(provider, model, opts, interactive?) do
    route = %{"provider" => provider, "model" => model}
    route = if opts[:base_url], do: Map.put(route, "base_url", opts[:base_url]), else: route

    cond do
      provider == "openrouter" ->
        with {:ok, upstream} <-
               route_field(
                 "OpenRouter upstream slug (required): ",
                 opts[:upstream],
                 interactive?,
                 nil
               ),
             {:ok, policy} <-
               route_field(
                 "Data collection deny/allow (default deny): ",
                 opts[:data_collection],
                 interactive?,
                 "deny"
               ),
             route = Map.merge(route, %{"upstream" => upstream, "data_collection" => policy}),
             :ok <- Ipse.Config.Profiles.validate_profile(route),
             do: {:ok, route}

      Keyword.has_key?(opts, :upstream) or Keyword.has_key?(opts, :data_collection) ->
        {:error, "Upstream and data collection options apply only to OpenRouter setup."}

      provider == "openai_compatible" ->
        with {:ok, url} <-
               route_field("Loopback base URL (required): ", opts[:base_url], interactive?, nil),
             route = Map.put(route, "base_url", url),
             :ok <- Ipse.Config.Profiles.validate_profile(route),
             do: {:ok, route}

      true ->
        with :ok <- Ipse.Config.Profiles.validate_profile(route), do: {:ok, route}
    end
  end

  defp route_field(_, value, _, _) when is_binary(value), do: {:ok, value}

  defp route_field(prompt, nil, true, default) do
    case read_line(prompt) do
      {:ok, ""} -> {:ok, default}
      {:ok, answer} -> {:ok, answer}
      _ -> {:error, "Setup cancelled at end of input; no configuration was written."}
    end
  end

  defp route_field(_, nil, false, default), do: {:ok, default}

  defp document(original, selection, route) do
    with :ok <- compatible_main(original, selection) do
      document = Map.update(original, "settings", selection, &Map.merge(&1, selection))

      needs_profile? =
        route["provider"] in ["openrouter", "openai_compatible"] or
          Map.has_key?(route, "base_url")

      main = get_in(original, ["roles", "main"])
      profile = get_in(original, ["profiles", main])

      cond do
        not needs_profile? ->
          {:ok, document}

        is_map(profile) ->
          values = Map.merge(Ipse.Provider.Registry.profile_values(profile), profile)

          if Enum.all?(route, fn {key, value} -> values[key] == value end),
            do: {:ok, document},
            else:
              {:error,
               "Setup preserves the existing main profile. Its endpoint, upstream or data policy differs; edit and review the operator file explicitly."}

        true ->
          id = "setup_" <> route["provider"]
          profiles = original["profiles"] || %{}

          if Map.has_key?(profiles, id) do
            {:error,
             "The setup profile name already exists. Setup preserves it; edit and review profiles explicitly."}
          else
            {:ok,
             document
             |> Map.put("profiles", Map.put(profiles, id, route))
             |> Map.put("roles", Map.put(original["roles"] || %{}, "main", id))}
          end
      end
    end
  end

  defp credential_step(provider, interactive?, home) do
    case Ipse.Provider.Registry.fetch!(provider).credential do
      :chatgpt_auth ->
        subscription_step(interactive?, home)

      :xai_auth ->
        Terminal.puts(
          "Credential source: protected xAI subscription sign-in. An approved Ipse OAuth client is required; set IPSE_XAI_CLIENT_ID, then run ipse login --provider xai_oauth. No API-key fallback is used."
        )

        if interactive? and
             read_line("Run xAI device authorization now? Type yes to continue: ") == {:ok, "yes"},
           do: Ipse.Auth.XAI.login(Path.join(home, "auth")),
           else: :ok

      credential ->
        source =
          case credential do
            {:env, name} -> name <> " (private environment)"
            :none -> "none"
          end

        Terminal.puts("Credential source: #{source}. Setup never asks for or stores an API key.")
        :ok
    end
  end

  defp subscription_step(interactive?, home) do
    Terminal.puts(
      "Credential source: protected ChatGPT sign-in. Run ipse login; no API key is stored in configuration."
    )

    if interactive? and
         read_line("Run ipse login now? Type yes to start browser authorization: ") ==
           {:ok, "yes"} do
      Ipse.Auth.login(Path.join(home, "auth"))
    else
      :ok
    end
  end

  defp choose_sandbox(value, document, cwd, home, interactive?) do
    existing = get_in(document, ["settings", "sandbox"]) || "off"

    if interactive? and is_nil(value) do
      {_, report} = Doctor.run([provider: "demo", project_config: false], home, cwd)

      available? =
        Enum.any?(report["checks"], &(&1["id"] == "sandbox.native" and &1["status"] == "ok"))

      Terminal.puts(
        "Shell off uses your account permissions. Native confinement is optional and fails closed."
      )

      if available? do
        case read_line("Shell policy off/native (default #{existing}): ") do
          {:ok, answer} ->
            choose_sandbox(
              if(answer == "", do: existing, else: answer),
              document,
              cwd,
              home,
              false
            )

          _ ->
            {:error, "Setup cancelled at end of input; no configuration was written."}
        end
      else
        Terminal.puts(
          "Native policy is unavailable or experimental for this workspace. Existing shell policy is retained; inspect ipse doctor before using native."
        )

        {:ok, existing}
      end
    else
      case value || existing do
        "off" ->
          {:ok, "off"}

        "native" ->
          case Ipse.Tools.Sandbox.resolve(:native, cwd) do
            {:ok, _} ->
              {:ok, "native"}

            _ ->
              {:error,
               "Native policy is unavailable for this workspace; inspect ipse doctor or explicitly choose --sandbox off."}
          end

        _ ->
          {:error, "Invalid setup shell policy; choose --sandbox off or --sandbox native."}
      end
    end
  end

  defp read_existing(path) do
    case File.lstat(path) do
      {:error, :enoent} ->
        {:ok, %{bytes: nil, document: %{"version" => 1}}}

      {:ok, %{type: :regular, size: size}} when size <= @limit ->
        with {:ok, file} <- File.open(path, [:read, :binary]) do
          try do
            with bytes when is_binary(bytes) and byte_size(bytes) <= @limit <-
                   IO.binread(file, @limit + 1),
                 {:ok, document} <- Ipse.JSON.decode_bounded(bytes, @limit),
                 :ok <- validate(document) do
              {:ok, %{bytes: bytes, document: document}}
            else
              _ ->
                {:error,
                 "Existing setup configuration is malformed, unsupported or oversized; preserve it and inspect ipse config before replacing it."}
            end
          after
            File.close(file)
          end
        end

      _ ->
        {:error,
         "Setup target must be a readable regular configuration file or a new path; symlinks are refused."}
    end
  end

  defp validate(document) do
    with :ok <- Ipse.JSON.validate_arguments(Ipse.Config.schema(), document),
         :ok <-
           Ipse.Config.Profiles.validate(document["profiles"] || %{}, document["roles"] || %{}),
         :ok <- Ipse.Config.Profiles.validate_embeddings(document["embedding_profiles"] || %{}),
         :ok <- Ipse.Config.Decisions.validate(document["decision_profiles"] || %{}),
         :ok <- Ipse.Extension.Config.validate(document),
         do: :ok
  end

  defp compatible_main(document, selection) do
    profile = get_in(document, ["profiles", get_in(document, ["roles", "main"])])

    if is_nil(profile) or
         (profile["provider"] == selection["provider"] and profile["model"] == selection["model"]),
       do: :ok,
       else:
         {:error,
          "The existing main role selects a different provider/model profile. Setup preserves profiles and roles; edit the operator file explicitly instead of replacing this route silently."}
  end

  defp write_configuration(path, bytes, original) do
    with {:ok, current} <- read_existing(path),
         true <-
           current.bytes == original.bytes ||
             {:error,
              "Configuration changed during setup; inspect ipse config and preview again before writing."},
         :ok <- backup(path, original.bytes),
         :ok <- Ipse.PrivateFile.write_atomic(path, bytes, replace: not is_nil(original.bytes)) do
      :ok
    else
      {:error, :eexist} ->
        {:error,
         "A target or timestamped backup already exists; nothing was overwritten. Inspect the files and preview setup again."}

      _ ->
        {:error,
         "Could not save private configuration; inspect the original and any timestamped backup before retrying setup."}
    end
  end

  defp backup(_, nil), do: :ok

  defp backup(path, bytes) do
    suffix = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%SZ")
    destination = path <> ".bak-" <> suffix

    case Ipse.PrivateFile.write_atomic(destination, bytes, replace: false) do
      :ok ->
        Terminal.puts("Private backup: #{destination}")
        :ok

      error ->
        error
    end
  end

  defp read_line(prompt) do
    case IO.gets(prompt) do
      line when is_binary(line) -> {:ok, String.trim(line)}
      _ -> :eof
    end
  end

  defp billing(provider), do: Ipse.Usage.billing_mode(String.to_existing_atom(provider))
  defp provider_label(provider), do: Ipse.Provider.Registry.fetch!(provider).label
  defp quote_arg(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp fail(reason) do
    Terminal.puts(:stderr, Errors.format(reason))
    1
  end
end
