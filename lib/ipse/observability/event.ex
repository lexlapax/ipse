defmodule Ipse.Observability.Event do
  @moduledoc "Diagnostic delivery wraps shared metadata facts without replacing their identity."
  def build(source, record, sequence, elapsed) do
    with {:ok, event} <- Ipse.Lifecycle.Event.project(source, record, "metadata"),
         group = event["type"] |> String.split(".") |> hd(),
         group =
           (cond do
              String.contains?(event["type"], ".compaction_") -> "compaction"
              group in ["assistant", "answer"] -> "stream"
              true -> group
            end),
         true <- group in Ipse.Observability.Config.groups() do
      {:ok,
       %{
         "version" => 1,
         "sequence" => sequence,
         "elapsed_ms" => elapsed,
         "group" => group,
         "level" => level(event),
         "event" => event
       }}
    else
      _ -> {:error, :unsupported_observation}
    end
  end

  def valid?(value) do
    is_map(value) and
      Enum.sort(Map.keys(value)) == ~w(elapsed_ms event group level sequence version) and
      value["version"] === 1 and uint?(value["sequence"]) and value["sequence"] > 0 and
      uint?(value["elapsed_ms"]) and value["group"] in Ipse.Observability.Config.groups() and
      value["level"] in ~w(info error debug) and metadata?(value["event"]) and
      Ipse.Extension.validate(value) == :ok
  rescue
    _ -> false
  end

  defp metadata?(event) do
    reference = event["source"]

    Enum.sort(Map.keys(event)) ==
      ~w(correlations data data_version event_id origin source type version view) and
      event["version"] === 1 and event["data_version"] === 1 and event["origin"] == "host" and
      event["view"] == "metadata" and
      Enum.sort(Map.keys(reference)) == ~w(byte_offset event_id session_id version) and
      Ipse.Lifecycle.Source.valid?(Map.put(reference, "record_sha256", String.duplicate("0", 64))) and
      event["event_id"] == reference["event_id"] and
      event["type"] in ~w(session.created prompt.received prompt.expanded_committed prompt.projection_committed prompt.effective_committed answer.committed model.admitted model.usage_observed model.finished model.measured tool.started assistant.committed tool.result_recorded context.workspace_committed context.catalog_committed context.extensions_committed context.compaction_committed context.compaction_failed question.waiting question.answered question.closed child.started turn.settling turn.finished turn.cancelled extension.invocation_admitted extension.invocation_recorded extension.action_admitted extension.action_recorded extension.question_waiting extension.continuation_admitted extension.delivery_admitted extension.delivery_recorded extension.text_admitted extension.text_ready extension.text_closed) and
      Enum.all?(event["data"], fn
        {key, number}
        when key in ~w(input_bytes output_bytes original_bytes presented_bytes source_count tool_count sequence duration_ms action_count) ->
          uint?(number)

        {"kind", kind} ->
          kind in ~w(model compaction)

        {"finality", finality} ->
          finality in ~w(final partial)

        {key, outcome} when key in ~w(outcome status approval) ->
          outcome in ~w(ok error completed failed cancelled unknown denied conflict answered not_started acknowledged approved session_allow not_decided not_required)

        _ ->
          false
      end) and
      Enum.all?(event["correlations"], fn
        {"artifact_sha256", hash} ->
          is_binary(hash) and Regex.match?(~r/\A[0-9a-f]{64}\z/, hash)

        {key, id}
        when key in ~w(request_id attempt_id session_id turn_id parent_session_id parent_request_id invocation_id parent_invocation_id operation_id continuation_id delivery_id resource_id causing_event_id child_id) ->
          is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

        _ ->
          false
      end)
  end

  defp level(event) do
    cond do
      event["data"]["outcome"] in ~w(failed unknown) or
        event["data"]["status"] in ~w(error failed unknown) or
          String.ends_with?(event["type"], ".compaction_failed") ->
        "error"

      event["type"] == "model.usage_observed" ->
        "debug"

      true ->
        "info"
    end
  end

  defp uint?(v), do: is_integer(v) and v in 0..9_007_199_254_740_991
end
