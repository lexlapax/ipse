defmodule Ipse.Extensions.EmbeddingCall do
  @moduledoc "Explicit selected-profile embeddings with canonical accounting and private results."
  alias Ipse.{EmbeddingProfiles, Usage}
  alias Ipse.Extensions.EffectResult
  @error {:error, :invalid_extension_embedding_call}
  @source_keys ~w(type version operation_id parent_invocation_id identity_sha256 request_sha256 binding_sha256 execution admission)
  @failures ~w(embedding_request_failed embedding_response embedding_timeout embedding_cancelled embedding_limit)

  def operation?(request), do: is_map(request) and request["op"] == "embedding.create"

  def validate(request) do
    if keys?(request, ~w(op version profile inputs timeout_ms)) and operation?(request) and
         request["version"] in [1, 2] and profile_id?(request["profile"]) and
         is_integer(request["timeout_ms"]) and request["timeout_ms"] in 1000..120_000 and
         is_list(request["inputs"]) and length(request["inputs"]) in 1..8 and
         Enum.all?(request["inputs"], &text?/1) and
         Enum.sum(Enum.map(request["inputs"], &byte_size/1)) <= 12_288 and
         Ipse.Extension.validate(request) == :ok,
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def binding(config, request) do
    with {:ok, runtime, execution} <- EmbeddingProfiles.prepare(config, request),
         {:ok, destination} <- Ipse.Provider.destination(runtime) do
      {:ok,
       %{
         "kind" => "embedding",
         "version" => 1,
         "execution" => execution,
         "destination" => destination
       }}
    end
  end

  def valid_binding?(binding, request, scope \\ nil) do
    with :ok <- validate(request),
         true <- keys?(binding, ~w(kind version execution destination)),
         true <- binding["kind"] == "embedding" and binding["version"] === 1,
         true <- Ipse.Provider.valid_destination?(binding["destination"]),
         snapshot = Map.put(binding["execution"], "destination", binding["destination"]),
         true <- EmbeddingProfiles.public_profile?(snapshot),
         true <-
           snapshot["id"] == request["profile"] and
             snapshot["timeout_ms"] <= request["timeout_ms"] do
      if is_nil(scope) do
        true
      else
        with {:ok, execution} <- EmbeddingProfiles.execution(scope, request),
             profile = scope["embedding_profiles"][request["profile"]] do
          binding["execution"] === execution and binding["destination"] === profile["destination"]
        else
          _ -> false
        end
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def delegated_approval?("extension:embedding.create", proposed) do
    keys?(
      proposed,
      ~w(extension artifact_sha256 namespace request execution destination effect_binding)
    ) and
      profile_id?(proposed["extension"]) and hash?(proposed["artifact_sha256"]) and
      id?(proposed["namespace"]) and
      valid_binding?(proposed["effect_binding"], proposed["request"]) and
      proposed["execution"] === proposed["effect_binding"]["execution"] and
      proposed["destination"] === proposed["effect_binding"]["destination"]
  rescue
    _ -> false
  end

  def delegated_approval?(_, _), do: false

  def source(intent, admission, execution) do
    intent
    |> Map.take(~w(operation_id parent_invocation_id identity_sha256 request_sha256))
    |> Map.merge(%{
      "type" => "extension_embedding_request",
      "version" => 1,
      "binding_sha256" => Ipse.Compaction.digest([intent["effect_binding"]]),
      "execution" => execution,
      "admission" => admission
    })
  end

  def valid_source?(source, intent, scope) do
    with true <- keys?(source, @source_keys) and is_map(intent),
         true <- source["type"] == "extension_embedding_request" and source["version"] === 1,
         true <- intent["approval"] in ~w(approved session_allow) and intent["version"] === 2,
         true <- valid_binding?(intent["effect_binding"], intent["request"], scope),
         true <- source["binding_sha256"] == Ipse.Compaction.digest([intent["effect_binding"]]),
         true <- source["execution"] === intent["effect_binding"]["execution"],
         true <- source["request_sha256"] == Ipse.Compaction.digest([intent["request"]]),
         true <-
           Map.take(source, ~w(operation_id parent_invocation_id identity_sha256 request_sha256)) ==
             Map.take(
               intent,
               ~w(operation_id parent_invocation_id identity_sha256 request_sha256)
             ),
         admission = source["admission"],
         true <- Usage.operation(admission) == "embedding" and admission["kind"] == "extension",
         true <-
           admission["request_id"] == source["operation_id"] and
             admission["session_id"] == intent["namespace"],
         true <-
           Usage.valid_request_record?(
             Usage.request_record(%{
               admission: admission,
               observation: nil,
               completion: nil
             })
           ),
         true <-
           Enum.all?(
             ~w(provider model billing_mode endpoint_sha256),
             &(admission[&1] == source["execution"][&1])
           ),
         true <- admission["selected_profile"] == source["execution"]["id"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_response?(event, admission, intent) do
    inference = event["inference"]

    EffectResult.valid_source?(event, intent) and Usage.operation(admission) == "embedding" and
      inference["request_id"] == admission["request_id"] and
      inference["attempt_id"] == admission["attempt_id"] and
      inference["profile"] == admission["selected_profile"]
  rescue
    _ -> false
  end

  def response(intent, admission, completion, payload) do
    data = Map.take(payload, ~w(encoding dimensions vectors))

    inference = %{
      "request_id" => admission["request_id"],
      "attempt_id" => admission["attempt_id"],
      "profile" => admission["selected_profile"],
      "reported_model" => completion["reported_model"],
      "usage" => completion["usage"],
      "provider_response_sha256" => payload["provider_response_sha256"]
    }

    with true <- completion["outcome"] == "completed" and completion["finality"] == "final",
         true <-
           Ipse.Provider.Embedding.valid_result?(
             payload,
             intent["effect_binding"]["execution"],
             intent["request"]["inputs"]
           ),
         true <- completion["reported_model"] == payload["reported_model"],
         {:ok, event} <- EffectResult.embedding_source(intent, data, inference),
         true <- valid_response?(event, admission, intent) do
      {:ok, event}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def valid_result_source?(event, record, source) do
    outcome = event["outcome"]

    case {outcome["status"], record} do
      {"denied", nil} ->
        event["approval"] == "denied" and is_nil(source)

      {"unknown", _} ->
        is_nil(source) or
          (is_map(record) and
             valid_response?(
               source,
               record.admission,
               Ipse.Extensions.Actions.result_intent(event)
             ) and
             (is_nil(record.completion) or
                (record.completion["outcome"] == "completed" and
                   record.completion["finality"] == "final" and
                   record.completion["usage"] === source["inference"]["usage"] and
                   record.completion["reported_model"] === source["inference"]["reported_model"])))

      {"failed", nil} ->
        outcome["value"] == %{"code" => "embedding_limit"} and is_nil(source)

      {"ok", %{completion: %{"outcome" => "completed"} = completion, admission: admission}} ->
        valid_response?(source, admission, Ipse.Extensions.Actions.result_intent(event)) and
          completion["usage"] === source["inference"]["usage"] and
          completion["reported_model"] === source["inference"]["reported_model"] and
          value_from_completion(
            Ipse.Extensions.Actions.result_intent(event),
            admission,
            completion,
            source
          ) ==
            {:ok, outcome["value"]}

      {"failed", %{completion: %{} = completion}} ->
        is_nil(source) and
          case completion["outcome"] do
            "completed" -> outcome["value"]["code"] == "embedding_response"
            "cancelled" -> outcome["value"]["code"] in ~w(embedding_cancelled embedding_timeout)
            _ -> outcome["value"]["code"] == "embedding_request_failed"
          end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def value_from_completion(intent, admission, %{"outcome" => "completed"} = completion, source) do
    request = intent["request"]

    if valid_response?(source, admission, intent) and source["kind"] == "embedding.f32le" and
         completion["finality"] == "final" and
         source["operation_id"] == admission["request_id"] and
         source["inference"]["attempt_id"] == admission["attempt_id"] and
         source["inference"]["profile"] == request["profile"] and
         Ipse.Provider.Embedding.valid_data?(
           source["data"],
           request["inputs"],
           source["data"]["dimensions"]
         ) and
         completion["usage"] === source["inference"]["usage"] and
         completion["reported_model"] === source["inference"]["reported_model"] do
      value = %{
        "version" => request["version"],
        "request_id" => admission["request_id"],
        "attempt_id" => admission["attempt_id"],
        "profile" => request["profile"],
        "reported_model" => completion["reported_model"],
        "usage" => completion["usage"],
        "result" => EffectResult.descriptor(source)
      }

      value =
        if request["version"] == 2 do
          {:ok, selection} = selection_sha256(intent)
          Map.put(value, "selection_sha256", selection)
        else
          value
        end

      if Ipse.Extension.validate(value) == :ok,
        do: {:ok, value},
        else: failed("embedding_response")
    else
      failed("embedding_response")
    end
  rescue
    _ -> failed("embedding_response")
  end

  def value_from_completion(_, _, _, _), do: failed("embedding_request_failed")

  def selection_sha256(intent) do
    with true <- valid_binding?(intent["effect_binding"], intent["request"]) do
      binding = intent["effect_binding"]
      EmbeddingProfiles.selection_sha256(binding["execution"], binding["destination"])
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def bound_selection?(event) do
    if event["request"]["version"] === 1 do
      true
    else
      with {:ok, selection} <- selection_sha256(Ipse.Extensions.Actions.result_intent(event)) do
        event["outcome"]["value"]["selection_sha256"] === selection
      else
        _ -> false
      end
    end
  rescue
    _ -> false
  end

  def valid_outcome?(_request, status, value, _) when status in ~w(unknown denied),
    do: value == %{}

  def valid_outcome?(_, "failed", value, _),
    do: keys?(value, ["code"]) and value["code"] in @failures

  def valid_outcome?(request, "ok", value, operation) do
    fields = ~w(version request_id attempt_id profile reported_model usage result)
    fields = if request["version"] === 2, do: ["selection_sha256" | fields], else: fields

    validate(request) == :ok and
      keys?(value, fields) and value["version"] === request["version"] and
      (request["version"] === 1 or hash?(value["selection_sha256"])) and
      value["request_id"] == operation and id?(value["attempt_id"]) and
      value["profile"] == request["profile"] and is_binary(value["reported_model"]) and
      Ipse.RuntimeInfo.model_name(value["reported_model"]) == value["reported_model"] and
      Ipse.Usage.Normalizer.valid?(value["usage"], "embedding") and
      EffectResult.descriptor?(value["result"], operation) and value["result"]["version"] === 2 and
      value["result"]["vector_count"] == length(request["inputs"]) and
      Ipse.Extension.validate(value) == :ok
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def execute(context, intent) do
    Ipse.Extensions.Inference.execute(context, intent, :embedding, fn config, request, emit ->
      Ipse.Provider.Request.embed(config, request["inputs"], emit)
    end)
  end

  defp failed(code), do: {:failed, %{"code" => code}}
  defp text?(value), do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..4096

  defp profile_id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, value)

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
end
