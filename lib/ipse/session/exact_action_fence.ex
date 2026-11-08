defmodule Ipse.Session.ExactActionFence do
  @moduledoc """
  Restrictive, host-supplied one-attempt admission for one action operation.

  This is not approval, source authority, or a permission grant. The owning
  Session persists an attempt before presenting approval or starting the action.
  """
  alias Ipse.JSON

  @layout "session_sources_v2_exact_action"
  @digests ~w(identity_sha256 descriptor_sha256 arguments_sha256 request_sha256)
  @fields ~w(version operation) ++ @digests
  @attempt ~w(type version session_id turn_id parent_invocation_id operation_id operation fence_sha256 matched) ++
             @digests
  @error {:error, :invalid_exact_action_fence}

  def layout, do: @layout

  def valid?(value) when is_map(value) do
    Enum.sort(Map.keys(value)) === Enum.sort(@fields) and value["version"] === 2 and
      is_binary(value["operation"]) and
      Regex.match?(~r/\A[a-z][a-z0-9_.]{0,63}\z/, value["operation"]) and
      Enum.all?(@digests, &JSON.sha256?(value[&1]))
  end

  def valid?(_), do: false

  # Session-start options are supplied by trusted in-VM host code, not by an
  # extension worker. A restrictive fence cannot be supplied via config.
  def option(opts) when is_list(opts) do
    case Keyword.fetch(opts, :exact_action_fence) do
      :error -> {:ok, nil}
      {:ok, value} -> if valid?(value) and owner?(opts[:owner]), do: {:ok, value}, else: @error
    end
  rescue
    _ -> @error
  end

  def option(_), do: @error

  def owner?(owner),
    do: is_pid(owner) and node(owner) == node() and Process.alive?(owner)

  def header(metadata) when is_map(metadata) do
    case {metadata["source_layout"], Map.fetch(metadata, "exact_action_fence")} do
      {@layout, {:ok, fence}} -> if valid?(fence), do: {:ok, fence}, else: @error
      {layout, :error} when layout in [nil, "session_sources_v1"] -> {:ok, nil}
      _ -> @error
    end
  end

  def header(_), do: @error

  @doc false
  def resume_config(metadata, config) when is_map(config) do
    with {:ok, saved} <- header(metadata),
         requested = config[:exact_action_fence],
         true <- is_nil(requested) or requested === saved do
      {:ok, Map.put(config, :exact_action_fence, saved)}
    else
      _ -> @error
    end
  end

  def resume_config(_, _), do: @error

  @doc "Validate the complete recorded prefix and recover the one-attempt state."
  def restore(events, session) when is_list(events) and is_binary(session) do
    metadata = (List.first(events) || %{})["metadata"] || %{}

    with {:ok, fence} <- header(metadata) do
      initial = %{
        fence: fence,
        parents: %{},
        active_parent: nil,
        attempt: nil,
        action_seen: false,
        result_seen: false
      }

      Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
        case advance(state, event, session) do
          {:ok, next} -> {:cont, {:ok, next}}
          _ -> {:halt, @error}
        end
      end)
      |> case do
        {:ok, state} -> {:ok, Map.take(state, [:fence, :attempt])}
        _ -> @error
      end
    end
  rescue
    _ -> @error
  end

  def restore(_, _), do: @error

  defp advance(%{fence: nil} = state, %{"type" => "extension_invocation_intent"}, _),
    do: {:ok, state}

  defp advance(state, %{"type" => "extension_invocation_intent"} = event, _) do
    id = event["invocation_id"]

    if is_binary(id) and is_map(event["identity"]) and is_map(event["descriptor"]) and
         is_map(get_in(event, ["payload", "arguments"])) do
      parent = %{
        "identity_sha256" => JSON.digest([event["identity"]]),
        "descriptor_sha256" => JSON.digest([event["descriptor"]]),
        "arguments_sha256" => JSON.digest([event["payload"]["arguments"]]),
        "session_id" => get_in(event, ["payload", "session_id"]),
        "turn_id" => get_in(event, ["payload", "turn_id"])
      }

      if Map.has_key?(state.parents, id) or not is_nil(state.active_parent),
        do: @error,
        else: {:ok, %{state | parents: Map.put(state.parents, id, parent), active_parent: id}}
    else
      @error
    end
  end

  defp advance(%{fence: nil} = state, %{"type" => "extension_invocation_result"}, _),
    do: {:ok, state}

  defp advance(state, %{"type" => "extension_invocation_result"} = event, _) do
    if is_binary(state.active_parent) and event["invocation_id"] === state.active_parent,
      do: {:ok, %{state | active_parent: nil}},
      else: @error
  end

  defp advance(%{fence: nil} = state, %{"type" => "turn_finished", "status" => "ok"}, _),
    do: {:ok, state}

  defp advance(state, %{"type" => "turn_finished", "status" => "ok"}, _) do
    if is_nil(state.active_parent), do: {:ok, state}, else: @error
  end

  defp advance(state, %{"type" => type}, _) when type in ~w(cancelled turn_finished),
    do: {:ok, %{state | active_parent: nil}}

  defp advance(state, %{"type" => "message", "message" => %{"role" => "user"}}, _),
    do: {:ok, %{state | active_parent: nil}}

  defp advance(%{fence: nil} = state, %{"type" => "managed_supersession_delivered"}, _),
    do: {:ok, state}

  defp advance(state, %{"type" => "managed_supersession_delivered"} = event, _) do
    if is_binary(state.active_parent) and event["parent_invocation_id"] === state.active_parent,
      do: {:ok, %{state | active_parent: nil}},
      else: @error
  end

  defp advance(%{fence: nil}, %{"type" => "exact_action_fence_attempt"}, _), do: @error

  defp advance(
         %{fence: fence, attempt: nil} = state,
         %{"type" => "exact_action_fence_attempt"} = event,
         session
       )
       when is_map(fence) do
    parent = state.parents[event["parent_invocation_id"]]

    with true <- Enum.sort(Map.keys(event)) === Enum.sort(@attempt),
         true <- event["version"] === 2 and event["session_id"] === session,
         true <- id?(event["turn_id"]),
         true <- id?(event["parent_invocation_id"]) and id?(event["operation_id"]),
         true <- event["operation"] === fence["operation"],
         true <- JSON.sha256?(event["request_sha256"]),
         true <- event["fence_sha256"] === JSON.digest([fence]),
         true <- is_map(parent),
         true <- state.active_parent === event["parent_invocation_id"],
         true <- event["identity_sha256"] === parent["identity_sha256"],
         true <- event["descriptor_sha256"] === parent["descriptor_sha256"],
         true <- event["arguments_sha256"] === parent["arguments_sha256"],
         true <- parent["session_id"] === session and parent["turn_id"] === event["turn_id"],
         true <- is_boolean(event["matched"]),
         true <- event["matched"] === matches?(fence, event) do
      {:ok, %{state | attempt: event}}
    else
      _ -> @error
    end
  end

  defp advance(_, %{"type" => "exact_action_fence_attempt"}, _), do: @error

  defp advance(
         %{fence: fence} = state,
         %{"type" => "extension_action_intent", "request" => %{"op" => operation}} = event,
         _
       )
       when is_map(fence) do
    if operation === fence["operation"] do
      attempt = state.attempt

      if is_map(attempt) and attempt["matched"] === true and not state.action_seen and
           state.active_parent === event["parent_invocation_id"] and
           attempt["operation_id"] === event["operation_id"] and
           attempt["parent_invocation_id"] === event["parent_invocation_id"] and
           attempt["identity_sha256"] === event["identity_sha256"] and
           attempt["request_sha256"] === event["request_sha256"] and
           event["request_sha256"] === JSON.digest([event["request"]]) do
        {:ok, %{state | action_seen: true}}
      else
        @error
      end
    else
      {:ok, state}
    end
  end

  defp advance(%{fence: fence}, %{"type" => "extension_action_intent"}, _)
       when is_map(fence),
       do: @error

  defp advance(
         %{fence: fence} = state,
         %{"type" => "extension_action_result", "request" => %{"op" => operation}} = event,
         _
       )
       when is_map(fence) do
    if operation === fence["operation"] do
      attempt = state.attempt

      if is_map(attempt) and attempt["matched"] === true and state.action_seen and
           state.active_parent === event["parent_invocation_id"] and
           not state.result_seen and attempt["operation_id"] === event["operation_id"] and
           attempt["parent_invocation_id"] === event["parent_invocation_id"] and
           attempt["identity_sha256"] === event["identity_sha256"] and
           attempt["request_sha256"] === event["request_sha256"] and
           event["request_sha256"] === JSON.digest([event["request"]]) do
        {:ok, %{state | result_seen: true}}
      else
        @error
      end
    else
      {:ok, state}
    end
  end

  defp advance(%{fence: fence}, %{"type" => "extension_action_result"}, _)
       when is_map(fence),
       do: @error

  defp advance(state, _, _), do: {:ok, state}

  @doc "Return an attempt event before the Session enters its approval path."
  def attempt(%{fence: nil}, _, _, _), do: :unrestricted

  def attempt(%{fence: fence, attempt: prior}, parent, intent, session) when is_map(fence) do
    if get_in(intent, ["request", "op"]) === fence["operation"] do
      if is_nil(prior) and is_map(get_in(parent, ["payload", "arguments"])) and
           get_in(parent, ["payload", "session_id"]) === session and
           id?(get_in(parent, ["payload", "turn_id"])) and
           intent["parent_invocation_id"] === parent["invocation_id"] and
           intent["identity_sha256"] === JSON.digest([parent["identity"]]) and
           intent["request_sha256"] === JSON.digest([intent["request"]]) do
        event = %{
          "type" => "exact_action_fence_attempt",
          "version" => 2,
          "session_id" => session,
          "turn_id" => parent["payload"]["turn_id"],
          "parent_invocation_id" => parent["invocation_id"],
          "operation_id" => intent["operation_id"],
          "operation" => fence["operation"],
          "identity_sha256" => JSON.digest([parent["identity"]]),
          "descriptor_sha256" => JSON.digest([parent["descriptor"]]),
          "arguments_sha256" => JSON.digest([parent["payload"]["arguments"]]),
          "request_sha256" => JSON.digest([intent["request"]]),
          "fence_sha256" => JSON.digest([fence])
        }

        {:attempt, Map.put(event, "matched", matches?(fence, event))}
      else
        :consumed
      end
    else
      :unrestricted
    end
  rescue
    _ -> :consumed
  end

  def attempt(_, _, _, _), do: :consumed

  def permitted?(%{fence: nil}, _, _), do: true

  def permitted?(%{fence: fence, attempt: attempt}, parent, intent) when is_map(fence) do
    if get_in(intent, ["request", "op"]) !== fence["operation"] do
      true
    else
      is_map(attempt) and attempt["matched"] === true and
        attempt["parent_invocation_id"] === parent["invocation_id"] and
        attempt["session_id"] === get_in(parent, ["payload", "session_id"]) and
        attempt["turn_id"] === get_in(parent, ["payload", "turn_id"]) and
        attempt["identity_sha256"] === JSON.digest([parent["identity"]]) and
        attempt["descriptor_sha256"] === JSON.digest([parent["descriptor"]]) and
        is_map(get_in(parent, ["payload", "arguments"])) and
        attempt["arguments_sha256"] === JSON.digest([parent["payload"]["arguments"]]) and
        attempt["operation_id"] === intent["operation_id"] and
        intent["parent_invocation_id"] === parent["invocation_id"] and
        intent["identity_sha256"] === attempt["identity_sha256"] and
        intent["request_sha256"] === attempt["request_sha256"] and
        attempt["request_sha256"] === JSON.digest([intent["request"]]) and
        matches?(fence, attempt)
    end
  rescue
    _ -> false
  end

  def permitted?(_, _, _), do: false

  defp matches?(fence, event),
    do: Enum.all?(@digests, &(fence[&1] === event[&1]))

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
