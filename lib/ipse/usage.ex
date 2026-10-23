defmodule Ipse.Usage do
  @moduledoc "Durable content-free request identities and cumulative provider usage snapshots."

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
      "model" => Ipse.Provider.model_name(config.model),
      "billing_mode" => billing_mode(config.provider),
      "selected_profile" => profile(config[:execution]),
      "endpoint_sha256" =>
        if(is_binary(config[:base_url]), do: Ipse.JSON.sha256(config.base_url)),
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
      "usage" => normalize(@providers[admission["provider"]], operation(admission), raw)
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

          {"completed", normalize(@providers[admission["provider"]], operation(admission), raw),
           Ipse.Provider.model_name(reported)}

        other ->
          {if(other == :cancelled, do: "cancelled", else: "failed"),
           observed ||
             normalize(@providers[admission["provider"]], operation(admission), nil), nil}
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
         Ipse.Extension.ModelCall.valid_source?(event, ledger.model_action, ledger.scope),
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
         Ipse.Extension.EmbeddingCall.valid_source?(event, ledger.model_action, ledger.scope),
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
         Ipse.Extension.ModelCall.valid_response?(event, request.admission),
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
         Ipse.Extension.EmbeddingCall.valid_response?(
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

    if Ipse.Extension.Actions.result_intent(event) == ledger.model_action and
         Ipse.Extension.Actions.valid_result?(event) and
         Ipse.Extension.ModelCall.valid_result_source?(
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

    if Ipse.Extension.Actions.result_intent(event) == ledger.model_action and
         Ipse.Extension.Actions.valid_result?(event) and
         Ipse.Extension.EmbeddingCall.valid_result_source?(
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
        Ipse.Provider.model_name(
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
              normalize(
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
            valid_usage?(record["usage"], operation(admission)),
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
      e["billing_mode"] == billing_mode(@providers[e["provider"]]) and
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
      valid_usage?(e["usage"], operation_tag(e))
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
      valid_usage?(e["usage"], operation_tag(e))
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
    do: Enum.sort(Map.keys(e)) == Enum.sort(fields) and Ipse.JSON.validate_object(e) == :ok

  defp integer?(n), do: is_integer(n) and n >= 0 and n <= 9_007_199_254_740_991

  defp profile(execution) when is_map(execution),
    do: Ipse.Provider.model_name(execution[:id] || execution["id"])

  defp profile(_), do: nil
  defp model?(m), do: is_binary(m) and Ipse.Provider.model_name(m) == m
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  @counter_limit 1_000_000_000_000
  @fields ~w(input_tokens output_tokens total_tokens input_uncached_tokens input_cached_tokens input_cache_write_tokens input_cache_write_5m_tokens input_cache_write_1h_tokens output_reasoning_tokens provider_web_search_requests provider_web_fetch_requests provider_duration_ns)
  @billing %{
    chatgpt: "subscription",
    openai: "api",
    ollama: "local",
    anthropic: "api",
    demo: "none"
  }
  def counter_fields, do: @fields
  def counter_limit, do: @counter_limit
  def billing_mode(provider), do: @billing[provider]

  def normalize(:demo, _usage), do: record(empty(), [], "not_applicable", [])

  def normalize(provider, usage) when provider in [:chatgpt, :openai, :ollama, :anthropic] do
    usage = if is_nil(usage), do: %{}, else: usage

    with true <- is_map(usage),
         {:ok, counts} <- extract(provider, usage),
         {:ok, counts, derived} <- derive(provider, counts),
         true <- consistent?(counts) do
      quality =
        cond do
          is_integer(counts["input_tokens"]) and is_integer(counts["output_tokens"]) ->
            "totals_known"

          Enum.any?(Map.values(counts), &is_integer/1) ->
            "partial"

          true ->
            "unavailable"
        end

      record(counts, derived, quality, [])
    else
      _ -> record(empty(), [], "invalid", ["invalid_or_inconsistent_provider_counters"])
    end
  rescue
    _ -> record(empty(), [], "invalid", ["invalid_or_inconsistent_provider_counters"])
  end

  def normalize(_, _), do: record(empty(), [], "invalid", ["unsupported_provider"])

  def normalize(provider, operation, raw) when operation in [:text, "text"],
    do: normalize(provider, raw)

  def normalize(provider, operation, raw) when operation in [:embedding, "embedding"] do
    raw = if is_nil(raw), do: %{}, else: raw

    with true <- provider in [:openai, :ollama],
         true <- is_map(raw),
         {:ok, counts} <- embedding_counts(provider, raw),
         true <- embedding_consistent?(counts) do
      {counts, derived} =
        if is_integer(counts["input_tokens"]) and is_nil(counts["total_tokens"]),
          do: {Map.put(counts, "total_tokens", counts["input_tokens"]), ["total_tokens"]},
          else: {counts, []}

      quality =
        cond do
          is_integer(counts["input_tokens"]) and is_integer(counts["total_tokens"]) ->
            "totals_known"

          Enum.any?(Map.values(counts), &is_integer/1) ->
            "partial"

          true ->
            "unavailable"
        end

      embedding_record(counts, derived, quality, [])
    else
      _ ->
        issue =
          if provider in [:openai, :ollama],
            do: "invalid_or_inconsistent_provider_counters",
            else: "unsupported_provider"

        embedding_record(empty(), [], "invalid", [issue])
    end
  rescue
    _ -> embedding_record(empty(), [], "invalid", ["invalid_or_inconsistent_provider_counters"])
  end

  def normalize(_, _, _), do: record(empty(), [], "invalid", ["unsupported_provider"])

  def valid_usage?(usage, "text"),
    do: is_map(usage) and usage["version"] === 1 and valid_usage?(usage)

  def valid_usage?(usage, "embedding"),
    do: is_map(usage) and usage["version"] === 2 and valid_usage?(usage)

  def valid_usage?(_, _), do: false

  @doc "Validate stored normalized counters without accessing provider data or credentials."
  def valid_usage?(
        %{
          "version" => 1,
          "counts" => counts,
          "derived_fields" => derived,
          "quality" => quality,
          "issues" => issues
        } = record
      ) do
    Ipse.JSON.validate_object(record) == :ok and
      Enum.sort(Map.keys(record)) == ~w(counts derived_fields issues quality version) and
      is_map(counts) and Enum.all?(Map.keys(counts), &(&1 in @fields)) and
      Enum.all?(~w(input_tokens output_tokens total_tokens), &Map.has_key?(counts, &1)) and
      Enum.all?(Map.values(counts), &(is_nil(&1) or counter?(&1))) and
      is_list(derived) and length(derived) == length(Enum.uniq(derived)) and
      Enum.all?(derived, &(&1 in ~w(input_tokens total_tokens))) and
      Enum.all?(derived, &is_integer(counts[&1])) and
      quality in ~w(totals_known partial unavailable invalid not_applicable) and
      is_list(issues) and
      Enum.all?(
        issues,
        &(&1 in ~w(invalid_or_inconsistent_provider_counters unsupported_provider))
      ) and
      consistent?(counts) and quality_matches?(counts, quality)
  rescue
    _ -> false
  end

  def valid_usage?(%{"version" => 2, "operation" => "embedding"} = record) do
    counts = record["counts"]
    derived = record["derived_fields"]
    quality = record["quality"]
    issues = record["issues"]

    Ipse.JSON.validate_object(record) == :ok and
      Enum.sort(Map.keys(record)) ==
        ~w(counts derived_fields issues not_applicable_fields operation quality version) and
      record["not_applicable_fields"] == ["output_tokens"] and
      is_map(counts) and Enum.sort(Map.keys(counts)) == Enum.sort(@fields) and
      Enum.all?(Map.values(counts), &(is_nil(&1) or counter?(&1))) and
      Enum.all?(
        @fields -- ~w(input_tokens total_tokens provider_duration_ns),
        &is_nil(counts[&1])
      ) and
      derived in [[], ["total_tokens"]] and
      (derived == [] or
         (is_integer(counts["input_tokens"]) and is_integer(counts["total_tokens"]))) and
      embedding_consistent?(counts) and
      is_list(issues) and
      Enum.all?(
        issues,
        &(&1 in ~w(invalid_or_inconsistent_provider_counters unsupported_provider))
      ) and
      ((quality == "invalid" and issues != []) or (quality != "invalid" and issues == [])) and
      embedding_quality?(counts, quality)
  rescue
    _ -> false
  end

  def valid_usage?(_), do: false

  defp embedding_counts(provider, raw) do
    paths =
      case provider do
        :openai ->
          %{"input_tokens" => ["prompt_tokens"], "total_tokens" => ["total_tokens"]}

        :ollama ->
          %{"input_tokens" => ["prompt_eval_count"], "provider_duration_ns" => ["total_duration"]}
      end

    Enum.reduce_while(paths, {:ok, empty()}, fn {field, path}, {:ok, counts} ->
      case read(raw, path) do
        nil ->
          {:cont, {:ok, counts}}

        value when is_integer(value) and value >= 0 and value <= @counter_limit ->
          {:cont, {:ok, Map.put(counts, field, value)}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp embedding_consistent?(counts),
    do:
      is_nil(counts["input_tokens"]) or is_nil(counts["total_tokens"]) or
        counts["input_tokens"] == counts["total_tokens"]

  defp embedding_quality?(counts, "totals_known"),
    do: is_integer(counts["input_tokens"]) and is_integer(counts["total_tokens"])

  defp embedding_quality?(counts, quality) when quality in ~w(unavailable invalid),
    do: Enum.all?(Map.values(counts), &is_nil/1)

  defp embedding_quality?(counts, "partial"),
    do:
      Enum.any?(Map.values(counts), &is_integer/1) and
        not embedding_quality?(counts, "totals_known")

  defp embedding_quality?(_, _), do: false

  defp embedding_record(counts, derived, quality, issues),
    do: %{
      "version" => 2,
      "operation" => "embedding",
      "counts" => counts,
      "derived_fields" => derived,
      "quality" => quality,
      "issues" => issues,
      "not_applicable_fields" => ["output_tokens"]
    }

  defp extract(provider, raw) do
    paths =
      case provider do
        p when p in [:chatgpt, :openai] ->
          %{
            "input_tokens" => ["input_tokens"],
            "output_tokens" => ["output_tokens"],
            "total_tokens" => ["total_tokens"],
            "input_cached_tokens" => ["input_tokens_details", "cached_tokens"],
            "input_cache_write_tokens" => ["input_tokens_details", "cache_write_tokens"],
            "output_reasoning_tokens" => ["output_tokens_details", "reasoning_tokens"]
          }

        :anthropic ->
          %{
            "input_uncached_tokens" => ["input_tokens"],
            "output_tokens" => ["output_tokens"],
            "input_cached_tokens" => ["cache_read_input_tokens"],
            "input_cache_write_tokens" => ["cache_creation_input_tokens"],
            "input_cache_write_5m_tokens" => ["cache_creation", "ephemeral_5m_input_tokens"],
            "input_cache_write_1h_tokens" => ["cache_creation", "ephemeral_1h_input_tokens"],
            "output_reasoning_tokens" => ["output_tokens_details", "thinking_tokens"],
            "provider_web_search_requests" => ["server_tool_use", "web_search_requests"],
            "provider_web_fetch_requests" => ["server_tool_use", "web_fetch_requests"]
          }

        :ollama ->
          Map.new(
            ~w(input_tokens output_tokens input_cached_tokens provider_duration_ns),
            &{&1, [&1]}
          )
      end

    Enum.reduce_while(paths, {:ok, empty()}, fn {field, path}, {:ok, counts} ->
      case read(raw, path) do
        nil ->
          {:cont, {:ok, counts}}

        value when is_integer(value) and value >= 0 and value <= @counter_limit ->
          {:cont, {:ok, Map.put(counts, field, value)}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp read(value, []), do: value
  defp read(nil, _path), do: nil
  defp read(map, [key | rest]) when is_map(map), do: read(Map.get(map, key), rest)
  defp read(_, _), do: :invalid

  defp derive(provider, counts) do
    {counts, derived} =
      if provider == :anthropic do
        parts =
          Enum.map(
            ~w(input_uncached_tokens input_cached_tokens input_cache_write_tokens),
            &counts[&1]
          )

        if Enum.all?(parts, &is_integer/1),
          do: {Map.put(counts, "input_tokens", Enum.sum(parts)), ["input_tokens"]},
          else: {counts, []}
      else
        {counts, []}
      end

    {counts, derived} =
      if is_nil(counts["total_tokens"]) and is_integer(counts["input_tokens"]) and
           is_integer(counts["output_tokens"]) do
        {Map.put(counts, "total_tokens", counts["input_tokens"] + counts["output_tokens"]),
         derived ++ ["total_tokens"]}
      else
        {counts, derived}
      end

    if Enum.all?(Map.values(counts), &(is_nil(&1) or counter?(&1))),
      do: {:ok, counts, derived},
      else: :error
  end

  defp consistent?(counts) do
    input = counts["input_tokens"]
    output = counts["output_tokens"]
    total = counts["total_tokens"]

    (is_nil(input) or is_nil(output) or is_nil(total) or input + output == total) and
      subset?(counts["input_cached_tokens"], input) and
      subset?(counts["input_cache_write_tokens"], input) and
      subset?(counts["output_reasoning_tokens"], output) and
      subset?(counts["input_cache_write_5m_tokens"], counts["input_cache_write_tokens"]) and
      subset?(counts["input_cache_write_1h_tokens"], counts["input_cache_write_tokens"])
  end

  defp subset?(nil, _), do: true
  defp subset?(_, nil), do: true
  defp subset?(part, total), do: part <= total
  defp counter?(value), do: is_integer(value) and value >= 0 and value <= @counter_limit
  defp empty, do: Map.new(@fields, &{&1, nil})

  defp record(counts, derived, quality, issues),
    do: %{
      "version" => 1,
      "counts" => counts,
      "derived_fields" => derived,
      "quality" => quality,
      "issues" => issues
    }

  defp quality_matches?(counts, "totals_known"),
    do: is_integer(counts["input_tokens"]) and is_integer(counts["output_tokens"])

  defp quality_matches?(counts, quality) when quality in ~w(unavailable invalid not_applicable),
    do: Enum.all?(Map.values(counts), &is_nil/1)

  defp quality_matches?(counts, "partial"),
    do:
      Enum.any?(Map.values(counts), &is_integer/1) and
        not (is_integer(counts["input_tokens"]) and is_integer(counts["output_tokens"]))
end
