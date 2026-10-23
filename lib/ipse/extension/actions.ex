defmodule Ipse.Extension.Actions do
  @moduledoc "Typed finite host-call continuations with source-bound durable operation receipts."

  @keys ~w(type version parent_invocation_id operation_id step identity_sha256 namespace context_sha256 service request request_sha256 approval)
  @types ~w(extension_action_intent extension_action_result)
  @error {:error, :invalid_extension_action}
  @limit 16
  @read_limit 10_000
  @diagnostic_types Ipse.Observability.types()
  def types, do: @types
  def limit, do: @limit

  def limit(identity) do
    cond do
      "host.actions.mixed" in identity["capabilities"] -> 528
      "host.usage.scan" in identity["capabilities"] -> @read_limit
      "host.state.scan" in identity["capabilities"] -> 512
      "host.results" in identity["capabilities"] -> 512
      true -> @limit
    end
  end

  def limit(identity, request) do
    cond do
      "host.actions.mixed" in identity["capabilities"] ->
        528

      result_read?(request) and "host.results" in identity["capabilities"] ->
        512

      usage?(request) and "host.usage.scan" in identity["capabilities"] ->
        @read_limit

      request["op"] in ~w(state.get state.list state.scan) and
          "host.state.scan" in identity["capabilities"] ->
        512

      true ->
        @limit
    end
  end

  def allowed?(identity, request, results) when is_list(results) do
    if "host.actions.mixed" in identity["capabilities"] do
      reads = Enum.count(results, &read?(&1["request"]))
      others = length(results) - reads

      length(results) < 528 and
        if(read?(request), do: reads < 512, else: others < 16)
    else
      length(results) < limit(identity, request)
    end
  rescue
    _ -> false
  end

  def allowed?(_, _, _), do: false

  defp read?(%{"op" => op}),
    do:
      op in ~w(state.get state.list state.scan history.read usage.read usage.children usage.child.read effect.result.read)

  defp read?(_), do: false

  def proposal(response, identity) do
    with :ok <- Ipse.Extension.validate(response),
         true <- Ipse.Extension.Registry.valid_identity?(identity),
         true <- Enum.sort(Map.keys(response)) == ~w(api_version kind request),
         true <- response["api_version"] === 1 and response["kind"] == "host_call",
         :ok <- validate_operation(response["request"]),
         true <- "host.actions" in identity["capabilities"],
         true <-
           not history?(response["request"]) or
             "host.history" in identity["capabilities"],
         true <- capability(response["request"]) in identity["capabilities"] do
      {:ok, response["request"]}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def intent(
        parent,
        request,
        step,
        approval,
        cwd,
        context_sha256 \\ nil,
        service \\ nil,
        effect_binding \\ nil
      ) do
    with {:ok, namespace} <-
           namespace(
             parent["identity"],
             request,
             cwd,
             parent["payload"]["session_id"]
           ) do
      event = %{
        "type" => "extension_action_intent",
        "version" => 1,
        "parent_invocation_id" => parent["invocation_id"],
        "operation_id" => Ipse.Usage.id(),
        "step" => step,
        "identity_sha256" => Ipse.JSON.digest([parent["identity"]]),
        "namespace" => namespace,
        "context_sha256" => context_sha256,
        "service" => service,
        "request" => request,
        "request_sha256" => Ipse.JSON.digest([request]),
        "approval" => approval
      }

      event =
        if version_two?(parent["identity"], request),
          do: event |> Map.put("version", 2) |> Map.put("effect_binding", effect_binding),
          else: event

      if valid_intent?(event, parent, cwd), do: {:ok, event}, else: @error
    end
  rescue
    _ -> @error
  end

  def result(intent, outcome) do
    event =
      Map.merge(intent, %{
        "type" => "extension_action_result",
        "outcome" => outcome,
        "outcome_sha256" => Ipse.JSON.digest([outcome])
      })

    if valid_result?(event), do: {:ok, event}, else: @error
  end

  def resume(event) do
    payload = %{
      "api_version" => 1,
      "invocation_id" => event["parent_invocation_id"],
      "operation_id" => event["operation_id"],
      "step" => event["step"],
      "outcome" => event["outcome"]
    }

    if question?(event["request"]) or service?(event["request"]),
      do: Map.put(payload, "checkpoint", event["request"]["checkpoint"]),
      else: payload
  end

  def result_intent(event),
    do:
      event |> Map.drop(~w(outcome outcome_sha256)) |> Map.put("type", "extension_action_intent")

  def valid_result?(event) do
    outcome = event["outcome"]

    keys?(event, intent_keys(event) ++ ~w(outcome outcome_sha256)) and
      event["type"] == "extension_action_result" and
      event["outcome_sha256"] == Ipse.JSON.digest([outcome]) and
      keys?(outcome, ~w(status value)) and
      outcome["status"] in ~w(ok conflict denied unknown answered cancelled failed) and
      outcome["status"] == "denied" == (event["approval"] == "denied") and
      valid_outcome?(
        event["request"],
        outcome["status"],
        outcome["value"],
        event["operation_id"],
        event["service"]
      ) and
      (not history?(event["request"]) or Ipse.Extension.History.bound_outcome?(event)) and
      Ipse.Extension.validate(resume(event)) == :ok and bounded?(event)
  rescue
    _ -> false
  end

  def valid_intent?(event, parent, cwd) do
    with true <- keys?(event, intent_keys(event)),
         true <- event["type"] == "extension_action_intent",
         true <-
           event["version"] ===
             if(version_two?(parent["identity"], event["request"]), do: 2, else: 1),
         true <- event["parent_invocation_id"] == parent["invocation_id"],
         true <-
           id?(event["operation_id"]) and is_integer(event["step"]) and
             event["step"] in 1..limit(parent["identity"], event["request"]),
         true <- event["identity_sha256"] == Ipse.JSON.digest([parent["identity"]]),
         {:ok, request} <-
           proposal(
             %{"api_version" => 1, "kind" => "host_call", "request" => event["request"]},
             parent["identity"]
           ),
         true <- event["request_sha256"] == Ipse.JSON.digest([request]),
         true <- effect_binding?(event, parent["identity"]),
         {:ok, namespace} <-
           namespace(
             parent["identity"],
             request,
             cwd,
             parent["payload"]["session_id"]
           ),
         true <- event["namespace"] == namespace,
         true <-
           if(service?(request),
             do:
               Ipse.Extension.Services.valid_binding?(
                 parent["identity"],
                 request,
                 event["service"]
               ),
             else: is_nil(event["service"])
           ),
         true <-
           if(tool?(request),
             do: Ipse.JSON.sha256?(event["context_sha256"]),
             else: is_nil(event["context_sha256"])
           ),
         true <-
           event["approval"] in if(mutating?(request),
             do: ~w(approved session_allow denied),
             else: ["not_required"]
           ),
         true <- bounded?(event) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def validate_events(events) do
    case restore(events) do
      {:ok, _} -> :ok
      _ -> @error
    end
  end

  def restore([%{"metadata" => metadata} | _] = events) do
    :ok = Ipse.Journal.validate_limit_events(events)
    {:ok, _} = Ipse.Session.RuntimeLifecycle.restore(events)
    :ok = Ipse.Observability.validate_events(events)
    :ok = Ipse.Extension.Subscriptions.validate_events(events)
    {:ok, catalog} = Ipse.Extension.Catalog.from_metadata(metadata)
    :ok = Ipse.Extension.Services.validate_metadata(Map.get(metadata, "extensions", []), catalog)
    {:ok, usage_reads} = Ipse.Extension.UsageRead.restore(events)
    {:ok, child_usage} = Ipse.Extension.ChildUsage.restore(events)

    initial = %{
      parent: nil,
      usage_reads: usage_reads,
      child_usage: child_usage,
      action: nil,
      step: 0,
      seen: MapSet.new(),
      unknown: false,
      results_rev: [],
      question: nil,
      resume_needed: nil,
      context_sha256: nil,
      contributions: %{},
      context_request: nil,
      identities: Map.new(Map.get(metadata, "extensions", []), &{&1["instance"], &1}),
      catalog: catalog,
      metadata: metadata,
      effect_sources: %{}
    }

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
      case validate_event(event, state, metadata["cwd"]) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, @error}
      end
    end)
    |> case do
      {:ok, state} ->
        {reversed, state} = Map.pop!(state, :results_rev)
        {:ok, Map.put(state, :results, Enum.reverse(reversed))}

      error ->
        error
    end
  rescue
    _ -> @error
  end

  def restore(_), do: @error

  def question_event(parent, action, steps) do
    event = %{
      "type" => "extension_question",
      "version" => 1,
      "parent_invocation_id" => parent["invocation_id"],
      "operation_id" => action["operation_id"],
      "steps" => steps
    }

    Map.put(event, "question_sha256", Ipse.JSON.digest([event]))
  end

  def continuation(parent, result) do
    %{
      "type" => "extension_continuation_intent",
      "version" => 1,
      "parent_invocation_id" => parent["invocation_id"],
      "operation_id" => result["operation_id"],
      "continuation_id" => Ipse.Usage.id(),
      "result_sha256" => Ipse.JSON.digest([result])
    }
  end

  defp validate_event(%{"type" => type}, state, _)
       when type in @diagnostic_types,
       do: {:ok, state}

  defp validate_event(%{"type" => "lifecycle_question_sources"}, state, _),
    do: {:ok, state}

  defp validate_event(%{"type" => "journal_limit_reached"} = event, state, _),
    do: if(Ipse.Journal.valid_limit_receipt?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => type}, state, _)
       when type in ~w(extension_text_intent extension_text_ready extension_text_closed),
       do: {:ok, state}

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(lifecycle_epoch_started lifecycle_epoch_closed lifecycle_wait_started lifecycle_wait_finished lifecycle_recording_stopped),
       do: if(Ipse.Session.RuntimeLifecycle.valid_record?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(extension_feed_intent extension_feed_ready extension_feed_delivery_intent extension_feed_delivery_result extension_feed_closed),
       do: if(Ipse.Extension.Feeds.valid_record?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(lifecycle_tool_intent lifecycle_tool_outcome lifecycle_tool_recording_stopped),
       do: if(Ipse.Session.ToolLifecycle.valid?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => "delegation_finished"} = event, state, _),
    do: if(Ipse.Tools.Delegation.valid_child_record?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => "extension_invocation_intent"} = event, state, _) do
    if is_nil(state.parent),
      do:
        {:ok,
         %{
           state
           | parent: event,
             action: nil,
             step: 0,
             unknown: false,
             results_rev: [],
             effect_sources: %{},
             question: nil,
             resume_needed: nil
         }},
      else: @error
  end

  defp validate_event(%{"type" => "extension_invocation_result"} = event, state, _) do
    if state.parent != nil and event["invocation_id"] == state.parent["invocation_id"] and
         is_nil(state.action) and not state.unknown and
         is_nil(state.resume_needed) and is_nil(state.question) and
         event["action_count"] == state.step and
         event["actions_sha256"] == Ipse.JSON.digest(Enum.reverse(state.results_rev)),
       do: {:ok, %{state | parent: nil}},
       else: @error
  end

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(extension_output_begin extension_output_chunk extension_output_seal) do
    if state.parent != nil and event["invocation_id"] == state.parent["invocation_id"] and
         is_nil(state.action) and not state.unknown and is_nil(state.resume_needed) and
         is_nil(state.question),
       do: {:ok, state},
       else: @error
  end

  defp validate_event(%{"type" => "extension_action_intent"} = event, state, cwd) do
    if state.parent != nil and is_nil(state.action) and not state.unknown and
         is_nil(state.resume_needed) and is_nil(state.question) and
         event["step"] == state.step + 1 and
         not MapSet.member?(state.seen, event["operation_id"]) and
         valid_intent?(event, state.parent, cwd) and
         allowed?(state.parent["identity"], event["request"], state.results_rev) do
      if (not tool?(event["request"]) or event["context_sha256"] == state.context_sha256) and
           service_source?(event, state) and
           effect_binding?(event, state.parent["identity"], state.metadata) and
           readable?(event["request"], state.effect_sources, state.results_rev) do
        {:ok,
         %{
           state
           | action: event,
             step: event["step"],
             seen: MapSet.put(state.seen, event["operation_id"])
         }}
      else
        @error
      end
    else
      @error
    end
  end

  defp validate_event(%{"type" => "extension_action_result"} = event, state, _) do
    question = question?(event["request"])

    with true <-
           state.action != nil and result_intent(event) == state.action and valid_result?(event),
         true <- bound_effect?(event, state.effect_sources, state.results_rev),
         true <- not question or not is_nil(state.question),
         {:ok, contributions} <-
           Ipse.Extension.Context.apply_result(
             state.contributions,
             state.parent,
             if(event["request"]["op"] == "context.publish",
               do: Enum.reverse(state.results_rev),
               else: []
             ),
             event
           ) do
      {:ok,
       %{
         state
         | action: nil,
           unknown: event["outcome"]["status"] in ~w(unknown cancelled),
           results_rev: [event | state.results_rev],
           question: nil,
           resume_needed: if(event["outcome"]["status"] == "answered", do: event),
           contributions: contributions
       }}
    else
      _ -> @error
    end
  end

  defp validate_event(%{"type" => "extension_effect_result"} = event, state, _) do
    id = event["operation_id"]

    if state.parent != nil and state.action != nil and
         not Map.has_key?(state.effect_sources, id) and
         Ipse.Extension.EffectResult.valid_source?(event, state.action) do
      {:ok, %{state | effect_sources: Map.put(state.effect_sources, id, event)}}
    else
      @error
    end
  end

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(extension_model_request extension_embedding_request) do
    if state.action != nil and inference?(state.action["request"]) and
         type == "extension_embedding_request" == embedding?(state.action["request"]) and
         event["operation_id"] == state.action["operation_id"] and
         event["parent_invocation_id"] == state.parent["invocation_id"] and
         event["admission"]["session_id"] == state.parent["payload"]["session_id"] and
         event["admission"]["turn_id"] == state.parent["payload"]["turn_id"] and
         state.action["approval"] in ~w(approved session_allow) do
      {:ok, state}
    else
      @error
    end
  end

  defp validate_event(%{"type" => "request_admitted", "kind" => "model"} = event, state, _) do
    if is_nil(state.context_request) and is_nil(state.question) do
      request = if map_size(state.contributions) > 0, do: event
      {:ok, %{state | context_request: request}}
    else
      @error
    end
  end

  defp validate_event(%{"type" => "extension_context_snapshot"} = event, state, _) do
    if state.context_request != nil and
         event ==
           Ipse.Extension.Context.snapshot(state.contributions, state.context_request),
       do: {:ok, %{state | context_request: nil}},
       else: @error
  end

  defp validate_event(%{"type" => "request_finished"}, state, _) do
    if is_nil(state.context_request) and is_nil(state.question), do: {:ok, state}, else: @error
  end

  defp validate_event(%{"type" => "extension_question"} = event, state, _) do
    if keys?(event, ~w(type version parent_invocation_id operation_id steps question_sha256)) and
         event["question_sha256"] ==
           Ipse.JSON.digest([Map.delete(event, "question_sha256")]) and
         event["version"] === 1 and
         state.parent != nil and state.action != nil and is_nil(state.question) and
         question?(state.action["request"]) and
         event["parent_invocation_id"] == state.parent["invocation_id"] and
         event["operation_id"] == state.action["operation_id"] and
         is_integer(event["steps"]) and event["steps"] in 0..100_000 do
      {:ok, %{state | question: event}}
    else
      @error
    end
  end

  defp validate_event(%{"type" => "extension_continuation_intent"} = event, state, _) do
    if keys?(
         event,
         ~w(type version parent_invocation_id operation_id continuation_id result_sha256)
       ) and
         event["version"] === 1 and state.parent != nil and state.resume_needed != nil and
         is_nil(state.action) and is_nil(state.question) and not state.unknown and
         event["parent_invocation_id"] == state.parent["invocation_id"] and
         event["operation_id"] == state.resume_needed["operation_id"] and
         event["result_sha256"] == Ipse.JSON.digest([state.resume_needed]) and
         id?(event["continuation_id"]) and
         not MapSet.member?(state.seen, event["continuation_id"]) do
      {:ok, %{state | resume_needed: nil, seen: MapSet.put(state.seen, event["continuation_id"])}}
    else
      @error
    end
  end

  defp validate_event(%{"type" => "turn_finished", "status" => "ok"}, state, _) do
    if is_nil(state.parent), do: {:ok, state}, else: @error
  end

  defp validate_event(%{"type" => type}, state, _) when type in ~w(cancelled turn_finished) do
    {:ok,
     %{state | parent: nil, action: nil, question: nil, resume_needed: nil, context_request: nil}}
  end

  defp validate_event(%{"type" => "message", "message" => %{"role" => "user"}}, state, _) do
    if is_nil(state.question),
      do: {:ok, %{state | parent: nil, action: nil, resume_needed: nil, context_request: nil}},
      else: @error
  end

  defp validate_event(%{"type" => "workspace_context_snapshot", "snapshot" => snapshot}, state, _) do
    if is_nil(state.question) and Ipse.Workspace.valid?(snapshot),
      do: {:ok, %{state | context_sha256: Ipse.JSON.digest([snapshot])}},
      else: @error
  end

  defp validate_event(event, state, _) do
    if not is_nil(state.question) or Map.has_key?(event, "operation_id") or
         Map.has_key?(event, "parent_invocation_id"),
       do: @error,
       else: {:ok, state}
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp service_source?(event, state) do
    if service?(event["request"]) do
      context = event["service"]

      state.identities[context["identity"]["instance"]] == context["identity"] and
        context["descriptor"] in state.catalog["entries"]
    else
      true
    end
  end

  def readable?(request, sources, results) do
    not result_read?(request) or
      match?({:ok, _}, effect_source(request, sources, results))
  end

  def effect_source(request, sources, results) do
    id = request["operation_id"]
    source = sources[id]

    if is_map(source) and source["source_sha256"] == request["source_sha256"] and
         Enum.any?(results, fn result ->
           result["operation_id"] == id and result["outcome"]["status"] == "ok" and
             (result["outcome"]["value"] == Ipse.Extension.EffectResult.descriptor(source) or
                (embedding?(result["request"]) and
                   result["outcome"]["value"]["result"] ==
                     Ipse.Extension.EffectResult.descriptor(source)))
         end),
       do: {:ok, source},
       else: @error
  rescue
    _ -> @error
  end

  def bound_effect?(event, sources, results) do
    request = event["request"]
    outcome = event["outcome"]

    cond do
      mcp?(request) and outcome["status"] == "ok" ->
        source = sources[event["operation_id"]]
        is_map(source) and outcome["value"] == Ipse.Extension.EffectResult.descriptor(source)

      embedding?(request) and outcome["status"] == "ok" ->
        source = sources[event["operation_id"]]

        is_map(source) and Ipse.Extension.EmbeddingCall.bound_selection?(event) and
          outcome["value"]["result"] == Ipse.Extension.EffectResult.descriptor(source)

      result_read?(request) ->
        with {:ok, source} <- effect_source(request, sources, results) do
          Ipse.Extension.EffectResult.bound_outcome?(source, request, outcome)
        else
          _ -> false
        end

      true ->
        true
    end
  rescue
    _ -> false
  end

  defp effect_binding?(event, identity, metadata \\ nil) do
    cond do
      embedding?(event["request"]) ->
        Ipse.Extension.EmbeddingCall.valid_binding?(
          event["effect_binding"],
          event["request"],
          metadata
        )

      mcp?(event["request"]) ->
        Ipse.Extension.MCPCall.valid_binding?(
          event["effect_binding"],
          event["request"],
          identity,
          metadata
        )

      result_read?(event["request"]) ->
        event["effect_binding"] == Ipse.Extension.EffectResult.binding(event["request"])

      true ->
        is_nil(event["effect_binding"])
    end
  end

  defp version_two?(identity, request),
    do:
      "host.actions.mixed" in identity["capabilities"] or mcp?(request) or
        result_read?(request) or embedding?(request)

  defp intent_keys(%{"version" => 2}), do: @keys ++ ["effect_binding"]
  defp intent_keys(_), do: @keys

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
  defp bounded?(event), do: byte_size(Jason.encode!(event)) <= 65_536
  alias Ipse.Extension.State

  def validate_operation(%{"op" => "embedding.create"} = request),
    do: Ipse.Extension.EmbeddingCall.validate(request)

  def validate_operation(%{"op" => "mcp.call"} = request),
    do: Ipse.Extension.MCPCall.validate(request)

  def validate_operation(%{"op" => "effect.result.read"} = request),
    do: Ipse.Extension.EffectResult.validate(request)

  def validate_operation(%{"op" => "model.complete"} = request),
    do: Ipse.Extension.ModelCall.validate(request)

  def validate_operation(%{"op" => "history.read"} = request),
    do: Ipse.Extension.History.validate(request)

  def validate_operation(%{"op" => "usage.read"} = request),
    do: Ipse.Extension.UsageRead.validate(request)

  def validate_operation(%{"op" => op} = request) when op in ~w(usage.children usage.child.read),
    do: Ipse.Extension.ChildUsage.validate(request)

  def validate_operation(%{"op" => "context.publish"} = request),
    do: Ipse.Extension.Context.validate(request)

  def validate_operation(%{"op" => "service.call"} = request),
    do: Ipse.Extension.Services.validate_request(request)

  def validate_operation(%{"op" => "tool.call"} = request),
    do: Ipse.Extension.ToolAction.validate(request)

  def validate_operation(%{"op" => "operator.question"} = request) do
    with true <- Enum.sort(Map.keys(request)) == ~w(arguments checkpoint op),
         :ok <- Ipse.Extension.validate(request),
         {:ok, _} <- Ipse.Tools.Questions.validate(request["arguments"]),
         true <- is_map(request["checkpoint"]),
         true <- byte_size(Jason.encode!(request["checkpoint"])) <= 8192 do
      :ok
    else
      _ -> {:error, :invalid_extension_question}
    end
  rescue
    _ -> {:error, :invalid_extension_question}
  end

  def validate_operation(request), do: State.validate(request)
  def question?(request), do: is_map(request) and request["op"] == "operator.question"
  def tool?(request), do: is_map(request) and request["op"] == "tool.call"
  def service?(request), do: is_map(request) and request["op"] == "service.call"
  def model?(request), do: Ipse.Extension.ModelCall.operation?(request)
  def embedding?(request), do: Ipse.Extension.EmbeddingCall.operation?(request)
  def inference?(request), do: model?(request) or embedding?(request)
  def mcp?(request), do: Ipse.Extension.MCPCall.operation?(request)
  def result_read?(request), do: Ipse.Extension.EffectResult.operation?(request)
  def history?(request), do: Ipse.Extension.History.operation?(request)

  def usage?(request),
    do:
      Ipse.Extension.UsageRead.operation?(request) or
        Ipse.Extension.ChildUsage.operation?(request)

  def capability(%{"op" => "history.read"} = request),
    do: Ipse.Extension.History.capability(request)

  def capability(%{"op" => "context.publish"}), do: "host.context"
  def capability(%{"op" => "usage.read"}), do: "host.usage"

  def capability(%{"op" => op}) when op in ~w(usage.children usage.child.read),
    do: "host.usage.children"

  def capability(%{"op" => "service.call"}), do: "host.services"
  def capability(%{"op" => "tool.call"}), do: "host.tools"
  def capability(%{"op" => "operator.question"}), do: "host.question"
  def capability(%{"op" => "model.complete"}), do: "host.model"
  def capability(%{"op" => "embedding.create"}), do: "host.embedding"
  def capability(%{"op" => "mcp.call"}), do: "host.mcp"
  def capability(%{"op" => "effect.result.read"}), do: "host.results"
  def capability(request), do: State.capability(request)
  def mutating?(%{"op" => "tool.call", "name" => name}), do: Ipse.Tools.mutating?(name)
  def mutating?(%{"op" => "model.complete"}), do: true
  def mutating?(%{"op" => "embedding.create"}), do: true
  def mutating?(%{"op" => "mcp.call"}), do: true
  def mutating?(request), do: State.mutating?(request)

  def namespace(_identity, %{"op" => "operator.question"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "model.complete"}, _cwd, id), do: {:ok, id}
  def namespace(_identity, %{"op" => "embedding.create"}, _cwd, id), do: {:ok, id}
  def namespace(_identity, %{"op" => "mcp.call"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "effect.result.read"}, _cwd, id), do: {:ok, id}
  def namespace(_identity, %{"op" => "tool.call"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "service.call"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "context.publish"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "history.read"}, _cwd, id), do: {:ok, id}
  def namespace(_identity, %{"op" => "usage.read"}, _cwd, id), do: {:ok, id}

  def namespace(_identity, %{"op" => op}, _cwd, id)
      when op in ~w(usage.children usage.child.read) do
    {:ok, id}
  end

  def namespace(identity, request, cwd, id),
    do: State.namespace(identity, request["scope"], cwd, id)

  def valid_outcome?(%{"op" => "service.call"}, status, value, id, service),
    do: Ipse.Extension.Services.valid_outcome?(service, status, value, id)

  def valid_outcome?(request, status, value, id, _service),
    do: valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "tool.call"} = request, status, value, _),
    do: Ipse.Extension.ToolAction.valid_outcome?(request, status, value)

  def valid_outcome?(%{"op" => "model.complete"} = request, status, value, id),
    do: Ipse.Extension.ModelCall.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "embedding.create"} = request, status, value, id),
    do: Ipse.Extension.EmbeddingCall.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "mcp.call"} = request, status, value, id),
    do: Ipse.Extension.MCPCall.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "effect.result.read"} = request, status, value, id),
    do: Ipse.Extension.EffectResult.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "history.read"} = request, status, value, id),
    do: Ipse.Extension.History.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "usage.read"} = request, status, value, id),
    do: Ipse.Extension.UsageRead.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => op} = request, status, value, id)
      when op in ~w(usage.children usage.child.read),
      do: Ipse.Extension.ChildUsage.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "context.publish"} = request, status, value, id),
    do: Ipse.Extension.Context.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "operator.question"} = request, "answered", value, _) do
    Enum.sort(Map.keys(value)) == ["answers"] and
      match?(
        {:ok, _},
        Ipse.Tools.Questions.validate_answers(request["arguments"], value["answers"])
      )
  rescue
    _ -> false
  end

  def valid_outcome?(%{"op" => "operator.question"}, status, value, _)
      when status in ~w(cancelled unknown) do
    value == %{}
  end

  def valid_outcome?(%{"op" => "operator.question"}, _, _, _), do: false

  def valid_outcome?(request, status, value, id),
    do: State.valid_outcome?(request, status, value, id)
end
