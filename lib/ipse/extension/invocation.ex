defmodule Ipse.Extension.Invocation do
  @moduledoc "Pure intent/result receipts for owned tools, commands and typed services."
  alias Ipse.Extension.{Catalog, Registry, ResultSource}

  @intent_keys ~w(type version invocation_id identity descriptor payload payload_sha256 parent_call_id parent_request_id approval)
  @result_keys ~w(value text text_sha256 action_count actions_sha256)
  @saved_keys ~w(delivery elapsed_ms text text_sha256 action_count actions_sha256)
  @types ~w(extension_invocation_intent extension_invocation_result)
  @limit 10_000
  @error {:error, :invalid_extension_invocation}
  def types, do: @types
  def limit, do: @limit
  def count(events), do: Enum.count(events, &(&1["type"] == "extension_invocation_intent"))
  def validate_intent(event), do: if(valid_intent?(event), do: :ok, else: @error)

  def validate_intent(event, metadata),
    do:
      if(valid_intent?(event) and valid_semantic_metadata?(event, metadata),
        do: :ok,
        else: @error
      )

  def intent(
        identity,
        descriptor,
        arguments,
        session_id,
        turn_id,
        parent_call_id,
        parent_request_id,
        approval,
        semantic_binding \\ nil
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

    event = %{
      "type" => "extension_invocation_intent",
      "version" => 1,
      "invocation_id" => id,
      "identity" => identity,
      "descriptor" => descriptor,
      "payload" => payload,
      "payload_sha256" => Ipse.JSON.digest([payload]),
      "parent_call_id" => parent_call_id,
      "parent_request_id" => parent_request_id,
      "approval" => approval
    }

    if approval == "saved_consent",
      do: event |> Map.put("version", 3) |> Map.put("semantic_binding", semantic_binding),
      else: event
  end

  def build_result(intent, response, actions \\ []) do
    with true <- valid_intent?(intent),
         {:ok, value} <- Catalog.validate_response(intent["descriptor"], response),
         true <-
           is_list(actions) and
             length(actions) <= Ipse.Extension.Actions.limit(intent["identity"]),
         true <- Enum.all?(actions, &Ipse.Extension.Actions.valid_result?/1),
         text = Jason.encode!(value),
         event =
           Map.merge(intent, %{
             "type" => "extension_invocation_result",
             "value" => value,
             "action_count" => length(actions),
             "actions_sha256" => Ipse.JSON.digest(actions),
             "text" => text,
             "text_sha256" => Ipse.JSON.sha256(text)
           }),
         true <- valid_result?(event) do
      {:ok, event}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def build_saved_result(intent, delivery, actions, elapsed_ms) do
    with true <- valid_intent?(intent),
         true <- is_list(actions),
         true <- length(actions) <= Ipse.Extension.Actions.limit(intent["identity"]),
         true <- Enum.all?(actions, &Ipse.Extension.Actions.valid_result?/1),
         text = Jason.encode!(delivery),
         event =
           intent
           |> Map.merge(%{
             "type" => "extension_invocation_result",
             "version" => if(intent["version"] === 3, do: 4, else: 2),
             "delivery" => delivery,
             "elapsed_ms" => elapsed_ms,
             "action_count" => length(actions),
             "actions_sha256" => Ipse.JSON.digest(actions),
             "text" => text,
             "text_sha256" => Ipse.JSON.sha256(text)
           }),
         true <- valid_saved_result?(event) do
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
        Map.merge(%{"name" => event["descriptor"]["name"], "stage" => stage}, delivery(event))

      _ ->
        nil
    end)
  end

  def source_call_valid?(%{"tool_calls" => calls}, id, name, arguments)
      when is_list(calls) do
    with true <- Ipse.Tools.valid_call_id?(id),
         [call] <- Enum.filter(calls, &(&1["id"] == id)),
         true <- get_in(call, ["function", "name"]) == name,
         {:ok, parsed} <- Ipse.JSON.decode_bounded(get_in(call, ["function", "arguments"])) do
      parsed == arguments
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def source_call_valid?(_, _, _, _), do: false

  def delivery(%{"version" => version, "delivery" => delivery}) when version in [2, 4],
    do: %{"delivery" => delivery}

  def delivery(%{"version" => version, "value" => value}) when version in [1, 3],
    do: %{"value" => value}

  def validate_events(events) do
    with [%{"metadata" => metadata} | _] <- events,
         {:ok, catalog} <- Catalog.from_metadata(metadata),
         {:ok, sources} <- ResultSource.restore(events) do
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
        requests: %{},
        metadata: metadata,
        sources: sources
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
    with true <- valid_intent?(event) and valid_semantic_metadata?(event, state.metadata),
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

    with true <-
           if(event["version"] in [2, 4],
             do: valid_saved_result?(event) and ResultSource.published?(state.sources, event),
             else: valid_result?(event)
           ),
         true <- state.active == id and not Map.has_key?(state.results, id),
         true <- state.intents[id] == result_intent(event) do
      {:ok, %{state | active: nil, results: Map.put(state.results, id, event)}}
    else
      _ -> @error
    end
  end

  defp validate_event(%{"type" => type} = event, state, _, _)
       when type in ~w(extension_output_begin extension_output_chunk extension_output_seal) do
    if state.active == event["invocation_id"], do: {:ok, state}, else: @error
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
         true <-
           event["version"] !== 3 or
             (started["version"] === 2 and
                started["semantic_binding"] === event["semantic_binding"]),
         {:ok, args} <- Ipse.JSON.decode_bounded(get_in(call, ["function", "arguments"])),
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
      trigger["intent_sha256"] == Ipse.JSON.digest([delivery]) and
      Ipse.JSON.digest([event["payload"]["arguments"]["event"]]) ==
        delivery["payload_sha256"]
  end

  defp valid_origin?(_, _), do: true

  defp valid_intent?(event) do
    payload = event["payload"]
    descriptor = event["descriptor"]
    identity = event["identity"]

    Enum.sort(Map.keys(event)) == Enum.sort(intent_keys(event)) and
      event["type"] == "extension_invocation_intent" and
      event["version"] === if(event["approval"] == "saved_consent", do: 3, else: 1) and
      Registry.valid_identity?(identity) and id?(event["invocation_id"]) and
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
      event["payload_sha256"] == Ipse.JSON.digest([payload]) and
      valid_parent?(event) and valid_semantic_binding?(event) and
      byte_size(Jason.encode!(event)) <= 65_536
  rescue
    _ -> false
  end

  defp valid_parent?(%{"descriptor" => %{"stage" => "invoke.tool"}} = event) do
    not Map.has_key?(event, "event_trigger") and
      Ipse.Tools.valid_call_id?(event["parent_call_id"]) and
      id?(event["parent_request_id"]) and
      event["approval"] in if(event["version"] === 3,
        do: ["saved_consent"],
        else: ~w(approved session_allow)
      )
  end

  defp valid_parent?(%{"descriptor" => %{"stage" => "event.job"}} = event) do
    is_nil(event["parent_call_id"]) and is_nil(event["parent_request_id"]) and
      event["approval"] == "event_trigger" and
      "event.job" in event["identity"]["capabilities"] and
      valid_event_trigger?(event["event_trigger"]) and
      event["payload"]["trigger"] ==
        public_event_trigger(event["event_trigger"])
  end

  defp valid_parent?(event),
    do:
      is_nil(event["parent_call_id"]) and is_nil(event["parent_request_id"]) and
        not Map.has_key?(event, "event_trigger") and
        event["approval"] ==
          if(event["version"] === 3, do: "saved_consent", else: "operator_request")

  defp valid_semantic_binding?(%{"version" => 3} = event) do
    Ipse.Extension.SemanticAdmission.valid_outer_binding?(
      event["semantic_binding"],
      event["identity"],
      event["descriptor"],
      event["payload"]["session_id"]
    )
  end

  defp valid_semantic_binding?(_), do: true

  defp valid_semantic_metadata?(%{"version" => 3} = event, metadata) do
    Ipse.Extension.SemanticAdmission.valid_outer_binding?(
      event["semantic_binding"],
      event["identity"],
      event["descriptor"],
      event["payload"]["session_id"],
      metadata
    )
  end

  defp valid_semantic_metadata?(_, _), do: true

  defp valid_result?(event) do
    with true <- Enum.sort(Map.keys(event)) == Enum.sort(intent_keys(event) ++ @result_keys),
         true <- event["type"] == "extension_invocation_result",
         true <- event["version"] in [1, 3],
         true <- valid_intent?(result_intent(event)),
         true <-
           is_integer(event["action_count"]) and
             event["action_count"] in 0..Ipse.Extension.Actions.limit(event["identity"]),
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
           is_binary(event["text"]) and Ipse.JSON.sha256(event["text"]) == event["text_sha256"],
         {:ok, value} <- Ipse.JSON.decode_bounded(event["text"]),
         true <- value == event["value"],
         true <- byte_size(Jason.encode!(event)) <= 131_072 do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_saved_result?(event) do
    with true <- Enum.sort(Map.keys(event)) == Enum.sort(intent_keys(event) ++ @saved_keys),
         true <- event["type"] == "extension_invocation_result" and event["version"] in [2, 4],
         true <- valid_intent?(result_intent(event)),
         true <- event["identity"]["sdk"] === 2,
         true <- "invoke.result.pages" in event["identity"]["capabilities"],
         true <- event["descriptor"]["stage"] in ~w(invoke.tool invoke.command),
         true <- ResultSource.valid_descriptor?(event["delivery"]),
         true <- is_integer(event["elapsed_ms"]) and event["elapsed_ms"] in 0..120_000,
         true <-
           is_integer(event["action_count"]) and
             event["action_count"] in 0..Ipse.Extension.Actions.limit(event["identity"]),
         true <-
           is_binary(event["actions_sha256"]) and
             Regex.match?(~r/\A[a-f0-9]{64}\z/, event["actions_sha256"]),
         true <- event["text"] == Jason.encode!(event["delivery"]),
         true <- Ipse.JSON.sha256(event["text"]) == event["text_sha256"],
         true <- byte_size(Jason.encode!(event)) <= 131_072 do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def result_intent(event),
    do:
      event
      |> Map.drop(@result_keys ++ @saved_keys)
      |> Map.put("type", "extension_invocation_intent")
      |> Map.put("version", if(event["version"] in [3, 4], do: 3, else: 1))

  defp intent_keys(event),
    do:
      @intent_keys ++
        if(Map.has_key?(event, "event_trigger"), do: ["event_trigger"], else: []) ++
        if(event["version"] in [3, 4], do: ["semantic_binding"], else: [])

  defp find_call(%{"tool_calls" => calls}, id) when is_list(calls) do
    Enum.find(calls, &(&1["id"] == id))
  end

  defp find_call(_, _), do: nil
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  alias Ipse.Extension.{Catalog, Subscriptions}
  alias Ipse.Journal

  def event_schedule(declaration), do: Map.get(declaration, "schedule", "before_request")

  def event_outcome(actions),
    do:
      if(Enum.all?(actions, &(&1["outcome"]["status"] in ~w(ok answered))),
        do: "completed",
        else: "failed"
      )

  def prepare_event(config, entry, delivery, payload, facts, session, turn) do
    name = "ext__" <> entry.identity["instance"] <> "__" <> delivery["declaration"]["handler"]

    with true <- payload != nil,
         {:ok, ^entry, descriptor} <- Catalog.lookup(config, "event.job", name),
         arguments = %{"event" => payload},
         :ok <- Catalog.validate_call(descriptor, arguments),
         trigger = %{
           "version" => 1,
           "delivery_id" => delivery["delivery_id"],
           "intent_sha256" => Ipse.JSON.digest([delivery]),
           "event_id" => delivery["source"]["event_id"],
           "schedule" => event_schedule(delivery["declaration"]),
           "sources" =>
             answer_source(
               %{
                 "received" => facts.received.source,
                 "effective" => facts.effective.source
               },
               delivery,
               facts
             )
         },
         parent =
           intent(
             entry.identity,
             descriptor,
             arguments,
             session,
             turn,
             nil,
             nil,
             "event_trigger"
           ),
         public_payload = Map.put(parent["payload"], "trigger", public_event_trigger(trigger)),
         parent =
           parent
           |> Map.put("event_trigger", trigger)
           |> Map.put("payload", public_payload)
           |> Map.put("payload_sha256", Ipse.JSON.digest([public_payload])),
         :ok <- validate_intent(parent),
         true <-
           event_matches?(
             parent,
             delivery,
             facts.received.record,
             facts.effective.record,
             if(facts[:answer], do: facts.answer.record)
           ) do
      {:ok, parent}
    else
      _ -> {:error, :event_job_refused}
    end
  end

  def public_event_trigger(trigger),
    do: %{
      "kind" => "event",
      "delivery_id" => trigger["delivery_id"],
      "event_id" => trigger["event_id"],
      "schedule" => trigger["schedule"]
    }

  def valid_event_trigger?(trigger) do
    is_map(trigger) and
      Enum.sort(Map.keys(trigger)) ==
        ~w(delivery_id event_id intent_sha256 schedule sources version) and
      trigger["version"] === 1 and id?(trigger["delivery_id"]) and id?(trigger["event_id"]) and
      is_binary(trigger["intent_sha256"]) and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, trigger["intent_sha256"]) and
      trigger["schedule"] in ~w(before_request after_turn) and
      is_map(trigger["sources"]) and
      Enum.sort(Map.keys(trigger["sources"])) in [
        ~w(effective received),
        ~w(answer effective received)
      ] and
      Enum.all?(trigger["sources"], fn {_, source} -> Journal.valid_source?(source) end) and
      Enum.all?(trigger["sources"], fn {_, source} ->
        source["session_id"] == trigger["sources"]["effective"]["session_id"]
      end) and
      (not Map.has_key?(trigger["sources"], "answer") or trigger["schedule"] == "after_turn")
  rescue
    _ -> false
  end

  def event_matches?(parent, delivery, received, effective, answer \\ nil) do
    trigger = parent["event_trigger"]

    record =
      case delivery["declaration"]["event"] do
        "prompt.received" -> received
        "prompt.effective_committed" -> effective
        "answer.committed" -> answer
      end

    valid_event_trigger?(trigger) and delivery["declaration"]["mode"] == "job" and
      parent["descriptor"]["stage"] == "event.job" and parent["identity"] == delivery["identity"] and
      parent["descriptor"]["id"] == delivery["declaration"]["handler"] and
      parent["payload"]["turn_id"] == delivery["turn_id"] and
      parent["payload"]["session_id"] == delivery["source"]["session_id"] and
      trigger["delivery_id"] == delivery["delivery_id"] and
      trigger["event_id"] == delivery["source"]["event_id"] and
      trigger["intent_sha256"] == Ipse.JSON.digest([delivery]) and
      trigger["schedule"] == event_schedule(delivery["declaration"]) and
      trigger["sources"]["received"] == effective["received_source"] and
      Journal.source_matches?(trigger["sources"]["received"], received) and
      Journal.source_matches?(trigger["sources"]["effective"], effective) and
      answer_matches?(trigger, delivery, answer, effective) and
      parent["payload"]["trigger"] == public_event_trigger(trigger) and
      parent["payload"]["arguments"] == %{"event" => Subscriptions.payload(delivery, record)}
  rescue
    _ -> false
  end

  defp answer_source(sources, %{"declaration" => %{"event" => "answer.committed"}}, facts),
    do: Map.put(sources, "answer", facts.answer.source)

  defp answer_source(sources, _, _), do: sources

  defp answer_matches?(
         trigger,
         %{"declaration" => %{"event" => "answer.committed"}} = delivery,
         answer,
         effective
       ),
       do:
         Ipse.Session.Lifecycle.valid_answer?(answer) and
           trigger["sources"]["answer"] == delivery["source"] and
           Journal.source_matches?(trigger["sources"]["answer"], answer) and
           answer["effective_source"] == trigger["sources"]["effective"] and
           answer["turn_id"] == effective["turn_id"]

  defp answer_matches?(trigger, _, _, _), do: not Map.has_key?(trigger["sources"], "answer")

  def restore_event_question(nil, _, _, _), do: {:ok, nil}

  def restore_event_question(
        %{kind: :extension, parent: %{"event_trigger" => trigger} = parent},
        directory,
        session,
        events
      ) do
    with true <- valid_event_trigger?(trigger),
         delivery when is_map(delivery) <-
           Enum.find(
             events,
             &(&1["type"] == "extension_event_intent" and
                 &1["delivery_id"] == trigger["delivery_id"])
           ),
         {:ok, %{records: [received]}} <-
           Ipse.Journal.source_page(
             directory,
             session,
             trigger["sources"]["received"]["byte_offset"],
             1
           ),
         {:ok, %{records: [effective]}} <-
           Ipse.Journal.source_page(
             directory,
             session,
             trigger["sources"]["effective"]["byte_offset"],
             1
           ),
         true <-
           received.source == trigger["sources"]["received"] and
             effective.source == trigger["sources"]["effective"],
         {:ok, answer} <- restore_answer(trigger, directory, session),
         true <-
           event_matches?(
             parent,
             delivery,
             received.record,
             effective.record,
             if(answer, do: answer.record)
           ) do
      {:ok,
       %{
         received: received,
         effective: effective,
         answer: answer,
         intent: delivery,
         turn: delivery["turn_id"],
         schedule: trigger["schedule"]
       }}
    else
      _ -> {:error, :invalid_event_job_question}
    end
  end

  def restore_event_question(_, _, _, _), do: {:ok, nil}

  defp restore_answer(%{"sources" => %{"answer" => source}}, directory, session) do
    with {:ok, %{records: [fact]}} <-
           Ipse.Journal.source_page(directory, session, source["byte_offset"], 1),
         true <- fact.source == source do
      {:ok, fact}
    else
      _ -> {:error, :invalid_event_job_question}
    end
  end

  defp restore_answer(_, _, _), do: {:ok, nil}
end
