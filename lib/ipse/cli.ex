defmodule Ipse.CLI do
  @moduledoc "Terminal client for the Ipse session API."

  @help """
  Ipse 0.1 — an Elixir coding agent

  ipse login                      Continue with ChatGPT
  ipse status                     Show subscription sign-in status
  ipse logout                     Sign out of ChatGPT
  ipse chat [options]              Interactive conversation
  ipse run [options] "task"         Run one task
  ipse demo                        Scripted demo in a temporary directory
  ipse sessions                    List saved sessions
  ipse skills [--cwd PATH]         List available skills

  --provider chatgpt|openai|ollama|anthropic|demo  (default: chatgpt)
  --model NAME                         Override the provider default
  --cwd PATH                           Workspace (default: current directory)
  --resume ID                          Resume a saved session
  --yes                                Allow mutations, shell, configured MCP, and enabled delegation
  --base-url URL                       API endpoint root (API/Ollama only)
  --state-dir PATH                     Session directory
  --max-steps N                        Model calls per turn (default: 30)
  --context-bytes N                    Context byte ceiling (default: 400000)
  --no-compact                         Stop at the ceiling without summarizing
  --sandbox off|native                 Shell OS policy (default: off)
  --mcp-config PATH                    Explicit local stdio servers and capability allowlists
  --subagents                          Enable bounded local delegation with parent approvals

  Chat asks before writes, shell, MCP, and delegation. Headless run denies them without --yes.
  Shell execution uses your user permissions unless --sandbox native is selected.
  Native enforcement fails closed when unavailable; approvals remain required.
  Chat commands: /help /skills /session /info /context /context refresh /cancel /exit.
  Invoke skills with $name.
  EOF finishes accepted work; errors and /cancel clear queued input.
  """

  def main(args) do
    Application.ensure_all_started(:ipse)
    code = run(args)
    if code != 0, do: System.halt(code)
  rescue
    e in [ArgumentError, File.Error] ->
      IO.puts(:stderr, "Error: #{Exception.message(e)}")
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
          yes: :boolean,
          base_url: :string,
          max_steps: :integer,
          context_bytes: :integer,
          compact: :boolean,
          sandbox: :string,
          mcp_config: :string,
          subagents: :boolean,
          help: :boolean,
          demo: :boolean
        ],
        aliases: [h: :help, y: :yes]
      )

    cond do
      invalid != [] ->
        IO.puts(:stderr, "Unknown options: #{inspect(invalid)}")
        1

      opts[:help] ->
        IO.puts(@help)
        0

      true ->
        dispatch(rest, opts)
    end
  end

  defp dispatch(["login"], _opts), do: report(Ipse.Auth.login(auth_dir()))
  defp dispatch(["logout"], _opts), do: report(Ipse.Auth.logout(auth_dir()))

  defp dispatch(["status"], _opts) do
    case Ipse.Auth.status(auth_dir()) do
      {:ok, status} ->
        IO.puts(inspect(status))
        0

      {:error, error} ->
        IO.puts(:stderr, to_string(error))
        1
    end
  end

  defp dispatch(["sessions"], opts) do
    for %{"id" => id, "metadata" => meta} <- Ipse.Journal.list(state_dir(opts)) do
      IO.puts("#{id}  #{meta["provider"]}/#{meta["model"]}  #{meta["cwd"]}")
    end

    0
  end

  defp dispatch(["skills"], opts) do
    print_skills(opts[:cwd] || default_cwd())
    0
  end

  defp dispatch(["demo"], opts) do
    cwd =
      opts[:cwd] ||
        Path.join(
          System.tmp_dir!(),
          "ipse-demo-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
        )

    File.mkdir_p!(cwd)

    IO.puts("Scripted demo workspace: #{cwd}\nThis demo creates ipse-demo.txt and runs printf.")

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
          IO.puts(:stderr, "Provide a task after run, or on stdin.")
          1
        )
  end

  defp dispatch([], opts), do: start(opts, nil, true)
  defp dispatch(["chat"], opts), do: start(opts, nil, true)

  defp dispatch(_, _),
    do:
      (
        IO.puts(@help)
        1
      )

  defp start(opts, prompt, interactive) do
    with {:ok, opts} <- resume_options(opts),
         {:ok, config} <- config(opts, interactive),
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session,
              config: config,
              cwd: opts[:cwd] || default_cwd(),
              state_dir: state_dir(opts),
              id: opts[:resume],
              subscriber: self()}
           ) do
      ref = Process.monitor(pid)
      info = Ipse.Session.info(pid)

      IO.puts(
        :stderr,
        "Ipse · #{config.provider}/#{config.model}\nSession: #{info.id}\nWorkspace: #{info.cwd}"
      )

      IO.puts(:stderr, "Shell policy requested: #{config.sandbox}.")

      if config.subagents,
        do:
          IO.puts(
            :stderr,
            "Local subagents enabled: same provider/model/workspace; parent approvals apply. " <>
              "Up to two children per turn and six model steps per child, additional to the parent budget."
          )

      for server <- config.mcp_servers do
        policy =
          if Map.get(server, :sandbox, :off) == :native,
            do: "native workspace sandbox requested; fails closed",
            else: "trusted user permissions; outside shell sandbox"

        IO.puts(:stderr, "MCP local server (#{policy}):")
        IO.puts(:stderr, Jason.encode!(Ipse.MCP.Config.manifest(server), pretty: true))
      end

      if config.sandbox == :native and :os.type() == {:unix, :darwin} do
        IO.puts(
          :stderr,
          "macOS restricts files and network. Detached child processes may survive cancellation."
        )
      end

      if config.approval == :allow,
        do:
          IO.puts(
            :stderr,
            "Mutations, shell, configured MCP, and enabled delegation are allowed for this session (--yes)."
          )

      client = self()
      reader = if interactive, do: spawn(fn -> read_input(client) end), else: nil
      if prompt, do: Ipse.Session.prompt(pid, prompt)

      if interactive,
        do: IO.puts("Type a task, $review, or /help. Use /cancel while work is running.")

      result =
        client_loop(%{
          pid: pid,
          ref: ref,
          interactive: interactive,
          busy: prompt != nil,
          cancelling: false,
          approval: nil,
          queued: [],
          exit: false,
          cwd: info.cwd
        })

      if reader && Process.alive?(reader), do: Process.exit(reader, :kill)
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
      Process.demonitor(ref, [:flush])
      result
    else
      {:error, reason} ->
        IO.puts(:stderr, "Cannot start: #{format_error(reason)}")
        1
    end
  end

  defp read_input(client) do
    case IO.gets("you> ") do
      :eof ->
        send(client, {:input, :eof})

      {:error, _} ->
        send(client, {:input, :eof})

      text ->
        send(client, {:input, String.trim(text)})
        read_input(client)
    end
  end

  defp client_loop(s) do
    pid = s.pid

    receive do
      {:input, :eof} ->
        if s.busy do
          if s.approval, do: Ipse.Session.approve(s.pid, s.approval, false)
          client_loop(%{s | exit: true, approval: nil})
        else
          0
        end

      {:input, "/exit"} ->
        Ipse.Session.cancel(s.pid)
        0

      {:input, "/cancel"} ->
        cond do
          s.cancelling ->
            IO.puts(:stderr, "Cancellation already requested.")
            client_loop(s)

          s.busy ->
            IO.puts(:stderr, "Cancelling active work…")
            Ipse.Session.cancel(s.pid)
            client_loop(%{s | cancelling: true, approval: nil, queued: []})

          true ->
            IO.puts(:stderr, "No active work to cancel.")
            client_loop(s)
        end

      {:input, "/help"} ->
        IO.puts(@help)
        client_loop(s)

      {:input, "/skills"} ->
        print_skills(s.cwd)
        client_loop(s)

      {:input, "/session"} ->
        IO.puts(inspect(Ipse.Session.info(s.pid)))
        client_loop(s)

      {:input, "/info"} ->
        IO.puts(Ipse.RuntimeInfo.format(Ipse.Session.info(s.pid).runtime))
        client_loop(s)

      {:input, "/context"} ->
        print_context(Ipse.Session.info(s.pid).context)
        client_loop(s)

      {:input, "/context refresh"} ->
        case Ipse.Session.refresh_context(s.pid) do
          :ok ->
            IO.puts(:stderr, "Refreshing workspace instructions…")
            client_loop(%{s | busy: true})

          {:error, :busy} ->
            IO.puts(:stderr, "Finish or cancel active work before refreshing instructions.")
            client_loop(s)
        end

      {:input, ""} ->
        client_loop(s)

      {:input, _text} when s.cancelling ->
        IO.puts(
          :stderr,
          "Input received during cancellation was discarded. Send it again after cancellation finishes."
        )

        client_loop(s)

      {:input, text} when s.approval != nil ->
        Ipse.Session.approve(s.pid, s.approval, String.downcase(text) in ["y", "yes"])
        client_loop(%{s | approval: nil})

      {:input, text} when s.busy ->
        IO.puts(:stderr, "Queued for the next turn. /cancel interrupts current work.")
        client_loop(%{s | queued: s.queued ++ [text]})

      {:input, text} ->
        Ipse.Session.prompt(s.pid, text)
        client_loop(%{s | busy: true})

      {:ipse, ^pid, {:status, :compacting}} ->
        unless s.cancelling,
          do: IO.puts(:stderr, "Compacting context with the selected provider…")

        client_loop(s)

      {:ipse, ^pid, {:compacted, before_bytes, after_bytes}} ->
        IO.puts(
          :stderr,
          "Context compacted: #{before_bytes} → #{after_bytes} bytes. Original journal retained."
        )

        client_loop(s)

      {:ipse, ^pid, {:context_refreshed, manifest}} ->
        print_context(manifest)
        client_loop(s)

      {:ipse, ^pid, {:status, _status}} ->
        unless s.cancelling, do: IO.puts(:stderr, "Running…")
        client_loop(s)

      {:ipse, ^pid, {:subagent, id, status}} ->
        unless s.cancelling, do: IO.puts(:stderr, "Subagent #{id}: #{status}")
        client_loop(s)

      {:ipse, ^pid, {:text, delta}} ->
        IO.write(delta)
        client_loop(s)

      {:ipse, ^pid, {:tool_output, delta}} ->
        IO.write(:stderr, delta)
        client_loop(s)

      {:ipse, ^pid, {:tool, name, args}} ->
        IO.puts(:stderr, "\n→ #{name} #{preview(args)}")
        client_loop(s)

      {:ipse, ^pid, {:tool_result, name, text}} ->
        IO.puts(:stderr, "← #{name}: #{String.slice(text, 0, 800)}")
        client_loop(s)

      {:ipse, ^pid, {:skill, name}} ->
        IO.puts(:stderr, "Skill: #{name}")
        client_loop(s)

      {:ipse, ^pid, {:mcp_approval_context, manifest}} ->
        IO.puts(:stderr, "External MCP target:\n" <> Jason.encode!(manifest, pretty: true))
        client_loop(s)

      {:ipse, ^pid, {:approval, ref, name, args}} ->
        if s.exit do
          Ipse.Session.approve(s.pid, ref, false)
          client_loop(s)
        else
          IO.puts(
            :stderr,
            "\nWaiting for approval: #{name}\nAllow #{name}?\n#{Jason.encode!(args, pretty: true)}\nType y to allow, anything else to deny."
          )

          client_loop(%{s | approval: ref})
        end

      {:ipse, ^pid, {:error, error}} ->
        IO.puts(:stderr, "\nError: #{error}")
        client_loop(s)

      {:ipse, ^pid, {:done, status}} when s.cancelling and status != :cancelled ->
        client_loop(s)

      {:ipse, ^pid, {:done, status}} ->
        IO.puts("")

        IO.puts(
          :stderr,
          case status do
            :cancelled ->
              "Cancelled. Started effects may have occurred; inspect the workspace before retrying."

            :error ->
              "Finished with an error."

            _ ->
              "Finished."
          end
        )

        cond do
          not s.interactive ->
            if status == :error, do: 1, else: 0

          status == :error ->
            if s.queued != [],
              do:
                IO.puts(
                  :stderr,
                  "Queued input was discarded after the error. Review the failure and send it again."
                )

            if s.exit,
              do: 1,
              else: client_loop(%{s | busy: false, cancelling: false, approval: nil, queued: []})

          s.queued != [] ->
            [next | rest] = s.queued
            Ipse.Session.prompt(s.pid, next)
            client_loop(%{s | busy: true, cancelling: false, approval: nil, queued: rest})

          s.exit ->
            0

          true ->
            client_loop(%{s | busy: false, cancelling: false, approval: nil, queued: []})
        end

      {:ipse, _, _} ->
        client_loop(s)

      {:DOWN, ref, _, _, _reason} when ref == s.ref ->
        IO.puts(
          :stderr,
          "Session stopped unexpectedly. Resume the saved session to inspect its history."
        )

        1
    end
  end

  defp config(opts, interactive) do
    name = opts[:provider] || System.get_env("IPSE_PROVIDER") || "chatgpt"

    provider =
      %{
        "chatgpt" => :chatgpt,
        "openai" => :openai,
        "ollama" => :ollama,
        "anthropic" => :anthropic,
        "demo" => :demo
      }[name]

    model =
      opts[:model] || System.get_env("IPSE_MODEL") ||
        %{
          chatgpt: "gpt-6.1-sol",
          openai: "gpt-6.1-sol",
          ollama: "qwen3:8b",
          anthropic: "claude-sonnet-4-5",
          demo: "scripted"
        }[provider]

    sandbox_name = opts[:sandbox] || "off"
    sandbox = %{"off" => :off, "native" => :native}[sandbox_name]

    cond do
      provider == nil ->
        {:error, "Unknown provider: #{name}"}

      sandbox == nil ->
        {:error, "Unknown sandbox mode: #{sandbox_name}; choose off or native"}

      opts[:max_steps] && opts[:max_steps] < 1 ->
        {:error, "--max-steps must be positive"}

      opts[:context_bytes] && opts[:context_bytes] < 8192 ->
        {:error, "--context-bytes must be at least 8192"}

      provider == :chatgpt && opts[:base_url] ->
        {:error, "Subscription credentials only go to the official OpenAI endpoint."}

      true ->
        with {:ok, servers} <- Ipse.MCP.Config.load(opts[:mcp_config]),
             {:ok, _policy} <- Ipse.Sandbox.resolve(sandbox, opts[:cwd] || default_cwd()),
             {:ok, _key} <- credential(provider) do
          {:ok,
           %{
             provider: provider,
             model: model,
             auth_dir: auth_dir(),
             home: home(),
             sandbox: sandbox,
             base_url: opts[:base_url],
             max_steps: opts[:max_steps] || 30,
             context_bytes: opts[:context_bytes] || 400_000,
             compact: opts[:compact] != false,
             mcp_servers: servers,
             subagents: opts[:subagents] == true,
             approval: if(opts[:yes], do: :allow, else: if(interactive, do: :ask, else: :deny))
           }}
        end
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
      with {:ok, [%{"metadata" => meta} | _]} <-
             Ipse.Journal.load(state_dir(opts), opts[:resume]) do
        {:ok,
         opts
         |> Keyword.put_new(:cwd, meta["cwd"])
         |> Keyword.put_new(:provider, meta["provider"])
         |> Keyword.put_new(:model, meta["model"])
         |> Keyword.put_new(:sandbox, Map.get(meta, "sandbox", "off"))
         |> Keyword.put_new(:subagents, Map.get(meta, "subagents", false))}
      else
        _ -> {:error, "Session could not be loaded."}
      end
    else
      {:ok, opts}
    end
  end

  defp state_dir(opts), do: opts[:state_dir] || Path.join(home(), "sessions")
  defp auth_dir, do: Path.join(home(), "auth")
  defp default_cwd, do: System.get_env("IPSE_WORKSPACE") || File.cwd!()
  defp home, do: System.get_env("IPSE_HOME") || Path.expand("~/.ipse")
  defp print_skills(cwd), do: IO.puts(Ipse.Skills.catalog(Ipse.Skills.discover(cwd)))

  defp print_context(manifest), do: IO.puts(Jason.encode!(manifest, pretty: true))
  defp preview(args), do: args |> Jason.encode!() |> String.slice(0, 600)
  defp report(:ok), do: 0

  defp report({:error, reason}),
    do:
      (
        IO.puts(:stderr, format_error(reason))
        1
      )

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
