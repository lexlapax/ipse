defmodule Ipse.CLI do
  @moduledoc "Owning terminal client for the Ipse session API."
  alias Ipse.CLI.Terminal

  @deferred_display ~w(status compacted context_refreshed subagent text presentation extension_result tool_output tool tool_result skill)a

  @help """
  Ipse 0.1 — a general-purpose local AI agent

  ipse login                      Continue with ChatGPT
  ipse status                     Show subscription sign-in status
  ipse logout                     Sign out of ChatGPT
  ipse chat [options]              Interactive conversation
  ipse run [options] "task"         Run one task
  ipse demo                        Scripted demo in a temporary directory
  ipse sessions [--json]           List saved sessions
  ipse skills [--cwd PATH]         List available skills
  ipse config [options]            Show effective non-secret configuration
  ipse extension import PATH       Copy a local inert extension artifact
  ipse extension inspect DIGEST    Verify an installed artifact without executing it
  ipse extension list              List inert built-in extension descriptors
  ipse extension check --fixture PATH  Exercise selected extensions with synthetic inputs
  ipse research --resume ID        Export a saved session's evidence ledger locally
  ipse result OUTPUT_ID --resume ID  Read a complete saved extension result locally
  ipse diagnose --resume ID        Inspect content-free saved context measurements
  ipse budget --resume ID          Inspect saved shared admission reservations
  ipse handoff --resume ID --note TEXT  Export an explicit recovery note locally

  --provider chatgpt|openai|ollama|anthropic|demo  (default: chatgpt)
  --model NAME                         Override the provider default
  --cwd PATH                           Workspace (default: current directory)
  --handoff PATH                       Fresh chat only: import reviewed historical recovery context
  --resume ID                          Resume a saved session
  --yes                                Allow mutations, shell, configured MCP, and enabled delegation
  --base-url URL                       API endpoint root (API/Ollama only)
  --state-dir PATH                     Session directory
  --json                               sessions only: JSON array of id/provider/model/cwd
  --note TEXT                          handoff only: operator-written continuation note
  --max-steps N                        Model calls per turn (default: 30)
  --max-output-tokens N                Per-request provider cap (API/Ollama only; no aggregate budget)
  --context-bytes N                    Context byte ceiling (default: 400000)
  --no-compact                         Stop at the ceiling without automatic reduction
  --sandbox off|native                 Shell OS policy (default: off)
  --mcp-config PATH                    Explicit stdio/HTTP servers and capability allowlists
  --subagents                          Enable bounded local delegation with parent approvals
  --subagent-concurrency 1|2            Permit two parallel local children (requires --subagents)
  --config PATH                        Explicit operator JSON configuration
  --trust-project-config               Authorize scoped project settings for this run
  --no-project-config                  Ignore project/directory configuration
  --timeout-ms N                       Provider request timeout (1000..600000)
  --profile ID                         Select an operator-configured main profile
  --extension INSTANCE                 Activate a configured temporary extension instance
  --no-extensions                      Disable configured extension instances
  --fixture PATH                       Synthetic inputs for extension check
  --keep-fixture                       Retain its private scratch state and journals
  --developer-trace                    Sample synthetic Session dispatcher calls
  --trace-ms N                         Capture deadline, 1..5000 ms (default 1000)
  --trace-events N                     Sample limit, 1..128 (default 32)
  --observability off|local|export      Operator diagnostic capture policy (default off)

  Chat asks before writes, shell, MCP, and delegation. Headless run denies them without --yes.
  Shell execution uses your user permissions unless --sandbox native is selected.
  Native enforcement fails closed when unavailable; approvals remain required.
  Chat commands: /help /skills /session /info /diagnostics /observability off /events off /context /context refresh /ext [NAME JSON] /result JSON /cancel /exit.
  Invoke skills with $name.
  EOF finishes accepted work; errors and /cancel clear queued input.
  """

  def main(args) do
    Application.ensure_all_started(:ipse)
    code = run(args)
    if code != 0, do: System.halt(code)
  rescue
    e in [ArgumentError, File.Error] ->
      Terminal.puts(:stderr, "Error: #{Exception.message(e)}")
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
          help: :boolean,
          demo: :boolean
        ],
        aliases: [h: :help, y: :yes]
      )

    cond do
      invalid != [] ->
        Terminal.puts(:stderr, "Unknown options: #{inspect(invalid)}")
        1

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
        Terminal.puts(@help)
        0

      true ->
        dispatch(rest, opts)
    end
  end

  defp dispatch(["login"], _opts), do: report(Ipse.Auth.login(auth_dir()))

  defp dispatch(["budget"], opts) do
    if opts[:resume] do
      case Ipse.Budget.saved(state_dir(opts), opts[:resume]) do
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
        Terminal.puts(inspect(status))
        0

      {:error, error} ->
        Terminal.puts(:stderr, to_string(error))
        1
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
    case Ipse.Config.resolve(opts[:cwd] || default_cwd(), home(), opts) do
      {:ok, effective} ->
        Terminal.puts(Jason.encode!(Ipse.Config.manifest(effective), pretty: true))
        0

      {:error, reason} ->
        report({:error, reason})
    end
  end

  defp dispatch(["extension", "list"], _opts) do
    Terminal.puts(Jason.encode!(Ipse.Extensions.Registry.builtins(), pretty: true))
    0
  end

  defp dispatch(["extension", "import", source], _opts) do
    extension_artifact(
      Ipse.Extensions.Store.import(source, Path.join(home(), "extensions/artifacts"))
    )
  end

  defp dispatch(["extension", "inspect", digest], _opts) do
    extension_artifact(
      Ipse.Extensions.Registry.lookup(Path.join(home(), "extensions/artifacts"), digest)
    )
  end

  defp dispatch(["extension", "check"], opts) do
    allowed =
      ~w(config cwd trust_project_config project_config extension extensions yes sandbox observability fixture keep_fixture developer_trace trace_ms trace_events json)a

    with true <- is_binary(opts[:fixture]) and Enum.all?(Keyword.keys(opts), &(&1 in allowed)),
         {:ok, _} <- Ipse.DeveloperTrace.policy(opts),
         {:ok, fixture, digest} <- Ipse.Extensions.Conformance.read(opts[:fixture]),
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

      case Ipse.Extensions.Conformance.run(effective.extensions, home(), fixture, check_opts) do
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
    case Ipse.Extensions.ResultReader.saved(state_dir(opts), opts[:resume], output_id) do
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
    case Ipse.Research.load(state_dir(opts), opts[:resume]) do
      {:ok, ledger} ->
        Terminal.puts(Jason.encode!(ledger, pretty: true))
        0

      {:error, reason} ->
        report({:error, reason})
    end
  end

  defp dispatch(["diagnose"], opts) do
    case Ipse.Diagnostics.saved(state_dir(opts), opts[:resume]) do
      {:ok, result} ->
        Terminal.puts(Jason.encode!(result, pretty: true))
        0

      {:error, reason} ->
        report({:error, reason})
    end
  end

  defp dispatch(["handoff"], opts) do
    case Ipse.Handoff.export(state_dir(opts), opts[:resume], opts[:note]) do
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
        Terminal.puts(@help)
        1
      )

  defp handoff_options(opts) do
    if Keyword.has_key?(opts, :handoff) do
      case Ipse.Handoff.read(opts[:handoff]) do
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

      Terminal.puts(:stderr, Ipse.Sandbox.describe(config.sandbox))

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
          Jason.encode!(Ipse.Extensions.Registry.manifests(config), pretty: true)
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
        do: Terminal.puts(:stderr, Ipse.Handoff.notice(handoff_opts[:handoff]))

      client = self()

      reader = if interactive, do: spawn(fn -> read_input(client) end), else: nil

      if interactive,
        do: Terminal.puts("Type a task, $review, or /help. Use /cancel while work is running.")

      result =
        try do
          if prompt, do: dispatch_prompt(pid, prompt)

          client_loop(%{
            pid: pid,
            ref: ref,
            interactive: interactive,
            busy: prompt != nil,
            cancelling: false,
            approval: nil,
            approval_token: nil,
            approval_display: nil,
            approval_context: nil,
            approval_redraw: true,
            deferred_display: [],
            deferred_bytes: 0,
            deferred_dropped: 0,
            question: nil,
            question_token: nil,
            question_answers: %{},
            queued: [],
            exit: false,
            cwd: info.cwd
          })
        catch
          :exit, _ ->
            Terminal.puts(
              :stderr,
              "Session request acknowledgment is unconfirmed; it may have taken effect and was not retried. Inspect saved receipts and the workspace before continuing."
            )

            1
        after
          if reader && Process.alive?(reader), do: Process.exit(reader, :kill)
        end

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

  defp read_input(client) do
    case IO.gets("you> ") do
      :eof ->
        send(client, {:input, :eof})

      {:error, _} ->
        send(client, {:input, :eof})

      text ->
        text = if String.valid?(text), do: String.trim(text), else: text
        send(client, {:input, text})
        read_input(client)
    end
  end

  defp client_loop(s) do
    pid = s.pid

    if s.approval != nil and s.approval_redraw do
      {name, args, context} = s.approval_display

      if context,
        do:
          Terminal.puts(:stderr, "External MCP target:\n" <> Jason.encode!(context, pretty: true))

      Terminal.puts(
        :stderr,
        "\nWaiting for approval: #{name}\nAllow #{name}?\n#{Jason.encode!(args, pretty: true)}\nType allow #{s.approval_token} to allow, n to deny."
      )
    end

    s = %{s | approval_redraw: true}
    {event, s} = next_client_event(s)

    case event do
      {:ipse, ^pid, event}
      when s.approval != nil and is_tuple(event) and elem(event, 0) in @deferred_display ->
        bytes = :erlang.external_size(event)

        next =
          if length(s.deferred_display) < 64 and s.deferred_bytes + bytes <= 65_536 do
            %{
              s
              | deferred_display: [event | s.deferred_display],
                deferred_bytes: s.deferred_bytes + bytes
            }
          else
            %{s | deferred_dropped: s.deferred_dropped + 1}
          end

        client_loop(%{next | approval_redraw: false})

      {:input, :eof} ->
        if s.question, do: Ipse.Session.cancel(s.pid)

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
            Terminal.puts(:stderr, "Cancellation already requested.")
            client_loop(s)

          s.busy ->
            Terminal.puts(:stderr, "Cancelling active work…")
            Ipse.Session.cancel(s.pid)

            client_loop(%{
              s
              | cancelling: true,
                approval: nil,
                question: nil,
                question_answers: %{},
                queued: []
            })

          true ->
            Terminal.puts(:stderr, "No active work to cancel.")
            client_loop(s)
        end

      {:input, "/help"} ->
        Terminal.puts(@help)
        client_loop(s)

      {:input, "/skills"} ->
        Terminal.puts(Ipse.Skills.catalog(Ipse.Session.info(s.pid).context["skills"]))
        client_loop(s)

      {:input, "/session"} ->
        Terminal.puts(inspect(Ipse.Session.info(s.pid)))
        client_loop(s)

      {:input, "/info"} ->
        Terminal.puts(Ipse.RuntimeInfo.format(Ipse.Session.info(s.pid).runtime))
        client_loop(s)

      {:input, "/diagnostics"} ->
        Terminal.puts(Jason.encode!(Ipse.Session.diagnostics(s.pid), pretty: true))
        client_loop(s)

      {:input, "/observability off"} ->
        :ok = Ipse.Session.stop_observability(s.pid)

        Terminal.puts(
          "Diagnostic capture stopped; recovery journaling and usage accounting remain active."
        )

        client_loop(s)

      {:input, "/events off"} ->
        case Ipse.Session.stop_feeds(s.pid) do
          :ok ->
            Terminal.puts("Live event feeds stopped; inspect /diagnostics for coverage.")

          _ ->
            Terminal.puts(
              "Live event feeds stopped with unconfirmed cleanup; inspect /diagnostics."
            )
        end

        client_loop(s)

      {:input, "/result " <> json} ->
        with {:ok, request} <- Ipse.JSON.decode_bounded(json),
             {:ok, view} <- Ipse.Session.read_saved_result(s.pid, request) do
          Terminal.puts(Jason.encode!(view))
        else
          _ -> Terminal.puts(:stderr, "Saved result view unavailable or invalid.")
        end

        client_loop(s)

      {:input, "/ext"} ->
        Terminal.puts(Jason.encode!(Ipse.Session.exports(s.pid), pretty: true))
        client_loop(s)

      {:input, "/ext " <> input} ->
        case String.split(input, ~r/\s+/, parts: 2, trim: true) do
          [name, json] ->
            with {:ok, arguments} <- Ipse.JSON.decode_bounded(json),
                 true <- is_map(arguments),
                 :ok <- Ipse.Session.invoke_export(s.pid, :command, name, arguments) do
              client_loop(%{s | busy: true})
            else
              _ ->
                Terminal.puts(
                  :stderr,
                  "Extension command unavailable, invalid, or busy. Use /ext to inspect names and schemas."
                )

                client_loop(s)
            end

          _ ->
            Terminal.puts(
              :stderr,
              "Use /ext NAME JSON_OBJECT; use {} for an empty argument object."
            )

            client_loop(s)
        end

      {:input, "/context"} ->
        print_context(Ipse.Session.info(s.pid).context)
        client_loop(s)

      {:input, "/context refresh"} ->
        case Ipse.Session.refresh_context(s.pid) do
          :ok ->
            Terminal.puts(:stderr, "Refreshing workspace instructions…")
            client_loop(%{s | busy: true})

          {:error, :busy} ->
            Terminal.puts(:stderr, "Finish or cancel active work before refreshing instructions.")
            client_loop(s)
        end

      {:input, ""} ->
        client_loop(s)

      {:input, _text} when s.cancelling ->
        Terminal.puts(
          :stderr,
          "Input received during cancellation was discarded. Send it again after cancellation finishes."
        )

        client_loop(s)

      {:input, text} when s.question != nil ->
        {id, arguments, remaining} = s.question
        [question | rest] = remaining

        case question_answer(question, s.question_token, text) do
          {:ok, answer} ->
            answers = Map.put(s.question_answers, question["id"], answer)

            if rest == [] do
              case Ipse.Session.answer(s.pid, id, answers) do
                :ok ->
                  client_loop(%{
                    s
                    | question: nil,
                      question_token: nil,
                      question_answers: %{},
                      busy: true
                  })

                {:error, reason} ->
                  Terminal.puts(:stderr, "Answer rejected: #{inspect(reason)}")
                  client_loop(s)
              end
            else
              token = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
              Terminal.puts(:stderr, question_prompt(hd(rest), token))

              client_loop(%{
                s
                | question: {id, arguments, rest},
                  question_token: token,
                  question_answers: answers
              })
            end

          {:error, :question_confirmation} ->
            Terminal.puts(
              :stderr,
              "Question confirmation does not match. " <>
                question_prompt(question, s.question_token)
            )

            client_loop(s)

          _ ->
            Terminal.puts(
              :stderr,
              "Invalid answer. " <> question_prompt(question, s.question_token)
            )

            client_loop(s)
        end

      {:input, text} when s.approval != nil ->
        confirmation = if String.valid?(text), do: String.downcase(text), else: ""

        cond do
          confirmation == "allow #{s.approval_token}" ->
            Ipse.Session.approve(s.pid, s.approval, true)
            client_loop(%{s | approval: nil, approval_token: nil})

          confirmation in ["n", "no", "deny"] ->
            Ipse.Session.approve(s.pid, s.approval, false)
            client_loop(%{s | approval: nil, approval_token: nil})

          true ->
            Terminal.puts(
              :stderr,
              "Confirmation does not match the pending proposal. Review its arguments and use its displayed allow code, or n to deny."
            )

            client_loop(s)
        end

      {:input, text} when s.busy ->
        if String.valid?(text) and length(s.queued) < 16 and
             byte_size(text) + Enum.sum(Enum.map(s.queued, &byte_size/1)) <= 1_048_576 do
          Terminal.puts(:stderr, "Queued for the next turn. /cancel interrupts current work.")
          client_loop(%{s | queued: s.queued ++ [text]})
        else
          Terminal.puts(
            :stderr,
            "Input refused: queued tasks are limited to 16 entries and 1 MiB of UTF-8 text. Send it again after work finishes."
          )

          client_loop(s)
        end

      {:input, text} ->
        dispatch_prompt(s.pid, text)
        client_loop(%{s | busy: true})

      {:ipse, ^pid, {:status, :compacting}} ->
        unless s.cancelling,
          do: Terminal.puts(:stderr, "Compacting context with the selected provider…")

        client_loop(s)

      {:ipse, ^pid, {:compacted, before_bytes, after_bytes}} ->
        Terminal.puts(
          :stderr,
          "Context compacted: #{before_bytes} → #{after_bytes} bytes. Original journal retained."
        )

        client_loop(s)

      {:ipse, ^pid, {:context_refreshed, manifest}} ->
        print_context(manifest)
        client_loop(s)

      {:ipse, ^pid, {:status, _status}} ->
        unless s.cancelling, do: Terminal.puts(:stderr, "Running…")
        client_loop(s)

      {:ipse, ^pid, {:subagent, id, status}} ->
        unless s.cancelling, do: Terminal.puts(:stderr, "Subagent #{id}: #{status}")
        client_loop(s)

      {:ipse, ^pid, {:text, delta}} ->
        Terminal.write(delta)
        client_loop(s)

      {:ipse, ^pid, {:presentation, text}} ->
        Terminal.puts("\n" <> text)
        client_loop(s)

      {:ipse, ^pid, {:extension_result, display}} ->
        value = display["delivery"] || display["value"]
        Terminal.puts("\nExtension #{display["name"]}: #{Jason.encode!(value)}")
        client_loop(s)

      {:ipse, ^pid, {:tool_output, delta}} ->
        Terminal.write(:stderr, delta)
        client_loop(s)

      {:ipse, ^pid, {:tool, name, args}} ->
        Terminal.puts(:stderr, "\n→ #{name} #{preview(args)}")
        client_loop(s)

      {:ipse, ^pid, {:tool_result, name, text}} ->
        Terminal.puts(:stderr, "← #{name}: #{String.slice(text, 0, 800)}")
        client_loop(s)

      {:ipse, ^pid, {:skill, name}} ->
        Terminal.puts(:stderr, "Skill: #{name}")
        client_loop(s)

      {:ipse, ^pid, {:mcp_approval_context, manifest}} ->
        Terminal.puts(:stderr, "External MCP target:\n" <> Jason.encode!(manifest, pretty: true))
        client_loop(%{s | approval_context: manifest})

      {:ipse, ^pid, {:question, id, arguments}} ->
        if s.exit do
          Ipse.Session.cancel(s.pid)
          client_loop(%{s | question: nil, question_answers: %{}})
        else
          Terminal.puts(:stderr, "Waiting for operator clarification (not action approval):")
          token = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
          Terminal.puts(:stderr, question_prompt(hd(arguments["questions"]), token))

          client_loop(%{
            s
            | busy: true,
              question: {id, arguments, arguments["questions"]},
              question_token: token,
              question_answers: %{}
          })
        end

      {:ipse, ^pid, {:approval, ref, name, args}} ->
        if s.exit do
          Ipse.Session.approve(s.pid, ref, false)
          client_loop(s)
        else
          client_loop(%{
            s
            | approval: ref,
              approval_token: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
              approval_display: {name, args, s.approval_context},
              approval_context: nil
          })
        end

      {:ipse, ^pid, {:error, error}} ->
        Terminal.puts(:stderr, "\nError: #{error}")
        client_loop(s)

      {:ipse, ^pid, {:done, status}} when s.cancelling and status != :cancelled ->
        client_loop(s)

      {:ipse, ^pid, {:done, status}} ->
        Terminal.puts("")

        Terminal.puts(
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
                Terminal.puts(
                  :stderr,
                  "Queued input was discarded after the error. Review the failure and send it again."
                )

            if s.exit,
              do: 1,
              else:
                client_loop(%{
                  s
                  | busy: false,
                    cancelling: false,
                    approval: nil,
                    question: nil,
                    question_answers: %{},
                    queued: []
                })

          s.queued != [] ->
            [next | rest] = s.queued
            dispatch_prompt(s.pid, next)
            client_loop(%{s | busy: true, cancelling: false, approval: nil, queued: rest})

          s.exit ->
            0

          true ->
            client_loop(%{
              s
              | busy: false,
                cancelling: false,
                approval: nil,
                question: nil,
                question_answers: %{},
                queued: []
            })
        end

      {:ipse, _, _} ->
        client_loop(s)

      {:DOWN, ref, _, _, reason} when ref == s.ref ->
        Terminal.puts(
          :stderr,
          if(reason == :journal_limit_reached,
            do:
              "Session stopped at its journal resource limit. Inspect preserved history with ipse diagnose or handoff; this sealed journal cannot resume.",
            else: "Session stopped unexpectedly. Resume the saved session to inspect its history."
          )
        )

        1

      _ ->
        client_loop(s)
    end
  end

  defp question_prompt(question, token),
    do: Ipse.Questions.render(question) <> "\nReply with answer #{token} VALUE."

  defp question_answer(question, token, text) do
    prefix = "answer #{token} "

    if String.valid?(text) and String.starts_with?(text, prefix) do
      Ipse.Questions.parse_line(
        question,
        binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix))
      )
    else
      {:error, :question_confirmation}
    end
  end

  defp dispatch_prompt(pid, text) do
    case Ipse.Session.prompt(pid, text) do
      :ok ->
        :ok

      {:error, :skill_catalog_changed} ->
        :ok

      {:error, reason} ->
        message =
          case reason do
            :invalid_prompt ->
              "Prompt must be valid UTF-8 text."

            :prompt_too_large ->
              "Prompt exceeds 1 MiB after skill expansion. Use a smaller task and load resources explicitly."

            _ ->
              "Task was not accepted. Inspect session status and configuration."
          end

        send(self(), {:ipse, pid, {:error, message}})
        send(self(), {:ipse, pid, {:done, :error}})
        :error
    end
  end

  defp next_client_event(%{approval: nil, deferred_display: [_ | _]} = s) do
    s = release_display(s)
    {event, remaining} = List.pop_at(s.deferred_display, -1)

    {{:ipse, s.pid, event},
     %{
       s
       | deferred_display: remaining,
         deferred_bytes: s.deferred_bytes - :erlang.external_size(event)
     }}
  end

  defp next_client_event(s) do
    s = if is_nil(s.approval), do: release_display(s), else: s

    receive do
      event ->
        {event, s}
    end
  end

  defp release_display(s) do
    if s.deferred_dropped > 0 do
      Terminal.puts(
        :stderr,
        "Deferred display overflow: #{s.deferred_dropped} events omitted while approval was pending. Saved records are unchanged."
      )
    end

    %{s | deferred_dropped: 0}
  end

  defp config(opts, interactive) do
    workspace = opts[:cwd] || default_cwd()
    home = home()

    client = %{
      workspace: workspace,
      home: home,
      auth_dir: Path.join(home, "auth"),
      operator_home: Ipse.Skills.operator_home(),
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
  defp print_skills(cwd), do: Terminal.puts(Ipse.Skills.catalog(Ipse.Skills.discover(cwd)))

  defp print_context(manifest), do: Terminal.puts(Jason.encode!(manifest, pretty: true))
  defp preview(args), do: args |> Jason.encode!() |> String.slice(0, 600)
  defp report(:ok), do: 0

  defp report({:error, reason}),
    do:
      (
        Terminal.puts(:stderr, format_error(reason))
        1
      )

  defp format_error(:invalid_handoff),
    do:
      "Invalid handoff: expected one closed version-1 UTF-8 artifact of at most 16 KiB with consistent unknown-effect provenance."

  defp format_error(:invalid_handoff_record),
    do:
      "Invalid committed handoff record; refusing recovery. Preserve the original journal for inspection."

  defp format_error(:resume_configuration_mismatch),
    do:
      "Saved session configuration differs. Restore its provider, model, endpoint (--base-url), profiles and extensions, or start a fresh session."

  defp format_error(:journal_limit_reached),
    do:
      "Journal resource limit reached. History was preserved; inspect it and use an explicit fresh-session handoff. Oversized legacy files require bounded source-page inspection."

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
