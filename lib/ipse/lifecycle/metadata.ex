defmodule Ipse.Lifecycle.Metadata do
  @moduledoc "Allowlisted metadata projections of committed facts, independent of diagnostic delivery."
  @error {:error, :invalid_lifecycle_event}
  @approval ~w(approved session_allow denied not_decided not_required)
  @extensions %{
    "extension_invocation_intent" => {"extension.invocation_admitted", ~w(invocation_id)},
    "extension_invocation_result" => {"extension.invocation_recorded", ~w(invocation_id)},
    "extension_action_intent" =>
      {"extension.action_admitted", ~w(parent_invocation_id operation_id)},
    "extension_action_result" =>
      {"extension.action_recorded", ~w(parent_invocation_id operation_id)},
    "extension_question" => {"extension.question_waiting", ~w(parent_invocation_id operation_id)},
    "extension_continuation_intent" =>
      {"extension.continuation_admitted", ~w(parent_invocation_id operation_id continuation_id)},
    "extension_event_intent" => {"extension.delivery_admitted", ~w(delivery_id turn_id)},
    "extension_event_result" => {"extension.delivery_recorded", ~w(delivery_id turn_id)},
    "extension_text_intent" => {"extension.text_admitted", ~w(resource_id session_id turn_id)},
    "extension_text_ready" => {"extension.text_ready", ~w(resource_id)},
    "extension_text_closed" => {"extension.text_closed", ~w(resource_id)}
  }

  def describe(%{"type" => "session", "metadata" => metadata}) when is_map(metadata),
    do: result("session.created", %{}, %{})

  def describe(%{"type" => type} = record)
      when type in ~w(lifecycle_tool_intent lifecycle_tool_outcome lifecycle_tool_recording_stopped),
      do: Ipse.Lifecycle.Tool.describe(record)

  def describe(%{"type" => type} = record)
      when type in ~w(lifecycle_epoch_started lifecycle_epoch_closed lifecycle_wait_started lifecycle_wait_finished lifecycle_recording_stopped),
      do: Ipse.Lifecycle.Runtime.describe(record)

  def describe(%{"type" => "request_admitted", "version" => 1} = record),
    do:
      fields(
        "model.admitted",
        record,
        [],
        ~w(request_id attempt_id session_id turn_id),
        ~w(parent_session_id parent_request_id),
        %{"kind" => ~w(model compaction)}
      )

  def describe(%{"type" => "request_usage_observed", "version" => 1} = record),
    do: fields("model.usage_observed", record, ~w(sequence), ~w(request_id attempt_id))

  def describe(%{"type" => "request_finished", "version" => 1} = record),
    do:
      fields("model.finished", record, ~w(duration_ms), ~w(request_id attempt_id), [], %{
        "outcome" => ~w(completed failed cancelled),
        "finality" => ~w(final partial)
      })

  def describe(%{"type" => "request_measured"} = record),
    do:
      fields("model.measured", record, ~w(duration_ms), [], [], %{
        "kind" => ~w(model compaction),
        "outcome" => ~w(completed failed cancelled)
      })

  def describe(%{"type" => "tool_started"} = record),
    do: fields("tool.started", record, [], [], [], %{"approval" => @approval})

  def describe(%{"type" => "message", "message" => %{"role" => "assistant"} = message} = record),
    do: message("assistant.committed", message, Map.take(record, ~w(request_id)))

  def describe(%{"type" => "message", "message" => %{"role" => "tool"} = message}),
    do: message("tool.result_recorded", message, %{})

  def describe(%{"type" => "workspace_context_snapshot", "snapshot" => %{"sources" => sources}})
      when is_list(sources),
      do: result("context.workspace_committed", %{"source_count" => length(sources)}, %{})

  def describe(%{"type" => "mcp_catalog", "version" => 1, "tools" => tools}) when is_list(tools),
    do: result("context.catalog_committed", %{"tool_count" => length(tools)}, %{})

  def describe(%{"type" => "extension_context_snapshot", "version" => 1} = record),
    do: fields("context.extensions_committed", record, [], ~w(request_id))

  def describe(%{"type" => type}) when type in ~w(context_compacted tool_results_compacted),
    do: result("context.compaction_committed", %{}, %{})

  def describe(%{"type" => "compaction_failed"}),
    do: result("context.compaction_failed", %{}, %{})

  def describe(%{"type" => type, "version" => 1})
      when type in ~w(operator_question operator_answer operator_question_closed),
      do:
        result(
          %{
            "operator_question" => "question.waiting",
            "operator_answer" => "question.answered",
            "operator_question_closed" => "question.closed"
          }[type],
          %{},
          %{}
        )

  def describe(%{"type" => "delegation_started"} = record),
    do: fields("child.started", record, [], ~w(child_id))

  def describe(%{"type" => "lifecycle_turn_settling", "version" => 1} = record),
    do: fields("turn.settling", record, [], ~w(turn_id))

  def describe(%{"type" => "turn_finished"} = record),
    do: fields("turn.finished", record, [], [], [], %{"status" => ~w(ok error cancelled)})

  def describe(%{"type" => "cancelled"}), do: result("turn.cancelled", %{}, %{})

  def describe(%{"type" => type, "version" => 1} = record)
      when is_map_key(@extensions, type) do
    {event, ids} = @extensions[type]

    with {:ok, _, _, _, _, correlations} <- fields(event, record, [], ids),
         {:ok, data} <- extension_data(type, record),
         {:ok, correlations} <- trigger(record, correlations) do
      result(event, data, correlations)
    else
      _ -> @error
    end
  end

  def describe(_), do: {:error, :unsupported_lifecycle_record}

  defp extension_data("extension_event_result", record),
    do: enum_data(record, %{"outcome" => ~w(acknowledged completed failed unknown not_started)})

  defp extension_data("extension_action_result", %{"outcome" => outcome}),
    do:
      enum_data(outcome, %{"status" => ~w(ok conflict denied unknown answered cancelled failed)})

  defp extension_data("extension_invocation_result", record),
    do: numeric_data(record, ~w(action_count))

  defp extension_data(_, _), do: {:ok, %{}}

  defp trigger(%{"event_trigger" => trigger}, correlations) do
    if Ipse.Extensions.EventJob.valid_trigger?(trigger) do
      {:ok,
       Map.merge(correlations, %{
         "delivery_id" => trigger["delivery_id"],
         "causing_event_id" => trigger["event_id"]
       })}
    else
      @error
    end
  end

  defp trigger(_, correlations), do: {:ok, correlations}

  defp message(type, %{"content" => content}, correlations)
       when is_binary(content) do
    if String.valid?(content) and Enum.all?(correlations, fn {_, value} -> id?(value) end),
      do: result(type, %{"output_bytes" => byte_size(content)}, correlations),
      else: @error
  end

  defp message(_, _, _), do: @error

  defp fields(type, record, numbers, required_ids, optional_ids \\ [], enums \\ %{}) do
    with {:ok, data} <- numeric_data(record, numbers),
         {:ok, dimensions} <- enum_data(record, enums),
         true <- Enum.all?(required_ids, &id?(record[&1])),
         true <- Enum.all?(optional_ids, &(is_nil(record[&1]) or id?(record[&1]))) do
      correlations =
        Map.take(record, required_ids ++ optional_ids)
        |> Map.reject(fn {_, value} -> is_nil(value) end)

      result(type, Map.merge(data, dimensions), correlations)
    else
      _ -> @error
    end
  end

  defp numeric_data(record, keys) do
    if Enum.all?(keys, &uint?(record[&1])),
      do: {:ok, Map.take(record, keys)},
      else: @error
  end

  defp enum_data(record, enums) do
    if Enum.all?(enums, fn {key, values} -> record[key] in values end),
      do: {:ok, Map.take(record, Map.keys(enums))},
      else: @error
  end

  defp result(type, data, correlations), do: {:ok, type, nil, nil, data, correlations}
  defp uint?(value), do: is_integer(value) and value in 0..9_007_199_254_740_991
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
