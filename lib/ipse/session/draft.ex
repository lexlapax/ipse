defmodule Ipse.Session.Draft do
  @moduledoc false
  alias Ipse.JSON

  @notice "[Host intent status: the draft was abandoned and must not supply requirements for later work.]"
  @error {:error, :invalid_saved_draft}

  def notice, do: @notice

  def effective(original) do
    request =
      case String.trim_leading(original) do
        "/enhance " <> text -> String.trim(text)
        _ -> original
      end

    "Draft a clearer version of the request below. Do not carry out the request. Return only the proposed request.\n\n" <>
      request
  end

  def draft_config(config) do
    {:ok, mode} = Ipse.Extension.Mode.capture(config)
    rank = %{"normal" => 0, "draft" => 1, "planning" => 2, "read_only" => 3}
    enclosing = Enum.max_by([mode["ceiling"], mode["enclosing_ceiling"]], &rank[&1])

    config
    |> Map.put(:execution_mode, :draft)
    |> Map.put(:enclosing_mode, enclosing)
    |> Map.put(:max_steps, min(config[:max_steps] || 30, 3))
    |> Map.put(:max_response_bytes, min(config[:max_response_bytes] || 65_536, 65_536))
  end

  def started(session, turn, id, original, effective, messages, reported_model, historical_model) do
    %{
      "type" => "draft_started",
      "version" => 1,
      "session_id" => session,
      "turn_id" => turn,
      "draft_id" => id,
      "revision" => 1,
      "input_sha256" => JSON.sha256(original),
      "effective_sha256" => JSON.sha256(effective),
      "prefix_count" => length(messages),
      "prefix_sha256" => JSON.digest(messages),
      "prior_reported_model" => reported_model,
      "prior_historical_model" => historical_model
    }
  end

  def completed(draft, assistant) do
    %{
      "type" => "draft_completed",
      "version" => 1,
      "session_id" => draft.session_id,
      "turn_id" => draft.turn_id,
      "draft_id" => draft.id,
      "revision" => 1,
      "assistant_sha256" => JSON.digest([assistant]),
      "text_sha256" => JSON.sha256(assistant["content"])
    }
  end

  def cancelled(draft, messages) do
    %{
      "type" => "draft_cancelled",
      "version" => 1,
      "session_id" => draft.session_id,
      "turn_id" => draft.turn_id,
      "draft_id" => draft.id,
      "revision" => draft.revision,
      "end_count" => length(messages),
      "segment_sha256" =>
        JSON.digest(
          Enum.slice(messages, draft.prefix_count, length(messages) - draft.prefix_count)
        ),
      "notice_sha256" => JSON.sha256(@notice)
    }
  end

  def replaced(draft, text) do
    %{
      "type" => "draft_replaced",
      "version" => 1,
      "session_id" => draft.session_id,
      "turn_id" => draft.turn_id,
      "draft_id" => draft.id,
      "previous_revision" => draft.revision,
      "revision" => draft.revision + 1,
      "text" => text,
      "text_sha256" => JSON.sha256(text)
    }
  end

  def replaced(draft, text, observation),
    do: replaced(draft, text) |> Map.put("version", 2) |> Map.put("observation", observation)

  def replaced_lines(draft, text, pieces),
    do: replaced(draft, text) |> Map.put("version", 3) |> Map.put("pieces", pieces)

  def accepted(draft) do
    %{
      "type" => "draft_accepted",
      "version" => 1,
      "session_id" => draft.session_id,
      "turn_id" => draft.turn_id,
      "draft_id" => draft.id,
      "revision" => draft.revision,
      "text_sha256" => JSON.sha256(draft.proposal),
      "input_source_id" => draft.input_source_id,
      "question_ids" => draft.question_ids,
      "answer_source_ids" => draft.answer_source_ids,
      "tool_evidence" => draft.tool_evidence
    }
  end

  def accepted(draft, receipt),
    do: accepted(draft) |> Map.put("version", 2) |> Map.put("receipt", receipt)

  def consumed(draft, turn, messages) do
    %{
      "type" => "draft_consumed",
      "version" => 1,
      "session_id" => draft.session_id,
      "turn_id" => draft.turn_id,
      "draft_id" => draft.id,
      "revision" => draft.revision,
      "accepted_turn_id" => turn,
      "text_sha256" => JSON.sha256(draft.proposal),
      "end_count" => length(messages),
      "segment_sha256" =>
        JSON.digest(
          Enum.slice(messages, draft.prefix_count, length(messages) - draft.prefix_count)
        )
    }
  end

  def effect_intent(draft, call) do
    %{
      "type" => "draft_effect_intent",
      "version" => 1,
      "session_id" => draft.session_id,
      "draft_id" => draft.id,
      "revision" => draft.revision,
      "turn_id" => draft.accepted_turn,
      "call_id" => call["id"],
      "call_sha256" => JSON.digest([call]),
      "input_source_id" => draft.input_source_id,
      "question_ids" => draft.question_ids,
      "answer_source_ids" => draft.answer_source_ids,
      "tool_evidence" => draft.tool_evidence
    }
  end

  def text?(text), do: is_binary(text) and String.valid?(text) and byte_size(text) in 1..32_768

  def rebased(draft, messages, references \\ MapSet.new(), native_policy \\ :none) do
    with true <- terminal?(draft),
         {:ok, projected} <- project(draft, messages, references, native_policy) do
      {:ok,
       %{
         "type" => "draft_rebased",
         "version" => 1,
         "session_id" => draft.session_id,
         "draft_id" => draft.id,
         "revision" => draft.revision,
         "before_sha256" => JSON.digest(messages),
         "after_sha256" => JSON.digest(projected)
       }, projected}
    else
      _ -> {:error, :draft_projection_unsafe}
    end
  end

  defp terminal?(%{status: :cancelled, notice: true}), do: true
  defp terminal?(%{status: :consumed, accepted_message: true}), do: true
  defp terminal?(_), do: false

  def withdrawable?(d, messages, references \\ MapSet.new(), native_policy \\ :none)
      when is_list(messages) do
    start = d.prefix_count
    prefix = Enum.take(messages, start)
    segment = Enum.drop(messages, start)

    d.tool_success_count == length(d.tool_evidence) and
      is_integer(start) and start >= 0 and start <= length(messages) and
      JSON.digest(Enum.take(messages, start)) == d.prefix_sha256 and
      Enum.all?(segment, &safe_to_withdraw?(&1, references, native_policy)) and
      native_interval?(prefix, segment, [], native_policy) and
      Ipse.Session.Reference.safe_tail?(prefix)
  rescue
    _ -> false
  end

  # Historical records stay intact. The exact bounded draft interval is removed
  # from subsequent model input only after its native prefix, segment and neutral
  # notice are independently checked against the journaled boundaries.
  def project(draft, messages, references \\ MapSet.new(), native_policy \\ :none)
  def project(nil, messages, _, _) when is_list(messages), do: {:ok, messages}

  def project(%{history: history} = draft, messages, references, native_policy)
      when is_list(history) and is_list(messages) do
    drafts = history ++ [Map.delete(draft, :history)]

    with true <- length(drafts) <= 16,
         true <-
           Enum.all?(
             drafts,
             &match?({:ok, _}, project_one(&1, messages, references, native_policy))
           ),
         intervals <- Enum.filter(drafts, &withdrawn?/1),
         true <- disjoint_intervals?(intervals),
         projected <-
           Enum.reduce(Enum.sort_by(intervals, & &1.prefix_count, :desc), messages, fn d, acc ->
             Enum.take(acc, d.prefix_count) ++ Enum.drop(acc, d.end_count)
           end),
         true <- Ipse.Session.Reference.safe_tail?(projected) do
      {:ok, projected}
    else
      _ -> {:error, :draft_projection_unsafe}
    end
  rescue
    _ -> {:error, :draft_projection_unsafe}
  end

  def project(draft, messages, references, native_policy),
    do: project_one(draft, messages, references, native_policy)

  defp withdrawn?(%{status: :cancelled, notice: true}), do: true
  defp withdrawn?(%{status: :consumed, accepted_message: true}), do: true
  defp withdrawn?(_), do: false

  defp disjoint_intervals?(intervals) do
    intervals
    |> Enum.sort_by(& &1.prefix_count)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a.end_count <= b.prefix_count end)
  end

  defp project_one(%{status: status}, messages, _, _)
       when status in [:pending, :completed, :accepted] and is_list(messages), do: {:ok, messages}

  defp project_one(%{status: :cancelled, notice: true} = d, messages, refs, policy)
       when is_list(messages),
       do: withdraw(d, messages, :cancelled, refs, policy)

  defp project_one(%{status: :cancelled, notice: false} = d, messages, refs, policy)
       when is_list(messages) do
    case withdraw(d, messages, :incomplete, refs, policy) do
      {:ok, _} -> {:ok, messages}
      error -> error
    end
  end

  defp project_one(%{status: :consumed, accepted_message: true} = d, messages, refs, policy)
       when is_list(messages),
       do: withdraw(d, messages, :accepted, refs, policy)

  defp project_one(%{status: :consumed, accepted_message: false} = d, messages, refs, policy)
       when is_list(messages) do
    case withdraw(d, messages, :incomplete, refs, policy) do
      {:ok, _} -> {:ok, messages}
      error -> error
    end
  end

  defp project_one(_, _, _, _), do: {:error, :draft_projection_unsafe}

  defp withdraw(d, messages, kind, references, native_policy) do
    start = d.prefix_count
    finish = d.end_count

    with true <-
           is_integer(start) and is_integer(finish) and start >= 0 and finish >= start and
             if(kind == :incomplete,
               do: finish == length(messages),
               else: finish < length(messages)
             ),
         prefix = Enum.take(messages, start),
         segment = Enum.slice(messages, start, finish - start),
         true <-
           JSON.digest(prefix) == d.prefix_sha256 and JSON.digest(segment) == d.segment_sha256,
         true <-
           kind != :cancelled or
             Enum.at(messages, finish) === %{"role" => "user", "content" => @notice},
         true <- Enum.all?(segment, &safe_to_withdraw?(&1, references, native_policy)),
         true <- native_interval?(prefix, segment, Enum.drop(messages, finish), native_policy),
         projected = prefix ++ Enum.drop(messages, finish),
         true <- Ipse.Session.Reference.safe_tail?(projected) do
      {:ok, projected}
    else
      _ -> {:error, :draft_projection_unsafe}
    end
  rescue
    _ -> {:error, :draft_projection_unsafe}
  end

  defp safe_to_withdraw?(message, references, native_policy),
    do:
      is_map(message) and
        (not Map.has_key?(message, "provider_data") or
           (native_policy == :chatgpt and Ipse.Session.DraftNative.responses_owned?([message]))) and
        not Map.has_key?(message, "ipse_checkpoint") and
        (not Map.has_key?(message, "ipse_reference") or
           (Ipse.Session.Reference.reference?(message) and
              MapSet.member?(references, JSON.digest([message]))))

  defp native_interval?(prefix, segment, tail, policy) do
    if Enum.any?(segment, &Map.has_key?(&1, "provider_data")),
      do:
        policy == :chatgpt and Ipse.Session.DraftNative.isolated_responses?(prefix, segment, tail),
      else: true
  end

  def restore(events, session) when is_list(events) do
    Enum.reduce_while(events, {:ok, nil}, fn event, {:ok, draft} ->
      case step(draft, event, session) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, @error}
      end
    end)
  rescue
    _ -> @error
  end

  def restore(_, _), do: @error

  def advance(draft, event, session), do: step(draft, event, session)

  defp step(nil, %{"type" => "draft_started"} = e, session) do
    if (keys?(
          e,
          ~w(type version session_id turn_id draft_id revision input_sha256 effective_sha256 prefix_count prefix_sha256 prior_reported_model prior_historical_model)
        ) or
          keys?(
            e,
            ~w(type version session_id turn_id draft_id revision input_sha256 effective_sha256 prefix_count prefix_sha256 prior_reported_model prior_historical_model mcp_snapshot)
          )) and
         e["version"] === 1 and e["revision"] === 1 and
         (is_nil(session) or e["session_id"] == session) and
         id?(e["session_id"]) and id?(e["turn_id"]) and id?(e["draft_id"]) and
         JSON.sha256?(e["input_sha256"]) and JSON.sha256?(e["effective_sha256"]) and
         JSON.safe_uint?(e["prefix_count"]) and JSON.sha256?(e["prefix_sha256"]) and
         valid_model?(e["prior_reported_model"]) and valid_model?(e["prior_historical_model"]) do
      {:ok,
       %{
         id: e["draft_id"],
         session_id: e["session_id"],
         turn_id: e["turn_id"],
         input_sha256: e["input_sha256"],
         effective_sha256: e["effective_sha256"],
         prefix_count: e["prefix_count"],
         prefix_sha256: e["prefix_sha256"],
         prior_reported_model: e["prior_reported_model"],
         prior_historical_model: e["prior_historical_model"],
         end_count: nil,
         segment_sha256: nil,
         input: false,
         message: false,
         assistant: nil,
         status: :pending,
         notice: false,
         revision: 1,
         proposal: nil,
         accepted_turn: nil,
         accepted_input: false,
         accepted_message: false,
         accepted_effective: nil,
         input_source_id: nil,
         question_ids: [],
         answer_source_ids: [],
         tool_success_count: 0,
         tool_evidence: [],
         current_turn: nil,
         active_calls: [],
         pending_effect: nil,
         accepted_event: nil,
         history: []
       }}
    else
      @error
    end
  end

  defp step(d, %{"type" => "draft_effect_intent", "version" => 2}, _), do: {:ok, d}

  defp step(nil, %{"type" => type}, _)
       when type in ~w(draft_completed draft_cancelled draft_replaced draft_accepted draft_consumed draft_rebased draft_effect_intent),
       do: @error

  defp step(nil, _, _), do: {:ok, nil}

  defp step(%{status: :cancelled, notice: true} = d, %{"type" => "draft_started"} = e, session),
    do: next_draft(d, e, session)

  defp step(
         %{status: :consumed, accepted_message: true} = d,
         %{"type" => "draft_started"} = e,
         session
       ),
       do: next_draft(d, e, session)

  defp step(_, %{"type" => "draft_started"}, _), do: @error

  defp step(%{status: :pending, input: false} = d, %{"type" => "input_received"} = e, _) do
    if is_binary(e["text"]) and String.valid?(e["text"]) and
         byte_size(e["text"]) in 1..32_768 and
         e["session_id"] == d.session_id and e["turn_id"] == d.turn_id and
         e["text_sha256"] == d.input_sha256 and e["effective_sha256"] == d.effective_sha256 and
         JSON.sha256(effective(e["text"])) == d.effective_sha256,
       do: {:ok, %{d | input: true, input_source_id: e["source_id"]}},
       else: @error
  end

  defp step(
         %{status: :pending, input: true, message: false} = d,
         %{"type" => "message", "message" => %{"role" => "user", "content" => text}},
         _
       ) do
    if is_binary(text) and JSON.sha256(text) == d.effective_sha256,
      do: {:ok, %{d | message: true}},
      else: @error
  end

  defp step(
         %{status: :pending, message: true} = d,
         %{"type" => "message", "message" => %{"role" => "assistant"} = m},
         _
       ) do
    {:ok, %{d | assistant: m}}
  end

  defp step(
         %{status: :pending, message: true} = d,
         %{"type" => "operator_question", "id" => id},
         _
       ) do
    if is_binary(id) and byte_size(id) in 1..128 and id not in d.question_ids and
         length(d.question_ids) < 3 and
         length(d.question_ids) == length(d.answer_source_ids),
       do: {:ok, %{d | question_ids: d.question_ids ++ [id]}},
       else: @error
  end

  defp step(
         %{status: :pending} = d,
         %{
           "type" => "operator_answer",
           "version" => 2,
           "id" => id,
           "origin" => %{"source_id" => source}
         },
         _
       ) do
    if List.last(d.question_ids) == id and
         length(d.question_ids) == length(d.answer_source_ids) + 1 and id?(source),
       do: {:ok, %{d | answer_source_ids: d.answer_source_ids ++ [source]}},
       else: @error
  end

  defp step(%{status: :pending}, %{"type" => "operator_answer"}, _), do: @error

  defp step(
         %{status: :pending} = d,
         %{
           "type" => "message",
           "message" => %{
             "role" => "tool",
             "ipse_tool_outcome" => %{"status" => "result_recorded"}
           }
         },
         _
       ) do
    if d.tool_success_count < 128,
      do: {:ok, %{d | tool_success_count: d.tool_success_count + 1}},
      else: @error
  end

  defp step(
         %{status: :pending} = d,
         %{
           "type" => "lifecycle_tool_outcome",
           "turn_id" => turn,
           "status" => "result_recorded",
           "result_source" => source
         },
         _
       ) do
    if turn == d.turn_id and is_map(source) and length(d.tool_evidence) < 128,
      do: {:ok, %{d | tool_evidence: d.tool_evidence ++ [source]}},
      else: @error
  end

  defp step(
         %{status: :pending, message: true, assistant: m} = d,
         %{"type" => "draft_completed"} = e,
         _
       )
       when is_map(m) do
    if text?(m["content"]) and m["tool_calls"] in [nil, []] and
         length(d.question_ids) == length(d.answer_source_ids) and completed(d, m) === e,
       do: {:ok, %{d | status: :completed, proposal: m["content"]}},
       else: @error
  end

  defp step(
         %{status: :completed, revision: rev} = d,
         %{"type" => "draft_replaced", "text" => text} = e,
         _
       )
       when rev < 100 do
    valid =
      case e do
        %{"version" => 1} ->
          replaced(d, text) === e

        %{"version" => 2, "observation" => observation} ->
          Ipse.Session.Input.valid_observation?(observation, text, 2) and
            replaced(d, text, observation) === e

        %{"version" => 3, "pieces" => pieces} ->
          valid_lines?(text, pieces) and replaced_lines(d, text, pieces) === e

        _ ->
          false
      end

    if text?(text) and valid,
      do: {:ok, %{d | revision: rev + 1, proposal: text}},
      else: @error
  end

  defp step(%{status: :completed} = d, %{"type" => "draft_accepted"} = e, _) do
    valid =
      case e do
        %{"version" => 2, "receipt" => receipt} ->
          Ipse.Session.DraftAcceptance.valid_receipt?(d, receipt) and accepted(d, receipt) === e

        _ ->
          false
      end

    if text?(d.proposal) and d.tool_success_count == length(d.tool_evidence) and valid,
      do: {:ok, %{d | status: :accepted, accepted_event: e}},
      else: @error
  end

  defp step(
         %{status: :accepted} = d,
         %{"type" => "draft_consumed", "accepted_turn_id" => turn} = e,
         _
       ) do
    if keys?(
         e,
         ~w(type version session_id turn_id draft_id revision accepted_turn_id text_sha256 end_count segment_sha256)
       ) and
         e["version"] === 1 and e["session_id"] == d.session_id and e["turn_id"] == d.turn_id and
         e["draft_id"] == d.id and e["revision"] === d.revision and id?(turn) and
         turn != d.turn_id and
         e["text_sha256"] == JSON.sha256(d.proposal) and JSON.safe_uint?(e["end_count"]) and
         e["end_count"] >= d.prefix_count and JSON.sha256?(e["segment_sha256"]),
       do:
         {:ok,
          %{
            d
            | status: :consumed,
              accepted_turn: turn,
              end_count: e["end_count"],
              segment_sha256: e["segment_sha256"]
          }},
       else: @error
  end

  defp step(%{status: :consumed, accepted_input: false} = d, %{"type" => "input_received"} = e, _) do
    if e["session_id"] == d.session_id and e["turn_id"] == d.accepted_turn and
         e["text"] == d.proposal and e["text_sha256"] == JSON.sha256(d.proposal) and
         e["effective_sha256"] == JSON.sha256(d.proposal),
       do:
         {:ok,
          %{
            d
            | accepted_input: true,
              accepted_effective: e["effective_sha256"],
              current_turn: e["turn_id"]
          }},
       else: @error
  end

  defp step(
         %{status: :consumed, accepted_input: true, accepted_message: false} = d,
         %{"type" => "message", "message" => %{"role" => "user", "content" => text}},
         _
       ) do
    if is_binary(text) and JSON.sha256(text) == d.accepted_effective,
      do: {:ok, %{d | accepted_message: true}},
      else: @error
  end

  defp step(%{status: status} = d, %{"type" => "draft_cancelled"} = e, _)
       when status in [:pending, :completed, :accepted] do
    if keys?(
         e,
         ~w(type version session_id turn_id draft_id revision end_count segment_sha256 notice_sha256)
       ) and
         e["version"] === 1 and e["session_id"] == d.session_id and e["turn_id"] == d.turn_id and
         e["draft_id"] == d.id and e["revision"] === d.revision and
         JSON.safe_uint?(e["end_count"]) and e["end_count"] >= d.prefix_count and
         JSON.sha256?(e["segment_sha256"]) and e["notice_sha256"] == JSON.sha256(@notice),
       do:
         {:ok,
          %{
            d
            | status: :cancelled,
              end_count: e["end_count"],
              segment_sha256: e["segment_sha256"]
          }},
       else: @error
  end

  defp step(
         %{status: :cancelled, notice: false} = d,
         %{"type" => "message", "message" => %{"role" => "user", "content" => text}},
         _
       ) do
    if text == @notice, do: {:ok, %{d | notice: true}}, else: @error
  end

  defp step(d, %{"type" => "draft_rebased"} = event, _) when is_map(d) do
    if terminal?(d) and
         keys?(event, ~w(type version session_id draft_id revision before_sha256 after_sha256)) and
         event["version"] === 1 and event["session_id"] == d.session_id and
         event["draft_id"] == d.id and event["revision"] === d.revision and
         JSON.sha256?(event["before_sha256"]) and JSON.sha256?(event["after_sha256"]),
       do: {:ok, nil},
       else: @error
  end

  defp step(_d, %{"type" => type}, _)
       when type in ~w(draft_started draft_completed draft_cancelled draft_replaced draft_accepted draft_consumed),
       do: @error

  defp step(%{status: :cancelled, notice: true} = d, %{"type" => "input_received"}, _),
    do: {:ok, d}

  defp step(
         %{status: :consumed, accepted_message: true} = d,
         %{"type" => "input_received", "turn_id" => turn},
         _
       ),
       do: {:ok, %{d | current_turn: turn, active_calls: [], pending_effect: nil}}

  defp step(
         %{status: :consumed, accepted_message: true} = d,
         %{"type" => "message", "message" => %{"role" => "assistant"} = message},
         _
       ) do
    calls = if is_list(message["tool_calls"]), do: message["tool_calls"], else: []
    {:ok, %{d | active_calls: calls}}
  end

  defp step(
         %{status: :consumed, accepted_message: true} = d,
         %{"type" => "draft_effect_intent", "call_id" => id} = event,
         _
       ) do
    case Enum.find(d.active_calls, &(&1["id"] == id)) do
      call when is_map(call) ->
        if d.current_turn == d.accepted_turn and d.pending_effect == nil and
             effect_intent(d, call) === event,
           do: {:ok, %{d | pending_effect: %{id: id, name: get_in(call, ["function", "name"])}}},
           else: @error

      _ ->
        @error
    end
  end

  defp step(_, %{"type" => "draft_effect_intent"}, _), do: @error

  defp step(d, %{"type" => "input_received"}, _) when is_map(d), do: @error
  defp step(d, _, _), do: {:ok, d}

  defp valid_lines?(text, pieces) when is_list(pieces) and length(pieces) in 1..16 do
    Enum.all?(pieces, fn piece ->
      is_map(piece) and Enum.sort(Map.keys(piece)) == ["observation", "text"] and
        is_binary(piece["text"]) and String.valid?(piece["text"]) and
        not String.contains?(piece["text"], ["\n", "\r"]) and
        Ipse.Session.Input.valid_observation?(piece["observation"], piece["text"], 2)
    end) and Enum.map_join(pieces, "\n", & &1["text"]) == text
  end

  defp valid_lines?(_, _), do: false

  defp next_draft(d, event, session) do
    history = d.history ++ [Map.delete(d, :history)]

    with true <- length(history) < 16,
         {:ok, next} <- step(nil, event, session),
         do: {:ok, %{next | history: history}},
         else: (_ -> @error)
  end

  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp valid_model?(nil), do: true
  defp valid_model?(v), do: Ipse.Provider.model_name(v) == v
  defp keys?(v, keys), do: Enum.sort(Map.keys(v)) == Enum.sort(keys)
end
