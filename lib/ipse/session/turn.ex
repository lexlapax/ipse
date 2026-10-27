defmodule Ipse.Session.Turn do
  @moduledoc "Turn progression, native tool dispatch and clarification. Called synchronously by the owning Session process."
  alias Ipse.Session
  alias Ipse.Session.Invocation, as: CurrentInvocation
  alias Ipse.Workspace
  alias Ipse.Tools
  alias Ipse.Tools.Questions
  alias Ipse.Extension.{Host, Catalog, Invocation, Actions, Subscriptions, ResultSource}

  @prompt_bytes 1_048_576

  defp prepare_prompt(text, skills) do
    with :ok <- prompt_text(text),
         {:ok, expanded, names} <- Workspace.expand_skills(text, skills),
         :ok <- prompt_text(expanded) do
      {:ok, expanded, names}
    end
  end

  defp prompt_text(text) do
    cond do
      byte_size(text) > @prompt_bytes -> {:error, :prompt_too_large}
      not String.valid?(text) -> {:error, :invalid_prompt}
      true -> :ok
    end
  end

  def prompt(s, text, from, observation \\ nil) do
    with :ok <- prompt_text(text) do
      if Workspace.explicit_skills(text, s.skills) == [] do
        commit_prompt(s, text, {:ok, text, []}, observation)
      else
        task = Session.owned_task(fn -> {text, prepare_prompt(text, s.skills), observation} end)
        {:noreply, %{s | phase: :prompt_preflight, task: task, prompt_from: from}}
      end
    else
      error -> {:reply, error, s}
    end
  end

  def prompt_prepared(s, {:error, error}) when is_binary(error) do
    GenServer.reply(s.prompt_from, {:error, :skill_preflight_failed})
    {:noreply, fail(%{s | prompt_from: nil}, error)}
  end

  def prompt_prepared(s, {original, result, observation}) do
    {:reply, reply, next} =
      commit_prompt(%{s | phase: :idle, prompt_from: nil}, original, result, observation)

    GenServer.reply(s.prompt_from, reply)
    {:noreply, next}
  end

  defp commit_prompt(s, original, prepared, observation) do
    turn = Ipse.Usage.id()

    case prepared do
      {:error, error} when error in [:invalid_prompt, :prompt_too_large] ->
        {:reply, {:error, error}, s}

      {:error, :skill_catalog_changed} = error ->
        {:reply, error,
         fail(
           s,
           "Selected skill changed or is unavailable. Use /context refresh before loading it."
         )}

      {:ok, text, names} ->
        if Subscriptions.declarations(s.config) == [] or
             match?(
               {:ok, _},
               Ipse.Journal.source(s.id, 0, Subscriptions.received(turn, original))
             ) do
          s = Session.enroll_feeds(s)

          input = Ipse.Session.Input.received(s.id, turn, original, text, observation)
          Session.record(s, input)

          s = %{
            s
            | turn_id: turn,
              event_received: nil,
              event_committed: nil,
              event_answer: nil,
              event_turn: nil,
              event_intent: nil,
              event_schedule: "before_request",
              event_after_started: false
          }

          Enum.each(names, &Session.notify(s, {:skill, &1}))
          s = Session.persist_skills(s, s.skills)

          s =
            if Subscriptions.declarations(s.config) != [] do
              event = Subscriptions.received(s.turn_id, original)
              source = Session.record_source(s, event)
              %{s | event_received: %{source: source, record: event}}
            else
              if Host.enabled?(s.config, "transform.prompt"),
                do:
                  Session.record(s, %{
                    "type" => "extension_prompt_received",
                    "version" => 1,
                    "original" => original,
                    "original_sha256" => Ipse.JSON.sha256(original)
                  })

              s
            end

          s = append_message(s, %{"role" => "user", "content" => text})

          s = %{
            s
            | steps: 0,
              final: "",
              mcp_ready: false,
              delegations: 0,
              tool_budget: Tools.empty_call_budget()
          }

          next =
            if Host.enabled?(s.config, "transform.prompt"),
              do: launch_extensions(s, :extension_prompt),
              else: model(s)

          {:reply, :ok, next}
        else
          {:reply, {:error, :subscription_prompt_too_large_or_invalid}, s}
        end
    end
  end

  def approve(s, choice, call, args) when choice in [:session_edits, :session_command] do
    {:ok, mode} = Ipse.Extension.Mode.capture(s.config)

    result =
      if Ipse.Extension.Mode.ordinary(mode, true) == :deny,
        do: {:error, :execution_mode_denied},
        else: Ipse.Session.Permissions.grant(s, get_in(call, ["function", "name"]), args, choice)

    case result do
      {:ok, permissions, source} ->
        Session.record(s, %{
          "type" => "approval_grant",
          "source" => source,
          "call_id" => call["id"],
          "cwd" => s.cwd
        })

        s = Session.finish_wait(%{s | approval: nil, permissions: permissions}, "approved")
        {:reply, :ok, launch_tool(s, call, args, "session_allow")}

      error ->
        {:reply, error, s}
    end
  end

  def approve(s, allowed, call, args) do
    {:ok, mode} = Ipse.Extension.Mode.capture(s.config)
    allowed = allowed == true and Ipse.Extension.Mode.ordinary(mode, true) != :deny

    s =
      Session.finish_wait(
        %{s | approval: nil},
        if(allowed == true, do: "approved", else: "denied")
      )

    if allowed == true,
      do: {:reply, :ok, launch_tool(s, call, args, "approved")},
      else:
        {:reply, :ok,
         tool_result(s, call, "Denied by user. Do not evade this denial.", "denied", "denied")}
  end

  def answer(s, id, answers, question, origin \\ nil) do
    case Questions.validate_answers(question.arguments, answers) do
      {:ok, answers} ->
        s = Session.enroll_feeds(s)

        message =
          Questions.tool_result(
            question.call,
            Jason.encode!(%{
              "answers" => answers,
              "notice" => "Clarification only; no action permission."
            }),
            "result_recorded"
          )

        event = %{
          "type" => "operator_answer",
          "version" => 1,
          "id" => id,
          "message" => message
        }

        event =
          if origin do
            {:ok, receipt} =
              Ipse.Session.OperatorAnswer.receipt(
                s.id,
                question,
                origin.client_id,
                origin.pieces,
                message
              )

            event |> Map.put("version", 2) |> Map.put("origin", receipt)
          else
            event
          end

        Session.record(s, event)

        s = Session.finish_wait(s, "answered")

        Session.notify(s, {:tool_result, "ask_operator", message["content"]})

        next = %{
          s
          | messages: s.messages ++ [message],
            calls: [],
            question: nil,
            phase: :idle,
            operator_render: nil,
            operator_answers: %{},
            operator_pieces: []
        }

        {:reply, :ok, model(next)}

      error ->
        {:reply, error, s}
    end
  end

  @doc false
  def model(s) do
    s = Session.ensure_source_tracking(s)
    s = Session.persist_skills(s, s.skills)
    servers = Map.get(s.config, :mcp_servers, [])

    cond do
      s.event_received != nil and s.event_received.record["turn_id"] == s.turn_id and
          s.event_turn != s.turn_id ->
        start_event_notifications(s)

      servers != [] and not s.mcp_ready ->
        resource = %{owner: self(), job_ref: make_ref()}
        task = Session.owned_task(fn -> Ipse.MCP.discover(servers, s.cwd, resource) end)
        Session.notify(s, {:status, :discovering_mcp})
        %{s | task: task, phase: :mcp_discovery, job_ref: resource.job_ref}

      s.steps >= Map.get(s.config, :max_steps, 30) ->
        fail(
          s,
          "Reached the #{Map.get(s.config, :max_steps, 30)}-step limit. Send another message to continue."
        )

      not Ipse.Usage.capacity?(s.accounting) ->
        fail(s, "The session request-accounting limit was reached; start a fresh session.")

      s.extension_text_turn != s.turn_id and Ipse.Extension.TextResources.entries(s.config) != [] ->
        start_extension_text(s)

      true ->
        case prepare_reference(s) do
          {:ok, prepared} ->
            model_context(prepared)

          {:error, _} ->
            fail(
              s,
              "Reference context could not be admitted within its bounds, or history or the tool catalog changed. Use /context refresh to review current context, or start a fresh session. No inference was dispatched."
            )
        end
    end
  end

  defp model_context(s) do
    system = Ipse.Session.Context.header(s)

    case Ipse.Session.Context.prepare_compaction(s.messages, s.config, system) do
      :skip ->
        launch_model(s, system ++ s.messages)

      {:ok, plan} ->
        config = Ipse.Session.Context.summary_config(s.config)
        Session.notify(s, {:status, :compacting})

        launch_request(
          %{s | compaction: plan},
          config,
          plan.summary_messages,
          [],
          :compaction
        )

      {:tool_results, messages, event} ->
        Session.record(s, event)
        Session.notify(s, {:compacted, event["before_bytes"], event["after_bytes"]})
        model(reference_compacted(%{s | messages: messages}))

      {:error, reason} ->
        compaction_failed(s, reason, "prepare")
    end
  end

  defp prepare_reference(%{reference: nil} = s), do: {:ok, s}

  defp prepare_reference(s) do
    tools =
      definitions(s.config, s.extension_result_sources, true) ++ Ipse.MCP.definitions(s.mcp_tools)

    with {:ok, events, reference, appended} <-
           Ipse.Session.Reference.prepare(
             s.reference,
             s.id,
             s.turn_id,
             Ipse.Session.Context.publishers(s),
             tools,
             s.messages
           ) do
      Enum.each(events, &Session.record(s, &1))
      {:ok, %{s | reference: reference, messages: s.messages ++ appended}}
    end
  end

  defp reference_compacted(%{reference: nil} = s), do: s

  defp reference_compacted(s) do
    {:ok, event, reference} = Ipse.Session.Reference.compacted(s.reference, s.id)
    Session.record(s, event)
    %{s | reference: reference}
  end

  defp launch_model(s, messages) do
    Session.notify(s, {:status, "Thinking"})

    launch_request(
      s,
      s.config,
      messages,
      definitions(s.config, s.extension_result_sources, s.reference != nil) ++
        Ipse.MCP.definitions(s.mcp_tools),
      :model
    )
  end

  defp start_event_notifications(s) do
    event =
      Subscriptions.committed(
        s.turn_id,
        List.last(s.messages)["content"],
        List.last(s.messages),
        s.event_received.source
      )

    if match?({:ok, _}, Ipse.Journal.source(s.id, 0, event)) do
      source = Session.record_source(s, event)

      s = %{
        s
        | event_committed: %{record: event, source: source},
          event_turn: s.turn_id,
          event_intent: nil
      }

      owner = self()
      ref = make_ref()
      plans = Subscriptions.declarations(s.config, "before_request")

      if plans == [] do
        model(s)
      else
        task = Session.owned_task(fn -> Host.notify_events(plans, owner, ref) end)
        %{s | task: task, job_ref: ref, phase: :extension_events}
      end
    else
      fail(
        s,
        "Effective prompt exceeds the event-source bound; no subscriber or inference was started."
      )
    end
  end

  defp start_extension_text(s) do
    entries =
      Enum.reject(Ipse.Extension.TextResources.entries(s.config), fn entry ->
        Enum.any?(s.extension_text, fn {_, resource} ->
          if resource.intent["identity"] == entry.identity and resource.ready and
               Process.alive?(resource.pid) and Ipse.Extension.Registry.live?(entry.identity) do
            enrolled =
              not resource.closed and
                Ipse.Session.TextStream.enrolled?(
                  s.text_stream,
                  resource.subscription_id,
                  resource.pid
                )

            cond do
              enrolled ->
                true

              entry.identity["text_required"] != true ->
                Session.notify(
                  s,
                  {:status,
                   "Optional text consumer is closing; continuing this turn without delivery to it."}
                )

                true

              true ->
                false
            end
          else
            false
          end
        end)
      end)

    s = %{s | extension_text_turn: s.turn_id}

    if entries == [] do
      model(s)
    else
      owner = self()
      ref = make_ref()
      task = Session.owned_task(fn -> Ipse.Extension.TextResources.start(entries, owner, ref) end)
      %{s | task: task, job_ref: ref, phase: :extension_text_start}
    end
  end

  @doc false
  def ensure_text_stream(%{text_stream: nil} = s) do
    ref = make_ref()
    {:ok, stream} = Ipse.Session.TextStream.start(self(), s.id, ref)

    %{
      s
      | text_stream: stream,
        text_stream_monitor: Process.monitor(stream),
        text_stream_policy_ref: ref
    }
  end

  @doc false
  def ensure_text_stream(s), do: s

  @doc false
  def subscribe_text_stream(stream, consumer, version, required) do
    Ipse.Session.TextStream.subscribe(stream, consumer, version, required)
  catch
    :exit, _ -> {:error, :text_stream_unavailable}
  end

  defp launch_request(s, config, messages, tools, phase) do
    s = Session.admit_request(s, config, Atom.to_string(phase))

    if phase == :model and map_size(s.extension_contributions) > 0,
      do:
        Session.record(
          s,
          Ipse.Extension.Context.snapshot(s.extension_contributions, s.active_request)
        )

    owner = self()
    job_ref = make_ref()
    request_id = s.active_request["request_id"]
    stream = if phase == :model, do: s.text_stream

    task =
      Session.owned_task(fn ->
        receive do
          {:provider_start, required, ready} ->
            emit = fn event ->
              case event do
                {:text, text} when phase == :model ->
                  :ok = Ipse.Session.TextStream.deliver(stream, request_id, text, required)
                  send(owner, {:progress, job_ref, event})

                {:provider_usage, _} ->
                  send(owner, {:progress, job_ref, event})

                _ ->
                  if phase == :model, do: send(owner, {:progress, job_ref, event})
              end
            end

            try do
              result =
                Ipse.Usage.Budget.run(config, s.active_request, emit, fn admitted, emit ->
                  if required and (not ready or not text_ready?(stream, request_id)),
                    do: raise(Ipse.Session.TextStream.RequiredFailure)

                  request(admitted, messages, tools, emit)
                end)

              outcome = if match?({:ok, _, _}, result), do: "completed", else: "failed"
              delivery = finish_text(stream, request_id, outcome)

              if required and outcome == "completed" and delivery != :ok do
                emit.({:provider_usage, elem(result, 2)})
                {:error, Exception.message(%Ipse.Session.TextStream.RequiredFailure{})}
              else
                result
              end
            rescue
              error in Ipse.Session.TextStream.RequiredFailure ->
                {:error, Exception.message(error)}
            end
        end
      end)

    s = %{
      s
      | task: task,
        phase: phase,
        steps: s.steps + 1,
        job_ref: job_ref,
        request_started_at: System.monotonic_time(:millisecond)
    }

    case begin_text(stream, request_id, task.pid) do
      {:ok, required} ->
        send(task.pid, {:provider_start, required, true})
        %{s | text_required: if(phase == :model, do: required, else: s.text_required)}

      _ ->
        send(task.pid, {:provider_start, s.text_required, false})
        s
    end
  end

  defp begin_text(nil, _, _), do: {:ok, false}

  defp begin_text(stream, id, producer) do
    Ipse.Session.TextStream.begin_with_policy(stream, id, producer)
  catch
    :exit, _ -> {:error, :text_stream_unavailable}
  end

  defp text_ready?(stream, id) do
    Ipse.Session.TextStream.check(stream, id) == :ok
  catch
    :exit, _ -> false
  end

  @doc false
  def finish_text(nil, _, _), do: :ok

  @doc false
  def finish_text(stream, id, outcome) do
    Ipse.Session.TextStream.finish(stream, id, outcome)
  catch
    :exit, _ -> {:error, :text_stream_unavailable}
  end

  @doc false
  def launch_extensions(s, phase) do
    owner = self()
    job_ref = make_ref()
    stage = if phase == :extension_prompt, do: "transform.prompt", else: "transform.presentation"
    task = Session.owned_task(fn -> Host.run(s.config, stage, owner, job_ref) end)
    %{s | phase: phase, task: task, job_ref: job_ref, extension_intent: nil}
  end

  defp request(config, messages, tools, emit),
    do: Ipse.Provider.request_complete(config, messages, tools, emit)

  @doc false
  def complete_compaction(s, assistant, usage) do
    case Ipse.Session.Context.finish_compaction(
           s.compaction,
           assistant,
           Ipse.Session.Context.header(s),
           s.config
         ) do
      {:ok, messages, checkpoint, stats} ->
        Session.record(s, %{
          "type" => "context_compacted",
          "request_id" => s.last_request_id,
          "version" => 1,
          "covered_messages" => length(s.compaction.prefix),
          "prefix_sha256" => Ipse.JSON.digest(s.compaction.prefix),
          "checkpoint" => checkpoint,
          "before_bytes" => stats.before_bytes,
          "after_bytes" => stats.after_bytes
        })

        Session.notify(s, {:compacted, stats.before_bytes, stats.after_bytes})
        Session.notify(s, {:usage, usage})

        model(
          reference_compacted(%{
            s
            | messages: messages,
              compaction: nil,
              usage: usage,
              reported_model: reported_model(assistant)
          })
        )

      {:error, reason} ->
        compaction_failed(s, reason, "validation")
    end
  end

  @doc false
  def compaction_failed(s, reason, stage) do
    Session.record(s, %{
      "type" => "compaction_failed",
      "stage" => stage,
      "reason" => reason,
      "diagnostics" =>
        Ipse.Session.Context.measure(s.messages, s.config, Ipse.Session.Context.header(s))
    })

    fail(
      s,
      "Context compaction stopped: " <>
        reason <>
        " Original history is retained. " <>
        "Review recorded effects before continuing. A short continuation may make an older turn eligible; " <>
        "otherwise choose a suitable context ceiling or start a new session with necessary context. No tools were replayed."
    )
  end

  @doc false
  def next_tool(%{calls: []} = s), do: model(s)

  @doc false
  def next_tool(s) do
    call = hd(s.calls)
    name = get_in(call, ["function", "name"])

    with args when is_binary(args) <- get_in(call, ["function", "arguments"]),
         {:ok, args} when is_map(args) <- Jason.decode(args) do
      if name in ["read", "write", "edit"] do
        task =
          Session.owned_task(fn ->
            with {:ok, snapshot, _added} <-
                   Workspace.nested(s.context_snapshot, args["path"]) do
              {:ok, snapshot, Workspace.drift(snapshot)}
            end
          end)

        Session.notify(s, {:status, :checking_workspace_context})
        %{s | phase: :context_preflight, task: task, job_ref: nil}
      else
        dispatch_tool(s, call, args)
      end
    else
      _ ->
        tool_result(
          s,
          call,
          "Invalid tool arguments: expected a JSON object.",
          "invalid_arguments",
          "not_decided"
        )
    end
  end

  @doc false
  def dispatch_pending_tool(s) do
    case s.calls do
      [call | _] ->
        with args when is_binary(args) <- get_in(call, ["function", "arguments"]),
             {:ok, args} when is_map(args) <- Jason.decode(args) do
          dispatch_tool(s, call, args)
        else
          _ ->
            tool_result(
              s,
              call,
              "Invalid tool arguments: expected a JSON object.",
              "invalid_arguments",
              "not_decided"
            )
        end

      [] ->
        model(s)
    end
  end

  defp dispatch_tool(s, call, args) do
    name = get_in(call, ["function", "name"])
    {:ok, execution_mode} = Ipse.Extension.Mode.capture(s.config)
    external = Ipse.MCP.external?(name)

    validation =
      cond do
        Catalog.external?(name) ->
          with true <- s.extension_invocations < Invocation.limit(),
               {:ok, _, descriptor} <- Catalog.lookup(s.config, "invoke.tool", name),
               {:ok, ^args} <-
                 Ipse.JSON.decode_bounded(get_in(call, ["function", "arguments"])),
               true <-
                 Invocation.source_call_valid?(
                   Enum.find(Enum.reverse(s.messages), &(&1["role"] == "assistant")),
                   call["id"],
                   name,
                   args
                 ),
               :ok <- Catalog.validate_call(descriptor, args) do
            :ok
          else
            _ -> {:error, "Invalid or unavailable extension tool; no callback executed."}
          end

        external ->
          Ipse.MCP.validate_call(Ipse.MCP.tool(s.mcp_tools, name), args)

        name in ["research_source", "research_claim", "research_ledger"] ->
          if s.config[:delegation_origin],
            do:
              {:error, "Research ledger belongs to the parent; child MCP capture is unavailable."},
            else: Ipse.Tools.Research.validate(name, args)

        name == "delegate" ->
          Ipse.Tools.Delegation.admit(s.config, s.delegations, call, args)

        name == "delegate_parallel" ->
          Ipse.Tools.Delegation.admit_parallel(s.config, s.delegations, args)

        true ->
          :ok
      end

    requires_approval =
      Tools.mutating?(name) or external or Catalog.external?(name) or
        name in ["delegate", "delegate_parallel"]

    mode = Ipse.Extension.Mode.ordinary(execution_mode, requires_approval)

    grant_source = Ipse.Session.Permissions.source(s, name, args)

    cond do
      name == "ask_operator" ->
        start_question(s, call, args)

      validation != :ok ->
        {:error, reason} = validation
        tool_result(s, call, reason, "invalid_arguments", "not_decided")

      protected_outer?(s, name) ->
        {:ok, entry, descriptor} = Catalog.lookup(s.config, "invoke.tool", name)
        ref = make_ref()

        task =
          Session.owned_task(fn ->
            result =
              Ipse.Extension.SemanticAdmission.outer(
                s.config,
                s.cwd,
                s.id,
                entry.identity,
                descriptor
              )

            {call, args, result}
          end)

        %{s | phase: :semantic_outer, task: task, job_ref: ref}

      requires_approval and mode == :deny ->
        tool_result(
          s,
          call,
          "Denied: this run is read-only. Ask the user to enable execution.",
          "denied",
          "policy_denied"
        )

      requires_approval and mode == :ask and is_nil(grant_source) ->
        ref = make_ref()

        s =
          Session.begin_wait(s, "tool", %{
            "turn_id" => s.turn_id,
            "request_id" => s.last_request_id
          })

        if external do
          Session.notify(
            s,
            {:mcp_approval_context, Ipse.MCP.manifest(Ipse.MCP.tool(s.mcp_tools, name))}
          )
        end

        Session.notify(s, {:approval, ref, name, args})
        %{s | phase: :approval, approval: {ref, call, args}}

      true ->
        decision = if requires_approval, do: "session_allow", else: "not_required"
        launch_tool(s, call, args, decision)
    end
  end

  def semantic_outer_completed(s, {call, args, {:ok, binding}}) do
    name = get_in(call, ["function", "name"])

    with true <- hd(s.calls) === call,
         {:ok, entry, descriptor} <- Catalog.lookup(s.config, "invoke.tool", name),
         true <-
           Ipse.Extension.SemanticAdmission.valid_outer_binding?(
             binding,
             entry.identity,
             descriptor,
             s.id
           ) do
      {:noreply, launch_tool(s, call, args, "saved_consent", binding)}
    else
      _ -> semantic_outer_completed(s, {call, args, :refused})
    end
  end

  def semantic_outer_completed(s, {call, _args, _}) do
    {:noreply,
     tool_result(
       s,
       call,
       "Saved semantic permission is unavailable or expired; no extension callback executed.",
       "denied",
       "policy_denied"
     )}
  end

  def semantic_outer_completed(s, _),
    do: {:noreply, fail(s, "Semantic admission failed; no extension callback executed.")}

  defp protected_outer?(s, name) do
    descriptor = s.config[:semantic_admission]

    is_map(descriptor) and descriptor["pin"] != nil and
      case Catalog.lookup(s.config, "invoke.tool", name) do
        {:ok, entry, _} -> entry.identity["instance"] == descriptor["instance"]
        _ -> false
      end
  end

  defp launch_tool(s, call, args, decision, binding \\ nil) do
    name = get_in(call, ["function", "name"])
    external = Ipse.MCP.tool(s.mcp_tools, name)

    event = %{
      "type" => "tool_started",
      "call_id" => call["id"],
      "name" => name,
      "approval" => decision,
      "approval_source" => Ipse.Session.Permissions.source(s, name, args) || decision,
      "arguments" =>
        if(external || Catalog.external?(name) || name in ["delegate", "delegate_parallel"],
          do: args
        ),
      "mcp" => if(external, do: Ipse.MCP.manifest(external)),
      "sandbox_requested" => to_string(Map.get(s.config, :sandbox, :off))
    }

    event =
      if decision == "saved_consent",
        do: event |> Map.put("version", 2) |> Map.put("semantic_binding", binding),
        else: event

    s =
      if Ipse.Session.ToolLifecycle.recording?(s.tool_lifecycle) do
        source = Session.optional_source(s, event)

        tool_records(
          s,
          Ipse.Session.ToolLifecycle.start(s.tool_lifecycle, source, event, call, length(s.calls))
        )
      else
        Session.record(s, event)
        s
      end

    Session.notify(s, {:tool, name, args})
    owner = self()
    job_ref = make_ref()

    context = %{
      cwd: s.cwd,
      skills: s.skills,
      sandbox: Map.get(s.config, :sandbox, :off),
      parallel_child: Map.get(s.config, :parallel_child, false),
      workspace_edit_grant: Ipse.Session.Permissions.source(s, name, args) == "workspace_edits",
      emit: fn event -> send(owner, {:progress, job_ref, event}) end
    }

    task =
      Session.owned_task(
        fn ->
          cond do
            Catalog.external?(name) ->
              Host.invoke_export("invoke.tool", name, args, owner, job_ref)

            external ->
              Ipse.MCP.call(external, args, s.cwd, %{owner: owner, job_ref: job_ref})

            name == "load_skill" ->
              Workspace.load_skill(s.skills, args["name"] || "")

            name == "load_skill_resource" ->
              Workspace.load_skill_resource(s.skills, args["name"], args["path"])

            name in ["research_source", "research_claim", "research_ledger"] ->
              Ipse.Tools.Research.call(s.dir, s.id, name, args)

            name == "saved_result_read" ->
              ResultSource.read_model(owner, job_ref, args)

            name in ~w(source_list source_read source_quote) ->
              Ipse.Extension.SourceRead.read_model(owner, job_ref, name, args)

            name in ["delegate", "delegate_parallel"] ->
              Ipse.Tools.Delegation.run(
                name,
                %{
                  owner: owner,
                  job_ref: job_ref,
                  id: s.id,
                  request_id: s.last_request_id,
                  dir: s.dir,
                  cwd: s.cwd,
                  config: s.config,
                  context_snapshot: s.context_snapshot,
                  call_id: call["id"]
                },
                args
              )

            true ->
              Tools.execute(name, args, context)
          end
        end,
        :unknown
      )

    count =
      cond do
        name == "delegate" -> s.delegations + 1
        name == "delegate_parallel" -> s.delegations + 2
        true -> s.delegations
      end

    %{
      s
      | phase: :tool,
        task: task,
        job_ref: job_ref,
        tool_decision: decision,
        delegations: count,
        invocation: %CurrentInvocation{semantic_binding: binding}
    }
  end

  @doc false
  def tool_result(s, call, text, status, approval) do
    name = get_in(call, ["function", "name"])

    provenance =
      if Ipse.MCP.external?(name) and status == "result_recorded",
        do: %{
          "call_id" => call["id"],
          "tool" => name,
          "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

    text =
      if Ipse.MCP.external?(name) and status == "result_recorded" do
        header = "Host-recorded MCP result: #{Jason.encode!(provenance)}\n"

        if byte_size(header) <= 512 do
          header <> text
        else
          "Host MCP call metadata exceeds display bounds; inspect the original journal.\n" <> text
        end
      else
        text
      end

    message = %{
      "role" => "tool",
      "tool_call_id" => call["id"],
      "content" => text,
      "ipse_tool_outcome" => %{"status" => status, "approval" => approval}
    }

    message =
      if provenance, do: Map.put(message, "ipse_external_result", provenance), else: message

    accept_tool_result(s, call, message)
  end

  @doc false
  def accept_tool_result(s, call, message) do
    s = append_tool_message(s, message, true)
    Session.notify(s, {:tool_result, get_in(call, ["function", "name"]), message["content"]})
    next_tool(%{s | calls: tl(s.calls), tool_decision: "not_decided"})
  end

  @doc false
  def settle_preflight_calls(%{phase: :context_preflight, calls: [call | queued]} = s, text) do
    s =
      append_tool_message(
        s,
        %{
          "role" => "tool",
          "tool_call_id" => call["id"],
          "content" => text,
          "ipse_tool_outcome" => %{"status" => "not_started", "approval" => "not_decided"}
        },
        false
      )

    settle_calls(%{s | calls: queued}, "Not executed: work stopped before this call started.")
  end

  @doc false
  def settle_calls(s, text) do
    s.calls
    |> Enum.with_index()
    |> Enum.reduce(s, fn {call, index}, state ->
      started = index == 0 and s.phase in [:tool, :delegated_approval, :extension_approval]
      approval = if started, do: s.tool_decision, else: "not_decided"
      status = if started, do: "unknown", else: "not_started"
      outcome = if started, do: text, else: "Not executed: work stopped before this call started."

      append_tool_message(
        state,
        %{
          "role" => "tool",
          "tool_call_id" => call["id"],
          "content" => outcome,
          "ipse_tool_outcome" => %{"status" => status, "approval" => approval}
        },
        started
      )
    end)
    |> Map.put(:calls, [])
  end

  @doc false
  def fail(s, error) do
    s = CurrentInvocation.release_output(s)
    s = Session.finish_wait(s, "interrupted")
    s = Session.settle_children(s, "worker_failed")
    Session.notify(s, {:error, error})

    s
    |> settle_calls("Outcome unknown after interruption. Inspect before retrying.")
    |> finish(:error)
  end

  @doc false
  def finish(s, status) do
    s = CurrentInvocation.release_output(s)
    after_plans = Subscriptions.declarations(s.config, "after_turn")
    s = record_source_answer(s, status, after_plans)

    if status == :ok and s.event_received != nil and s.event_turn == s.turn_id and
         not s.event_after_started and after_plans != [] do
      Session.record(s, %{
        "type" => "lifecycle_turn_settling",
        "version" => 1,
        "turn_id" => s.turn_id,
        "assistant_sha256" => Ipse.JSON.digest([List.last(s.messages)]),
        "final_sha256" => Ipse.JSON.sha256(s.final)
      })

      s =
        if Enum.any?(after_plans, &(&1.declaration["event"] == "answer.committed")) do
          event =
            Ipse.Session.Lifecycle.answer(
              s.turn_id,
              s.last_request_id,
              List.last(s.messages),
              s.final,
              s.event_committed.source
            )

          source = Session.record_source(s, event)
          %{s | event_answer: %{record: event, source: source}}
        else
          s
        end

      owner = self()
      ref = make_ref()
      task = Session.owned_task(fn -> Host.notify_events(after_plans, owner, ref) end)

      %{
        s
        | task: task,
          job_ref: ref,
          phase: :extension_events,
          event_schedule: "after_turn",
          event_after_started: true
      }
    else
      Session.record(s, %{"type" => "turn_finished", "status" => to_string(status)})
      Session.notify(s, {:done, status})

      %{
        s
        | phase: :idle,
          task: nil,
          approval: nil,
          job_ref: nil,
          compaction: nil,
          extension_intent: nil,
          invocation: %CurrentInvocation{},
          extension_mcp_context: nil,
          event_received: nil,
          event_committed: nil,
          event_answer: nil,
          event_turn: nil,
          event_intent: nil,
          event_schedule: "before_request",
          event_after_started: false,
          tool_decision: "not_decided"
      }
    end
  end

  defp record_source_answer(s, status, after_plans) do
    assistant = List.last(s.messages)

    if Ipse.Session.SourceWindow.enabled?(s.config) and status == :ok and
         not Enum.any?(after_plans, &(&1.declaration["event"] == "answer.committed")) and
         is_map(assistant) and assistant["role"] == "assistant" and
         assistant["tool_calls"] in [nil, []] and is_binary(assistant["content"]) do
      case Ipse.Journal.Writer.source_query(s.journal_writer, :effective_source) do
        {:ok, source} when is_map(source) ->
          Session.record_source(s, %{
            "type" => "source_answer_committed",
            "version" => 1,
            "answer" =>
              Ipse.Session.Lifecycle.answer(
                s.turn_id,
                s.last_request_id,
                assistant,
                s.final,
                source
              )
          })

        _ ->
          :ok
      end
    end

    s
  end

  @doc false
  def continue_event_plan(s, delivery) do
    plans = Subscriptions.declarations(s.config, s.event_schedule)

    index =
      Enum.find_index(
        plans,
        &(&1.instance == delivery["identity"]["instance"] and
            &1.declaration == delivery["declaration"])
      )

    if index == nil do
      fail(s, "Event job continuation no longer matches the selected plan.")
    else
      remaining = Enum.drop(plans, index + 1)

      if remaining == [] do
        if s.event_schedule == "after_turn", do: finish(s, :ok), else: model(s)
      else
        owner = self()
        ref = make_ref()
        task = Session.owned_task(fn -> Host.notify_events(remaining, owner, ref) end)
        %{s | task: task, job_ref: ref, phase: :extension_events}
      end
    end
  end

  @doc false
  def append_message(s, message) do
    event = %{"type" => "message", "message" => message}

    event =
      if message["role"] == "assistant",
        do: Map.put(event, "request_id", s.last_request_id),
        else: event

    s =
      if message["role"] == "assistant" and is_list(message["tool_calls"]) and
           message["tool_calls"] != [] and Ipse.Session.ToolLifecycle.recording?(s.tool_lifecycle) do
        source = Session.optional_source(s, event)

        tool_records(
          s,
          Ipse.Session.ToolLifecycle.proposal(s.tool_lifecycle, source, event, s.turn_id)
        )
      else
        Session.record(s, event)
        s
      end

    %{s | messages: s.messages ++ [message]}
  end

  defp append_tool_message(s, message, started) do
    if started and Ipse.Session.ToolLifecycle.active?(s.tool_lifecycle) do
      event = %{"type" => "message", "message" => message}
      source = Session.optional_source(s, event)
      s = tool_records(s, Ipse.Session.ToolLifecycle.finish(s.tool_lifecycle, source, event))
      %{s | messages: s.messages ++ [message]}
    else
      append_message(s, message)
    end
  end

  @doc false
  def tool_records(s, {context, records}) do
    Enum.reduce(records, %{s | tool_lifecycle: context}, fn event, state ->
      source = Session.record_source(state, event)

      if event["type"] == "lifecycle_tool_intent" do
        %{
          state
          | tool_lifecycle: Ipse.Session.ToolLifecycle.bind(state.tool_lifecycle, source, event)
        }
      else
        if event["type"] == "lifecycle_tool_recording_stopped",
          do:
            Session.notify(
              state,
              {:status,
               "Tool lifecycle recording stopped; original tool history and approvals remain active."}
            )

        state
      end
    end)
  end

  @doc false
  def reported_model(%{"provider_data" => data}) when is_map(data),
    do: Ipse.Provider.model_name(data["reported_model"])

  @doc false
  def reported_model(_), do: nil

  defp start_question(s, call, arguments) do
    case Questions.validate(arguments) do
      {:ok, arguments} ->
        if Questions.enabled?(s.config) do
          # Other proposed calls are settled without execution so the answer can change the plan.
          next =
            settle_calls(
              %{s | calls: tl(s.calls), phase: :idle},
              "Not started while clarification is required."
            )

          event = %{
            "type" => "operator_question",
            "version" => 1,
            "id" => call["id"],
            "call" => call,
            "arguments" => arguments,
            "steps" => s.steps,
            "covered_messages" => length(next.messages),
            "prefix_sha256" => Ipse.JSON.digest(next.messages)
          }

          source = Session.record_wait_subject(next, event)
          Session.checkpoint_event_question(next, %{id: call["id"]})
          if source, do: Session.offer_record(next, source, event)
          next = Session.question_wait(next, %{id: call["id"]}, source)
          Session.notify(next, {:question, call["id"], arguments})

          %{
            next
            | question: %{id: call["id"], call: call, arguments: arguments, steps: s.steps},
              calls: [call],
              phase: :question,
              task: nil,
              job_ref: nil,
              operator_render: nil,
              operator_answers: %{},
              operator_pieces: []
          }
        else
          message =
            Questions.tool_result(
              call,
              "Operator clarification unavailable in headless or child sessions. Provide the missing information in the task; no default answer was selected.",
              "error"
            )

          next = append_message(s, message)
          Session.notify(next, {:tool_result, "ask_operator", message["content"]})

          fail(
            %{next | calls: tl(s.calls)},
            "This task requires operator input; use interactive chat or supply the missing information."
          )
        end

      {:error, reason} ->
        tool_result(s, call, reason, "invalid_arguments", "not_required")
    end
  end

  @doc false
  def close_question(%{question: nil} = s), do: s

  @doc false
  def close_question(%{question: %{kind: :extension} = question} = s) do
    {:ok, result} = Actions.result(question.action, %{"status" => "cancelled", "value" => %{}})
    Session.record(s, result)

    %{
      s
      | question: nil,
        phase: CurrentInvocation.invocation_phase(question.parent),
        tool_decision: question.parent["approval"]
    }
  end

  @doc false
  def close_question(s) do
    message =
      Questions.tool_result(
        s.question.call,
        "Clarification cancelled without an answer. No action was authorized.",
        "not_started"
      )

    Session.record(s, %{
      "type" => "operator_question_closed",
      "version" => 1,
      "id" => s.question.id,
      "message" => message
    })

    %{s | question: nil, calls: [], messages: s.messages ++ [message]}
  end

  @doc false
  def mcp_discovered(s, tools) do
    Session.record(s, %{
      "type" => "mcp_catalog",
      "version" => 1,
      "tools" => Ipse.MCP.manifests(tools)
    })

    {:noreply, model(%{s | mcp_tools: tools, mcp_ready: true})}
  end

  @doc false
  def context_checked(s, snapshot, drift) do
    if snapshot == s.context_snapshot do
      {:noreply, dispatch_pending_tool(%{s | context_drift: drift})}
    else
      s = Session.persist_context(%{s | context_drift: drift}, snapshot)

      s =
        settle_preflight_calls(
          s,
          "Not executed: new scoped workspace context was loaded. Review it before retrying this action."
        )

      {:noreply, model(s)}
    end
  end

  @doc false
  def context_check_failed(s, reason) do
    s =
      settle_preflight_calls(
        s,
        "Not executed: scoped context could not be loaded (#{Ipse.Workspace.failure_message(reason)}). Check this call's target path and review workspace guidance before retrying."
      )

    {:noreply, model(s)}
  end

  @doc false
  def context_refreshed(s, snapshot, drift, skills) do
    s = Session.persist_context(%{s | context_drift: drift, skill_drift: []}, snapshot)
    s = Session.persist_skills(s, skills)

    s =
      if s.reference do
        {:ok, event, reference} =
          Ipse.Session.Reference.refresh(
            s.reference,
            s.id,
            Ipse.Session.Context.admission_header(s),
            Ipse.Session.Context.admission_publishers(s)
          )

        Session.record(s, event)
        %{s | reference: reference}
      else
        s
      end

    manifest =
      Ipse.Session.Context.manifest(s.context_snapshot, s.context_drift, s.skill_drift, s.skills)

    Session.notify(s, {:context_refreshed, manifest})
    Session.notify(s, {:done, :ok})
    {:noreply, %{s | phase: :idle, job_ref: nil}}
  end

  @doc false
  def context_refresh_failed(s, reason) do
    Session.notify(
      s,
      {:error,
       "Workspace context refresh failed: #{Ipse.Workspace.failure_message(reason)}. Check workspace access and instruction files, then retry the context refresh command."}
    )

    Session.notify(s, {:done, {:error, reason}})
    {:noreply, %{s | phase: :idle, job_ref: nil}}
  end

  @doc false
  def model_completed(s, assistant, usage) do
    calls = if is_nil(assistant["tool_calls"]), do: [], else: assistant["tool_calls"]
    admission = Tools.admit_calls(calls, s.tool_budget)
    valid_calls = match?({:ok, _}, admission)

    s =
      if valid_calls do
        append_message(s, assistant)
      else
        Session.record(s, %{
          "type" => "provider_response_refused",
          "version" => 1,
          "request_id" => s.last_request_id,
          "reason" => admission |> elem(1) |> Atom.to_string(),
          "message" => assistant
        })

        s
      end

    s = %{
      s
      | usage: usage,
        calls: if(valid_calls, do: calls, else: []),
        final: assistant["content"] || "",
        reported_model: reported_model(assistant)
    }

    s = if valid_calls, do: %{s | tool_budget: elem(admission, 1)}, else: s

    Session.notify(s, {:usage, usage})

    cond do
      not valid_calls ->
        {:noreply,
         fail(
           %{s | calls: []},
           if(admission == {:error, :tool_call_limit},
             do:
               "Tool-call count or argument budget exceeded; no call from this response was started.",
             else: "Invalid or duplicate tool-call identities; no call was started."
           )
         )}

      calls != [] ->
        {:noreply, next_tool(s)}

      Host.enabled?(s.config, "transform.presentation") ->
        {:noreply, launch_extensions(s, :extension_presentation)}

      true ->
        {:noreply, finish(s, :ok)}
    end
  end

  @doc false
  def tool_completed(s, :tool_error, text) do
    tool_completed(
      s,
      :error,
      "MCP tool reported an error after dispatch. Effects may have happened; inspect before retrying.\n" <>
        text
    )
  end

  def tool_completed(s, status, text) do
    s = %{
      s
      | delegation_workers: MapSet.new(),
        delegation_queue: [],
        delegation_effect: nil,
        delegation_claims: %{}
    }

    outcome = if status == :error, do: "error", else: "result_recorded"
    {:noreply, tool_result(s, hd(s.calls), text, outcome, s.tool_decision)}
  end

  defp definitions(config, result_sources, versioned) do
    Tools.definitions(Map.get(config, :sandbox, :off)) ++
      if(versioned or model_saved_results?(result_sources),
        do: [ResultSource.reader_definition()],
        else: []
      ) ++
      if(Ipse.Session.SourceWindow.enabled?(config),
        do: Ipse.Extension.SourceRead.definitions(),
        else: []
      ) ++
      Catalog.definitions(config) ++
      Ipse.Tools.Delegation.definitions(config) ++
      if(config[:delegation_origin], do: [], else: Ipse.Tools.Research.definitions()) ++
      [
        Questions.definition(),
        %{
          "type" => "function",
          "function" => %{
            "name" => "load_skill",
            "description" =>
              "Load a skill's full instructions by name. This grants no permissions.",
            "parameters" => %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}},
              "required" => ["name"]
            }
          }
        },
        %{
          "type" => "function",
          "function" => %{
            "name" => "load_skill_resource",
            "description" =>
              "Read one explicit UTF-8 file relative to a discovered skill directory (32 KiB maximum). Does not execute scripts or follow resource links; grants no permissions.",
            "parameters" => %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}, "path" => %{"type" => "string"}},
              "required" => ["name", "path"],
              "additionalProperties" => false
            }
          }
        }
      ]
  end

  defp model_saved_results?(%ResultSource.Index{committed: sources}),
    do:
      Enum.any?(sources, fn {_, source} ->
        source.intent["descriptor"]["stage"] == "invoke.tool"
      end)
end
