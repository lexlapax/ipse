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
        do: puts(:stderr, "External MCP target:\n" <> Jason.encode!(context, pretty: true))

      puts(
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
                  puts(:stderr, "Answer rejected: #{inspect(reason)}")
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
             byte_size(text) + Enum.sum(Enum.map(s.queued, &byte_size/1)) <= 1_048_576 do
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
          puts(:stderr, question_prompt(hd(arguments["questions"]), token))

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
        puts(:stderr, "\nError: #{error}")
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

  defp dispatch_prompt(pid, text) do
    case Ipse.Session.prompt(pid, text) do
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
    client = self()

    reader = if interactive, do: spawn(fn -> read_input(client) end), else: nil

    if interactive,
      do: puts("Type a task, $review, or /help. Use /cancel while work is running.")

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
