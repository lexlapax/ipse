defmodule Runespell.CLI do
  @moduledoc "Terminal client for the Runespell session API."

  @help """
  Runespell 0.1 — an Elixir coding agent

  runespell login                      Continue with ChatGPT
  runespell status                     Show subscription sign-in status
  runespell logout                     Sign out of ChatGPT
  runespell chat [options]              Interactive conversation
  runespell run [options] "task"         Run one task
  runespell demo                        Scripted demo in a temporary directory
  runespell sessions                    List saved sessions
  runespell skills [--cwd PATH]         List available skills

  --provider chatgpt|openai|ollama|anthropic|demo  (default: chatgpt)
  --model NAME                         Override the provider default
  --cwd PATH                           Workspace (default: current directory)
  --resume ID                          Resume a saved session
  --yes                                Allow writes and trusted local shell execution
  --base-url URL                       API endpoint root (API/Ollama only)
  --state-dir PATH                     Session directory
  --max-steps N                        Model calls per turn (default: 30)

  Chat asks before writes and shell commands. Headless run denies them without --yes.
  Shell execution has your user permissions; this prototype has no OS sandbox.
  Chat commands: /help /skills /session /cancel /exit. Invoke skills with $name.
  """

  def main(args) do
    Application.ensure_all_started(:runespell)
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

  defp dispatch(["login"], _opts), do: report(Runespell.Auth.login(auth_dir()))
  defp dispatch(["logout"], _opts), do: report(Runespell.Auth.logout(auth_dir()))

  defp dispatch(["status"], _opts) do
    case Runespell.Auth.status(auth_dir()) do
      {:ok, status} ->
        IO.puts(inspect(status))
        0

      {:error, error} ->
        IO.puts(:stderr, to_string(error))
        1
    end
  end

  defp dispatch(["sessions"], opts) do
    for %{"id" => id, "metadata" => meta} <- Runespell.Journal.list(state_dir(opts)) do
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
          "runespell-demo-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
        )

    File.mkdir_p!(cwd)

    IO.puts(
      "Scripted demo workspace: #{cwd}\nThis demo creates runespell-demo.txt and runs printf."
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
             Runespell.Sessions,
             {Runespell.Session,
              config: config,
              cwd: opts[:cwd] || default_cwd(),
              state_dir: state_dir(opts),
              id: opts[:resume],
              subscriber: self()}
           ) do
      ref = Process.monitor(pid)
      info = Runespell.Session.info(pid)

      IO.puts(
        :stderr,
        "Runespell · #{config.provider}/#{config.model}\nSession: #{info.id}\nWorkspace: #{info.cwd}"
      )

      if config.approval == :allow,
        do: IO.puts(:stderr, "Trusted local execution enabled (--yes).")

      client = self()
      reader = if interactive, do: spawn(fn -> read_input(client) end), else: nil
      if prompt, do: Runespell.Session.prompt(pid, prompt)

      if interactive,
        do: IO.puts("Type a task, $review, or /help. Use /cancel while work is running.")

      result =
        client_loop(%{
          pid: pid,
          ref: ref,
          interactive: interactive,
          busy: prompt != nil,
          approval: nil,
          queued: [],
          exit: false,
          cwd: info.cwd
        })

      if reader && Process.alive?(reader), do: Process.exit(reader, :kill)
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Runespell.Sessions, pid)
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
          if s.approval, do: Runespell.Session.approve(s.pid, s.approval, false)
          client_loop(%{s | exit: true, approval: nil})
        else
          0
        end

      {:input, "/exit"} ->
        Runespell.Session.cancel(s.pid)
        0

      {:input, "/cancel"} ->
        Runespell.Session.cancel(s.pid)
        client_loop(%{s | approval: nil, queued: []})

      {:input, "/help"} ->
        IO.puts(@help)
        client_loop(s)

      {:input, "/skills"} ->
        print_skills(s.cwd)
        client_loop(s)

      {:input, "/session"} ->
        IO.puts(inspect(Runespell.Session.info(s.pid)))
        client_loop(s)

      {:input, ""} ->
        client_loop(s)

      {:input, text} when s.approval != nil ->
        Runespell.Session.approve(s.pid, s.approval, String.downcase(text) in ["y", "yes"])
        client_loop(%{s | approval: nil})

      {:input, text} when s.busy ->
        IO.puts(:stderr, "Queued for the next turn. /cancel interrupts current work.")
        client_loop(%{s | queued: s.queued ++ [text]})

      {:input, text} ->
        Runespell.Session.prompt(s.pid, text)
        client_loop(%{s | busy: true})

      {:runespell, ^pid, {:text, delta}} ->
        IO.write(delta)
        client_loop(s)

      {:runespell, ^pid, {:tool_output, delta}} ->
        IO.write(:stderr, delta)
        client_loop(s)

      {:runespell, ^pid, {:tool, name, args}} ->
        IO.puts(:stderr, "\n→ #{name} #{preview(args)}")
        client_loop(s)

      {:runespell, ^pid, {:tool_result, name, text}} ->
        IO.puts(:stderr, "← #{name}: #{String.slice(text, 0, 800)}")
        client_loop(s)

      {:runespell, ^pid, {:skill, name}} ->
        IO.puts(:stderr, "Skill: #{name}")
        client_loop(s)

      {:runespell, ^pid, {:approval, ref, name, args}} ->
        if s.exit do
          Runespell.Session.approve(s.pid, ref, false)
          client_loop(s)
        else
          IO.puts(
            :stderr,
            "\nAllow #{name}?\n#{Jason.encode!(args, pretty: true)}\nType y to allow, anything else to deny."
          )

          client_loop(%{s | approval: ref})
        end

      {:runespell, ^pid, {:error, error}} ->
        IO.puts(:stderr, "\nError: #{error}")
        client_loop(s)

      {:runespell, ^pid, {:done, status}} ->
        IO.puts("")

        cond do
          not s.interactive or s.exit ->
            if status == :error, do: 1, else: 0

          s.queued != [] ->
            [next | rest] = s.queued
            Runespell.Session.prompt(s.pid, next)
            client_loop(%{s | busy: true, approval: nil, queued: rest})

          true ->
            client_loop(%{s | busy: false, approval: nil})
        end

      {:runespell, _, _} ->
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
    name = opts[:provider] || System.get_env("RUNESPELL_PROVIDER") || "chatgpt"

    provider =
      %{
        "chatgpt" => :chatgpt,
        "openai" => :openai,
        "ollama" => :ollama,
        "anthropic" => :anthropic,
        "demo" => :demo
      }[name]

    model =
      opts[:model] || System.get_env("RUNESPELL_MODEL") ||
        %{
          chatgpt: "gpt-6.1-sol",
          openai: "gpt-6.1-sol",
          ollama: "qwen3:8b",
          anthropic: "claude-sonnet-4-5",
          demo: "scripted"
        }[provider]

    cond do
      provider == nil ->
        {:error, "Unknown provider: #{name}"}

      opts[:max_steps] && opts[:max_steps] < 1 ->
        {:error, "--max-steps must be positive"}

      provider == :chatgpt && opts[:base_url] ->
        {:error, "Subscription credentials only go to the official OpenAI endpoint."}

      true ->
        with {:ok, _key} <- credential(provider) do
          {:ok,
           %{
             provider: provider,
             model: model,
             auth_dir: auth_dir(),
             base_url: opts[:base_url],
             max_steps: opts[:max_steps] || 30,
             approval: if(opts[:yes], do: :allow, else: if(interactive, do: :ask, else: :deny))
           }}
        end
    end
  end

  defp credential(:chatgpt), do: Runespell.Auth.token(auth_dir())
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
             Runespell.Journal.load(state_dir(opts), opts[:resume]) do
        {:ok,
         opts
         |> Keyword.put_new(:cwd, meta["cwd"])
         |> Keyword.put_new(:provider, meta["provider"])
         |> Keyword.put_new(:model, meta["model"])}
      else
        _ -> {:error, "Session could not be loaded."}
      end
    else
      {:ok, opts}
    end
  end

  defp state_dir(opts), do: opts[:state_dir] || Path.join(home(), "sessions")
  defp auth_dir, do: Path.join(home(), "auth")
  defp default_cwd, do: System.get_env("RUNESPELL_WORKSPACE") || File.cwd!()
  defp home, do: System.get_env("RUNESPELL_HOME") || Path.expand("~/.runespell")
  defp print_skills(cwd), do: IO.puts(Runespell.Skills.catalog(Runespell.Skills.discover(cwd)))
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
