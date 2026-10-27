defmodule Ipse.CLI.Terminal do
  @moduledoc "Interactive terminal client and escaped rendering of Session events."

  @controls ~r/[\x{0000}-\x{0008}\x{000b}-\x{001f}\x{007f}-\x{009f}\x{034f}\p{Cf}\p{Zl}\p{Zp}]/u

  def puts(text), do: puts(:stdio, text)
  def puts(device, text), do: output(device, [escape(text), "\n"])
  def write(text), do: write(:stdio, text)
  def write(device, text), do: output(device, escape(text))

  def escape(text) when is_binary(text), do: escaped(text, []) |> IO.iodata_to_binary()

  defp output(device, bytes) do
    device =
      case device do
        :stdio -> :standard_io
        :stderr -> :standard_error
        _ -> device
      end

    case :io.getopts(device) do
      options when is_list(options) ->
        if options[:encoding] == :latin1,
          do: IO.binwrite(device, bytes),
          else: IO.write(device, bytes)

      _ ->
        IO.write(device, bytes)
    end
  end

  defp escaped(text, acc) do
    case :unicode.characters_to_binary(text) do
      valid when is_binary(valid) ->
        Enum.reverse([escape_valid(valid) | acc])

      {_status, valid, <<byte, rest::binary>>} ->
        escaped(rest, [[escape_valid(valid), "\\x", hex(byte, 2)] | acc])
    end
  end

  defp escape_valid(text) do
    Regex.replace(@controls, text, fn <<codepoint::utf8>> -> unicode_escape(codepoint) end)
  end

  defp unicode_escape(codepoint) when codepoint <= 0xFFFF,
    do: "\\u" <> hex(codepoint, 4)

  defp unicode_escape(codepoint) do
    offset = codepoint - 0x10000
    unicode_escape(0xD800 + div(offset, 1024)) <> unicode_escape(0xDC00 + rem(offset, 1024))
  end

  defp hex(value, width),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")

  @deferred_display ~w(status compacted context_refreshed subagent text presentation extension_result tool_output tool tool_result skill)a

  @help """
  Ipse VERSION — a general-purpose local AI agent

  ipse --version                  Show the application version
  ipse version [--json]           Show version or non-secret runtime build identity
  ipse login                      Continue with ChatGPT
  ipse login --provider xai_oauth  Grok device login (registered Ipse client required)
  ipse status                     Show subscription sign-in status as JSON
  ipse logout                     Sign out of ChatGPT
  ipse status --provider xai_oauth  Inspect Grok subscription sign-in
  ipse logout --provider xai_oauth  Remove Grok subscription sign-in
  ipse chat [options]              Interactive conversation
  ipse run [options] "task"         Run one task
  ipse demo                        Scripted demo in a temporary directory
  ipse sessions [--json]           List saved sessions
  ipse skills [--cwd PATH]         List available skills
  ipse config [options]            Show effective non-secret configuration
  ipse doctor [options] [--json]    Diagnose setup offline; --probe-provider opts into GET probes
  ipse setup [options]             Preview or confirm private provider/model defaults
  ipse extension import PATH       Copy a local inert extension artifact
  ipse extension inspect DIGEST    Verify an installed artifact without executing it
  ipse extension list              List inert built-in extension descriptors
  ipse extension check --fixture PATH  Exercise selected extensions with synthetic inputs
  ipse research --resume ID        Export a saved session's evidence ledger locally
  ipse result OUTPUT_ID --resume ID  Read a complete saved extension result locally
  ipse diagnose --resume ID        Inspect content-free saved context measurements
  ipse budget --resume ID          Inspect saved shared admission reservations
  ipse handoff --resume ID --note TEXT  Export an explicit recovery note locally

  --provider #{Enum.join(Ipse.Provider.Registry.ids(), "|")}  (default: #{Ipse.Provider.Registry.default_id()})
  --model NAME                         Override the provider default
  --cwd PATH                           Workspace (default: current directory)
  --handoff PATH                       Fresh chat only: import reviewed historical recovery context
  --resume ID                          Resume a saved session
  --yes                                Allow mutations, shell, configured MCP, and enabled delegation
  --base-url URL                       Explicit API/local endpoint (no subscription override)
  --upstream SLUG                      setup only: pinned OpenRouter upstream
  --data-collection deny|allow          setup only: OpenRouter policy (default deny)
  --state-dir PATH                     Session directory
  --json                               sessions: id/provider/model/cwd; version/doctor: structured facts
  --probe-provider                     doctor only: bounded GET reachability checks, no inference
  --write                              setup only: save an explicit provider/model configuration
  --replace                            setup only: back up and replace setup-owned settings
  --note TEXT                          handoff only: operator-written continuation note
  --max-steps N                        Model calls per turn (default: 30)
  --max-output-tokens N                Per-request cap (API/local/Grok subscription; no aggregate budget)
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
  --accept-edits                       Allow native workspace file edits in interactive chat
  Chat commands: /help /skills /session /info /diagnostics /permissions /permissions clear /observability off /events off /context /context refresh /ext [NAME JSON] /result JSON /cancel /exit.
  Invoke skills with $name.
  EOF finishes accepted work; errors and /cancel clear queued input.
  """

  defp client_loop(s, injected \\ nil) do
    s = if injected == nil, do: refresh_reader(s), else: s
    pid = s.pid

    if s.approval != nil and s.approval_redraw and s.input_mode != :native do
      {name, args, context} = s.approval_display

      if context,
        do: puts(:stderr, "External MCP target:\n" <> Jason.encode!(context, pretty: true))

      puts(
        :stderr,
        "\nWaiting for approval: #{name}\nAllow #{name}?\n#{Jason.encode!(args, pretty: true)}\nType allow #{s.approval_token} to allow once, n to deny." <>
          permission_choice(name, s.approval_token, s.cwd)
      )
    end

    s = %{s | approval_redraw: true}
    {event, s} = if injected == nil, do: next_client_event(s), else: {injected, s}

    case event do
      {:native_input, generation, request, text, witness} ->
        native_input(s, generation, request, text, witness)

      {:observed_prompt, text, ticket} ->
        cond do
          s.cancelling ->
            Ipse.Session.discard_input(s.pid, s.input_channel, ticket)

            puts(
              :stderr,
              "Input received during cancellation was discarded. Send it again after cancellation finishes."
            )

            client_loop(s)

          s.busy and length(s.queued) < 16 and
              queued_bytes(s.queued) + byte_size(text) <= 1_048_576 ->
            puts(:stderr, "Queued for the next turn. /cancel clears active and queued work.")
            client_loop(%{s | queued: s.queued ++ [{text, ticket}]})

          s.busy ->
            Ipse.Session.discard_input(s.pid, s.input_channel, ticket)

            puts(
              :stderr,
              "Input refused: queued tasks are limited to 16 entries and 1 MiB of UTF-8 text. Send it again after work finishes."
            )

            client_loop(s)

          true ->
            dispatch_prompt(s.pid, {text, ticket})
            client_loop(%{s | busy: true})
        end

      {:input_mode, _} ->
        client_loop(s)

      {:input_notice, reason} ->
        puts(
          :stderr,
          if(reason == :operator_input_too_large,
            do: "Native input exceeds 1 MiB. The entire line was refused; send a smaller prompt.",
            else: "Native input was not valid UTF-8. The entire line was refused; send it again."
          )
        )

        client_loop(s)

      {:input_failure, _reason} ->
        puts(
          :stderr,
          "The verified operator channel stopped or its cleanup could not be confirmed. Active work is being cancelled; inspect the saved session before resuming."
        )

        Ipse.Session.cancel(s.pid)
        1

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
            puts(:stderr, "Cancellation already requested.")
            client_loop(s)

          s.busy ->
            puts(:stderr, "Cancelling active work…")
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
            puts(:stderr, "No active work to cancel.")
            client_loop(s)
        end

      {:input, "/help"} ->
        help()
        client_loop(s)

      {:input, "/permissions"} ->
        puts(Jason.encode!(Ipse.Session.permissions(s.pid), pretty: true))
        client_loop(s)

      {:input, "/permissions clear"} ->
        :ok = Ipse.Session.clear_permissions(s.pid)

        puts(
          :stderr,
          "Session grants cleared. Already dispatched effects may finish; --yes authority is unchanged."
        )

        client_loop(s)

      {:input, "/skills"} ->
        puts(Ipse.Workspace.skill_catalog(Ipse.Session.info(s.pid).context["skills"]))
        client_loop(s)

      {:input, "/session"} ->
        puts(inspect(Ipse.Session.info(s.pid)))
        client_loop(s)

      {:input, "/info"} ->
        puts(Ipse.Session.Context.format_runtime(Ipse.Session.info(s.pid).runtime))
        client_loop(s)

      {:input, "/diagnostics"} ->
        puts(Jason.encode!(Ipse.Session.diagnostics(s.pid), pretty: true))
        client_loop(s)

      {:input, "/observability off"} ->
        :ok = Ipse.Session.stop_observability(s.pid)

        puts(
          "Diagnostic capture stopped; recovery journaling and usage accounting remain active."
        )

        client_loop(s)

      {:input, "/events off"} ->
        case Ipse.Session.stop_feeds(s.pid) do
          :ok ->
            puts("Live event feeds stopped; inspect /diagnostics for coverage.")

          _ ->
            puts("Live event feeds stopped with unconfirmed cleanup; inspect /diagnostics.")
        end

        client_loop(s)

      {:input, "/result " <> json} ->
        with {:ok, request} <- Ipse.JSON.decode_bounded(json),
             {:ok, view} <- Ipse.Session.read_saved_result(s.pid, request) do
          puts(Jason.encode!(view))
        else
          _ -> puts(:stderr, "Saved result view unavailable or invalid.")
        end

        client_loop(s)

      {:input, "/ext"} ->
        puts(Jason.encode!(Ipse.Session.exports(s.pid), pretty: true))
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
                puts(
                  :stderr,
                  "Extension command unavailable, invalid, or busy. Use /ext to inspect names and schemas."
                )

                client_loop(s)
            end

          _ ->
            puts(
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
            puts(:stderr, "Refreshing workspace instructions…")
            client_loop(%{s | busy: true})

          {:error, :busy} ->
            puts(:stderr, "Finish or cancel active work before refreshing instructions.")
            client_loop(s)
        end

      {:input, ""} ->
        client_loop(s)

      {:input, _text} when s.cancelling ->
        puts(
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
                  puts(:stderr, "Answer rejected: #{Ipse.CLI.Errors.format(reason)}")
                  client_loop(s)
              end
            else
              token = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
              puts(:stderr, question_prompt(hd(rest), token))

              client_loop(%{
                s
                | question: {id, arguments, rest},
                  question_token: token,
                  question_answers: answers
              })
            end

          {:error, :question_confirmation} ->
            puts(
              :stderr,
              "Question confirmation does not match. " <>
                question_prompt(question, s.question_token)
            )

            client_loop(s)

          _ ->
            puts(
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

          confirmation in ["edits #{s.approval_token}", "session #{s.approval_token}"] ->
            choice =
              if String.starts_with?(confirmation, "edits "),
                do: :session_edits,
                else: :session_command

            case Ipse.Session.approve(s.pid, s.approval, choice) do
              :ok ->
                puts(
                  :stderr,
                  "Session grant saved; expires when this session closes. /permissions inspects; /permissions clear revokes."
                )

                client_loop(%{s | approval: nil, approval_token: nil})

              _ ->
                puts(
                  :stderr,
                  "Reusable grant unavailable for this proposal (native root tools only; at most 32 shell grants, 16 KiB each). Use allow CODE once or n."
                )

                client_loop(s)
            end

          confirmation in ["n", "no", "deny"] ->
            Ipse.Session.approve(s.pid, s.approval, false)
            client_loop(%{s | approval: nil, approval_token: nil})

          true ->
            puts(
              :stderr,
              "Confirmation does not match the pending proposal. Review its arguments and use its displayed allow code, or n to deny."
            )

            client_loop(s)
        end

      {:input, text} when s.busy ->
        if String.valid?(text) and length(s.queued) < 16 and
             byte_size(text) + queued_bytes(s.queued) <= 1_048_576 do
          puts(:stderr, "Queued for the next turn. /cancel interrupts current work.")
          client_loop(%{s | queued: s.queued ++ [text]})
        else
          puts(
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
          do: puts(:stderr, "Compacting context with the selected provider…")

        client_loop(s)

      {:ipse, ^pid, {:compacted, before_bytes, after_bytes}} ->
        puts(
          :stderr,
          "Context compacted: #{before_bytes} → #{after_bytes} bytes. Original journal retained."
        )

        client_loop(s)

      {:ipse, ^pid, {:context_refreshed, manifest}} ->
        print_context(manifest)
        client_loop(s)

      {:ipse, ^pid, {:status, _status}} ->
        unless s.cancelling, do: puts(:stderr, "Running…")
        client_loop(s)

      {:ipse, ^pid, {:subagent, id, status}} ->
        unless s.cancelling, do: puts(:stderr, "Subagent #{id}: #{status}")
        client_loop(s)

      {:ipse, ^pid, {:text, delta}} ->
        write(delta)
        client_loop(s)

      {:ipse, ^pid, {:presentation, text}} ->
        puts("\n" <> text)
        client_loop(s)

      {:ipse, ^pid, {:extension_result, display}} ->
        value = display["delivery"] || display["value"]
        puts("\nExtension #{display["name"]}: #{Jason.encode!(value)}")
        client_loop(s)

      {:ipse, ^pid, {:tool_output, delta}} ->
        write(:stderr, delta)
        client_loop(s)

      {:ipse, ^pid, {:tool, name, args}} ->
        puts(:stderr, "\n→ #{name} #{preview(args)}")
        client_loop(s)

      {:ipse, ^pid, {:tool_result, name, text}} ->
        puts(:stderr, "← #{name}: #{String.slice(text, 0, 800)}")
        client_loop(s)

      {:ipse, ^pid, {:skill, name}} ->
        puts(:stderr, "Skill: #{name}")
        client_loop(s)

      {:ipse, ^pid, {:mcp_approval_context, manifest}} ->
        puts(:stderr, "External MCP target:\n" <> Jason.encode!(manifest, pretty: true))
        client_loop(%{s | approval_context: manifest})

      {:ipse, ^pid, {:question, id, arguments}} ->
        if s.exit do
          Ipse.Session.cancel(s.pid)
          client_loop(%{s | question: nil, question_answers: %{}})
        else
          puts(:stderr, "Waiting for operator clarification (not action approval):")
          token = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

          if s.input_mode != :native,
            do: puts(:stderr, question_prompt(hd(arguments["questions"]), token))

          client_loop(%{
            s
            | busy: true,
              question: {id, arguments, arguments["questions"]},
              question_token: token,
              question_answers: %{},
              native_render: nil
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
        puts(:stderr, "\nError: #{Ipse.CLI.Errors.format(error)}")
        client_loop(s)

      {:ipse, ^pid, {:done, status}} when s.cancelling and status != :cancelled ->
        client_loop(s)

      {:ipse, ^pid, {:done, status}} ->
        puts("")

        puts(
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
            discard_queue(s)

            if s.queued != [],
              do:
                puts(
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
        puts(
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
    do: Ipse.Tools.Questions.render(question) <> "\nReply with answer #{token} VALUE."

  defp question_answer(question, token, text) do
    prefix = "answer #{token} "

    if String.valid?(text) and String.starts_with?(text, prefix) do
      Ipse.Tools.Questions.parse_line(
        question,
        binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix))
      )
    else
      {:error, :question_confirmation}
    end
  end

  defp queued_bytes(queue),
    do:
      Enum.reduce(queue, 0, fn item, total ->
        total +
          byte_size(
            case item do
              {text, _} -> text
              text -> text
            end
          )
      end)

  defp discard_queue(s) do
    Enum.each(s.queued, fn
      {_, ticket} -> Ipse.Session.discard_input(s.pid, s.input_channel, ticket)
      _ -> :ok
    end)
  end

  defp refresh_reader(%{input_mode: mode} = s) when mode != :native, do: s
  defp refresh_reader(%{exit: true, reader_key: :closed} = s), do: s

  defp refresh_reader(%{exit: true} = s) do
    Ipse.Session.cancel_input_read(s.pid, s.input_channel)
    %{s | reader_key: :closed, reader_generation: make_ref()}
  end

  defp refresh_reader(s) do
    s =
      if s.reader_key == nil and s.approval != nil,
        do: %{s | approval_token: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)},
        else: s

    {s, key, request} = reader_request(s)

    if key == s.reader_key do
      s
    else
      :ok = Ipse.Session.cancel_input_read(s.pid, s.input_channel)
      generation = make_ref()
      send(s.reader, {:read, generation, request})
      %{s | reader_key: key, reader_generation: generation}
    end
  end

  defp reader_request(%{approval: approval} = s) when approval != nil do
    {name, args, context} = s.approval_display

    case approval_display(name, args, context, s.approval_token, s.cwd) do
      {:ok, display} ->
        {s, {:approval, approval, s.approval_token, display},
         %{"kind" => "control", "display" => display}}

      {:error, :display_too_large} ->
        Ipse.Session.approve(s.pid, approval, false)

        puts(
          :stderr,
          "Approval refused: complete escaped arguments exceed the 16 MiB terminal display limit. No effect was approved."
        )

        reader_request(%{s | approval: nil, approval_display: nil})
    end
  end

  defp reader_request(%{question: {id, arguments, [item | _]}} = s) do
    item_id = item["id"]

    render =
      case s.native_render do
        %{"question_id" => ^id, "item_id" => ^item_id} = render -> {:ok, render}
        :unverified -> {:error, :extension_question}
        _ -> Ipse.Session.render_question(s.pid, s.input_channel, item["id"])
      end

    case render do
      {:ok, render} ->
        s = %{s | native_render: render}

        {s, {:question, render["render_id"]},
         %{"kind" => "question", "render_id" => render["render_id"]}}

      {:error, :extension_question} ->
        display = escape(question_prompt(item, s.question_token) <> "\nanswer> ")

        {%{s | native_render: :unverified},
         {:extension_question, id, item["id"], s.question_token, arguments},
         %{"kind" => "control", "display" => display}}

      _ ->
        send(self(), {:input_failure, :invalid_operator_render})

        {s, :invalid_question,
         %{"kind" => "control", "display" => "Question channel unavailable.\n"}}
    end
  end

  defp reader_request(s), do: {s, {:prompt, s.cancelling}, %{"kind" => "prompt"}}

  @doc false
  def approval_display(name, args, context, token, cwd) do
    display =
      if(context,
        do: "External MCP target:\n" <> Jason.encode!(context, pretty: true) <> "\n",
        else: ""
      ) <>
        "\nWaiting for approval: #{name}\nAllow #{name}?\n#{Jason.encode!(args, pretty: true)}\nType allow #{token} to allow once, n to deny." <>
        permission_choice(name, token, cwd) <> "\napproval> "

    display = escape(display)

    if byte_size(display) <= Ipse.Runner.Operator.display_limit(),
      do: {:ok, display},
      else: {:error, :display_too_large}
  end

  defp native_input(s, generation, request, text, witness) do
    normalized = if String.valid?(text), do: String.trim(text), else: text

    cond do
      generation != s.reader_generation ->
        Ipse.Session.discard_input(s.pid, s.input_channel, witness)
        client_loop(s)

      normalized == "" or String.starts_with?(normalized, "/") ->
        Ipse.Session.discard_input(s.pid, s.input_channel, witness)
        next = %{s | reader_key: nil}
        next = if request["kind"] == "question", do: %{next | native_render: nil}, else: next
        client_loop(next, {:input, normalized})

      request["kind"] == "question" ->
        result =
          Ipse.Session.answer_observed(
            s.pid,
            s.input_channel,
            request["render_id"],
            text,
            witness
          )

        Ipse.Session.discard_input(s.pid, s.input_channel, witness)
        s = %{s | reader_key: nil}

        case result do
          :ok ->
            client_loop(%{
              s
              | question: nil,
                native_render: nil,
                question_answers: %{},
                busy: true
            })

          {:ok, :more} ->
            {id, args, [_ | rest]} = s.question
            client_loop(%{s | question: {id, args, rest}, native_render: nil})

          _ ->
            puts(
              :stderr,
              "Invalid or stale answer. The question will be rendered with a fresh code."
            )

            client_loop(%{s | native_render: nil})
        end

      request["kind"] == "prompt" ->
        case Ipse.Session.stage_input(s.pid, s.input_channel, text, witness) do
          {:ok, ticket} ->
            client_loop(%{s | reader_key: nil}, {:observed_prompt, text, ticket})

          _ ->
            puts(
              :stderr,
              "Observed input was not accepted. Send it again after the current display settles."
            )

            client_loop(%{s | reader_key: nil})
        end

      true ->
        Ipse.Session.discard_input(s.pid, s.input_channel, witness)
        client_loop(%{s | reader_key: nil}, {:input, normalized})
    end
  end

  defp dispatch_prompt(pid, input) do
    result =
      case input do
        {text, witness} -> Ipse.Session.prompt(pid, text, witness)
        text -> Ipse.Session.prompt(pid, text)
      end

    case result do
      :ok ->
        :ok

      {:error, reason} when reason in [:skill_catalog_changed, :skill_preflight_failed] ->
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

  defp permission_choice(name, token, cwd) when name in ["write", "edit"],
    do:
      "\nOr edits #{token} to allow native workspace edits for this session in #{Jason.encode!(cwd)}; excludes shell, children and extensions."

  defp permission_choice("shell", token, cwd),
    do:
      "\nOr session #{token} to allow this exact shell call (all arguments) for this session in #{Jason.encode!(cwd)}. Shell retains the requested OS policy; command text is not confinement."

  defp permission_choice(_, _, _), do: ""

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
      puts(
        :stderr,
        "Deferred display overflow: #{s.deferred_dropped} events omitted while approval was pending. Saved records are unchanged."
      )
    end

    %{s | deferred_dropped: 0}
  end

  defp print_context(manifest), do: puts(Jason.encode!(manifest, pretty: true))
  defp preview(args), do: args |> Jason.encode!() |> String.slice(0, 600)

  def help, do: puts(String.replace(@help, "Ipse VERSION", "Ipse " <> Ipse.version()))

  def interact(pid, ref, interactive, prompt, cwd) do
    input = if interactive, do: Ipse.CLI.Input.start(pid), else: {:ok, nil, nil, :none}
    interact_input(input, pid, ref, interactive, prompt, cwd)
  end

  defp interact_input({:error, _}, _pid, _ref, _interactive, _prompt, _cwd) do
    puts(
      :stderr,
      "Operator input is unavailable. The terminal channel could not be verified; no alternate reader was started."
    )

    1
  end

  defp interact_input({:ok, reader, channel, mode}, pid, ref, interactive, prompt, cwd) do
    if interactive,
      do: puts("Type a task, $review, or /help. Use /cancel while work is running.")

    try do
      if prompt, do: dispatch_prompt(pid, prompt)

      client_loop(%{
        pid: pid,
        ref: ref,
        interactive: interactive,
        reader: reader,
        input_channel: channel,
        input_mode: mode,
        reader_key: nil,
        reader_generation: nil,
        native_render: nil,
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
        cwd: cwd
      })
    catch
      :exit, _ ->
        puts(
          :stderr,
          "Session request acknowledgment is unconfirmed; it may have taken effect and was not retried. Inspect saved receipts and the workspace before continuing."
        )

        1
    after
      if reader && Process.alive?(reader), do: Process.exit(reader, :kill)
    end
  end
end
