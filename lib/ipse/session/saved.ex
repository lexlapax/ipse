defmodule Ipse.Session.Saved do
  @moduledoc "Pure reconstruction from loaded journal events; source-page recovery stays with Session."
  alias Ipse.{Skills, Questions, ToolCall}
  alias Ipse.Extensions.{Actions, Feeds, Invocation, Projection, ResultSource}

  @doc "Rebuild pure resume facts after the owner has validated sources and reloaded its journal."
  def restore(events, id) do
    with {:ok, accounting} <- Ipse.Usage.restore(events, id),
         {:ok, extension_state} <- Actions.restore(events),
         {:ok, result_sources} <- ResultSource.restore(events),
         :ok <- validate_context_events(events),
         {:ok, messages, native} <- project(events, :validate),
         {:ok, _research} <- Ipse.Research.restore(events),
         {:ok, question, messages} <- finish_question(native, messages),
         {:ok, question, messages} <- restore_extension_question(events, messages, question) do
      {:ok,
       %{
         accounting: accounting,
         extension_state: extension_state,
         result_sources: result_sources,
         messages: messages,
         question: question,
         historical_model: historical_model(events),
         last_request_id: request_field(events, "request_id"),
         turn_id: request_field(events, "turn_id")
       }}
    end
  end

  defp reported_model(%{"provider_data" => data}) when is_map(data),
    do: Ipse.RuntimeInfo.model_name(data["reported_model"])

  defp reported_model(_), do: nil

  def event_final(events, messages) do
    presentation = Projection.presentation(events)

    if presentation != "",
      do: presentation,
      else:
        Enum.reverse(messages)
        |> Enum.find_value("", fn message ->
          if message["role"] == "assistant" and message["tool_calls"] in [nil, []],
            do: message["content"]
        end)
  end

  defp request_field(events, field) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "request_admitted", "kind" => "model"} = event -> event[field]
      _ -> nil
    end)
  end

  defp historical_model(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "message", "message" => %{"role" => "assistant"} = message} ->
        {:found, reported_model(message)}

      _ ->
        nil
    end)
    |> case do
      {:found, model} -> model
      nil -> nil
    end
  end

  def context(events) do
    with :ok <- validate_context_events(events),
         {:ok, messages, _} <- project(events, :ignore) do
      {:ok, messages}
    end
  end

  defp validate_context_events(events) do
    with :ok <- Ipse.Journal.Limits.validate_events(events),
         :ok <- Ipse.Handoff.validate_events(events),
         :ok <- Skills.validate_events(events),
         {:ok, _} <- Ipse.Lifecycle.Runtime.restore(events),
         {:ok, _} <- Ipse.Lifecycle.Tool.restore(events),
         {:ok, _} <- Ipse.Lifecycle.Child.restore(events),
         :ok <- Ipse.Observability.Resources.validate(events),
         {:ok, _} <- Feeds.validate(events),
         {:ok, _} <- Ipse.Usage.restore(events),
         :ok <- Projection.validate_events(events) do
      :ok
    end
  end

  defp project(events, question_mode) do
    Enum.reduce_while(events, {:ok, [], {:ok, nil}}, fn event, {:ok, messages, native} ->
      native =
        if question_mode == :validate,
          do: question_step(event, native, messages),
          else: native

      case context_step(event, messages) do
        {:ok, messages} -> {:cont, {:ok, messages, native}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, messages, native} -> {:ok, restore_messages(Enum.reverse(messages)), native}
      error -> error
    end
  end

  defp context_step(
         %{"type" => "extension_invocation_result", "descriptor" => %{"stage" => "invoke.tool"}} =
           event,
         messages
       ),
       do: {:ok, [Invocation.tool_message(event) | messages]}

  defp context_step(
         %{"type" => "message", "message" => %{"ipse_extension_result" => _} = message},
         messages
       ) do
    if List.first(messages) == message,
      do: {:ok, messages},
      else: {:error, :invalid_extension_invocation}
  end

  defp context_step(%{"type" => "extension_transform_intent"} = event, messages) do
    messages = restore_messages(Enum.reverse(messages))

    case Projection.validate_intent_context(messages, event) do
      :ok -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp context_step(%{"type" => "extension_transform_result"} = event, messages) do
    case Projection.apply(restore_messages(Enum.reverse(messages)), event) do
      {:ok, projected} -> {:ok, Enum.reverse(projected)}
      error -> error
    end
  end

  defp context_step(%{"type" => "handoff_imported", "message" => message}, messages),
    do: {:ok, [message | messages]}

  defp context_step(%{"type" => type, "message" => message}, messages)
       when type in ["message", "operator_answer", "operator_question_closed"] and is_map(message),
       do: {:ok, [message | messages]}

  defp context_step(%{"type" => "context_compacted"} = event, messages) do
    messages = restore_messages(Enum.reverse(messages))
    count = event["covered_messages"]

    if event["version"] == 1 and is_integer(count) and count > 0 and
         count <= length(messages) and Ipse.Compaction.valid_checkpoint?(event["checkpoint"]) and
         Ipse.JSON.digest(Enum.take(messages, count)) == event["prefix_sha256"] do
      {:ok, Enum.reverse([event["checkpoint"] | Enum.drop(messages, count)])}
    else
      {:error, :invalid_compaction_checkpoint}
    end
  end

  defp context_step(%{"type" => "tool_results_compacted"} = event, messages) do
    case Ipse.Compaction.restore_tool_results(restore_messages(Enum.reverse(messages)), event) do
      {:ok, projected} -> {:ok, Enum.reverse(projected)}
      error -> error
    end
  end

  defp context_step(_, messages), do: {:ok, messages}

  defp restore_messages([]), do: []

  defp restore_messages([%{"role" => "assistant", "tool_calls" => calls} = message | rest])
       when is_list(calls) do
    {results, tail} = Enum.split_while(rest, &(&1["role"] == "tool"))
    by_id = Enum.group_by(results, & &1["tool_call_id"])

    {ordered, _remaining} =
      Enum.map_reduce(calls, by_id, fn call, pending ->
        case Map.get(pending, call["id"], []) do
          [result | remaining] ->
            {result, Map.put(pending, call["id"], remaining)}

          [] ->
            {%{
               "role" => "tool",
               "tool_call_id" => call["id"],
               "content" =>
                 "Outcome unknown: session interrupted before a result was recorded. Inspect the workspace before retrying.",
               "ipse_tool_outcome" => %{"status" => "unknown", "approval" => "historical_unknown"}
             }, pending}
        end
      end)

    [message | ordered] ++ restore_messages(tail)
  end

  defp restore_messages([message | rest]), do: [message | restore_messages(rest)]

  defp restore_extension_question(events, messages, native) do
    with {:ok, state} <- Actions.restore(events) do
      if state.question do
        with true <- is_nil(native),
             parent = state.parent,
             call =
               if(parent["descriptor"]["stage"] == "invoke.tool",
                 do:
                   Enum.find_value(Enum.reverse(messages), fn message ->
                     Enum.find(
                       message["tool_calls"] || [],
                       &(&1["id"] == parent["parent_call_id"])
                     )
                   end)
               ),
             true <- parent["descriptor"]["stage"] != "invoke.tool" or is_map(call) do
          question = %{
            kind: :extension,
            id: state.action["operation_id"],
            arguments: state.action["request"]["arguments"],
            parent: parent,
            action: state.action,
            results: state.results,
            steps: state.question["steps"],
            call: call
          }

          messages =
            if call, do: remove_question_placeholder(messages, call["id"]), else: messages

          {:ok, question, messages}
        else
          _ -> {:error, :invalid_extension_question}
        end
      else
        {:ok, native, messages}
      end
    end
  end

  defp finish_question({:ok, nil}, messages), do: {:ok, nil, messages}

  defp finish_question({:ok, question}, messages),
    do: {:ok, question, remove_question_placeholder(messages, question.id)}

  defp finish_question(error, _messages), do: error

  defp question_step(_, {:error, _} = error, _messages), do: error

  defp question_step(%{"type" => "operator_question"} = event, {:ok, nil}, messages) do
    call = event["call"]

    with true <- event["version"] == 1 and is_map(call),
         true <- event["id"] == call["id"] and ToolCall.valid_id?(call["id"]),
         true <- get_in(call, ["function", "name"]) == "ask_operator",
         {:ok, args} <- Jason.decode(get_in(call, ["function", "arguments"])),
         {:ok, ^args} <- Questions.validate(event["arguments"]),
         true <- is_integer(event["steps"]) and event["steps"] >= 0 and event["steps"] <= 100_000,
         prefix =
           restore_messages(Enum.reverse(messages)) |> remove_question_placeholder(call["id"]),
         true <-
           length(prefix) == event["covered_messages"] and
             Ipse.JSON.digest(prefix) == event["prefix_sha256"],
         true <-
           Enum.any?(prefix, fn m ->
             m["role"] == "assistant" and call in (m["tool_calls"] || [])
           end) do
      {:ok, %{id: call["id"], call: call, arguments: args, steps: event["steps"]}}
    else
      _ -> {:error, :invalid_operator_question_checkpoint}
    end
  rescue
    _ -> {:error, :invalid_operator_question_checkpoint}
  end

  defp question_step(%{"type" => type} = event, {:ok, question}, _messages)
       when type in ["operator_answer", "operator_question_closed"] do
    if valid_question_end?(event, question),
      do: {:ok, nil},
      else: {:error, :invalid_operator_question_checkpoint}
  rescue
    _ -> {:error, :invalid_operator_question_checkpoint}
  end

  defp question_step(%{"type" => "operator_question"}, _native, _messages),
    do: {:error, :invalid_operator_question_checkpoint}

  defp question_step(_, native, _messages), do: native

  defp valid_question_end?(_, nil), do: false

  defp valid_question_end?(event, question) do
    message = event["message"]

    expected_status =
      if event["type"] == "operator_answer", do: "result_recorded", else: "not_started"

    valid =
      event["version"] == 1 and event["id"] == question.id and is_map(message) and
        Map.delete(message, "content") ==
          Map.delete(Questions.tool_result(question.call, "", expected_status), "content")

    if valid and event["type"] == "operator_answer" do
      case Jason.decode(message["content"]) do
        {:ok,
         %{"answers" => answers, "notice" => "Clarification only; no action permission."} = result}
        when map_size(result) == 2 ->
          match?({:ok, _}, Questions.validate_answers(question.arguments, answers))

        _ ->
          false
      end
    else
      valid and
        message["content"] ==
          "Clarification cancelled without an answer. No action was authorized."
    end
  end

  defp remove_question_placeholder(messages, id) do
    Enum.reject(messages, fn m ->
      m["role"] == "tool" and m["tool_call_id"] == id and
        get_in(m, ["ipse_tool_outcome", "approval"]) == "historical_unknown"
    end)
  end
end
