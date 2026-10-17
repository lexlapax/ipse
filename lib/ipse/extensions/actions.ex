defmodule Ipse.Extensions.Actions do
  @moduledoc "Typed finite host-call continuations with source-bound durable operation receipts."
  alias Ipse.Extensions.Operation

  @keys ~w(type version parent_invocation_id operation_id step identity_sha256 namespace context_sha256 service request request_sha256 approval)
  @types ~w(extension_action_intent extension_action_result)
  @error {:error, :invalid_extension_action}
  @limit 16
  @read_limit 10_000
  def types, do: @types
  def limit, do: @limit

  def limit(identity) do
    if "host.usage.scan" in identity["capabilities"], do: @read_limit, else: @limit
  end

  def limit(identity, request) do
    if Operation.usage?(request), do: limit(identity), else: @limit
  end

  def proposal(response, identity) do
    with :ok <- Ipse.Extension.validate(response),
         true <- Ipse.Extensions.Identity.valid?(identity),
         true <- Enum.sort(Map.keys(response)) == ~w(api_version kind request),
         true <- response["api_version"] === 1 and response["kind"] == "host_call",
         :ok <- Operation.validate(response["request"]),
         true <- "host.actions" in identity["capabilities"],
         true <-
           not Operation.history?(response["request"]) or
             "host.history" in identity["capabilities"],
         true <- Operation.capability(response["request"]) in identity["capabilities"] do
      {:ok, response["request"]}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def intent(parent, request, step, approval, cwd, context_sha256 \\ nil, service \\ nil) do
    with {:ok, namespace} <-
           Operation.namespace(
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
        "identity_sha256" => Ipse.Compaction.digest([parent["identity"]]),
        "namespace" => namespace,
        "context_sha256" => context_sha256,
        "service" => service,
        "request" => request,
        "request_sha256" => Ipse.Compaction.digest([request]),
        "approval" => approval
      }

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
        "outcome_sha256" => Ipse.Compaction.digest([outcome])
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

    if Operation.question?(event["request"]) or Operation.service?(event["request"]),
      do: Map.put(payload, "checkpoint", event["request"]["checkpoint"]),
      else: payload
  end

  def result_intent(event),
    do:
      event |> Map.drop(~w(outcome outcome_sha256)) |> Map.put("type", "extension_action_intent")

  def valid_result?(event) do
    outcome = event["outcome"]

    keys?(event, @keys ++ ~w(outcome outcome_sha256)) and
      event["type"] == "extension_action_result" and
      event["outcome_sha256"] == Ipse.Compaction.digest([outcome]) and
      keys?(outcome, ~w(status value)) and
      outcome["status"] in ~w(ok conflict denied unknown answered cancelled failed) and
      outcome["status"] == "denied" == (event["approval"] == "denied") and
      Operation.valid_outcome?(
        event["request"],
        outcome["status"],
        outcome["value"],
        event["operation_id"],
        event["service"]
      ) and
      (not Operation.history?(event["request"]) or Ipse.Extensions.History.bound_outcome?(event)) and
      Ipse.Extension.validate(resume(event)) == :ok and bounded?(event)
  rescue
    _ -> false
  end

  def valid_intent?(event, parent, cwd) do
    with true <- keys?(event, @keys),
         true <- event["type"] == "extension_action_intent" and event["version"] === 1,
         true <- event["parent_invocation_id"] == parent["invocation_id"],
         true <-
           id?(event["operation_id"]) and is_integer(event["step"]) and
             event["step"] in 1..limit(parent["identity"], event["request"]),
         true <- event["identity_sha256"] == Ipse.Compaction.digest([parent["identity"]]),
         {:ok, request} <-
           proposal(
             %{"api_version" => 1, "kind" => "host_call", "request" => event["request"]},
             parent["identity"]
           ),
         true <- event["request_sha256"] == Ipse.Compaction.digest([request]),
         {:ok, namespace} <-
           Operation.namespace(
             parent["identity"],
             request,
             cwd,
             parent["payload"]["session_id"]
           ),
         true <- event["namespace"] == namespace,
         true <-
           if(Operation.service?(request),
             do:
               Ipse.Extensions.Services.valid_binding?(
                 parent["identity"],
                 request,
                 event["service"]
               ),
             else: is_nil(event["service"])
           ),
         true <-
           if(Operation.tool?(request),
             do: hash?(event["context_sha256"]),
             else: is_nil(event["context_sha256"])
           ),
         true <-
           event["approval"] in if(Operation.mutating?(request),
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
    {:ok, _} = Ipse.Lifecycle.Runtime.restore(events)
    {:ok, catalog} = Ipse.Extensions.Catalog.from_metadata(metadata)
    :ok = Ipse.Extensions.Services.validate_metadata(Map.get(metadata, "extensions", []), catalog)
    {:ok, usage_reads} = Ipse.Extensions.UsageRead.restore(events)

    initial = %{
      parent: nil,
      usage_reads: usage_reads,
      action: nil,
      step: 0,
      seen: MapSet.new(),
      unknown: false,
      results: [],
      question: nil,
      resume_needed: nil,
      context_sha256: nil,
      contributions: %{},
      context_request: nil,
      identities: Map.new(Map.get(metadata, "extensions", []), &{&1["instance"], &1}),
      catalog: catalog
    }

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
      case validate_event(event, state, metadata["cwd"]) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, @error}
      end
    end)
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

    Map.put(event, "question_sha256", Ipse.Compaction.digest([event]))
  end

  def continuation(parent, result) do
    %{
      "type" => "extension_continuation_intent",
      "version" => 1,
      "parent_invocation_id" => parent["invocation_id"],
      "operation_id" => result["operation_id"],
      "continuation_id" => Ipse.Usage.id(),
      "result_sha256" => Ipse.Compaction.digest([result])
    }
  end

  defp validate_event(%{"type" => type}, state, _)
       when type in ~w(extension_text_intent extension_text_ready extension_text_closed),
       do: {:ok, state}

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(lifecycle_epoch_started lifecycle_epoch_closed lifecycle_wait_started lifecycle_wait_finished lifecycle_recording_stopped),
       do: if(Ipse.Lifecycle.Runtime.valid_record?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(extension_feed_intent extension_feed_ready extension_feed_delivery_intent extension_feed_delivery_result extension_feed_closed),
       do: if(Ipse.Extensions.Feeds.valid_record?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => type} = event, state, _)
       when type in ~w(lifecycle_tool_intent lifecycle_tool_outcome lifecycle_tool_recording_stopped),
       do: if(Ipse.Lifecycle.Tool.valid?(event), do: {:ok, state}, else: @error)

  defp validate_event(%{"type" => "delegation_finished"} = event, state, _),
    do: if(Ipse.Lifecycle.Child.valid_record?(event), do: {:ok, state}, else: @error)

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
             results: [],
             question: nil,
             resume_needed: nil
         }},
      else: @error
  end

  defp validate_event(%{"type" => "extension_invocation_result"} = event, state, _) do
    if state.parent != nil and event["invocation_id"] == state.parent["invocation_id"] and
         is_nil(state.action) and not state.unknown and
         is_nil(state.resume_needed) and is_nil(state.question) and
         event["action_count"] == length(state.results) and
         event["actions_sha256"] == Ipse.Compaction.digest(state.results),
       do: {:ok, %{state | parent: nil}},
       else: @error
  end

  defp validate_event(%{"type" => "extension_action_intent"} = event, state, cwd) do
    if state.parent != nil and is_nil(state.action) and not state.unknown and
         is_nil(state.resume_needed) and is_nil(state.question) and
         event["step"] == state.step + 1 and
         not MapSet.member?(state.seen, event["operation_id"]) and
         valid_intent?(event, state.parent, cwd) do
      if (not Operation.tool?(event["request"]) or event["context_sha256"] == state.context_sha256) and
           service_source?(event, state) do
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
    question = Operation.question?(event["request"])

    with true <-
           state.action != nil and result_intent(event) == state.action and valid_result?(event),
         true <- not question or not is_nil(state.question),
         {:ok, contributions} <-
           Ipse.Extensions.Contributions.apply_result(
             state.contributions,
             state.parent,
             state.results,
             event
           ) do
      {:ok,
       %{
         state
         | action: nil,
           unknown: event["outcome"]["status"] in ~w(unknown cancelled),
           results: state.results ++ [event],
           question: nil,
           resume_needed: if(event["outcome"]["status"] == "answered", do: event),
           contributions: contributions
       }}
    else
      _ -> @error
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
           Ipse.Extensions.Contributions.snapshot(state.contributions, state.context_request),
       do: {:ok, %{state | context_request: nil}},
       else: @error
  end

  defp validate_event(%{"type" => "request_finished"}, state, _) do
    if is_nil(state.context_request) and is_nil(state.question), do: {:ok, state}, else: @error
  end

  defp validate_event(%{"type" => "extension_question"} = event, state, _) do
    if keys?(event, ~w(type version parent_invocation_id operation_id steps question_sha256)) and
         event["question_sha256"] ==
           Ipse.Compaction.digest([Map.delete(event, "question_sha256")]) and
         event["version"] === 1 and
         state.parent != nil and state.action != nil and is_nil(state.question) and
         Operation.question?(state.action["request"]) and
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
         event["result_sha256"] == Ipse.Compaction.digest([state.resume_needed]) and
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
    if is_nil(state.question) and Ipse.WorkspaceContext.valid?(snapshot),
      do: {:ok, %{state | context_sha256: Ipse.Compaction.digest([snapshot])}},
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
    if Operation.service?(event["request"]) do
      context = event["service"]

      state.identities[context["identity"]["instance"]] == context["identity"] and
        context["descriptor"] in state.catalog["entries"]
    else
      true
    end
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
  defp hash?(hash), do: is_binary(hash) and Regex.match?(~r/\A[a-f0-9]{64}\z/, hash)
  defp bounded?(event), do: byte_size(Jason.encode!(event)) <= 65_536
end
