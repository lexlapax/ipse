defmodule Ipse.CLI do
  @moduledoc "Command parsing, configuration and Session startup."
  alias Ipse.CLI.Terminal

  def main(args) do
    Application.ensure_all_started(:ipse)
    code = run(args)
    if code != 0, do: System.halt(code)
  rescue
    e in [ArgumentError, File.Error] ->
      Terminal.puts(:stderr, "Error: #{format_error(e)}")
      System.halt(1)
  end

  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          provider: :string,
          model: :string,
          cwd: :string,
          state_dir: :string,
          resume: :string,
          handoff: :string,
          yes: :boolean,
          base_url: :string,
          max_steps: :integer,
          max_output_tokens: :integer,
          context_bytes: :integer,
          compact: :boolean,
          sandbox: :string,
          mcp_config: :string,
          subagents: :boolean,
          subagent_concurrency: :integer,
          config: :string,
          trust_project_config: :boolean,
          project_config: :boolean,
          timeout_ms: :integer,
          profile: :string,
          extension: :keep,
          extensions: :boolean,
          observability: :string,
          fixture: :string,
          keep_fixture: :boolean,
          developer_trace: :boolean,
          trace_ms: :integer,
          trace_events: :integer,
          json: :boolean,
          note: :string,
          version: :boolean,
          help: :boolean,
          demo: :boolean
        ],
        aliases: [h: :help, y: :yes]
      )

    cond do
      invalid != [] ->
        report(
          {:error,
           "Unknown or invalid options. Run ipse --help to review supported options; no task was started."}
        )

      Enum.any?(
        ~w(fixture keep_fixture developer_trace trace_ms trace_events)a,
        &Keyword.has_key?(opts, &1)
      ) and
          (rest != ["extension", "check"] or opts[:demo] == true) ->
        report({:error, "Fixture and developer trace options require extension check."})

      Keyword.has_key?(opts, :handoff) and
          (rest not in [[], ["chat"]] or Keyword.has_key?(opts, :resume) or opts[:demo] == true or
             opts[:help] == true) ->
        report(
          {:error,
           "--handoff requires fresh interactive chat; cannot combine with --resume or another command mode."}
        )

      opts[:help] ->
        Terminal.help()
        0

      opts[:version] ->
        Terminal.puts(Ipse.version())
        0

      true ->
        dispatch(rest, opts)
    end
  end

  defp dispatch(["version"], opts) do
    if opts[:json],
      do: Terminal.puts(Jason.encode!(Ipse.build_info(), pretty: true)),
      else: Terminal.puts("Ipse " <> Ipse.version())

    0
  end

  defp dispatch(["login"], _opts), do: report(Ipse.Auth.login(auth_dir()))

  defp dispatch(["budget"], opts) do
    if opts[:resume] do
      case Ipse.Usage.Budget.saved(state_dir(opts), opts[:resume]) do
        {:ok, snapshot} ->
          Terminal.puts(Jason.encode!(snapshot))
          0

        _ ->
          report({:error, "Saved budget unavailable; inspect the original journals and ledger."})
      end
    else
      report({:error, "budget requires --resume SESSION_ID"})
    end
  end

  defp dispatch(["logout"], _opts), do: report(Ipse.Auth.logout(auth_dir()))

  defp dispatch(["status"], _opts) do
    case Ipse.Auth.status(auth_dir()) do
      {:ok, status} ->
        Terminal.puts(Jason.encode!(status, pretty: true))
        0

      {:error, error} ->
        report({:error, error})
    end
  end

  defp dispatch(["sessions"], opts) do
    if opts[:json] do
      sessions =
        for %{"id" => id, "metadata" => meta} <- Ipse.Journal.list(state_dir(opts)) do
          %{
            "id" => id,
            "provider" => meta["provider"],
            "model" => meta["model"],
            "cwd" => meta["cwd"]
          }
        end

      Terminal.puts(Jason.encode!(sessions))
    else
      for %{"id" => id, "metadata" => meta} <- Ipse.Journal.list(state_dir(opts)) do
        Terminal.puts("#{id}  #{meta["provider"]}/#{meta["model"]}  #{meta["cwd"]}")
      end
    end

    0
  end

  defp dispatch(["skills"], opts) do
    print_skills(opts[:cwd] || default_cwd())
    0
  end

  defp dispatch(["config"], opts) do
    with {:ok, effective} <- Ipse.Config.resolve(opts[:cwd] || default_cwd(), home(), opts),
         {:ok, _servers} <- Ipse.MCP.Config.load(opts[:mcp_config]) do
      Terminal.puts(Jason.encode!(Ipse.Config.manifest(effective), pretty: true))
      0
    else
      {:error, reason} -> report({:error, reason})
    end
  end

  defp dispatch(["extension", "list"], _opts) do
    Terminal.puts(Jason.encode!(Ipse.Extension.Registry.builtins(), pretty: true))
    0
  end

  defp dispatch(["extension", "import", source], _opts) do
    extension_artifact(
      Ipse.Extension.Artifact.import(source, Path.join(home(), "extensions/artifacts"))
    )
  end

  defp dispatch(["extension", "inspect", digest], _opts) do
    extension_artifact(
      Ipse.Extension.Registry.lookup(Path.join(home(), "extensions/artifacts"), digest)
    )
  end

  defp dispatch(["extension", "check"], opts) do
    allowed =
      ~w(config cwd trust_project_config project_config extension extensions yes sandbox observability fixture keep_fixture developer_trace trace_ms trace_events json)a

    with true <- is_binary(opts[:fixture]) and Enum.all?(Keyword.keys(opts), &(&1 in allowed)),
         {:ok, _} <- Ipse.Observability.Trace.policy(opts),
         {:ok, fixture, digest} <- Ipse.Extension.Conformance.read(opts[:fixture]),
         {:ok, effective} <- Ipse.Config.resolve(opts[:cwd] || default_cwd(), home(), opts) do
      Terminal.puts(
        :stderr,
        "Synthetic SDK check: selected trusted workers use your OS permissions. Host mutations require --yes; context and state use a scratch workspace."
      )

      sandbox = if effective.settings["sandbox"] == "native", do: :native, else: :off

      check_opts =
        [
          yes: opts[:yes] == true,
          keep: opts[:keep_fixture] == true,
          sandbox: sandbox,
          observability: effective.observability.policy,
          developer_trace: opts[:developer_trace] == true
        ] ++ Keyword.take(opts, [:trace_ms, :trace_events])

      case Ipse.Extension.Conformance.run(effective.extensions, home(), fixture, check_opts) do
        {:ok, result} ->
          Terminal.puts(Jason.encode!(Map.put(result, "fixture_sha256", digest), pretty: true))
          if result["passed"], do: 0, else: 1

        _ ->
          report(
            {:error, "Synthetic conformance execution failed; no fixture content was printed."}
          )
      end
    else
      _ ->
        report(
          {:error, "Invalid conformance fixture/configuration or unsupported check options."}
        )
    end
  end

  defp dispatch(["result", output_id], opts) do
    case Ipse.Extension.ResultSource.read_saved(state_dir(opts), opts[:resume], output_id) do
      {:ok, %{bytes: bytes}} ->
        Terminal.puts(bytes)
        0

      _ ->
        report(
          {:error, "Saved result unavailable or invalid; use its original session and output ID."}
        )
    end
  end

  defp dispatch(["research"], opts) do
    case Ipse.Tools.Research.load(state_dir(opts), opts[:resume]) do
      {:ok, ledger} ->
        Terminal.puts(Jason.encode!(ledger, pretty: true))
        0

      {:error, reason} ->
        report({:error, reason})
    end
  end

  defp dispatch(["diagnose"], opts) do
    case Ipse.Session.Saved.inspect_saved(state_dir(opts), opts[:resume]) do
      {:ok, result} ->
        Terminal.puts(Jason.encode!(result, pretty: true))
        0

      {:error, reason} ->
        report({:error, reason})
    end
  end

  defp dispatch(["handoff"], opts) do
    case Ipse.Session.Saved.export_handoff(state_dir(opts), opts[:resume], opts[:note]) do
      {:ok, result} ->
        Terminal.puts(Jason.encode!(result, pretty: true))
        0

      {:error, reason} ->
        report({:error, reason})
    end
  end

  defp dispatch(["demo"], opts) do
    cwd =
      opts[:cwd] ||
        Path.join(
          System.tmp_dir!(),
          "ipse-demo-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
        )

    File.mkdir_p!(cwd)

    Terminal.puts(
      "Scripted demo workspace: #{cwd}\nThis demo creates ipse-demo.txt and runs printf."
    )

    start(
      Keyword.merge(opts, cwd: cwd, provider: "demo", yes: true),
      "Demonstrate the coding loop",
      false
    )
  end

  defp dispatch(["run" | prompt], opts) do
    prompt = if prompt == [], do: IO.read(:stdio, :eof), else: Enum.join(prompt, " ")

    if is_binary(prompt) and String.trim(prompt) != "",
      do: start(opts, prompt, false),
      else:
        (
          Terminal.puts(:stderr, "Provide a task after run, or on stdin.")
          1
        )
  end

  defp dispatch([], opts), do: start(opts, nil, true)
  defp dispatch(["chat"], opts), do: start(opts, nil, true)

  defp dispatch(_, _),
    do:
      (
        Terminal.help()
        1
      )

  defp handoff_options(opts) do
    if Keyword.has_key?(opts, :handoff) do
      case Ipse.Session.Saved.read_handoff(opts[:handoff]) do
        {:ok, bytes} -> {:ok, [handoff: bytes]}
        {:error, _} -> {:error, :invalid_handoff}
      end
    else
      {:ok, []}
    end
  end

  defp extension_artifact({:ok, artifact}) do
    Terminal.puts(
      Jason.encode!(%{"digest" => artifact.digest, "manifest" => artifact.manifest}, pretty: true)
    )

    0
  end

  defp extension_artifact({:error, _}),
    do: report({:error, "Extension artifact import/verification failed; no code was activated."})

  defp start(opts, prompt, interactive) do
    with {:ok, handoff_opts} <- handoff_options(opts),
         {:ok, opts} <- resume_options(opts),
         {:ok, config} <- config(opts, interactive),
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session,
              [
                config: config,
                cwd: opts[:cwd] || default_cwd(),
                state_dir: state_dir(opts),
                id: opts[:resume],
                subscriber: self(),
                owner: self()
              ] ++ handoff_opts}
           ) do
      ref = Process.monitor(pid)
      info = Ipse.Session.info(pid)

      Terminal.puts(
        :stderr,
        "Ipse · #{config.provider}/#{config.model}\nSession: #{info.id}\nWorkspace: #{info.cwd}"
      )

      Terminal.puts(:stderr, Ipse.Tools.Sandbox.describe(config.sandbox))

      if config.configuration.sources != [],
        do:
          Terminal.puts(
            :stderr,
            "Effective configuration:\n" <> Jason.encode!(config.configuration, pretty: true)
          )

      if config.extensions != [] do
        Terminal.puts(
          :stderr,
          "Extensions enabled: trusted worker programs use your OS permissions outside the shell sandbox."
        )

        Terminal.puts(
          :stderr,
          Jason.encode!(Ipse.Extension.Registry.manifests(config), pretty: true)
        )
      end

      if config.subagents,
        do:
          Terminal.puts(
            :stderr,
            "Local subagents enabled: same workspace; configured routine/profile routing or parent provider/model; parent approvals apply. " <>
              "Concurrency #{Map.get(config, :subagent_concurrency, 1)}; up to two children per turn and six model steps per child. Child requests share a configured session-tree budget."
          )

      if config[:budget],
        do:
          Terminal.puts(
            :stderr,
            "Shared session-tree reservations enabled; unknown liability is retained. " <>
              "Fresh sessions have separate quotas. Inspect with ipse budget --resume #{info.id} using the same --state-dir."
          )

      for server <- config.mcp_servers do
        policy =
          if Map.get(server, :sandbox, :off) == :native,
            do: "native workspace sandbox requested; fails closed",
            else: "trusted user permissions; outside shell sandbox"

        notice =
          if Map.get(server, :transport) == :http,
            do:
              "MCP network server (explicit endpoint; remote effects and cancellation are outside the local sandbox):",
            else: "MCP local server (#{policy}):"

        Terminal.puts(:stderr, notice)
        Terminal.puts(:stderr, Jason.encode!(Ipse.MCP.Config.manifest(server), pretty: true))
      end

      if config.approval == :allow,
        do:
          Terminal.puts(
            :stderr,
            "Mutations, shell, configured MCP, and enabled delegation are allowed for this session (--yes)."
          )

      if handoff_opts != [],
        do: Terminal.puts(:stderr, Ipse.Session.Saved.handoff_notice(handoff_opts[:handoff]))

      result = Terminal.interact(pid, ref, interactive, prompt, info.cwd)

      cleanup = if Process.alive?(pid), do: Ipse.Session.close(pid), else: :ok
      Process.demonitor(ref, [:flush])

      if cleanup == :ok do
        result
      else
        Terminal.puts(
          :stderr,
          "Owned work cleanup could not be confirmed; inspect saved receipts and running processes."
        )

        max(result, 1)
      end
    else
      {:error, reason} ->
        Terminal.puts(:stderr, "Cannot start: #{format_error(reason)}")
        1
    end
  end

  defp config(opts, interactive) do
    workspace = opts[:cwd] || default_cwd()
    home = home()

    client = %{
      workspace: workspace,
      home: home,
      auth_dir: Path.join(home, "auth"),
      operator_home: Ipse.Workspace.operator_home(),
      mcp_config: opts[:mcp_config],
      base_url: opts[:base_url],
      operator_questions: interactive,
      approval: if(opts[:yes], do: :allow, else: if(interactive, do: :ask, else: :deny))
    }

    with {:ok, effective} <- Ipse.Config.resolve(workspace, home, opts),
         {:ok, runtime} <- Ipse.Config.runtime(effective, client),
         {:ok, _key} <- credential(runtime.provider) do
      {:ok, runtime}
    end
  end

  defp credential(:chatgpt), do: Ipse.Auth.token(auth_dir())
  defp credential(:openai), do: env_key("OPENAI_API_KEY")
  defp credential(:anthropic), do: env_key("ANTHROPIC_API_KEY")
  defp credential(_), do: {:ok, nil}

  defp env_key(name) do
    case System.get_env(name) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, "Set #{name} first."}
    end
  end

  defp resume_options(opts) do
    if opts[:resume] do
      with {:ok, %{"type" => "session", "metadata" => meta}} when is_map(meta) <-
             Ipse.Journal.header(state_dir(opts), opts[:resume]) do
        saved = get_in(meta, ["configuration", "settings"]) || %{}

        saved =
          if meta["max_output_tokens"],
            do: Map.put_new(saved, "max_output_tokens", meta["max_output_tokens"]),
            else: saved

        restored =
          Enum.reduce(saved, opts, fn {key, value}, acc ->
            case key do
              key
              when key in ~w(provider model sandbox max_steps context_bytes compact subagents subagent_concurrency timeout_ms max_output_tokens) ->
                Keyword.put_new(acc, String.to_existing_atom(key), value)

              _ ->
                acc
            end
          end)

        {:ok,
         restored
         |> Keyword.put_new(:profile, get_in(meta, ["configuration", "execution", "id"]))
         |> Keyword.put_new(:cwd, meta["cwd"])
         |> Keyword.put_new(:provider, meta["provider"])
         |> Keyword.put_new(:model, meta["model"])
         |> Keyword.put_new(:sandbox, Map.get(meta, "sandbox", "off"))
         |> Keyword.put_new(:subagents, Map.get(meta, "subagents", false))
         |> then(fn restored ->
           if restored[:subagents],
             do:
               Keyword.put_new(
                 restored,
                 :subagent_concurrency,
                 Map.get(meta, "subagent_concurrency", 1)
               ),
             else: restored
         end)}
      else
        {:error, :enoent} -> {:error, :session_not_found}
        {:error, :invalid_id} -> {:error, :invalid_id}
        _ -> {:error, :invalid_journal}
      end
    else
      {:ok, opts}
    end
  end

  defp state_dir(opts), do: opts[:state_dir] || Path.join(home(), "sessions")
  defp auth_dir, do: Path.join(home(), "auth")
  defp default_cwd, do: System.get_env("IPSE_WORKSPACE") || File.cwd!()
  defp home, do: System.get_env("IPSE_HOME") || Path.expand("~/.ipse")

  defp print_skills(cwd),
    do: Terminal.puts(Ipse.Workspace.skill_catalog(Ipse.Workspace.discover_skills(cwd)))

  defp report(:ok), do: 0

  defp report({:error, reason}),
    do:
      (
        Terminal.puts(:stderr, format_error(reason))
        1
      )

  defp format_error(reason), do: Ipse.CLI.Errors.format(reason)
end
