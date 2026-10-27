defmodule Ipse.Session.DraftLineage do
  @moduledoc false
  alias Ipse.JSON
  @limit 16
  @error {:error, :invalid_draft_lineage}
  @extension_targets ~w(extension_invocation_intent extension_action_intent extension_model_request extension_decision_request extension_embedding_request extension_transform_intent extension_event_intent extension_feed_intent extension_feed_delivery_intent extension_text_intent extension_continuation_intent)

  def limit, do: @limit

  def entry(accepted, turn) do
    %{
      "draft_id" => accepted["draft_id"],
      "revision" => accepted["revision"],
      "accepted_turn_id" => turn,
      "accepted_sha256" => JSON.digest([accepted]),
      "input_source_id" => accepted["input_source_id"],
      "question_ids" => accepted["question_ids"],
      "answer_source_ids" => accepted["answer_source_ids"],
      "tool_evidence" => accepted["tool_evidence"]
    }
  end

  def intent(session, turn, call, lineages) do
    %{
      "type" => "draft_effect_intent",
      "version" => 2,
      "session_id" => session,
      "turn_id" => turn,
      "call_id" => call["id"],
      "call_sha256" => JSON.digest([call]),
      "possible_source_lineages" => lineages
    }
  end

  def inference_intent(session, turn, request, phase, messages, lineages) do
    %{
      "type" => "draft_inference_intent",
      "version" => 1,
      "session_id" => session,
      "turn_id" => turn,
      "request_id" => request,
      "phase" => phase,
      "input_sha256" => JSON.digest([messages]),
      "possible_source_lineages" => lineages
    }
  end

  def extension_target?(%{"type" => type}) when type in @extension_targets,
    do: true

  def extension_target?(%{"type" => "request_admitted", "kind" => kind})
      when kind not in ["model", "compaction"], do: true

  def extension_target?(%{"type" => "inference_dispatch_intent", "phase" => phase})
      when phase not in ["model", "compaction"], do: true

  def extension_target?(_), do: false

  def extension_intent(session, turn, event, lineages) do
    %{
      "type" => "draft_extension_intent",
      "version" => 1,
      "session_id" => session,
      "turn_id" => turn,
      "target_type" => event["type"],
      "target_sha256" => JSON.digest([event]),
      "possible_source_lineages" => lineages
    }
  end

  # Conservative lineage remains attached after compaction: the host cannot
  # establish that summaries or later turns are independent of earlier inputs.
  def restore(events, session) when is_list(events) do
    session =
      session ||
        Enum.find_value(events, &if(&1["type"] == "draft_consumed", do: &1["session_id"]))

    initial = %{
      lineages: [],
      accepted: nil,
      turn: nil,
      calls: [],
      pending: nil,
      request: nil,
      extension_pending: nil
    }

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
      with {:ok, state} <- extension_step(state, event, session),
           {:ok, next} <- step(state, event, session) do
        {:cont, {:ok, next}}
      else
        _ -> {:halt, @error}
      end
    end)
    |> case do
      {:ok, state} -> {:ok, state.lineages}
      error -> error
    end
  rescue
    _ -> @error
  end

  defp extension_step(s, %{"type" => "draft_extension_intent"} = event, session) do
    if s.lineages != [] and s.extension_pending == nil and event["session_id"] == session and
         event["turn_id"] == s.turn and event["possible_source_lineages"] == s.lineages and
         event["version"] === 1 and JSON.sha256?(event["target_sha256"]) and
         Enum.sort(Map.keys(event)) ==
           ~w(possible_source_lineages session_id target_sha256 target_type turn_id type version),
       do: {:ok, %{s | extension_pending: event}},
       else: @error
  end

  defp extension_step(s, event, session) do
    cond do
      extension_target?(event) and s.lineages != [] ->
        if s.extension_pending === extension_intent(session, s.turn, event, s.lineages),
          do: {:ok, %{s | extension_pending: nil}},
          else: @error

      event["type"] in ~w(input_received lifecycle_epoch_started) ->
        {:ok, %{s | extension_pending: nil}}

      s.extension_pending != nil ->
        @error

      true ->
        {:ok, s}
    end
  end

  defp step(s, %{"type" => "draft_accepted", "version" => 2} = event, _),
    do: {:ok, %{s | accepted: event}}

  defp step(s, %{"type" => "draft_cancelled"}, _), do: {:ok, %{s | accepted: nil}}

  defp step(
         %{accepted: accepted} = s,
         %{"type" => "draft_consumed", "draft_id" => id, "accepted_turn_id" => turn},
         _
       )
       when is_map(accepted) do
    if accepted["draft_id"] == id and length(s.lineages) < @limit,
      do: {:ok, %{s | lineages: s.lineages ++ [entry(accepted, turn)], accepted: nil}},
      else: @error
  end

  defp step(s, %{"type" => "input_received", "turn_id" => turn}, _),
    do: {:ok, %{s | turn: turn, calls: [], pending: nil, request: nil}}

  defp step(
         %{lineages: [_ | _]} = s,
         %{"type" => "request_admitted", "request_id" => id, "turn_id" => turn, "kind" => kind},
         _
       )
       when kind in ["model", "compaction"] do
    if turn == s.turn and s.request == nil,
      do: {:ok, %{s | request: %{id: id, phase: kind, input_sha256: nil}}},
      else: @error
  end

  defp step(
         %{request: %{id: request, phase: phase, input_sha256: nil}} = s,
         %{"type" => "draft_inference_intent"} = event,
         session
       ) do
    if Enum.sort(Map.keys(event)) ==
         ~w(input_sha256 phase possible_source_lineages request_id session_id turn_id type version) and
         event["version"] === 1 and event["session_id"] == session and event["turn_id"] == s.turn and
         event["request_id"] == request and event["phase"] == phase and
         event["possible_source_lineages"] == s.lineages and JSON.sha256?(event["input_sha256"]),
       do: {:ok, put_in(s.request.input_sha256, event["input_sha256"])},
       else: @error
  end

  defp step(_, %{"type" => "draft_inference_intent"}, _), do: @error

  defp step(
         %{request: %{id: id, input_sha256: hash}} = s,
         %{"type" => "inference_dispatch_intent", "request_id" => id, "input_sha256" => hash},
         _
       )
       when is_binary(hash), do: {:ok, s}

  defp step(
         %{lineages: [_ | _]} = s,
         %{"type" => "inference_dispatch_intent", "phase" => phase},
         _
       )
       when phase not in ["model", "compaction"], do: {:ok, s}

  defp step(%{lineages: [_ | _]}, %{"type" => "inference_dispatch_intent"}, _), do: @error

  defp step(
         %{request: %{id: id, input_sha256: hash}} = s,
         %{"type" => "request_finished", "request_id" => id},
         _
       )
       when is_binary(hash), do: {:ok, %{s | request: nil}}

  defp step(%{request: %{id: id}} = _s, %{"type" => "request_finished", "request_id" => id}, _),
    do: @error

  defp step(s, %{"type" => "message", "message" => %{"role" => "assistant"} = message}, _),
    do:
      {:ok, %{s | calls: if(is_list(message["tool_calls"]), do: message["tool_calls"], else: [])}}

  defp step(s, %{"type" => "draft_effect_intent", "call_id" => id} = event, session) do
    case Enum.find(s.calls, &(&1["id"] == id)) do
      call when is_map(call) ->
        if s.lineages != [] and s.pending == nil and
             event === intent(session, s.turn, call, s.lineages),
           do: {:ok, %{s | pending: %{id: id, name: get_in(call, ["function", "name"])}}},
           else: @error

      _ ->
        @error
    end
  end

  defp step(
         %{lineages: [_ | _]} = s,
         %{"type" => "tool_started", "call_id" => id, "name" => name},
         _
       ) do
    if s.pending == %{id: id, name: name}, do: {:ok, %{s | pending: nil}}, else: @error
  end

  defp step(s, _, _), do: {:ok, s}
end
