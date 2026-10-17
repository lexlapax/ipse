defmodule Ipse.Extensions.Actions do
  @moduledoc "Typed finite host-call continuations with source-bound durable operation receipts."
  alias Ipse.Extensions.State

  @keys ~w(type version parent_invocation_id operation_id step identity_sha256 namespace request request_sha256 approval)
  @types ~w(extension_action_intent extension_action_result)
  @error {:error, :invalid_extension_action}
  @limit 16
  def types, do: @types
  def limit, do: @limit

  def proposal(response, identity) do
    with :ok <- Ipse.Extension.validate(response),
         true <- Enum.sort(Map.keys(response)) == ~w(api_version kind request),
         true <- response["api_version"] === 1 and response["kind"] == "host_call",
         :ok <- State.validate(response["request"]),
         true <- "host.actions" in identity["capabilities"],
         true <- State.capability(response["request"]) in identity["capabilities"] do
      {:ok, response["request"]}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def intent(parent, request, step, approval, cwd) do
    with {:ok, namespace} <-
           State.namespace(
             parent["identity"],
             request["scope"],
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
    %{
      "api_version" => 1,
      "invocation_id" => event["parent_invocation_id"],
      "operation_id" => event["operation_id"],
      "step" => event["step"],
      "outcome" => event["outcome"]
    }
  end

  def result_intent(event),
    do:
      event |> Map.drop(~w(outcome outcome_sha256)) |> Map.put("type", "extension_action_intent")

  def valid_result?(event) do
    outcome = event["outcome"]

    keys?(event, @keys ++ ~w(outcome outcome_sha256)) and
      event["type"] == "extension_action_result" and
      event["outcome_sha256"] == Ipse.Compaction.digest([outcome]) and
      keys?(outcome, ~w(status value)) and outcome["status"] in ~w(ok conflict denied unknown) and
      outcome["status"] == "denied" == (event["approval"] == "denied") and
      State.valid_outcome?(
        event["request"],
        outcome["status"],
        outcome["value"],
        event["operation_id"]
      ) and Ipse.Extension.validate(resume(event)) == :ok and bounded?(event)
  rescue
    _ -> false
  end

  def valid_intent?(event, parent, cwd) do
    with true <- keys?(event, @keys),
         true <- event["type"] == "extension_action_intent" and event["version"] === 1,
         true <- event["parent_invocation_id"] == parent["invocation_id"],
         true <-
           id?(event["operation_id"]) and is_integer(event["step"]) and event["step"] in 1..@limit,
         true <- event["identity_sha256"] == Ipse.Compaction.digest([parent["identity"]]),
         {:ok, request} <-
           proposal(
             %{"api_version" => 1, "kind" => "host_call", "request" => event["request"]},
             parent["identity"]
           ),
         true <- event["request_sha256"] == Ipse.Compaction.digest([request]),
         {:ok, namespace} <-
           State.namespace(
             parent["identity"],
             request["scope"],
             cwd,
             parent["payload"]["session_id"]
           ),
         true <- event["namespace"] == namespace,
         true <-
           event["approval"] in if(State.mutating?(request),
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

  def validate_events([%{"metadata" => metadata} | _] = events) do
    initial = %{
      parent: nil,
      action: nil,
      step: 0,
      seen: MapSet.new(),
      unknown: false,
      results: []
    }

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
      case validate_event(event, state, metadata["cwd"]) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, @error}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_events(_), do: @error

  defp validate_event(%{"type" => "extension_invocation_intent"} = event, state, _) do
    if is_nil(state.parent),
      do: {:ok, %{state | parent: event, action: nil, step: 0, unknown: false, results: []}},
      else: @error
  end

  defp validate_event(%{"type" => "extension_invocation_result"} = event, state, _) do
    if state.parent != nil and event["invocation_id"] == state.parent["invocation_id"] and
         is_nil(state.action) and not state.unknown and
         event["action_count"] == length(state.results) and
         event["actions_sha256"] == Ipse.Compaction.digest(state.results),
       do: {:ok, %{state | parent: nil}},
       else: @error
  end

  defp validate_event(%{"type" => "extension_action_intent"} = event, state, cwd) do
    if state.parent != nil and is_nil(state.action) and not state.unknown and
         event["step"] == state.step + 1 and
         not MapSet.member?(state.seen, event["operation_id"]) and
         valid_intent?(event, state.parent, cwd) do
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
  end

  defp validate_event(%{"type" => "extension_action_result"} = event, state, _) do
    if state.action != nil and result_intent(event) == state.action and valid_result?(event),
      do:
        {:ok,
         %{
           state
           | action: nil,
             unknown: event["outcome"]["status"] == "unknown",
             results: state.results ++ [event]
         }},
      else: @error
  end

  defp validate_event(%{"type" => "turn_finished", "status" => "ok"}, state, _) do
    if is_nil(state.parent), do: {:ok, state}, else: @error
  end

  defp validate_event(%{"type" => type}, state, _) when type in ~w(cancelled turn_finished) do
    {:ok, %{state | parent: nil, action: nil}}
  end

  defp validate_event(%{"type" => "message", "message" => %{"role" => "user"}}, state, _),
    do: {:ok, %{state | parent: nil, action: nil}}

  defp validate_event(event, state, _) do
    if Map.has_key?(event, "operation_id") or Map.has_key?(event, "parent_invocation_id"),
      do: @error,
      else: {:ok, state}
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
  defp bounded?(event), do: byte_size(Jason.encode!(event)) <= 65_536
end
