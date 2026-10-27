defmodule Ipse.Session.Lifecycle do
  @moduledoc "Typed host projections of journal facts; choosing a view is not a subscriber permission grant."
  alias Ipse.Journal
  alias Ipse.Extension.Projection

  @doc "Project one supported occurrence into metadata or its explicit private view. No callbacks run."
  def project(source, record, view) do
    with true <- is_binary(view) and Journal.source_matches?(source, record),
         {:ok, type, private_view, text, metrics, correlations} <- describe(record, view),
         {:ok, reference, data} <- data(source, view, private_view, text, metrics),
         envelope = %{
           "version" => 1,
           "data_version" => if(record["approval"] == "saved_consent", do: 2, else: 1),
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
    if valid_answer?(record) do
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
         record["original_sha256"] == Ipse.JSON.sha256(record["original"]) do
      {:ok, "prompt.received", "prompt.original", record["original"],
       %{"input_bytes" => byte_size(record["original"])}, %{}}
    else
      {:error, :invalid_lifecycle_event}
    end
  end

  defp describe(%{"type" => "lifecycle_prompt_received"} = record) do
    if Ipse.Extension.Subscriptions.valid_received?(record),
      do:
        {:ok, "prompt.received", "prompt.original", record["original"],
         %{"input_bytes" => byte_size(record["original"])}, %{"turn_id" => record["turn_id"]}},
      else: {:error, :invalid_lifecycle_event}
  end

  defp describe(%{"type" => "lifecycle_prompt_committed"} = record) do
    if Ipse.Extension.Subscriptions.valid_committed?(record),
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

  defp describe(record), do: describe_metadata(record)

  defp data(source, "metadata", _private, _text, metrics) do
    with {:ok, reference} <- Journal.source_metadata(source) do
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
    if Ipse.Session.ToolLifecycle.private_data?(view, value),
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
      event["version"] === 1 and valid_data_version?(event) and event["origin"] == "host" and
      event["view"] == "metadata" and
      Ipse.Journal.valid_source_metadata?(reference) and
      event["event_id"] == reference["event_id"] and
      event["type"] in metadata_types() and
      Enum.all?(event["data"], fn
        {key, number}
        when key in ~w(input_bytes output_bytes original_bytes presented_bytes source_count tool_count sequence duration_ms action_count) ->
          Ipse.JSON.safe_uint?(number)

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
          outcome in ~w(ok error result_recorded completed failed cancelled interrupted expired unknown denied conflict answered not_started acknowledged approved session_allow not_decided not_required) or
            (key == "approval" and outcome == "saved_consent" and event["data_version"] === 2)

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

  def metadata_types,
    do:
      ~w(session.created session.started session.resumed session.close_committed session.recording_stopped tool.intent_committed tool.outcome_recorded tool.recording_stopped wait.started wait.finished prompt.received prompt.expanded_committed prompt.projection_committed prompt.effective_committed answer.committed model.admitted model.usage_observed model.finished model.measured tool.started assistant.committed tool.result_recorded context.workspace_committed context.catalog_committed context.extensions_committed context.compaction_committed context.compaction_failed question.waiting question.answered question.closed child.started child.finished turn.settling turn.finished turn.cancelled extension.invocation_admitted extension.invocation_recorded extension.action_admitted extension.action_recorded extension.question_waiting extension.continuation_admitted extension.delivery_admitted extension.delivery_recorded extension.text_admitted extension.text_ready extension.text_closed)

  @error {:error, :invalid_lifecycle_event}
  @approval ~w(approved session_allow denied not_decided not_required)
  defp valid_data_version?(event) do
    event["data_version"] === 1 or
      (event["data_version"] === 2 and
         event["type"] in ~w(tool.started tool.intent_committed tool.outcome_recorded extension.invocation_admitted extension.invocation_recorded extension.action_admitted extension.action_recorded))
  end

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

  defp describe_metadata(%{"type" => "session", "metadata" => metadata}) when is_map(metadata),
    do: result("session.created", %{}, %{})

  defp describe_metadata(%{"type" => type} = record)
       when type in ~w(lifecycle_tool_intent lifecycle_tool_outcome lifecycle_tool_recording_stopped),
       do: Ipse.Session.ToolLifecycle.describe(record)

  defp describe_metadata(%{"type" => type} = record)
       when type in ~w(lifecycle_epoch_started lifecycle_epoch_closed lifecycle_wait_started lifecycle_wait_finished lifecycle_recording_stopped),
       do: Ipse.Session.RuntimeLifecycle.describe(record)

  defp describe_metadata(
         %{"type" => "request_admitted", "version" => 2, "operation" => "embedding"} = record
       ),
       do:
         fields(
           "embedding.admitted",
           record,
           [],
           ~w(request_id attempt_id session_id turn_id),
           ~w(parent_session_id parent_request_id),
           %{"kind" => ["extension"]}
         )

  defp describe_metadata(
         %{"type" => "request_usage_observed", "version" => 2, "operation" => "embedding"} =
           record
       ),
       do: fields("embedding.usage_observed", record, ~w(sequence), ~w(request_id attempt_id))

  defp describe_metadata(
         %{"type" => "request_finished", "version" => 2, "operation" => "embedding"} = record
       ),
       do:
         fields("embedding.finished", record, ~w(duration_ms), ~w(request_id attempt_id), [], %{
           "outcome" => ~w(completed failed cancelled),
           "finality" => ~w(final partial)
         })

  defp describe_metadata(%{"type" => "request_admitted", "version" => 1} = record),
    do:
      fields(
        "model.admitted",
        record,
        [],
        ~w(request_id attempt_id session_id turn_id),
        ~w(parent_session_id parent_request_id),
        %{"kind" => ~w(model compaction extension)}
      )

  defp describe_metadata(%{"type" => "request_usage_observed", "version" => 1} = record),
    do: fields("model.usage_observed", record, ~w(sequence), ~w(request_id attempt_id))

  defp describe_metadata(%{"type" => "request_finished", "version" => 1} = record),
    do:
      fields("model.finished", record, ~w(duration_ms), ~w(request_id attempt_id), [], %{
        "outcome" => ~w(completed failed cancelled),
        "finality" => ~w(final partial)
      })

  defp describe_metadata(%{"type" => "request_measured"} = record),
    do:
      fields("model.measured", record, ~w(duration_ms), [], [], %{
        "kind" => ~w(model compaction),
        "outcome" => ~w(completed failed cancelled)
      })

  defp describe_metadata(%{"type" => "tool_started", "version" => 2} = record) do
    if record["approval"] == "saved_consent" and
         Ipse.Extension.SemanticAdmission.valid_outer_receipt?(
           record["semantic_binding"],
           record["semantic_binding"]["pin"]["session_id"]
         ),
       do: fields("tool.started", record, [], [], [], %{"approval" => ["saved_consent"]}),
       else: @error
  end

  defp describe_metadata(%{"type" => "tool_started"} = record),
    do: fields("tool.started", record, [], [], [], %{"approval" => @approval})

  defp describe_metadata(
         %{"type" => "message", "message" => %{"role" => "assistant"} = message} = record
       ),
       do: message("assistant.committed", message, Map.take(record, ~w(request_id)))

  defp describe_metadata(%{"type" => "message", "message" => %{"role" => "tool"} = message}),
    do: message("tool.result_recorded", message, %{})

  defp describe_metadata(%{
         "type" => "workspace_context_snapshot",
         "snapshot" => %{"sources" => sources}
       })
       when is_list(sources),
       do: result("context.workspace_committed", %{"source_count" => length(sources)}, %{})

  defp describe_metadata(%{"type" => "mcp_catalog", "version" => 1, "tools" => tools})
       when is_list(tools),
       do: result("context.catalog_committed", %{"tool_count" => length(tools)}, %{})

  defp describe_metadata(%{"type" => "extension_context_snapshot", "version" => 1} = record),
    do: fields("context.extensions_committed", record, [], ~w(request_id))

  defp describe_metadata(%{"type" => type})
       when type in ~w(context_compacted tool_results_compacted),
       do: result("context.compaction_committed", %{}, %{})

  defp describe_metadata(%{"type" => "compaction_failed"}),
    do: result("context.compaction_failed", %{}, %{})

  defp describe_metadata(%{"type" => type, "version" => version})
       when (version === 1 and
               type in ~w(operator_question operator_answer operator_question_closed)) or
              (version === 2 and type == "operator_answer"),
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

  defp describe_metadata(%{"type" => "delegation_started"} = record),
    do: fields("child.started", record, [], ~w(child_id))

  defp describe_metadata(%{"type" => "delegation_finished"} = record) do
    if Ipse.Tools.Delegation.valid_child_record?(record) do
      result(
        "child.finished",
        Map.take(record, ~w(status cleanup_confirmed duration_ms reason)),
        Map.take(record, ~w(child_id turn_id request_id))
        |> Map.put("causing_event_id", record["started_source"]["event_id"])
      )
    else
      @error
    end
  end

  defp describe_metadata(%{"type" => "lifecycle_turn_settling", "version" => 1} = record),
    do: fields("turn.settling", record, [], ~w(turn_id))

  defp describe_metadata(%{"type" => "turn_finished"} = record),
    do: fields("turn.finished", record, [], [], [], %{"status" => ~w(ok error cancelled)})

  defp describe_metadata(%{"type" => "cancelled"}), do: result("turn.cancelled", %{}, %{})

  defp describe_metadata(%{"type" => type, "version" => version} = record)
       when is_map_key(@extensions, type) and
              (version === 1 or
                 (version === 2 and
                    type in ~w(extension_action_intent extension_action_result extension_invocation_result)) or
                 (version === 3 and
                    type in ~w(extension_invocation_intent extension_invocation_result)) or
                 (version === 4 and type == "extension_invocation_result")) do
    {event, ids} = @extensions[type]

    with true <- valid_extension_projection?(record),
         {:ok, _, _, _, _, correlations} <- fields(event, record, [], ids),
         {:ok, data} <- extension_data(type, record),
         {:ok, correlations} <- trigger(record, correlations) do
      result(event, data, correlations)
    else
      _ -> @error
    end
  end

  defp describe_metadata(_), do: {:error, :unsupported_lifecycle_record}

  defp valid_extension_projection?(%{"version" => version} = record) when version in [3, 4] do
    record["approval"] == "saved_consent" and
      Ipse.Extension.Invocation.validate_intent(Ipse.Extension.Invocation.result_intent(record)) ==
        :ok
  end

  defp valid_extension_projection?(%{"approval" => "saved_consent"} = record),
    do:
      record["version"] === 2 and get_in(record, ["request", "op"]) == "collection.call" and
        Ipse.Extension.CollectionCall.validate(record["request"]) == :ok and
        Ipse.Extension.SemanticConsent.pin?(get_in(record, ["effect_binding", "pin"])) and
        get_in(record, ["effect_binding", "pin", "identity_sha256"]) == record["identity_sha256"]

  defp valid_extension_projection?(_), do: true

  defp extension_data("extension_event_result", record),
    do: enum_data(record, %{"outcome" => ~w(acknowledged completed failed unknown not_started)})

  defp extension_data("extension_action_result", %{"outcome" => outcome}),
    do:
      enum_data(outcome, %{"status" => ~w(ok conflict denied unknown answered cancelled failed)})

  defp extension_data("extension_invocation_result", record),
    do: numeric_data(record, ~w(action_count))

  defp extension_data(_, _), do: {:ok, %{}}

  defp trigger(%{"event_trigger" => trigger}, correlations) do
    if Ipse.Extension.Invocation.valid_event_trigger?(trigger) do
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
    if Enum.all?(keys, &Ipse.JSON.safe_uint?(record[&1])),
      do: {:ok, Map.take(record, keys)},
      else: @error
  end

  defp enum_data(record, enums) do
    if Enum.all?(enums, fn {key, values} -> record[key] in values end),
      do: {:ok, Map.take(record, Map.keys(enums))},
      else: @error
  end

  defp result(type, data, correlations), do: {:ok, type, nil, nil, data, correlations}
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)

  alias Ipse.Journal

  @keys ~w(type version turn_id request_id effective_source assistant_sha256 original original_bytes original_sha256 presented presented_bytes presented_sha256)

  def answer(turn, request, assistant, presented, effective_source) do
    original = assistant["content"]

    %{
      "type" => "lifecycle_answer_committed",
      "version" => 1,
      "turn_id" => turn,
      "request_id" => request,
      "effective_source" => effective_source,
      "assistant_sha256" => Ipse.JSON.digest([assistant]),
      "original" => bounded(original),
      "original_bytes" => byte_size(original),
      "original_sha256" => Ipse.JSON.sha256(original),
      "presented" => bounded(presented),
      "presented_bytes" => byte_size(presented),
      "presented_sha256" => Ipse.JSON.sha256(presented)
    }
  end

  def valid_answer?(record) do
    is_map(record) and Enum.sort(Map.keys(record)) == Enum.sort(@keys) and
      record["type"] == "lifecycle_answer_committed" and record["version"] === 1 and
      id?(record["turn_id"]) and id?(record["request_id"]) and
      Journal.valid_source?(record["effective_source"]) and
      Ipse.JSON.sha256?(record["assistant_sha256"]) and
      Enum.all?(
        ~w(original presented),
        &view?(record[&1], record[&1 <> "_bytes"], record[&1 <> "_sha256"])
      )
  rescue
    _ -> false
  end

  defp bounded(text), do: if(byte_size(text) <= 8192, do: text)

  defp view?(nil, bytes, hash),
    do: is_integer(bytes) and bytes in 8193..9_007_199_254_740_991 and Ipse.JSON.sha256?(hash)

  defp view?(text, bytes, hash) when is_binary(text),
    do:
      String.valid?(text) and byte_size(text) <= 8192 and bytes === byte_size(text) and
        Ipse.JSON.sha256(text) == hash

  defp view?(_, _, _), do: false
end
