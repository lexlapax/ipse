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

  def configuration(config) do
    if valid_admission?(admission(id(), config, "model", id())),
      do: :ok,
      else: {:error, :invalid_usage_configuration}
  rescue
    _ -> {:error, :invalid_usage_configuration}
  end

  def admission(session, config, kind, turn_id) do
    origin = config[:delegation_origin] || %{}

    %{
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
  end

  def observation(admission, raw, sequence) do
    %{
      "type" => "request_usage_observed",
      "version" => 1,
      "request_id" => admission["request_id"],
      "attempt_id" => admission["attempt_id"],
      "sequence" => sequence,
      "usage" => Normalizer.normalize(@providers[admission["provider"]], raw)
    }
  end

  def completion(admission, result, duration, observed) do
    {outcome, usage, model} =
      case result do
        {:ok, assistant, raw} ->
          {"completed", Normalizer.normalize(@providers[admission["provider"]], raw),
           Ipse.RuntimeInfo.model_name(get_in(assistant, ["provider_data", "reported_model"]))}

        other ->
          {if(other == :cancelled, do: "cancelled", else: "failed"),
           observed || Normalizer.normalize(@providers[admission["provider"]], nil), nil}
      end

    %{
      "type" => "request_finished",
      "version" => 1,
      "request_id" => admission["request_id"],
      "attempt_id" => admission["attempt_id"],
      "outcome" => outcome,
      "duration_ms" => duration,
      "reported_model" => model,
      "usage" => usage,
      "finality" => if(outcome == "completed", do: "final", else: "partial")
    }
  end

  def restore(events, expected_session_id \\ nil) when is_list(events) do
    metadata = (List.first(events) || %{})["metadata"] || %{}
    version = metadata["usage_version"]

    if version in [nil, 1] do
      Enum.reduce_while(
        events,
        {:ok,
         %{
           requests: %{},
           order: [],
           legacy_unmetered: version != 1,
           bindings: MapSet.new(),
           session_id: expected_session_id,
           scope: Map.take(metadata, ~w(provider model delegation_origin))
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

  def apply_event(ledger, %{"type" => "request_admitted"} = event) do
    with true <- valid_admission?(event),
         true <- scope_matches?(ledger, event),
         nil <- ledger.requests[event["request_id"]],
         true <- capacity?(ledger),
         false <-
           Enum.any?(ledger.requests, fn {_, r} ->
             r.admission["attempt_id"] == event["attempt_id"]
           end) do
      request = %{admission: event, observation: nil, completion: nil, sequence: 0}
      ledger = put_in(ledger, [:requests, event["request_id"]], request)

      {:ok,
       %{ledger | order: ledger.order ++ [event["request_id"]], session_id: event["session_id"]}}
    else
      %{admission: ^event} -> {:ok, ledger}
      _ -> {:error, :invalid_usage_journal}
    end
  end

  def apply_event(ledger, %{"type" => type} = event) when type in @types do
    with %{} = request <- ledger.requests[event["request_id"]],
         true <- event["attempt_id"] == request.admission["attempt_id"],
         true <- valid_result?(event) do
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

  def snapshot(ledger) do
    requests = Enum.map(ledger.order, &ledger.requests[&1])

    %{
      "version" => 1,
      "legacy_unmetered" => ledger.legacy_unmetered,
      "request_count" => length(requests),
      "unknown_outcome_count" => Enum.count(requests, &is_nil(&1.completion)),
      "shown_request_count" => min(length(requests), 16),
      "requests" =>
        Enum.map(Enum.take(requests, -16), fn request ->
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
                    Normalizer.normalize(@providers[request.admission["provider"]], nil)
              }
            )
          )
        end)
    }
  end

  defp valid_admission?(e) do
    closed?(
      e,
      ~w(type version request_id attempt_id attempt session_id turn_id parent_session_id parent_request_id kind provider model billing_mode selected_profile endpoint_sha256 admitted_at_ms)
    ) and
      e["version"] === 1 and e["attempt"] === 1 and
      Enum.all?(~w(request_id attempt_id session_id turn_id), &id?(e[&1])) and
      Enum.all?(~w(parent_session_id parent_request_id), &(is_nil(e[&1]) or id?(e[&1]))) and
      e["kind"] in ~w(model compaction) and Map.has_key?(@providers, e["provider"]) and
      e["billing_mode"] == Normalizer.billing_mode(@providers[e["provider"]]) and
      (is_nil(e["selected_profile"]) or model?(e["selected_profile"])) and
      (is_nil(e["endpoint_sha256"]) or
         (is_binary(e["endpoint_sha256"]) and
            Regex.match?(~r/\A[0-9a-f]{64}\z/, e["endpoint_sha256"]))) and
      model?(e["model"]) and integer?(e["admitted_at_ms"])
  end

  defp scope_matches?(ledger, event) do
    origin = ledger.scope["delegation_origin"] || %{}

    (is_nil(ledger.session_id) or ledger.session_id == event["session_id"]) and
      Enum.all?(~w(provider model), fn field ->
        not Map.has_key?(ledger.scope, field) or ledger.scope[field] == event[field]
      end) and
      Enum.all?(~w(parent_session_id parent_request_id), fn field ->
        origin[field] == event[field]
      end)
  end

  defp valid_result?(%{"type" => "request_usage_observed"} = e) do
    closed?(e, ~w(type version request_id attempt_id sequence usage)) and e["version"] === 1 and
      is_integer(e["sequence"]) and e["sequence"] > 0 and Normalizer.valid?(e["usage"])
  end

  defp valid_result?(%{"type" => "request_finished"} = e) do
    closed?(
      e,
      ~w(type version request_id attempt_id outcome duration_ms reported_model usage finality)
    ) and
      e["version"] === 1 and e["outcome"] in ~w(completed failed cancelled) and
      integer?(e["duration_ms"]) and (is_nil(e["reported_model"]) or model?(e["reported_model"])) and
      e["finality"] == if(e["outcome"] == "completed", do: "final", else: "partial") and
      Normalizer.valid?(e["usage"])
  end

  defp closed?(e, fields),
    do: Enum.sort(Map.keys(e)) == Enum.sort(fields) and Ipse.MCP.Schema.validate_object(e) == :ok

  defp integer?(n), do: is_integer(n) and n >= 0 and n <= 9_007_199_254_740_991

  defp profile(execution) when is_map(execution),
    do: Ipse.RuntimeInfo.model_name(execution[:id] || execution["id"])

  defp profile(_), do: nil
  defp model?(m), do: is_binary(m) and Ipse.RuntimeInfo.model_name(m) == m
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
