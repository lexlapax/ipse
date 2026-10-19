defmodule Ipse.Usage do
  @moduledoc "Durable content-free request identities and cumulative provider usage snapshots."
  alias Ipse.Usage.Normalizer
  @types ~w(request_admitted request_usage_observed request_finished)
  @providers %{
    "chatgpt" => :chatgpt,
    "openai" => :openai,
    "ollama" => :ollama,
    "anthropic" => :anthropic,
    "demo" => :demo
  }
  @limit 10_000

  def id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  def capacity?(ledger), do: map_size(ledger.requests) < @limit

  def operation(admission) do
    if valid_admission?(admission), do: operation_tag(admission)
  rescue
    _ -> nil
  end

  def configuration(config) do
    kind = if config[:operation] == :embedding, do: "extension", else: "model"

    if valid_admission?(admission(id(), config, kind, id())),
      do: :ok,
      else: {:error, :invalid_usage_configuration}
  rescue
    _ -> {:error, :invalid_usage_configuration}
  end

  def admission(session, config, kind, turn_id) do
    origin = config[:delegation_origin] || %{}

    event = %{
      "type" => "request_admitted",
      "version" => 1,
      "request_id" => id(),
      "attempt_id" => id(),
      "attempt" => 1,
      "session_id" => session,
      "turn_id" => turn_id,
      "parent_session_id" => origin["parent_session_id"],
      "parent_request_id" => origin["parent_request_id"],
      "kind" => kind,
      "provider" => to_string(config.provider),
      "model" => Ipse.RuntimeInfo.model_name(config.model),
      "billing_mode" => Normalizer.billing_mode(config.provider),
      "selected_profile" => profile(config[:execution]),
      "endpoint_sha256" =>
        if(is_binary(config[:base_url]), do: Ipse.Extensions.Manifest.sha256(config.base_url)),
      "admitted_at_ms" => System.system_time(:millisecond)
    }

    case config[:operation] do
      nil -> event
      :text -> event
      :embedding -> Map.merge(event, %{"version" => 2, "operation" => "embedding"})
      _ -> Map.put(event, "operation", "unsupported")
    end
  end

  def observation(admission, raw, sequence) do
    versioned(admission, %{
      "type" => "request_usage_observed",
      "version" => 1,
      "request_id" => admission["request_id"],
      "attempt_id" => admission["attempt_id"],
      "sequence" => sequence,
      "usage" =>
        Normalizer.normalize(@providers[admission["provider"]], operation(admission), raw)
    })
  end

  def completion(admission, result, duration, observed) do
    {outcome, usage, model} =
      case result do
        {:ok, value, raw} ->
          reported =
            if operation(admission) == "embedding",
              do: value["reported_model"],
              else: get_in(value, ["provider_data", "reported_model"])

          {"completed",
           Normalizer.normalize(@providers[admission["provider"]], operation(admission), raw),
           Ipse.RuntimeInfo.model_name(reported)}

        other ->
          {if(other == :cancelled, do: "cancelled", else: "failed"),
           observed ||
             Normalizer.normalize(@providers[admission["provider"]], operation(admission), nil),
           nil}
      end

    versioned(admission, %{
      "type" => "request_finished",
      "version" => 1,
      "request_id" => admission["request_id"],
      "attempt_id" => admission["attempt_id"],
      "outcome" => outcome,
      "duration_ms" => duration,
      "reported_model" => model,
      "usage" => usage,
      "finality" => if(outcome == "completed", do: "final", else: "partial")
    })
  end

  def restore(events, expected_session_id \\ nil) when is_list(events) do
    metadata = (List.first(events) || %{})["metadata"] || %{}
    version = metadata["usage_version"]

    if version in [nil, 1, 2] do
      Enum.reduce_while(
        events,
        {:ok,
         %{
           requests: %{},
           order: [],
           attempts: MapSet.new(),
           legacy_unmetered: version == nil,
           usage_version: version,
           bindings: MapSet.new(),
           model_action: nil,
           model_route: nil,
           model_sources: %{},
           model_responses: %{},
           session_id: expected_session_id,
           scope:
             Map.take(
               metadata,
               ~w(provider model delegation_origin model_profiles embedding_profiles max_output_tokens budget)
             )
         }},
        fn event, {:ok, ledger} ->
          case apply_event(ledger, event) do
            {:ok, next} -> {:cont, {:ok, next}}
            error -> {:halt, error}
          end
        end
      )
    else
      {:error, :unsupported_usage_version}
    end
  rescue
    _ -> {:error, :invalid_usage_journal}
  end

  def apply_event(
        ledger,
        %{"type" => "extension_action_intent", "request" => %{"op" => "model.complete"}} = event
      ),
      do: {:ok, %{ledger | model_action: event, model_route: nil}}

  def apply_event(
        ledger,
        %{"type" => "extension_action_intent", "request" => %{"op" => "embedding.create"}} = event
      ),
      do: {:ok, %{ledger | model_action: event, model_route: nil}}

  def apply_event(ledger, %{"type" => "extension_model_request"} = event) do
    if ledger.model_route == nil and
         not Map.has_key?(ledger.model_sources, event["operation_id"]) and
         Ipse.Extensions.ModelCall.valid_source?(event, ledger.model_action, ledger.scope),
       do:
         {:ok,
          %{
            ledger
            | model_route: event["admission"],
              model_sources: Map.put(ledger.model_sources, event["operation_id"], event)
          }},
       else: {:error, :invalid_usage_journal}
  end

  def apply_event(ledger, %{"type" => "extension_embedding_request"} = event) do
    if ledger.usage_version == 2 and ledger.model_route == nil and
         not Map.has_key?(ledger.model_sources, event["operation_id"]) and
         Ipse.Extensions.EmbeddingCall.valid_source?(event, ledger.model_action, ledger.scope),
       do:
         {:ok,
          %{
            ledger
            | model_route: event["admission"],
              model_sources: Map.put(ledger.model_sources, event["operation_id"], event)
          }},
       else: {:error, :invalid_usage_journal}
  end

  def apply_event(ledger, %{"type" => "extension_model_response"} = event) do
    request = ledger.requests[event["request_id"]]

    if request != nil and operation(request.admission) == "text" and
         request.admission["kind"] == "extension" and
         request.completion == nil and
         not Map.has_key?(ledger.model_responses, event["request_id"]) and
         Ipse.Extensions.ModelCall.valid_response?(event, request.admission),
       do:
         {:ok,
          %{ledger | model_responses: Map.put(ledger.model_responses, event["request_id"], event)}},
       else: {:error, :invalid_usage_journal}
  end

  def apply_event(
        ledger,
        %{"type" => "extension_effect_result", "version" => 2, "kind" => "embedding.f32le"} =
          event
      ) do
    id = get_in(event, ["inference", "request_id"])
    request = ledger.requests[id]

    if request != nil and operation(request.admission) == "embedding" and
         request.completion == nil and
         not Map.has_key?(ledger.model_responses, id) and
         Ipse.Extensions.EmbeddingCall.valid_response?(
           event,
           request.admission,
           ledger.model_action
         ),
       do: {:ok, %{ledger | model_responses: Map.put(ledger.model_responses, id, event)}},
       else: {:error, :invalid_usage_journal}
  end

  def apply_event(
        ledger,
        %{"type" => "extension_action_result", "request" => %{"op" => "model.complete"}} = event
      ) do
    id = event["operation_id"]

    if Ipse.Extensions.Actions.result_intent(event) == ledger.model_action and
         Ipse.Extensions.Actions.valid_result?(event) and
         Ipse.Extensions.ModelCall.valid_result_source?(
           event,
           ledger.requests[id],
           ledger.model_responses[id]
         ) and
         ledger.model_route == nil,
       do:
         {:ok,
          %{ledger | model_action: nil, model_responses: Map.delete(ledger.model_responses, id)}},
       else: {:error, :invalid_usage_journal}
  end

  def apply_event(
        ledger,
        %{"type" => "extension_action_result", "request" => %{"op" => "embedding.create"}} = event
      ) do
    id = event["operation_id"]

    if Ipse.Extensions.Actions.result_intent(event) == ledger.model_action and
         Ipse.Extensions.Actions.valid_result?(event) and
         Ipse.Extensions.EmbeddingCall.valid_result_source?(
           event,
           ledger.requests[id],
           ledger.model_responses[id]
         ) and
         ledger.model_route == nil,
       do:
         {:ok,
          %{ledger | model_action: nil, model_responses: Map.delete(ledger.model_responses, id)}},
       else: {:error, :invalid_usage_journal}
  end

  def apply_event(ledger, %{"type" => type}) when type in ~w(cancelled turn_finished),
    do: {:ok, %{ledger | model_action: nil, model_route: nil}}

  def apply_event(ledger, %{"type" => "request_admitted"} = event) do
    with true <- valid_admission?(event),
         true <- scope_matches?(ledger, event),
         nil <- ledger.requests[event["request_id"]],
         true <- capacity?(ledger),
         false <- MapSet.member?(ledger.attempts, event["attempt_id"]) do
      request = %{admission: event, observation: nil, completion: nil, sequence: 0}
      ledger = put_in(ledger, [:requests, event["request_id"]], request)

      {:ok,
       %{
         ledger
         | order: [event["request_id"] | ledger.order],
           attempts: MapSet.put(ledger.attempts, event["attempt_id"]),
           session_id: event["session_id"],
           model_route: if(event["kind"] == "extension", do: nil, else: ledger.model_route)
       }}
    else
      %{admission: ^event} -> {:ok, ledger}
      _ -> {:error, :invalid_usage_journal}
    end
  end

  def apply_event(ledger, %{"type" => type} = event) when type in @types do
    with %{} = request <- ledger.requests[event["request_id"]],
         true <- event["attempt_id"] == request.admission["attempt_id"],
         true <- valid_result?(event),
         true <- operation_tag(event) == operation(request.admission),
         true <- response_matches?(ledger, request, event) do
      case type do
        "request_usage_observed" ->
          cond do
            event["sequence"] == request.sequence and event["usage"] == request.observation ->
              {:ok, ledger}

            request.completion == nil and event["sequence"] == request.sequence + 1 and
                event["sequence"] <= 64 ->
              next = %{request | sequence: event["sequence"], observation: event["usage"]}
              {:ok, put_in(ledger, [:requests, event["request_id"]], next)}

            true ->
              {:error, :invalid_usage_journal}
          end

        "request_finished" ->
          cond do
            request.completion == event ->
              {:ok, ledger}

            request.completion == nil ->
              {:ok, put_in(ledger, [:requests, event["request_id"], :completion], event)}

            true ->
              {:error, :invalid_usage_journal}
          end
      end
    else
      _ -> {:error, :invalid_usage_journal}
    end
  end

  def apply_event(ledger, %{"type" => "message", "message" => %{"role" => "assistant"}} = event),
    do: bind(ledger, event, "model")

  def apply_event(ledger, %{"type" => "context_compacted"} = event),
    do: bind(ledger, event, "compaction")

  def apply_event(ledger, event) do
    if Map.has_key?(event, "attempt_id"),
      do: {:error, :invalid_usage_journal},
      else: {:ok, ledger}
  end

  defp response_matches?(
         ledger,
         %{admission: %{"version" => 2, "operation" => "embedding"}},
         %{"type" => "request_finished"} = event
       ) do
    response = ledger.model_responses[event["request_id"]]

    response == nil or
      (event["outcome"] == "completed" and event["finality"] == "final" and
         event["reported_model"] == response["inference"]["reported_model"] and
         event["usage"] === response["inference"]["usage"])
  end

  defp response_matches?(
         ledger,
         request,
         %{"type" => "request_finished", "outcome" => "completed"} = event
       ) do
    response = ledger.model_responses[event["request_id"]]

    request.admission["kind"] != "extension" or response == nil or
      event["reported_model"] ==
        Ipse.RuntimeInfo.model_name(
          get_in(response, ["assistant", "provider_data", "reported_model"])
        )
  end

  defp response_matches?(_, _, _), do: true

  defp bind(ledger, event, kind) do
    request = ledger.requests[event["request_id"]]

    cond do
      is_nil(event["request_id"]) and ledger.legacy_unmetered ->
        {:ok, ledger}

      is_nil(request) ->
        {:error, :invalid_usage_journal}

      request.admission["kind"] != kind or is_nil(request.completion) ->
        {:error, :invalid_usage_journal}

      request.completion["outcome"] != "completed" or
          MapSet.member?(ledger.bindings, event["request_id"]) ->
        {:error, :invalid_usage_journal}

      true ->
        {:ok, %{ledger | bindings: MapSet.put(ledger.bindings, event["request_id"])}}
    end
  end

  @doc "Validated request IDs in canonical admission order."
  def order(ledger), do: Enum.reverse(ledger.order)

  def snapshot(ledger) do
    requests = Enum.map(order(ledger), &ledger.requests[&1])

    %{
      "version" => projection_version(requests),
      "legacy_unmetered" => ledger.legacy_unmetered,
      "request_count" => length(requests),
      "unknown_outcome_count" => Enum.count(requests, &is_nil(&1.completion)),
      "shown_request_count" => min(length(requests), 16),
      "requests" => Enum.map(Enum.take(requests, -16), &request_record/1)
    }
  end

  @doc "Project one validated ledger entry without conversation or provider-native content."
  def request_record(request) do
    Map.merge(
      Map.delete(request.admission, "type"),
      if(request.completion,
        do: Map.drop(request.completion, ~w(type version request_id attempt_id)),
        else: %{
          "outcome" => "unknown",
          "finality" => "partial",
          "duration_ms" => nil,
          "reported_model" => nil,
          "usage" =>
            request.observation ||
              Normalizer.normalize(
                @providers[request.admission["provider"]],
                operation(request.admission),
                nil
              )
        }
      )
    )
  end

  @doc "Validate the closed accounting projection; this does not authenticate a supplied ledger."
  def valid_request_record?(record) do
    fields = admission_fields(record) -- ["type"]

    admission = record |> Map.take(fields) |> Map.put("type", "request_admitted")

    result =
      record
      |> Map.drop(fields)
      |> Map.merge(Map.take(record, ~w(version request_id attempt_id operation)))
      |> Map.put("type", "request_finished")

    valid_admission?(admission) and
      closed?(record, fields ++ ~w(outcome finality duration_ms reported_model usage)) and
      if(record["outcome"] == "unknown",
        do:
          record["finality"] == "partial" and record["duration_ms"] == nil and
            record["reported_model"] == nil and
            Normalizer.valid?(record["usage"], operation(admission)),
        else: valid_result?(result)
      )
  rescue
    _ -> false
  end

  defp valid_admission?(e) do
    closed?(
      e,
      admission_fields(e)
    ) and
      operation_tag(e) != nil and e["attempt"] === 1 and
      Enum.all?(~w(request_id attempt_id session_id turn_id), &id?(e[&1])) and
      Enum.all?(~w(parent_session_id parent_request_id), &(is_nil(e[&1]) or id?(e[&1]))) and
      e["kind"] in ~w(model compaction extension) and Map.has_key?(@providers, e["provider"]) and
      e["billing_mode"] == Normalizer.billing_mode(@providers[e["provider"]]) and
      (is_nil(e["selected_profile"]) or model?(e["selected_profile"])) and
      (is_nil(e["endpoint_sha256"]) or
         (is_binary(e["endpoint_sha256"]) and
            Regex.match?(~r/\A[0-9a-f]{64}\z/, e["endpoint_sha256"]))) and
      model?(e["model"]) and integer?(e["admitted_at_ms"]) and
      (operation_tag(e) == "text" or
         (e["kind"] == "extension" and e["provider"] in ~w(openai ollama) and
            model?(e["selected_profile"])))
  end

  defp scope_matches?(ledger, event) do
    origin = ledger.scope["delegation_origin"] || %{}

    (operation_tag(event) == "text" or ledger.usage_version == 2) and
      (is_nil(ledger.session_id) or ledger.session_id == event["session_id"]) and
      if event["kind"] == "extension" do
        ledger.model_route === event
      else
        Enum.all?(~w(provider model), fn field ->
          not Map.has_key?(ledger.scope, field) or ledger.scope[field] == event[field]
        end)
      end and
      Enum.all?(~w(parent_session_id parent_request_id), fn field ->
        origin[field] == event[field]
      end)
  end

  defp valid_result?(%{"type" => "request_usage_observed"} = e) do
    closed?(e, version_fields(e, ~w(type version request_id attempt_id sequence usage))) and
      operation_tag(e) != nil and
      is_integer(e["sequence"]) and e["sequence"] > 0 and
      Normalizer.valid?(e["usage"], operation_tag(e))
  end

  defp valid_result?(%{"type" => "request_finished"} = e) do
    closed?(
      e,
      version_fields(
        e,
        ~w(type version request_id attempt_id outcome duration_ms reported_model usage finality)
      )
    ) and
      operation_tag(e) != nil and e["outcome"] in ~w(completed failed cancelled) and
      integer?(e["duration_ms"]) and (is_nil(e["reported_model"]) or model?(e["reported_model"])) and
      e["finality"] == if(e["outcome"] == "completed", do: "final", else: "partial") and
      Normalizer.valid?(e["usage"], operation_tag(e))
  end

  defp valid_result?(_), do: false

  defp admission_fields(e),
    do:
      version_fields(
        e,
        ~w(type version request_id attempt_id attempt session_id turn_id parent_session_id parent_request_id kind provider model billing_mode selected_profile endpoint_sha256 admitted_at_ms)
      )

  defp version_fields(%{"version" => 2}, fields), do: fields ++ ["operation"]
  defp version_fields(_, fields), do: fields

  defp versioned(%{"version" => 2, "operation" => "embedding"}, event),
    do: Map.merge(event, %{"version" => 2, "operation" => "embedding"})

  defp versioned(_, event), do: event

  defp operation_tag(%{"version" => 1} = event),
    do: if(not Map.has_key?(event, "operation"), do: "text")

  defp operation_tag(%{"version" => 2, "operation" => "embedding"}), do: "embedding"
  defp operation_tag(_), do: nil

  defp projection_version(requests),
    do: if(Enum.any?(requests, &(operation_tag(&1.admission) == "embedding")), do: 2, else: 1)

  defp closed?(e, fields),
    do: Enum.sort(Map.keys(e)) == Enum.sort(fields) and Ipse.MCP.Schema.validate_object(e) == :ok

  defp integer?(n), do: is_integer(n) and n >= 0 and n <= 9_007_199_254_740_991

  defp profile(execution) when is_map(execution),
    do: Ipse.RuntimeInfo.model_name(execution[:id] || execution["id"])

  defp profile(_), do: nil
  defp model?(m), do: is_binary(m) and Ipse.RuntimeInfo.model_name(m) == m
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
