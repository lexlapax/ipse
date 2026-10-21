defmodule Ipse.Session.Saved do
  @moduledoc "Pure reconstruction from loaded journal events; source-page recovery stays with Session."
  alias Ipse.{Skills, Questions, ToolCall}
  alias Ipse.Extensions.{Actions, Feeds, Invocation, Projection, ResultSource}

  @doc "Rebuild pure resume facts after the owner has validated sources and reloaded its journal."
  def restore(events, id) do
    with {:ok, accounting} <- Ipse.Usage.restore(events, id),
         {:ok, extension_state} <- Actions.restore(events),
         {:ok, result_sources} <- ResultSource.restore(events),
         {:ok, messages} <- context(events),
         {:ok, _research} <- Ipse.Research.restore(events),
         {:ok, question, messages} <- restore_question(events, messages),
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
      restore_validated_context(events)
    end
  end

  defp restore_validated_context(events) do
    Enum.reduce_while(events, {:ok, []}, fn
      %{"type" => "extension_invocation_result", "descriptor" => %{"stage" => "invoke.tool"}} =
          event,
      {:ok, messages} ->
        {:cont, {:ok, [Invocation.tool_message(event) | messages]}}

      %{"type" => "message", "message" => %{"ipse_extension_result" => _} = message},
      {:ok, messages} ->
        if List.first(messages) == message,
          do: {:cont, {:ok, messages}},
          else: {:halt, {:error, :invalid_extension_invocation}}

      %{"type" => "extension_transform_intent"} = event, {:ok, messages} ->
        messages = restore_messages(Enum.reverse(messages))

        case Projection.validate_intent_context(messages, event) do
          :ok -> {:cont, {:ok, Enum.reverse(messages)}}
          error -> {:halt, error}
        end

      %{"type" => "extension_transform_result"} = event, {:ok, messages} ->
        case Projection.apply(restore_messages(Enum.reverse(messages)), event) do
          {:ok, projected} -> {:cont, {:ok, Enum.reverse(projected)}}
          error -> {:halt, error}
        end

      %{"type" => "handoff_imported", "message" => message}, {:ok, messages} ->
        {:cont, {:ok, [message | messages]}}

      %{"type" => type, "message" => message}, {:ok, messages}
      when type in ["message", "operator_answer", "operator_question_closed"] and is_map(message) ->
        {:cont, {:ok, [message | messages]}}

      %{"type" => "context_compacted"} = event, {:ok, messages} ->
        messages = restore_messages(Enum.reverse(messages))
        count = event["covered_messages"]

        if event["version"] == 1 and is_integer(count) and count > 0 and
             count <= length(messages) and
             Ipse.Compaction.valid_checkpoint?(event["checkpoint"]) and
             Ipse.JSON.digest(Enum.take(messages, count)) == event["prefix_sha256"] do
          {:cont, {:ok, Enum.reverse([event["checkpoint"] | Enum.drop(messages, count)])}}
        else
          {:halt, {:error, :invalid_compaction_checkpoint}}
        end

      %{"type" => "tool_results_compacted"} = event, {:ok, messages} ->
        case Ipse.Compaction.restore_tool_results(restore_messages(Enum.reverse(messages)), event) do
          {:ok, projected} -> {:cont, {:ok, Enum.reverse(projected)}}
          error -> {:halt, error}
        end

      _, acc ->
        {:cont, acc}
    end)
    |> case do
      {:ok, messages} -> {:ok, restore_messages(Enum.reverse(messages))}
      error -> error
    end
  end

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

  defp restore_question(events, messages) do
    # The whole history has already passed context/1. Project each
    # prefix for its checkpoint hash without repeating every durable reducer.
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, nil}, fn
      {%{"type" => "operator_question"} = event, index}, {:ok, nil} ->
        call = event["call"]

        with true <- event["version"] == 1 and is_map(call),
             true <-
               event["id"] == call["id"] and ToolCall.valid_id?(call["id"]),
             true <- get_in(call, ["function", "name"]) == "ask_operator",
             {:ok, args} <- Jason.decode(get_in(call, ["function", "arguments"])),
             {:ok, ^args} <- Questions.validate(event["arguments"]),
             true <-
               is_integer(event["steps"]) and event["steps"] >= 0 and event["steps"] <= 100_000,
             {:ok, prefix} <- restore_validated_context(Enum.take(events, index)),
             prefix = remove_question_placeholder(prefix, call["id"]),
             true <-
               length(prefix) == event["covered_messages"] and
                 Ipse.JSON.digest(prefix) == event["prefix_sha256"],
             true <-
               Enum.any?(prefix, fn m ->
                 m["role"] == "assistant" and call in (m["tool_calls"] || [])
               end) do
          {:cont, {:ok, %{id: call["id"], call: call, arguments: args, steps: event["steps"]}}}
        else
          _ -> {:halt, {:error, :invalid_operator_question_checkpoint}}
        end

      {%{"type" => type} = event, _}, {:ok, question}
      when type in ["operator_answer", "operator_question_closed"] ->
        if valid_question_end?(event, question),
          do: {:cont, {:ok, nil}},
          else: {:halt, {:error, :invalid_operator_question_checkpoint}}

      {%{"type" => "operator_question"}, _}, _ ->
        {:halt, {:error, :invalid_operator_question_checkpoint}}

      _, state ->
        {:cont, state}
    end)
    |> case do
      {:ok, nil} -> {:ok, nil, messages}
      {:ok, question} -> {:ok, question, remove_question_placeholder(messages, question.id)}
      error -> error
    end
  rescue
    _ -> {:error, :invalid_operator_question_checkpoint}
  end

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
