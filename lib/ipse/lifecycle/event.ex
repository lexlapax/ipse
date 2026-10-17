defmodule Ipse.Lifecycle.Event do
  @moduledoc "Typed host projections of journal facts; choosing a view is not a subscriber permission grant."
  alias Ipse.Lifecycle.Source
  alias Ipse.Extensions.{Manifest, Projection}

  @doc "Project one supported occurrence into metadata or its explicit private view. No callbacks run."
  def project(source, record, view) do
    with true <- is_binary(view) and Source.matches?(source, record),
         {:ok, type, private_view, text, metrics, correlations} <- describe(record, view),
         {:ok, reference, data} <- data(source, view, private_view, text, metrics),
         envelope = %{
           "version" => 1,
           "data_version" => 1,
           "event_id" => source["event_id"],
           "type" => type,
           "source" => reference,
           "origin" => "host",
           "view" => view,
           "correlations" => correlations,
           "data" => data
         },
         :ok <- Ipse.Extension.validate(envelope) do
      {:ok, envelope}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_lifecycle_event}
    end
  rescue
    _ -> {:error, :invalid_lifecycle_event}
  end

  defp describe(%{"type" => "lifecycle_answer_committed"} = record, view) do
    if Ipse.Lifecycle.Answer.valid?(record) do
      key = %{"answer.original" => "original", "answer.presented" => "presented"}[view]

      {:ok, "answer.committed", if(key, do: view), if(key, do: record[key]),
       Map.take(record, ~w(original_bytes presented_bytes)),
       %{
         "turn_id" => record["turn_id"],
         "request_id" => record["request_id"],
         "causing_event_id" => record["effective_source"]["event_id"]
       }}
    else
      {:error, :invalid_lifecycle_event}
    end
  end

  defp describe(record, _view), do: describe(record)

  defp describe(%{"type" => "extension_prompt_received"} = record) do
    if Enum.sort(Map.keys(record)) == ~w(original original_sha256 type version) and
         record["version"] === 1 and text?(record["original"]) and
         record["original_sha256"] == Manifest.sha256(record["original"]) do
      {:ok, "prompt.received", "prompt.original", record["original"],
       %{"input_bytes" => byte_size(record["original"])}, %{}}
    else
      {:error, :invalid_lifecycle_event}
    end
  end

  defp describe(%{"type" => "lifecycle_prompt_received"} = record) do
    if Ipse.Extensions.Subscriptions.valid_received?(record),
      do:
        {:ok, "prompt.received", "prompt.original", record["original"],
         %{"input_bytes" => byte_size(record["original"])}, %{"turn_id" => record["turn_id"]}},
      else: {:error, :invalid_lifecycle_event}
  end

  defp describe(%{"type" => "lifecycle_prompt_committed"} = record) do
    if Ipse.Extensions.Subscriptions.valid_committed?(record),
      do:
        {:ok, "prompt.effective_committed", "prompt.effective", record["text"],
         %{"input_bytes" => byte_size(record["text"])}, %{"turn_id" => record["turn_id"]}},
      else: {:error, :invalid_lifecycle_event}
  end

  defp describe(%{"type" => "message", "message" => %{"role" => "user", "content" => text}}) do
    if text?(text),
      do:
        {:ok, "prompt.expanded_committed", "prompt.expanded", text,
         %{"input_bytes" => byte_size(text)}, %{}},
      else: {:error, :invalid_lifecycle_event}
  end

  defp describe(%{"type" => "extension_transform_result", "stage" => "transform.prompt"} = record) do
    intent =
      record
      |> Map.drop(~w(input output result output_sha256))
      |> Map.put("type", "extension_transform_intent")

    with {:ok, expected} <- Projection.build(intent, record["input"], record["result"]),
         true <- expected == record do
      {:ok, "prompt.projection_committed", "prompt.projection", record["output"],
       %{
         "input_bytes" => byte_size(record["input"]),
         "output_bytes" => byte_size(record["output"])
       },
       %{
         "operation_id" => record["request_id"],
         "artifact_sha256" => record["identity"]["artifact_sha256"]
       }}
    else
      _ -> {:error, :invalid_lifecycle_event}
    end
  end

  defp describe(record), do: Ipse.Lifecycle.Metadata.describe(record)

  defp data(source, "metadata", _private, _text, metrics) do
    with {:ok, reference} <- Source.metadata(source) do
      {:ok, reference, metrics}
    end
  end

  defp data(source, view, view, text, _metrics) when is_binary(text) do
    case Ipse.Extension.validate(%{"text" => text}) do
      :ok -> {:ok, source, %{"text" => text}}
      _ -> {:error, :private_lifecycle_view_too_large}
    end
  end

  defp data(source, view, view, value, _metrics)
       when is_map(value) and view in ~w(tool.input tool.result) do
    if Ipse.Lifecycle.Tool.private_data?(view, value),
      do: {:ok, source, value},
      else: {:error, :private_lifecycle_view_too_large}
  end

  defp data(_, view, view, nil, _), do: {:error, :private_lifecycle_view_too_large}

  defp data(_, _, _, _, _), do: {:error, :lifecycle_view_unavailable}
  defp text?(value), do: is_binary(value) and String.valid?(value)

  def valid_metadata?(event) do
    reference = event["source"]

    Enum.sort(Map.keys(event)) ==
      ~w(correlations data data_version event_id origin source type version view) and
      event["version"] === 1 and event["data_version"] === 1 and event["origin"] == "host" and
      event["view"] == "metadata" and
      Ipse.Lifecycle.Source.valid_metadata?(reference) and
      event["event_id"] == reference["event_id"] and
      event["type"] in metadata_types() and
      Enum.all?(event["data"], fn
        {key, number}
        when key in ~w(input_bytes output_bytes original_bytes presented_bytes source_count tool_count sequence duration_ms action_count) ->
          uint?(number)

        {"kind", kind} ->
          kind in ~w(model compaction extension approval question)

        {"domain", domain} ->
          domain in ~w(tool extension_action delegated_tool native_question extension_question)

        {"previous_state", state} ->
          state in ~w(none closed unclosed)

        {"closure", closure} ->
          closure in ~w(close owner_down cleanup_failure)

        {"cleanup_confirmed", cleanup} ->
          is_boolean(cleanup)

        {"reason", reason} ->
          reason in ~w(limit source_unavailable epoch_unavailable binding_unavailable completed admission_refused worker_failed child_failed child_down timeout bounds result_unavailable cleanup_unconfirmed cancelled owner_down)

        {"finality", finality} ->
          finality in ~w(final partial)

        {key, outcome} when key in ~w(outcome status approval) ->
          outcome in ~w(ok error result_recorded completed failed cancelled interrupted expired unknown denied conflict answered not_started acknowledged approved session_allow not_decided not_required)

        _ ->
          false
      end) and
      Enum.all?(event["correlations"], fn
        {"artifact_sha256", hash} ->
          is_binary(hash) and Regex.match?(~r/\A[0-9a-f]{64}\z/, hash)

        {key, id}
        when key in ~w(tool_id epoch_id previous_epoch_id wait_id request_id attempt_id session_id turn_id parent_session_id parent_request_id invocation_id parent_invocation_id operation_id continuation_id delivery_id resource_id causing_event_id child_id) ->
          is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

        _ ->
          false
      end)
  rescue
    _ -> false
  end

  defp uint?(value), do: is_integer(value) and value in 0..9_007_199_254_740_991

  def metadata_types,
    do:
      ~w(session.created session.started session.resumed session.close_committed session.recording_stopped tool.intent_committed tool.outcome_recorded tool.recording_stopped wait.started wait.finished prompt.received prompt.expanded_committed prompt.projection_committed prompt.effective_committed answer.committed model.admitted model.usage_observed model.finished model.measured tool.started assistant.committed tool.result_recorded context.workspace_committed context.catalog_committed context.extensions_committed context.compaction_committed context.compaction_failed question.waiting question.answered question.closed child.started child.finished turn.settling turn.finished turn.cancelled extension.invocation_admitted extension.invocation_recorded extension.action_admitted extension.action_recorded extension.question_waiting extension.continuation_admitted extension.delivery_admitted extension.delivery_recorded extension.text_admitted extension.text_ready extension.text_closed)
end
