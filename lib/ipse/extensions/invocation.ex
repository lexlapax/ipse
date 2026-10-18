defmodule Ipse.Extensions.Invocation do
  @moduledoc "Pure intent/result receipts for owned tools, commands and typed services."
  alias Ipse.Extensions.{Catalog, Identity, Manifest}

  @intent_keys ~w(type version invocation_id identity descriptor payload payload_sha256 parent_call_id parent_request_id approval)
  @result_keys ~w(value text text_sha256 action_count actions_sha256)
  @types ~w(extension_invocation_intent extension_invocation_result)
  @limit 10_000
  @error {:error, :invalid_extension_invocation}
  def types, do: @types
  def limit, do: @limit
  def count(events), do: Enum.count(events, &(&1["type"] == "extension_invocation_intent"))
  def validate_intent(event), do: if(valid_intent?(event), do: :ok, else: @error)

  def intent(
        identity,
        descriptor,
        arguments,
        session_id,
        turn_id,
        parent_call_id,
        parent_request_id,
        approval
      ) do
    id = Ipse.Usage.id()

    payload = %{
      "api_version" => 1,
      "invocation_id" => id,
      "session_id" => session_id,
      "turn_id" => turn_id,
      "id" => descriptor["id"],
      "arguments" => arguments
    }

    %{
      "type" => "extension_invocation_intent",
      "version" => 1,
      "invocation_id" => id,
      "identity" => identity,
      "descriptor" => descriptor,
      "payload" => payload,
      "payload_sha256" => Ipse.Compaction.digest([payload]),
      "parent_call_id" => parent_call_id,
      "parent_request_id" => parent_request_id,
      "approval" => approval
    }
  end

  def build_result(intent, response, actions \\ []) do
    with true <- valid_intent?(intent),
         {:ok, value} <- Catalog.validate_response(intent["descriptor"], response),
         true <-
           is_list(actions) and
             length(actions) <= Ipse.Extensions.Actions.limit(intent["identity"]),
         true <- Enum.all?(actions, &Ipse.Extensions.Actions.valid_result?/1),
         text = Jason.encode!(value),
         event =
           Map.merge(intent, %{
             "type" => "extension_invocation_result",
             "value" => value,
             "action_count" => length(actions),
             "actions_sha256" => Ipse.Compaction.digest(actions),
             "text" => text,
             "text_sha256" => Manifest.sha256(text)
           }),
         true <- valid_result?(event) do
      {:ok, event}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def tool_message(result) do
    %{
      "role" => "tool",
      "tool_call_id" => result["parent_call_id"],
      "content" => result["text"],
      "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => result["approval"]},
      "ipse_extension_result" => %{
        "invocation_id" => result["invocation_id"],
        "artifact_sha256" => result["identity"]["artifact_sha256"],
        "result_sha256" => result["text_sha256"]
      }
    }
  end

  def latest_display(events) do
    Enum.reverse(events)
    |> Enum.find_value(fn
      %{"type" => "extension_invocation_result", "descriptor" => %{"stage" => stage}} = event
      when stage in ~w(invoke.command invoke.service) ->
        %{"name" => event["descriptor"]["name"], "stage" => stage, "value" => event["value"]}

      _ ->
        nil
    end)
  end

  def source_call_valid?(%{"tool_calls" => calls}, id, name, arguments)
      when is_list(calls) do
    with true <- Ipse.ToolCall.valid_id?(id),
         [call] <- Enum.filter(calls, &(&1["id"] == id)),
         true <- get_in(call, ["function", "name"]) == name,
         {:ok, parsed} <- Manifest.decode_json(get_in(call, ["function", "arguments"])) do
      parsed == arguments
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def source_call_valid?(_, _, _, _), do: false

  def validate_events(events) do
    with [%{"metadata" => metadata} | _] <- events,
         {:ok, catalog} <- Catalog.from_metadata(metadata) do
      identities = Map.new(Map.get(metadata, "extensions", []), &{&1["instance"], &1})

      initial = %{
        intents: %{},
        results: %{},
        active: nil,
        assistant: nil,
        parent_request: nil,
        started: %{},
        bound: MapSet.new(),
        claimed_calls: MapSet.new(),
        session_id: nil,
        delivery: nil,
        requests: %{}
      }

      Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
        case validate_event(event, state, identities, catalog) do
          {:ok, next} -> {:cont, {:ok, next}}
          _ -> {:halt, @error}
        end
      end)
      |> case do
        {:ok, _} -> :ok
        _ -> @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp validate_event(%{"type" => "request_admitted"} = event, state, _, _) do
    if is_nil(state.session_id) or state.session_id == event["session_id"] do
      {:ok,
       %{
         state
         | session_id: event["session_id"],
           requests: Map.put(state.requests, event["request_id"], event)
       }}
    else
      @error
    end
  end

  defp validate_event(
         %{"type" => "message", "message" => %{"role" => "assistant"} = message} = event,
         state,
         _,
         _
       ) do
    if is_nil(state.active),
      do: {:ok, %{state | assistant: message, parent_request: event["request_id"], started: %{}}},
      else: @error
  end

  defp validate_event(%{"type" => "tool_started"} = event, state, _, _) do
    {:ok, %{state | started: Map.put(state.started, event["call_id"], event)}}
  end

  defp validate_event(
         %{"type" => "extension_invocation_intent"} = event,
         state,
         identities,
         catalog
       ) do
    with true <- valid_intent?(event),
         true <- is_nil(state.active) and not Map.has_key?(state.intents, event["invocation_id"]),
         true <- map_size(state.intents) < @limit,
         true <- identities[event["identity"]["instance"]] == event["identity"],
         true <- event["descriptor"] in catalog["entries"],
         true <- event["descriptor"]["instance"] == event["identity"]["instance"],
         true <- is_nil(state.session_id) or state.session_id == event["payload"]["session_id"],
         true <- valid_origin?(event, state) do
      {:ok,
       %{
         state
         | active: event["invocation_id"],
           session_id: event["payload"]["session_id"],
           intents: Map.put(state.intents, event["invocation_id"], event),
           claimed_calls:
             if(event["descriptor"]["stage"] == "invoke.tool",
               do:
                 MapSet.put(
                   state.claimed_calls,
                   {event["parent_request_id"], event["parent_call_id"]}
                 ),
               else: state.claimed_calls
             )
       }}
    else
      _ -> @error
    end
  end

  defp validate_event(%{"type" => "extension_invocation_result"} = event, state, _, _) do
    id = event["invocation_id"]

    with true <- valid_result?(event),
         true <- state.active == id and not Map.has_key?(state.results, id),
         true <- state.intents[id] == result_intent(event) do
      {:ok, %{state | active: nil, results: Map.put(state.results, id, event)}}
    else
      _ -> @error
    end
  end

  defp validate_event(
         %{"type" => "message", "message" => %{"role" => "tool"} = message},
         state,
         _,
         _
       ) do
    case message["ipse_extension_result"] do
      %{"invocation_id" => id} ->
        result = state.results[id]

        if result != nil and result["descriptor"]["stage"] == "invoke.tool" and
             tool_message(result) == message and not MapSet.member?(state.bound, id),
           do: {:ok, %{state | bound: MapSet.put(state.bound, id)}},
           else: @error

      nil ->
        call = find_call(state.assistant, message["tool_call_id"])

        if call != nil and Catalog.external?(get_in(call, ["function", "name"])) and
             get_in(message, ["ipse_tool_outcome", "status"]) == "result_recorded",
           do: @error,
           else: {:ok, state}

      _ ->
        @error
    end
  end

  defp validate_event(%{"type" => "message", "message" => %{"role" => "user"}}, state, _, _),
    do: {:ok, %{state | active: nil}}

  defp validate_event(%{"type" => type}, state, _, _) when type in ~w(cancelled turn_finished),
    do: {:ok, %{state | active: nil}}

  defp validate_event(%{"type" => "extension_event_intent"} = event, state, _, _),
    do: {:ok, %{state | delivery: event}}

  defp validate_event(%{"type" => "extension_event_result"}, state, _, _),
    do: {:ok, %{state | delivery: nil}}

  defp validate_event(%{"type" => type}, _, _, _) when type in @types, do: @error

  defp validate_event(event, state, _, _) do
    if Map.has_key?(event, "invocation_id"), do: @error, else: {:ok, state}
  end

  defp valid_origin?(%{"descriptor" => %{"stage" => "invoke.tool"}} = event, state) do
    call = find_call(state.assistant, event["parent_call_id"])
    started = state.started[event["parent_call_id"]]
    request = state.requests[event["parent_request_id"]]

    with false <-
           MapSet.member?(
             state.claimed_calls,
             {event["parent_request_id"], event["parent_call_id"]}
           ),
         true <- is_map(call) and is_map(started) and is_map(request),
         true <- state.parent_request == event["parent_request_id"],
         true <- request["turn_id"] == event["payload"]["turn_id"],
         true <- get_in(call, ["function", "name"]) == event["descriptor"]["name"],
         true <-
           started["name"] == event["descriptor"]["name"] and
             started["approval"] == event["approval"],
         {:ok, args} <- Manifest.decode_json(get_in(call, ["function", "arguments"])),
         true <-
           source_call_valid?(
             state.assistant,
             event["parent_call_id"],
             event["descriptor"]["name"],
             args
           ),
         true <- args == event["payload"]["arguments"] and started["arguments"] == args do
      true
    else
      _ -> false
    end
  end

  defp valid_origin?(%{"descriptor" => %{"stage" => "event.job"}} = event, state) do
    delivery = state.delivery
    trigger = event["event_trigger"]

    is_map(delivery) and delivery["declaration"]["mode"] == "job" and
      delivery["identity"] == event["identity"] and
      delivery["declaration"]["handler"] == event["descriptor"]["id"] and
      trigger["delivery_id"] == delivery["delivery_id"] and
      trigger["intent_sha256"] == Ipse.Compaction.digest([delivery]) and
      Ipse.Compaction.digest([event["payload"]["arguments"]["event"]]) ==
        delivery["payload_sha256"]
  end

  defp valid_origin?(_, _), do: true

  defp valid_intent?(event) do
    payload = event["payload"]
    descriptor = event["descriptor"]
    identity = event["identity"]

    Enum.sort(Map.keys(event)) == Enum.sort(intent_keys(event)) and
      event["type"] == "extension_invocation_intent" and event["version"] === 1 and
      Identity.valid?(identity) and id?(event["invocation_id"]) and
      Catalog.validate_snapshot(%{"version" => 1, "entries" => [descriptor]}) == :ok and
      descriptor["stage"] in identity["capabilities"] and
      descriptor["instance"] == identity["instance"] and
      Ipse.Extension.validate(payload) == :ok and
      Enum.sort(Map.keys(payload)) ==
        Enum.sort(
          ~w(api_version arguments id invocation_id session_id turn_id) ++
            if(Map.has_key?(event, "event_trigger"), do: ["trigger"], else: [])
        ) and
      payload["api_version"] === 1 and payload["invocation_id"] == event["invocation_id"] and
      Enum.all?(~w(session_id turn_id), &id?(payload[&1])) and payload["id"] == descriptor["id"] and
      Catalog.validate_call(descriptor, payload["arguments"]) == :ok and
      event["payload_sha256"] == Ipse.Compaction.digest([payload]) and
      valid_parent?(event) and byte_size(Jason.encode!(event)) <= 65_536
  rescue
    _ -> false
  end

  defp valid_parent?(%{"descriptor" => %{"stage" => "invoke.tool"}} = event) do
    not Map.has_key?(event, "event_trigger") and Ipse.ToolCall.valid_id?(event["parent_call_id"]) and
      id?(event["parent_request_id"]) and
      event["approval"] in ~w(approved session_allow)
  end

  defp valid_parent?(%{"descriptor" => %{"stage" => "event.job"}} = event) do
    is_nil(event["parent_call_id"]) and is_nil(event["parent_request_id"]) and
      event["approval"] == "event_trigger" and
      "event.job" in event["identity"]["capabilities"] and
      Ipse.Extensions.EventJob.valid_trigger?(event["event_trigger"]) and
      event["payload"]["trigger"] ==
        Ipse.Extensions.EventJob.public_trigger(event["event_trigger"])
  end

  defp valid_parent?(event),
    do:
      is_nil(event["parent_call_id"]) and is_nil(event["parent_request_id"]) and
        not Map.has_key?(event, "event_trigger") and
        event["approval"] == "operator_request"

  defp valid_result?(event) do
    with true <- Enum.sort(Map.keys(event)) == Enum.sort(intent_keys(event) ++ @result_keys),
         true <- event["type"] == "extension_invocation_result",
         true <- valid_intent?(result_intent(event)),
         true <-
           is_integer(event["action_count"]) and
             event["action_count"] in 0..Ipse.Extensions.Actions.limit(event["identity"]),
         true <-
           is_binary(event["actions_sha256"]) and
             Regex.match?(~r/\A[a-f0-9]{64}\z/, event["actions_sha256"]),
         {:ok, _} <-
           Catalog.validate_response(event["descriptor"], %{
             "api_version" => 1,
             "kind" => "result",
             "value" => event["value"]
           }),
         true <-
           is_binary(event["text"]) and Manifest.sha256(event["text"]) == event["text_sha256"],
         {:ok, value} <- Manifest.decode_json(event["text"]),
         true <- value == event["value"],
         true <- byte_size(Jason.encode!(event)) <= 131_072 do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def result_intent(event),
    do: event |> Map.drop(@result_keys) |> Map.put("type", "extension_invocation_intent")

  defp intent_keys(event),
    do: @intent_keys ++ if(Map.has_key?(event, "event_trigger"), do: ["event_trigger"], else: [])

  defp find_call(%{"tool_calls" => calls}, id) when is_list(calls) do
    Enum.find(calls, &(&1["id"] == id))
  end

  defp find_call(_, _), do: nil
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
