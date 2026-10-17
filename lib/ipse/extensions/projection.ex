defmodule Ipse.Extensions.Projection do
  @moduledoc "Deterministic, provenance-bound prompt/display projections; callbacks never run on restore."
  alias Ipse.Extensions.Manifest
  @stages ~w(transform.prompt transform.presentation)
  @intent_keys ~w(type version request_id identity stage input_sha256 context_sha256 source_message_sha256)
  @invalid {:error, :invalid_extension_projection}

  def intent(identity, stage, input, messages) do
    %{
      "type" => "extension_transform_intent",
      "version" => 1,
      "request_id" => Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      "identity" => identity,
      "stage" => stage,
      "input_sha256" => Manifest.sha256(input),
      "context_sha256" => Ipse.Compaction.digest(messages),
      "source_message_sha256" => Ipse.Compaction.digest([List.last(messages)])
    }
  end

  def build(intent, input, result) do
    with true <- intent_valid?(intent),
         :ok <- Ipse.Extension.validate(%{"text" => input}),
         true <- Manifest.sha256(input) == intent["input_sha256"],
         :ok <- Ipse.MCP.Schema.validate_arguments(result_schema(intent["stage"]), result),
         output = render(intent, input, result),
         true <- byte_size(output) <= 16_384 do
      event =
        Map.merge(intent, %{
          "type" => "extension_transform_result",
          "input" => input,
          "output" => output,
          "result" => result,
          "output_sha256" => Manifest.sha256(output)
        })

      if byte_size(Jason.encode!(event)) <= 65_536, do: {:ok, event}, else: @invalid
    else
      _ -> @invalid
    end
  rescue
    _ -> @invalid
  end

  def apply(messages, event) do
    with true <- is_list(messages) and messages != [],
         true <- event["context_sha256"] == Ipse.Compaction.digest(messages),
         last = List.last(messages),
         true <- event["source_message_sha256"] == Ipse.Compaction.digest([last]),
         true <- valid_result?(event) do
      case event["stage"] do
        "transform.prompt" ->
          if last["role"] == "user" and last["content"] == event["input"],
            do: {:ok, Enum.drop(messages, -1) ++ [Map.put(last, "content", event["output"])]},
            else: @invalid

        "transform.presentation" ->
          if last["role"] == "assistant" and Map.get(last, "tool_calls", []) in [nil, []],
            do: {:ok, messages},
            else: @invalid
      end
    else
      _ -> @invalid
    end
  rescue
    _ -> @invalid
  end

  def validate_intent_context(messages, event) do
    if messages != [] and event["context_sha256"] == Ipse.Compaction.digest(messages) and
         event["source_message_sha256"] == Ipse.Compaction.digest([List.last(messages)]),
       do: :ok,
       else: @invalid
  end

  @doc "Validate all callback intents/results against pinned session identities before repair or resume."
  def validate_events(events) when is_list(events) do
    extensions? =
      Enum.any?(events, fn event ->
        is_map(event) and is_binary(event["type"]) and
          String.starts_with?(event["type"], "extension_")
      end)

    registered? = match?([%{"metadata" => %{"extensions" => [_ | _]}} | _], events)

    with :ok <- Ipse.Extensions.Invocation.validate_events(events),
         :ok <- Ipse.Extensions.Actions.validate_events(events) do
      if extensions? or registered?, do: validate_extension_events(events), else: :ok
    end
  end

  defp validate_extension_events(events) do
    with [%{"type" => "session", "metadata" => metadata} | _] <- events,
         identities = Map.get(metadata, "extensions", []),
         true <- is_list(identities) and length(identities) <= 8,
         true <- Enum.all?(identities, &identity_valid?/1),
         registered = Map.new(identities, &{&1["instance"], &1}),
         true <- map_size(registered) == length(identities) do
      Enum.reduce_while(
        events,
        {:ok, %{intents: %{}, seen: MapSet.new(), last: nil, presentation: nil, active: nil}},
        fn event, {:ok, state} ->
          case validate_event(event, state, registered) do
            {:ok, next} -> {:cont, {:ok, next}}
            _ -> {:halt, @invalid}
          end
        end
      )
      |> case do
        {:ok, _} -> :ok
        _ -> @invalid
      end
    else
      _ -> @invalid
    end
  rescue
    _ -> @invalid
  end

  def presentation(events) do
    Enum.reduce(events, "", fn
      %{
        "type" => "extension_transform_result",
        "stage" => "transform.presentation",
        "output" => output
      },
      _ ->
        output

      _, previous ->
        previous
    end)
  end

  def identity_valid?(identity), do: Ipse.Extensions.Identity.valid?(identity)

  defp validate_event(%{"type" => "extension_transform_intent"} = event, state, registered) do
    id = event["request_id"]

    with true <- intent_valid?(event),
         true <- is_nil(state.active),
         true <- intent_source_matches?(event, state),
         true <- registered[event["identity"]["instance"]] == event["identity"],
         false <- MapSet.member?(state.seen, id),
         true <- event["stage"] in event["identity"]["capabilities"] do
      {:ok,
       %{
         state
         | intents: Map.put(state.intents, id, event),
           seen: MapSet.put(state.seen, id),
           active: id
       }}
    else
      _ -> @invalid
    end
  end

  defp validate_event(%{"type" => "extension_transform_result"} = event, state, _registered) do
    id = event["request_id"]

    with intent when is_map(intent) <- state.intents[id],
         true <- state.active == id,
         true <- result_intent(event) == intent,
         true <- valid_result?(event),
         true <- input_matches?(event, state) do
      next = %{state | intents: Map.delete(state.intents, id), active: nil}

      if event["stage"] == "transform.prompt",
        do: {:ok, %{next | last: Map.put(state.last, "content", event["output"])}},
        else: {:ok, %{next | presentation: event["output"]}}
    else
      _ -> @invalid
    end
  end

  defp validate_event(%{"type" => type}, state, _registered)
       when type in ~w(extension_invocation_intent extension_invocation_result extension_action_intent extension_action_result) do
    if is_nil(state.active), do: {:ok, state}, else: @invalid
  end

  defp validate_event(%{"type" => "cancelled"}, state, _), do: {:ok, %{state | active: nil}}

  defp validate_event(%{"type" => "turn_finished", "status" => status}, state, _)
       when status != "ok" do
    {:ok, %{state | active: nil}}
  end

  defp validate_event(%{"identity" => _, "stage" => _, "request_id" => _}, _state, _registered),
    do: @invalid

  defp validate_event(
         %{"type" => "turn_finished", "status" => "ok"},
         %{active: active},
         _registered
       )
       when active != nil do
    @invalid
  end

  defp validate_event(%{"type" => type, "message" => message}, state, _registered)
       when type in ~w(message handoff_imported operator_answer operator_question_closed) do
    if is_map(message) and (message["role"] == "user" or state.active == nil),
      do: {:ok, %{state | last: message, presentation: nil, active: nil}},
      else: @invalid
  end

  defp validate_event(%{"type" => "extension_prompt_received"} = event, state, _registered) do
    if Enum.sort(Map.keys(event)) == ~w(original original_sha256 type version) and
         event["version"] === 1 and
         is_binary(event["original"]) and
         Manifest.sha256(event["original"]) == event["original_sha256"],
       do: {:ok, state},
       else: @invalid
  end

  defp validate_event(%{"type" => type}, state, _registered) when is_binary(type) do
    if String.starts_with?(type, "extension_"), do: @invalid, else: {:ok, state}
  end

  defp validate_event(_, state, _registered), do: {:ok, state}

  defp input_matches?(%{"stage" => "transform.prompt"} = event, state),
    do:
      is_map(state.last) and state.last["role"] == "user" and
        state.last["content"] == event["input"]

  defp input_matches?(%{"stage" => "transform.presentation"} = event, state),
    do:
      is_map(state.last) and state.last["role"] == "assistant" and
        (state.presentation || state.last["content"] || "") == event["input"]

  defp intent_source_matches?(event, state) do
    input =
      case {event["stage"], state.last} do
        {"transform.prompt", %{"role" => "user", "content" => content}} ->
          content

        {"transform.presentation", %{"role" => "assistant"} = message} ->
          state.presentation || message["content"] || ""

        _ ->
          nil
      end

    is_binary(input) and Manifest.sha256(input) == event["input_sha256"] and
      Ipse.Compaction.digest([state.last]) == event["source_message_sha256"]
  end

  defp intent_valid?(event) do
    is_map(event) and Enum.sort(Map.keys(event)) == Enum.sort(@intent_keys) and
      event["type"] == "extension_transform_intent" and event["version"] === 1 and
      is_binary(event["request_id"]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, event["request_id"]) and
      identity_valid?(event["identity"]) and event["stage"] in @stages and
      Enum.all?(~w(input_sha256 context_sha256 source_message_sha256), &hash?(event[&1]))
  end

  defp valid_result?(event) do
    with {:ok, expected} <- build(result_intent(event), event["input"], event["result"]),
         do: expected == event
  end

  defp result_intent(event),
    do:
      event
      |> Map.drop(~w(input output result output_sha256))
      |> Map.put("type", "extension_transform_intent")

  defp result_schema("transform.prompt"),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["append"],
      "properties" => %{"append" => %{"type" => "string", "maxLength" => 4096}}
    }

  defp result_schema("transform.presentation"),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["prefix", "suffix"],
      "properties" =>
        Map.new(~w(prefix suffix), &{&1, %{"type" => "string", "maxLength" => 4096}})
    }

  defp render(%{"stage" => "transform.prompt", "identity" => identity}, input, result),
    do:
      input <>
        "\n\n[Untrusted extension context: #{identity["instance"]}; artifact #{identity["artifact_sha256"]}]\n" <>
        result["append"] <> "\n[/Extension context]"

  defp render(%{"stage" => "transform.presentation"}, input, result),
    do: result["prefix"] <> input <> result["suffix"]

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
