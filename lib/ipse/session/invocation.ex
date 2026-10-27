defmodule Ipse.Session.Invocation do
  @moduledoc "Extension invocation state and execution. Session retains caller and phase admission; all transitions run in that same process."
  alias Ipse.Session
  alias Ipse.Session.Invocation, as: CurrentInvocation
  alias Ipse.Workspace
  alias Ipse.Tools.Questions
  alias Ipse.Journal.Writer

  alias Ipse.Extension.{
    Host,
    Catalog,
    Invocation,
    Actions,
    ModelCall,
    EmbeddingCall,
    DecisionCall,
    Subscriptions,
    Feeds,
    ResultSource
  }

  alias Ipse.Session.Turn

  defstruct parent: nil,
            request: nil,
            action: nil,
            step: 0,
            effect_sources: %{},
            results: [],
            semantic_binding: nil,
            interrupted: false

  @type t :: %__MODULE__{
          parent: map() | nil,
          request: map() | nil,
          action: map() | nil,
          step: non_neg_integer(),
          effect_sources: map(),
          results: [map()],
          interrupted: boolean()
        }

  def restore(%{kind: :extension} = question, effect_sources) do
    %__MODULE__{
      parent: question.parent,
      action: %{intent: question.action},
      step: question.action["step"],
      effect_sources: effect_sources,
      results: question.results
    }
  end

  def restore(_, _), do: %__MODULE__{}

  def invoke_export(s, kind, name, arguments) do
    stage = "invoke." <> Atom.to_string(kind)

    with {:ok, entry, descriptor} <- Catalog.lookup(s.config, stage, name),
         true <- s.extension_invocations < Invocation.limit(),
         true <- Ipse.Extension.Registry.live?(entry.identity),
         :ok <- Catalog.validate_call(descriptor, arguments) do
      s = Session.enroll_feeds(s)
      owner = self()
      job_ref = make_ref()
      request = %{stage: stage, name: name, arguments: arguments}
      admission = s.config[:semantic_admission]

      protected =
        kind == :command and is_map(admission) and admission["pin"] != nil and
          admission["instance"] == entry.identity["instance"]

      task =
        Session.owned_task(fn ->
          if protected,
            do:
              {:extension_command_outer, request,
               Ipse.Extension.SemanticAdmission.outer(
                 s.config,
                 s.cwd,
                 s.id,
                 entry.identity,
                 descriptor
               )},
            else: Host.invoke_export(stage, name, arguments, owner, job_ref)
        end)

      phase =
        if protected,
          do: :semantic_outer,
          else: if(kind == :command, do: :extension_command, else: :extension_service)

      {:reply, :ok,
       %{
         s
         | phase: phase,
           task: task,
           job_ref: job_ref,
           invocation: %CurrentInvocation{request: request}
       }}
    else
      _ -> {:reply, {:error, :invalid_extension_call}, s}
    end
  end

  def command_outer(s, request, {:ok, binding}) do
    with true <- s.invocation.request === request,
         {:ok, entry, descriptor} <- Catalog.lookup(s.config, request.stage, request.name),
         true <-
           Ipse.Extension.SemanticAdmission.valid_outer_binding?(
             binding,
             entry.identity,
             descriptor,
             s.id
           ) do
      owner = self()
      ref = make_ref()

      task =
        Session.owned_task(fn ->
          Host.invoke_export(request.stage, request.name, request.arguments, owner, ref)
        end)

      {:noreply,
       %{
         s
         | task: task,
           job_ref: ref,
           phase: :extension_command,
           invocation: %{s.invocation | semantic_binding: binding}
       }}
    else
      _ -> command_outer(s, request, :refused)
    end
  end

  def command_outer(s, _, _),
    do:
      {:noreply,
       Turn.fail(
         s,
         "Saved semantic permission is unavailable or expired; no extension callback executed."
       )}

  def begin(s, ref, stage, name, arguments, phase) do
    origin =
      if phase == :tool do
        call = hd(s.calls)

        with {:ok, parsed} <- Jason.decode(get_in(call, ["function", "arguments"])),
             true <-
               stage == "invoke.tool" and get_in(call, ["function", "name"]) == name and
                 parsed == arguments do
          {:ok, call["id"], s.last_request_id, s.tool_decision}
        else
          _ -> :error
        end
      else
        if s.invocation.request == %{stage: stage, name: name, arguments: arguments},
          do:
            {:ok, nil, nil,
             if(s.invocation.semantic_binding, do: "saved_consent", else: "operator_request")},
          else: :error
      end

    with {:ok, parent_call, parent_request, approval} <- origin,
         true <- s.extension_invocations < Invocation.limit(),
         {:ok, entry, descriptor} <- Catalog.lookup(s.config, stage, name),
         true <- Ipse.Extension.Registry.live?(entry.identity),
         :ok <- Catalog.validate_call(descriptor, arguments),
         intent =
           Invocation.intent(
             entry.identity,
             descriptor,
             arguments,
             s.id,
             s.turn_id,
             parent_call,
             parent_request,
             approval,
             s.invocation.semantic_binding
           ),
         :ok <- Invocation.validate_intent(intent) do
      entry = Map.merge(entry, %{host_config: s.config, host_cwd: s.cwd})
      {clock, entry} = output_clock(entry, descriptor["stage"], ref)
      Session.record(s, intent)

      {:reply, {:ok, intent, entry},
       %{
         s
         | invocation: %CurrentInvocation{parent: intent, request: s.invocation.request},
           extension_output_clock: clock,
           extension_invocations: s.extension_invocations + 1,
           extension_mcp_context: nil
       }}
    else
      _ -> {:reply, {:error, :extension_admission_refused}, s}
    end
  end

  def open_output(s, offer) do
    with true <- output_timely?(s) and s.extension_output_clock != nil,
         true <- is_nil(s.invocation.action) and not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         {:ok, event, source, index} <-
           ResultSource.index_open(
             s.extension_result_sources,
             s.invocation.parent,
             offer,
             output_elapsed(s)
           ),
         {:ok, final} <-
           Invocation.build_saved_result(
             s.invocation.parent,
             ResultSource.descriptor(source),
             s.invocation.results,
             120_000
           ),
         {:ok, capacity} <- ResultSource.reservation_size(source, final),
         true <- ResultSource.fits_reservation?(s.extension_result_sources, capacity),
         {:ok, limits} <- Ipse.Journal.normalize_limits(s.config[:journal]),
         true <- capacity.max_record_bytes <= limits["max_record_bytes"],
         {:ok, token} <-
           Writer.reserve(s.journal_writer, Map.take(capacity, [:bytes, :events])) do
      if output_timely?(s) do
        case Writer.append_reserved(s.journal_writer, token, event) do
          :ok ->
            next = %{
              s
              | extension_result_sources: index,
                extension_output: %{token: token, id: event["output_id"], last_reply: nil}
            }

            reply = if output_timely?(next), do: {:ok, event}, else: {:error, :output_expired}
            {:reply, reply, next}

          {:error, reason} ->
            Session.journal_failed(s, reason)
        end
      else
        release_output_token(s, token)
        {:reply, {:error, :output_expired}, s}
      end
    else
      _ -> {:reply, {:error, :output_admission_refused}, s}
    end
  end

  def push_output(s, output_id, reply, active) do
    with true <- output_timely?(s),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]) do
      {:ok, current} = ResultSource.source(s.extension_result_sources, output_id)

      if ResultSource.acknowledged?(current, reply) do
        {:reply, :ok, s}
      else
        case ResultSource.index_push(s.extension_result_sources, output_id, reply) do
          {:ok, event, _source, index} ->
            record_output(s, event)

            {:reply, :ok,
             %{
               s
               | extension_result_sources: index,
                 extension_output: %{active | last_reply: reply}
             }}

          _ ->
            {:reply, {:error, :output_fragment_refused}, s}
        end
      end
    else
      _ -> {:reply, {:error, :output_fragment_refused}, s}
    end
  end

  def seal_output(s, proof, active) do
    with true <- output_timely?(s),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         {:ok, event, _source, index} <-
           ResultSource.index_accept_verified(s.extension_result_sources, active.id, proof) do
      record_output(s, event)
      {:reply, :ok, %{s | extension_result_sources: index}}
    else
      _ -> {:reply, {:error, :output_seal_refused}, s}
    end
  end

  def read_model_output(s, request) do
    if get_in(hd(s.calls), ["function", "name"]) == "saved_result_read",
      do: {:reply, readable_output(s, request, true), s},
      else: {:reply, {:error, :saved_result_read_refused}, s}
  end

  def tool_context(s, request) do
    with parent when is_map(parent) <- s.invocation.parent,
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         {:ok, _} <-
           Actions.proposal(
             %{"api_version" => 1, "kind" => "host_call", "request" => request},
             parent["identity"]
           ),
         true <- Ipse.Extension.Actions.tool?(request) do
      {:reply, {:ok, s.context_snapshot}, %{s | extension_tool_context: nil}}
    else
      _ -> {:reply, {:error, :extension_tool_context_refused}, s}
    end
  end

  def commit_tool_context(s, ref, request, old_hash, snapshot, drift) do
    with true <- old_hash == Ipse.JSON.digest([s.context_snapshot]),
         true <- Workspace.valid?(snapshot),
         true <-
           Map.take(snapshot, ~w(version cwd boundary)) ==
             Map.take(s.context_snapshot, ~w(version cwd boundary)),
         true <-
           Enum.take(snapshot["sources"], length(s.context_snapshot["sources"])) ==
             s.context_snapshot["sources"],
         :ok <- Ipse.Extension.ToolAction.validate(request) do
      if snapshot == s.context_snapshot do
        gate = %{
          request: Ipse.JSON.digest([request]),
          context: old_hash,
          job: ref,
          identity: Ipse.JSON.digest([s.invocation.parent["identity"]])
        }

        {:reply, :ok, %{s | extension_tool_context: gate, context_drift: drift}}
      else
        s =
          Session.persist_context(
            %{s | context_drift: drift, extension_tool_context: nil},
            snapshot
          )

        Session.notify(
          s,
          {:context_refreshed,
           Ipse.Session.Context.manifest(
             s.context_snapshot,
             s.context_drift,
             s.skill_drift,
             s.skills
           )}
        )

        {:reply, {:error, :review_new_workspace_instructions}, s}
      end
    else
      _ -> {:reply, {:error, :extension_tool_context_refused}, s}
    end
  end

  def prepare_mcp(s, ref, request) do
    with {:ok, limits} <- Ipse.Journal.normalize_limits(s.config[:journal]),
         true <- Ipse.Extension.EffectResult.source_record_limit() <= limits["max_record_bytes"],
         {:ok, server, tool_id} <- extension_mcp_target(s, request) do
      {:reply, {:ok, server, tool_id, s.cwd, %{owner: self(), job_ref: ref}},
       %{s | extension_mcp_context: nil}}
    else
      _ -> {:reply, {:error, :extension_mcp_refused}, s}
    end
  end

  def bind_mcp(s, ref, request, descriptor, binding) do
    with {:ok, server, tool_id} <- extension_mcp_target(s, request),
         true <- descriptor.server == server and descriptor.tool_id == tool_id,
         true <- binding == Ipse.Extension.MCPCall.binding(descriptor, request["binding"]),
         true <-
           Ipse.Extension.MCPCall.valid_binding?(
             binding,
             request,
             s.invocation.parent["identity"]
           ),
         :ok <- Ipse.MCP.validate_call(descriptor, request["arguments"]) do
      gate = %{
        request: Ipse.JSON.digest([request]),
        identity: Ipse.JSON.digest([s.invocation.parent["identity"]]),
        job: ref,
        descriptor: descriptor,
        binding: binding
      }

      {:reply, :ok, %{s | extension_mcp_context: gate}}
    else
      _ -> {:reply, {:error, :extension_mcp_refused}, %{s | extension_mcp_context: nil}}
    end
  end

  def begin_action(s, request, from, phase) do
    mutation = Ipse.Extension.Actions.mutating?(request)
    {:ok, captured_mode} = Ipse.Extension.Mode.capture(s.config)

    read_outer =
      get_in(s.invocation.parent || %{}, ["semantic_binding", "class"]) == "collection.read"

    mode =
      if read_outer and mutation,
        do: :deny,
        else: Ipse.Extension.Mode.ordinary(captured_mode, mutation)

    protected =
      (Ipse.Extension.CollectionCall.operation?(request) or
         Ipse.Extension.ManagedCollectionCall.operation?(request)) and mutation and not read_outer and
        s.invocation.parent["version"] === 3 and
        get_in(s.invocation.parent, ["semantic_binding", "class"]) == "collection.publish" and
        Ipse.Extension.Mode.knowledge(captured_mode, "collection.publish") == :ok

    approval =
      if protected,
        do: "saved_consent",
        else:
          if(mutation,
            do: if(mode == :deny, do: "denied", else: "session_allow"),
            else: "not_required"
          )

    with parent when is_map(parent) <- s.invocation.parent,
         true <- output_timely?(s),
         true <- not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         true <- Actions.allowed?(parent["identity"], request, s.invocation.results),
         true <-
           Actions.readable?(request, s.invocation.effect_sources, s.invocation.results),
         true <-
           not Ipse.Extension.Actions.question?(request) or Questions.enabled?(s.config),
         {:ok, context_hash} <- extension_action_context(s, request),
         {:ok, service} <- extension_service_context(s, request),
         {:ok, effect_binding} <- extension_effect_binding(s, request),
         :ok <- extension_model_configuration(s.config, request),
         {:ok, intent} <-
           Actions.intent(
             parent,
             request,
             s.invocation.step + 1,
             approval,
             s.cwd,
             context_hash,
             service,
             effect_binding
           ),
         :ok <- extension_effect_record_capacity(s, intent) do
      cond do
        Ipse.Extension.Actions.question?(request) ->
          Session.record(s, intent)

          reply =
            if output_timely?(s),
              do: {:question, intent},
              else: {:error, :extension_action_expired}

          {:reply, reply,
           %{
             s
             | invocation: %{
                 s.invocation
                 | action: %{intent: intent},
                   step: s.invocation.step + 1
               }
           }}

        mutation and mode == :ask and not protected ->
          approval_ref = make_ref()

          s =
            Session.begin_wait(s, "extension_action", %{
              "turn_id" => parent["payload"]["turn_id"],
              "parent_invocation_id" => parent["invocation_id"],
              "operation_id" => intent["operation_id"]
            })

          proposed = %{
            "extension" => parent["identity"]["instance"],
            "artifact_sha256" => parent["identity"]["artifact_sha256"],
            "namespace" => intent["namespace"],
            "request" => request
          }

          proposed =
            if Ipse.Extension.Actions.inference?(request) do
              {:ok, runtime, execution} = prepare_inference(s.config, request)
              {:ok, destination} = inference_destination(runtime, request)
              proposed |> Map.put("execution", execution) |> Map.put("destination", destination)
            else
              proposed
            end

          proposed =
            if effect_binding,
              do: Map.put(proposed, "effect_binding", effect_binding),
              else: proposed

          Session.notify(s, {:approval, approval_ref, "extension:" <> request["op"], proposed})

          {:noreply,
           %{
             s
             | phase: :extension_approval,
               approval: {:extension, approval_ref, from, phase},
               extension_tool_context: nil,
               invocation: %{s.invocation | action: %{intent: intent}}
           }}

        true ->
          s =
            if Ipse.Extension.SourceRead.operation?(request) or
                 Ipse.Extension.CollectionCall.operation?(request) or
                 Ipse.Extension.ManagedCollectionCall.operation?(request),
               do: Session.ensure_source_window(s),
               else: s

          {s, source} =
            cond do
              (Ipse.Extension.Actions.history?(request) or
                 Ipse.Extension.Actions.usage?(request)) and request["snapshot"] == nil ->
                {s, Session.record_source(s, intent)}

              true ->
                {Session.record_extension_action(s, intent), nil}
            end

          context = extension_execution_context(s, intent, source)

          reply =
            cond do
              not output_timely?(s) -> {:error, :extension_action_expired}
              approval == "denied" -> {:denied, intent}
              true -> {:ok, intent, context}
            end

          if Ipse.Extension.Actions.tool?(request) and match?({:ok, _, _}, reply),
            do: Session.notify(s, {:tool, "extension:tool.call", request})

          {:reply, reply,
           %{
             s
             | invocation: %{
                 s.invocation
                 | action: %{
                     intent: intent,
                     usage_read: context[:usage_read],
                     child_usage: context[:child_usage],
                     source_read: context[:source_read]
                   },
                   step: s.invocation.step + 1
               },
               extension_tool_context: nil
           }}
      end
    else
      _ -> {:reply, {:error, :extension_action_refused}, s}
    end
  end

  def bind_effect_source(s, intent, kind, data) do
    with true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <- not Map.has_key?(s.invocation.effect_sources, intent["operation_id"]),
         {:ok, source} <- Ipse.Extension.EffectResult.source(intent, kind, data) do
      Session.record(s, source)

      {:reply, {:ok, source},
       %{
         s
         | invocation: %{
             s.invocation
             | effect_sources:
                 Map.put(s.invocation.effect_sources, intent["operation_id"], source)
           }
       }}
    else
      _ -> {:reply, {:error, :extension_effect_source_refused}, s}
    end
  end

  def begin_inference(s, message, intent) do
    with true <- inference_begin?(message, intent["request"]),
         true <- output_timely?(s),
         true <- intent["approval"] in ~w(approved session_allow),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <- s.steps < Map.get(s.config, :max_steps, 30),
         true <- Ipse.Usage.capacity?(s.accounting),
         {:ok, config, execution} <- prepare_inference(s.config, intent["request"]),
         true <-
           not (EmbeddingCall.operation?(intent["request"]) or
                  DecisionCall.operation?(intent["request"])) or
             (intent["effect_binding"]["execution"] === execution and
                inference_destination(config, intent["request"]) ==
                  {:ok, intent["effect_binding"]["destination"]}),
         :ok <- extension_effect_record_capacity(s, intent) do
      admission =
        Ipse.Usage.admission(s.id, config, "extension", s.turn_id)
        |> Map.put("request_id", intent["operation_id"])

      source =
        case message do
          :extension_embedding_begin -> EmbeddingCall.source(intent, admission, execution)
          :extension_decision_begin -> DecisionCall.source(intent, admission, execution)
          :extension_model_begin -> ModelCall.source(intent, admission, execution)
        end

      s = Session.account(s, source)
      s = Session.account(s, admission)
      active = %{admission: admission, started: System.monotonic_time(:millisecond)}

      s = %{s | extension_model: active, steps: s.steps + 1}

      if output_timely?(s) do
        phase = intent["request"]["op"]

        reply =
          case Ipse.InferenceDispatch.selection(
                 s.config,
                 config,
                 phase,
                 intent["request"]["profile"]
               ) do
            {:ok, :unregistered} ->
              {:ok, config, admission}

            _ ->
              {:ok, ^config, input, tools, ^admission} = dispatch_view(s, phase)

              dispatch =
                Session.InferenceDispatch.prepare(s, config, input, tools, phase, admission)

              {:ok, config, admission, dispatch}
          end

        {:reply, reply, s}
      else
        code =
          case message do
            :extension_embedding_begin -> "embedding_request_failed"
            :extension_decision_begin -> "decision_request_failed"
            :extension_model_begin -> "model_request_failed"
          end

        {:reply, {:failed, %{"code" => code}}, Session.measure_request(s, :expired)}
      end
    else
      _ -> {:reply, {:error, :extension_model_refused}, s}
    end
  end

  @doc false
  def dispatch_view(
        %{invocation: %{action: %{intent: intent}}, extension_model: %{admission: admission}} = s,
        phase
      ) do
    request = intent["request"]

    with true <- request["op"] == phase,
         true <- intent["approval"] in ~w(approved session_allow),
         true <- output_timely?(s),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         {:ok, runtime, execution} <- prepare_inference(s.config, request),
         true <-
           not (EmbeddingCall.operation?(request) or DecisionCall.operation?(request)) or
             (intent["effect_binding"]["execution"] === execution and
                inference_destination(runtime, request) ==
                  {:ok, intent["effect_binding"]["destination"]}) do
      input =
        if phase == "model.complete",
          do: Ipse.Session.Context.helper_messages(request["instruction"], request["input"]),
          else: request

      {:ok, runtime, input, [], admission}
    else
      _ -> {:error, :inference_dispatch_refused}
    end
  end

  def dispatch_view(_, _), do: {:error, :inference_dispatch_refused}

  def observe_inference(s, message, id, usage, admission) do
    entry = s.accounting.requests[id]

    if inference_usage?(message, admission) and
         Ipse.Usage.valid_usage?(usage, Ipse.Usage.operation(admission)) and
         (entry.sequence < 64 or entry.observation == usage or message == :extension_model_usage) do
      s =
        if entry.sequence < 64 and entry.observation != usage do
          event = %{
            "type" => "request_usage_observed",
            "version" => admission["version"],
            "request_id" => id,
            "attempt_id" => admission["attempt_id"],
            "sequence" => entry.sequence + 1,
            "usage" => usage
          }

          event =
            if Ipse.Usage.operation(admission) in ["embedding", "decision"],
              do: Map.put(event, "operation", Ipse.Usage.operation(admission)),
              else: event

          Session.account(s, event)
        else
          s
        end

      {:reply, :ok, s}
    else
      {:reply, {:error, :invalid_extension_usage}, s}
    end
  end

  def finish_model(s, intent, result, capture, reason, admission) do
    assistant = if is_map(capture), do: capture.value

    {s, retained} =
      case ModelCall.response(admission, assistant) do
        {:ok, event} -> {Session.account(s, event), true}
        _ -> {s, false}
      end

    s = Session.measure_request(s, result)
    completion = s.accounting.requests[admission["request_id"]].completion

    outcome =
      cond do
        reason in ~w(model_cancelled model_timeout) ->
          {:failed, %{"code" => reason}}

        match?({:ok, _, _}, result) and not retained ->
          {:failed, %{"code" => "model_response"}}

        true ->
          ModelCall.value_from_completion(intent["request"], admission, completion, assistant)
      end

    {:reply, outcome, s}
  end

  def finish_embedding(s, intent, result, capture, reason, admission, started),
    do:
      finish_bounded_inference(s, intent, result, capture, reason, admission, started, :embedding)

  def finish_decision(s, intent, result, capture, reason, admission, started),
    do:
      finish_bounded_inference(s, intent, result, capture, reason, admission, started, :decision)

  defp finish_bounded_inference(s, intent, result, capture, reason, admission, started, kind) do
    adapter = if kind == :embedding, do: EmbeddingCall, else: DecisionCall
    operation = Atom.to_string(kind)

    if adapter.operation?(intent["request"]) and
         Ipse.Usage.operation(admission) == operation do
      valid_capture = bounded_capture?(capture, intent, kind)
      s = if valid_capture, do: observe_bound_capture(s, admission, capture.usage), else: s
      observed = s.accounting.requests[admission["request_id"]].observation

      completion =
        Ipse.Usage.completion(
          admission,
          result,
          max(System.monotonic_time(:millisecond) - started, 0),
          observed
        )

      source =
        with true <- valid_capture,
             {:ok, payload, raw} <- result,
             true <-
               payload === capture.value and
                 Ipse.Usage.observation(admission, raw, 1)["usage"] === capture.usage,
             {:ok, source} <- adapter.response(intent, admission, completion, payload),
             do: source

      {s, source} =
        if is_map(source) do
          s = Session.account(s, source)

          {%{
             s
             | invocation: %{
                 s.invocation
                 | effect_sources:
                     Map.put(s.invocation.effect_sources, intent["operation_id"], source)
               }
           }, source}
        else
          {s, nil}
        end

      s = Session.account(s, completion)
      s = %{s | extension_model: nil}

      outcome =
        cond do
          reason in [operation <> "_cancelled", operation <> "_timeout"] ->
            {:failed, %{"code" => reason}}

          match?({:ok, _, _}, result) and is_nil(source) ->
            {:failed, %{"code" => operation <> "_response"}}

          true ->
            adapter.value_from_completion(intent, admission, completion, source)
        end

      {:reply, outcome, s}
    else
      {:reply, {:error, :extension_inference_refused}, s}
    end
  end

  def commit_action(s, event, intent) do
    with true <- Actions.result_intent(event) == intent and Actions.valid_result?(event),
         true <-
           Ipse.Extension.SourceRead.bound_prepared?(
             intent["request"],
             event,
             Map.get(s.invocation.action, :source_read)
           ),
         true <-
           not Ipse.Extension.SourceRead.operation?(intent["request"]) or
             Ipse.Extension.SourceRead.bound_prepared?(
               intent["request"],
               event,
               Ipse.Extension.SourceRead.prepare(s, intent["request"]["op"], intent["request"])
             ),
         true <-
           Actions.bound_effect?(event, s.invocation.effect_sources, s.invocation.results),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <-
           is_nil(intent["service"]) or
             Ipse.Extension.Registry.live?(intent["service"]["identity"]),
         {:ok, usage_reads} <- commit_usage_read(s, intent, event),
         {:ok, child_usage} <- commit_child_usage(s, intent, event),
         {:ok, contributions} <-
           Ipse.Extension.Context.apply_result(
             s.extension_contributions,
             s.invocation.parent,
             s.invocation.results,
             event,
             if(s.reference, do: Ipse.Session.Reference.layout())
           ) do
      s = Session.record_extension_action(s, event)

      if Ipse.Extension.Actions.tool?(intent["request"]),
        do:
          Session.notify(
            s,
            {:tool_result, "extension:tool.call", Jason.encode!(event["outcome"])}
          )

      {:reply, {:ok, Actions.resume(event)},
       %{
         s
         | invocation: %{
             s.invocation
             | action: nil,
               interrupted: event["outcome"]["status"] == "unknown",
               results: s.invocation.results ++ [event]
           },
           extension_mcp_context: nil,
           usage_reads: usage_reads,
           child_usage: child_usage,
           extension_contributions: contributions
       }}
    else
      _ -> {:reply, {:error, :invalid_extension_action}, s}
    end
  end

  def approve(s, allowed, caller, phase, action) do
    intent =
      Map.put(action.intent, "approval", if(allowed == true, do: "approved", else: "denied"))

    {:ok, mode} = Ipse.Extension.Mode.capture(s.config)

    allowed =
      allowed == true and
        not (get_in(s.invocation.parent, ["semantic_binding", "class"]) == "collection.read" and
               Actions.mutating?(intent["request"])) and
        Ipse.Extension.Mode.ordinary(mode, Actions.mutating?(intent["request"])) != :deny

    intent = Map.put(intent, "approval", if(allowed, do: "approved", else: "denied"))

    if output_timely?(s) and Ipse.Extension.Registry.live?(s.invocation.parent["identity"]) do
      s = Session.record_extension_action(s, intent)
      s = Session.finish_wait(s, if(allowed == true, do: "approved", else: "denied"))

      reply =
        cond do
          not output_timely?(s) -> {:error, :extension_action_expired}
          allowed == true -> {:ok, intent, extension_execution_context(s, intent)}
          true -> {:denied, intent}
        end

      GenServer.reply(caller, reply)

      if match?({:ok, _, _}, reply) and Ipse.Extension.Actions.tool?(intent["request"]),
        do: Session.notify(s, {:tool, "extension:tool.call", intent["request"]})

      {:reply, :ok,
       %{
         s
         | approval: nil,
           phase: phase,
           invocation: %{s.invocation | action: %{intent: intent}, step: s.invocation.step + 1}
       }}
    else
      s = Session.finish_wait(s, "expired")
      GenServer.reply(caller, {:error, :extension_action_expired})
      {:reply, :ok, %{s | approval: nil, phase: phase, invocation: %{s.invocation | action: nil}}}
    end
  end

  def answer(s, answers, question) do
    with {:ok, _} <- Questions.validate_answers(question.arguments, answers),
         true <- Ipse.Extension.Registry.live?(question.parent["identity"]),
         {:ok, result} <-
           Actions.result(question.action, %{
             "status" => "answered",
             "value" => %{"answers" => answers}
           }),
         {:ok, entry, _} <-
           Catalog.lookup(
             s.config,
             question.parent["descriptor"]["stage"],
             question.parent["descriptor"]["name"]
           ),
         true <- entry.identity == question.parent["identity"] do
      s = Session.enroll_feeds(s)
      results = question.results ++ [result]
      Session.record(s, result)
      Session.record(s, Actions.continuation(question.parent, result))
      s = Session.finish_wait(s, "answered")
      entry = Map.merge(entry, %{host_config: s.config, host_cwd: s.cwd})
      owner = self()
      job_ref = make_ref()

      task =
        Session.owned_task(fn ->
          Host.resume_export(entry, question.parent, result, owner, job_ref, results)
        end)

      phase = invocation_phase(question.parent)

      {:reply, :ok,
       %{
         s
         | question: nil,
           phase: phase,
           task: task,
           job_ref: job_ref,
           invocation: %{
             s.invocation
             | parent: question.parent,
               action: nil,
               step: question.action["step"],
               results: results,
               interrupted: false
           },
           tool_decision: question.parent["approval"]
       }}
    else
      _ -> {:reply, {:error, :invalid_extension_answer_or_expired}, s}
    end
  end

  @doc false
  def commit_event_job(s, event) do
    with parent when is_map(parent) <- s.invocation.parent,
         delivery when is_map(delivery) <- s.event_intent,
         true <- is_nil(s.invocation.action) and not s.invocation.interrupted,
         true <-
           Invocation.event_matches?(
             parent,
             delivery,
             s.event_received.record,
             s.event_committed.record,
             if(s.event_answer, do: s.event_answer.record)
           ),
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         {:ok, expected} <-
           Invocation.build_result(
             parent,
             %{"api_version" => 1, "kind" => "result", "value" => event["value"]},
             s.invocation.results
           ),
         true <- expected == event do
      Session.record(s, event)
      outcome = Invocation.event_outcome(s.invocation.results)
      Session.record(s, Subscriptions.result(delivery, outcome, true))

      if outcome == "failed" and not delivery["declaration"]["required"],
        do:
          Session.notify(
            s,
            {:status,
             "Optional event job had a refused or failed action; inspect its saved receipts."}
          )

      {:ok,
       %{
         s
         | invocation: %CurrentInvocation{},
           extension_mcp_context: nil,
           event_intent: nil
       }, outcome}
    else
      _ -> {:error, :event_job_result_refused}
    end
  end

  defp output_clock(entry, stage, job_ref) do
    identity = entry.identity

    if Ipse.Extension.ResultPublication.eligible?(
         identity["sdk"],
         identity["capabilities"],
         stage
       ) do
      started = System.monotonic_time(:millisecond)
      timer = Process.send_after(self(), {:extension_output_deadline, job_ref}, 120_000)
      {%{started_ms: started, timer: timer}, Map.put(entry, :output_started_ms, started)}
    else
      {nil, entry}
    end
  end

  @doc false
  def output_elapsed(%{extension_output_clock: %{started_ms: started}}),
    do: System.monotonic_time(:millisecond) - started

  @doc false
  def output_timely?(%{extension_output_clock: nil}), do: true
  @doc false
  def output_timely?(s), do: output_elapsed(s) in 0..119_999

  defp release_output_token(s, token) do
    case Writer.release(s.journal_writer, token) do
      :ok -> :ok
      {:error, reason} -> Session.journal_failed(s, reason)
    end
  end

  @doc false
  def release_output(s) do
    if s.extension_output_clock, do: Process.cancel_timer(s.extension_output_clock.timer)
    if s.extension_output, do: release_output_token(s, s.extension_output.token)
    %{s | extension_output: nil, extension_output_clock: nil}
  end

  @doc false
  def record_output(s, event, observed \\ false) do
    token = s.extension_output.token

    result =
      if observed and
           ((s.observation != nil and s.observation.policy["mode"] != "off") or
              Feeds.active?(s.feeds)),
         do: Writer.append_reserved_observed(s.journal_writer, token, event),
         else: Writer.append_reserved(s.journal_writer, token, event)

    case result do
      :ok ->
        if observed, do: release_output(s), else: s

      {:ok, source} ->
        next = release_output(s)
        Session.offer_record(next, source, event)
        next

      {:error, reason} ->
        Session.journal_failed(s, reason)
    end
  end

  @doc false
  def complete_invocation_result(s, event) do
    s = release_output(s)
    s = %{s | invocation: %{s.invocation | parent: nil, request: nil}}

    if s.phase == :tool do
      Turn.accept_tool_result(s, hd(s.calls), Invocation.tool_message(event))
    else
      display =
        Map.merge(
          %{"name" => event["descriptor"]["name"], "stage" => event["descriptor"]["stage"]},
          Invocation.delivery(event)
        )

      Session.notify(s, {:extension_result, display})
      Turn.finish(%{s | extension_result: display}, :ok)
    end
  end

  @doc false
  def readable_output(s, request, model?) do
    with {:ok, source} <-
           ResultSource.source(
             s.extension_result_sources,
             ResultSource.request_output_id(request)
           ),
         true <- not model? or source.intent["descriptor"]["stage"] == "invoke.tool",
         delivery = ResultSource.descriptor(source),
         {:ok, source} <- ResultSource.readable_source(s.extension_result_sources, delivery) do
      {:ok, source, delivery}
    else
      _ -> {:error, :saved_result_read_refused}
    end
  end

  @doc false
  def invocation_phase(parent) do
    case parent["descriptor"]["stage"] do
      "invoke.tool" -> :tool
      "invoke.command" -> :extension_command
      "invoke.service" -> :extension_service
      "event.job" -> :extension_events
    end
  end

  defp extension_mcp_target(s, request) do
    with parent when is_map(parent) <- s.invocation.parent,
         true <- get_in(parent, ["semantic_binding", "class"]) != "collection.read",
         true <- not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         {:ok, ^request} <-
           Actions.proposal(
             %{"api_version" => 1, "kind" => "host_call", "request" => request},
             parent["identity"]
           ),
         true <- Actions.allowed?(parent["identity"], request, s.invocation.results) do
      Ipse.Extension.MCPCall.target(s.config, parent["identity"], request)
    else
      _ -> {:error, :extension_mcp_refused}
    end
  end

  defp extension_effect_binding(s, request) do
    cond do
      Ipse.Extension.ManagedCollectionCall.operation?(request) ->
        Ipse.Extension.ManagedCollectionCall.binding(s.config, s.invocation.parent, request)

      Ipse.Extension.CollectionCall.operation?(request) ->
        Ipse.Extension.CollectionCall.binding(s.config, s.invocation.parent["identity"], request)

      DecisionCall.operation?(request) ->
        DecisionCall.binding(s.config, request)

      EmbeddingCall.operation?(request) ->
        EmbeddingCall.binding(s.config, request)

      Ipse.Extension.Actions.mcp?(request) ->
        gate = s.extension_mcp_context

        if is_map(gate) and gate.job == s.job_ref and
             gate.request == Ipse.JSON.digest([request]) and
             gate.identity == Ipse.JSON.digest([s.invocation.parent["identity"]]),
           do: {:ok, gate.binding},
           else: {:error, :extension_mcp_not_bound}

      Ipse.Extension.Actions.result_read?(request) ->
        {:ok, Ipse.Extension.EffectResult.binding(request)}

      true ->
        {:ok, nil}
    end
  end

  defp extension_action_context(s, request) do
    if Ipse.Extension.Actions.tool?(request) do
      expected = %{
        request: Ipse.JSON.digest([request]),
        context: Ipse.JSON.digest([s.context_snapshot]),
        job: s.job_ref,
        identity: Ipse.JSON.digest([s.invocation.parent["identity"]])
      }

      if s.extension_tool_context == expected,
        do: {:ok, expected.context},
        else: {:error, :tool_context_not_reviewed}
    else
      {:ok, nil}
    end
  end

  defp extension_service_context(s, request) do
    if Ipse.Extension.Actions.service?(request) do
      with {:ok, entry, context} <-
             Ipse.Extension.Services.lookup(
               s.config,
               s.invocation.parent["identity"],
               request
             ),
           true <- Ipse.Extension.Registry.live?(entry.identity) do
        {:ok, context}
      else
        _ -> {:error, :service_unavailable}
      end
    else
      {:ok, nil}
    end
  end

  defp extension_execution_context(s, intent, source \\ nil) do
    context = %{
      root: Path.join(s.context_home, "extension-state-v1"),
      cwd: s.cwd,
      sandbox: Map.get(s.config, :sandbox, :off),
      parallel_child: Map.get(s.config, :parallel_child, false),
      contributions: s.extension_contributions,
      reference_layout: if(s.reference, do: Ipse.Session.Reference.layout()),
      identity: s.invocation.parent["identity"],
      actions: s.invocation.results
    }

    context =
      if Ipse.Extension.CollectionCall.operation?(intent["request"]) or
           Ipse.Extension.ManagedCollectionCall.operation?(intent["request"]),
         do:
           Map.merge(context, %{
             config: s.config,
             session_id: s.id,
             parent: s.invocation.parent,
             owner: self(),
             job_ref: s.job_ref
           }),
         else: context

    context =
      if s.extension_output_clock,
        do: Map.put(context, :output_deadline_ms, s.extension_output_clock.started_ms + 120_000),
        else: context

    context =
      if Ipse.Extension.Actions.inference?(intent["request"]),
        do: Map.merge(context, %{owner: self(), job_ref: s.job_ref}),
        else: context

    context =
      if Ipse.Extension.Actions.mcp?(intent["request"]),
        do:
          Map.merge(context, %{
            owner: self(),
            job_ref: s.job_ref,
            mcp_descriptor: s.extension_mcp_context.descriptor
          }),
        else: context

    context =
      if Ipse.Extension.Actions.result_read?(intent["request"]) do
        {:ok, effect_source} =
          Actions.effect_source(
            intent["request"],
            s.invocation.effect_sources,
            s.invocation.results
          )

        Map.put(context, :effect_source, effect_source)
      else
        context
      end

    context =
      if Ipse.Extension.Actions.history?(intent["request"]),
        do: Map.merge(context, %{history_dir: s.dir, history_session: s.id}),
        else: context

    context =
      if Ipse.Extension.SourceRead.operation?(intent["request"]),
        do:
          Map.put(
            context,
            :source_read,
            Ipse.Extension.SourceRead.prepare(s, intent["request"]["op"], intent["request"])
          ),
        else: context

    context =
      if source != nil and Ipse.Extension.Actions.history?(intent["request"]),
        do: Map.put(context, :history_snapshot, Ipse.Extension.History.snapshot(source, intent)),
        else: context

    context =
      if Ipse.Extension.UsageRead.operation?(intent["request"]),
        do:
          Map.put(
            context,
            :usage_read,
            Ipse.Extension.UsageRead.prepare(
              s.accounting,
              s.usage_reads,
              intent,
              if(source, do: elem(Ipse.Journal.source_metadata(source), 1))
            )
          ),
        else: context

    context =
      if Ipse.Extension.ChildUsage.operation?(intent["request"]) do
        Map.put(
          context,
          :child_usage,
          Ipse.Extension.ChildUsage.context(
            s.child_usage,
            intent,
            s.dir,
            if(source, do: elem(Ipse.Journal.source_metadata(source), 1))
          )
        )
      else
        context
      end

    if intent["service"] do
      target = Enum.find(s.config.extensions, &(&1.identity == intent["service"]["identity"]))
      Map.merge(context, %{service_entry: target, session_id: s.id, turn_id: s.turn_id})
    else
      context
    end
  end

  defp inference_begin?(:extension_model_begin, request), do: ModelCall.operation?(request)

  defp inference_begin?(:extension_embedding_begin, request),
    do: EmbeddingCall.operation?(request)

  defp inference_begin?(:extension_decision_begin, request),
    do: DecisionCall.operation?(request)

  defp inference_usage?(:extension_model_usage, admission),
    do: Ipse.Usage.operation(admission) == "text"

  defp inference_usage?(:extension_embedding_usage, admission),
    do: Ipse.Usage.operation(admission) == "embedding"

  defp inference_usage?(:extension_decision_usage, admission),
    do: Ipse.Usage.operation(admission) == "decision"

  defp bounded_capture?(%{value: value, usage: usage}, intent, :embedding) do
    Ipse.Provider.Embedding.valid_result?(
      value,
      intent["effect_binding"]["execution"],
      intent["request"]["inputs"]
    ) and
      Ipse.Usage.valid_usage?(usage, "embedding")
  end

  defp bounded_capture?(%{value: value, usage: usage}, intent, :decision) do
    Ipse.Provider.Decision.Transport.valid_result?(
      value,
      intent["effect_binding"]["execution"],
      DecisionCall.neutral(intent["request"])
    ) and
      Ipse.Usage.valid_usage?(usage, "decision")
  end

  defp bounded_capture?(_, _, _), do: false

  defp observe_bound_capture(s, admission, usage) do
    entry = s.accounting.requests[admission["request_id"]]

    cond do
      entry.observation === usage ->
        s

      entry.sequence < 64 ->
        Session.account(s, %{
          "type" => "request_usage_observed",
          "version" => admission["version"],
          "operation" => Ipse.Usage.operation(admission),
          "request_id" => admission["request_id"],
          "attempt_id" => admission["attempt_id"],
          "sequence" => entry.sequence + 1,
          "usage" => usage
        })

      true ->
        raise "Inference observation allowance exhausted"
    end
  end

  defp prepare_inference(config, %{"op" => "embedding.create"} = request),
    do: Ipse.Config.Profiles.prepare_embedding(config, request)

  defp prepare_inference(config, %{"op" => "decision.create"} = request),
    do: Ipse.Config.Decisions.prepare(config, request)

  defp prepare_inference(config, request), do: ModelCall.prepare(config, request)

  defp inference_destination(config, %{"op" => "decision.create"}),
    do: Ipse.Provider.Decision.Transport.destination(config)

  defp inference_destination(config, _), do: Ipse.Provider.destination(config)

  defp extension_effect_record_capacity(_s, %{"approval" => "denied"}), do: :ok

  defp extension_effect_record_capacity(s, intent) do
    request = intent["request"]

    result =
      cond do
        DecisionCall.operation?(request) ->
          {:ok, %{max_record_bytes: 65_536}}

        EmbeddingCall.operation?(request) ->
          with {:ok, config, execution} <- prepare_inference(s.config, request) do
            admission =
              Ipse.Usage.admission(s.id, config, "extension", s.turn_id)
              |> Map.put("request_id", intent["operation_id"])

            Ipse.Extension.EffectResult.embedding_capacity(intent, admission, execution)
          end

        Ipse.Extension.MCPCall.operation?(request) ->
          Ipse.Extension.EffectResult.mcp_capacity(intent)

        true ->
          {:ok, %{max_record_bytes: 0}}
      end

    with {:ok, capacity} <- result,
         {:ok, limits} <- Ipse.Journal.normalize_limits(s.config[:journal]),
         true <- capacity.max_record_bytes <= limits["max_record_bytes"] do
      :ok
    else
      _ -> {:error, :effect_record_capacity}
    end
  end

  defp extension_model_configuration(config, request) do
    if Ipse.Extension.Actions.inference?(request) do
      case prepare_inference(config, request) do
        {:ok, _, _} -> :ok
        _ -> {:error, :invalid_extension_model_configuration}
      end
    else
      :ok
    end
  end

  defp commit_usage_read(s, intent, event) do
    if Ipse.Extension.UsageRead.operation?(intent["request"]),
      do:
        Ipse.Extension.UsageRead.commit(
          s.usage_reads,
          intent,
          event,
          s.invocation.action.usage_read
        ),
      else: {:ok, s.usage_reads}
  end

  defp commit_child_usage(s, intent, event) do
    if Ipse.Extension.ChildUsage.operation?(intent["request"]) do
      Ipse.Extension.ChildUsage.commit(
        s.child_usage,
        intent,
        event,
        s.invocation.action.child_usage.source
      )
    else
      {:ok, s.child_usage}
    end
  end

  @doc false
  def suspend_for_question(s, invocation_phase, action) do
    with %{intent: ^action} <- s.invocation.action,
         true <- output_timely?(s),
         true <- Questions.enabled?(s.config),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]) do
      s = release_output(s)
      parent = s.invocation.parent

      next =
        if invocation_phase == :tool,
          do:
            Turn.settle_calls(
              %{s | calls: tl(s.calls), phase: :idle},
              "Not started while extension clarification is required."
            ),
          else: s

      call = if invocation_phase == :tool, do: hd(s.calls)

      question = %{
        kind: :extension,
        id: action["operation_id"],
        arguments: action["request"]["arguments"],
        parent: parent,
        action: action,
        results: s.invocation.results,
        steps: s.steps,
        call: call
      }

      event = Actions.question_event(parent, action, s.steps)
      source = Session.record_wait_subject(next, event)
      Session.checkpoint_event_question(next, question)
      if source, do: Session.offer_record(next, source, event)
      next = Session.question_wait(next, question, source)
      Session.notify(next, {:question, question.id, question.arguments})

      {:noreply,
       %{
         next
         | question: question,
           phase: :question,
           task: nil,
           job_ref: nil,
           calls: if(call, do: [call], else: [])
       }}
    else
      _ ->
        {:noreply,
         Turn.fail(
           s,
           "Extension question could not be committed; no answer or continuation was selected."
         )}
    end
  end

  @doc false
  def complete_event_job(s, event) do
    delivery = s.event_intent

    case commit_event_job(s, event) do
      {:ok, next, outcome} ->
        if outcome == "completed" or not delivery["declaration"]["required"],
          do: {:noreply, Turn.continue_event_plan(next, delivery)},
          else:
            {:noreply,
             Turn.fail(
               next,
               "Required event job had a refused or failed action; inspect its receipts."
             )}

      _ ->
        {:noreply,
         Turn.fail(
           s,
           "Event job result was invalid or expired; inspect its saved receipts before retrying."
         )}
    end
  end

  @doc false
  def publish_saved_result(s, delivery) do
    with intent when is_map(intent) <- s.invocation.parent,
         true <- s.extension_output != nil and s.extension_output_clock != nil,
         true <- output_timely?(s) and is_nil(s.invocation.action),
         true <- not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(intent["identity"]),
         {:ok, event} <-
           Invocation.build_saved_result(
             intent,
             delivery,
             s.invocation.results,
             output_elapsed(s)
           ),
         {:ok, index} <- ResultSource.publish(s.extension_result_sources, event) do
      next =
        record_output(%{s | extension_result_sources: index}, event, true)

      {:noreply, complete_invocation_result(next, event)}
    else
      _ ->
        {:noreply, Turn.fail(s, "Saved result publication refused; inspect its source receipts.")}
    end
  end

  @doc false
  def publish_inline_result(s, event) do
    with intent when is_map(intent) <- s.invocation.parent,
         true <- output_timely?(s) and is_nil(s.extension_output),
         true <- is_nil(s.invocation.action),
         true <- not s.invocation.interrupted,
         {:ok, expected} <-
           Invocation.build_result(
             intent,
             %{
               "api_version" => 1,
               "kind" => "result",
               "value" => event["value"]
             },
             s.invocation.results
           ),
         true <- expected == event and Ipse.Extension.Registry.live?(intent["identity"]) do
      Session.record(s, event)
      {:noreply, complete_invocation_result(s, event)}
    else
      _ ->
        {:noreply,
         Turn.fail(
           s,
           "Extension result was invalid or its lease expired; inspect the saved intent before retrying."
         )}
    end
  end
end
