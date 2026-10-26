defmodule Ipse.Extension.DecisionCall do
  @moduledoc "Profile-bound advisory decision effects admitted and journaled by the Session."
  alias Ipse.Config.Decisions
  alias Ipse.Provider.Decision.Transport
  alias Ipse.Usage
  @error {:error, :invalid_extension_decision_call}
  @source_keys ~w(type version operation_id parent_invocation_id identity_sha256 request_sha256 binding_sha256 execution admission)
  @failures ~w(decision_request_failed decision_response decision_timeout decision_cancelled decision_limit)

  def operation?(request), do: is_map(request) and request["op"] == "decision.create"
  def neutral(request), do: Map.take(request, ~w(version profile input questions))

  def validate(request) do
    if keys?(request, ~w(op version profile input questions timeout_ms)) and operation?(request) and
         request["version"] === 1 and profile_id?(request["profile"]) and
         is_integer(request["timeout_ms"]) and request["timeout_ms"] in 1000..120_000 and
         Ipse.Decision.validate_request(neutral(request)) == :ok and
         Ipse.Extension.validate(request) == :ok, do: :ok, else: @error
  rescue
    _ -> @error
  end

  def binding(config, request) do
    with :ok <- validate(request),
         {:ok, runtime, execution} <- Decisions.prepare(config, request),
         {:ok, _} <-
           Ipse.Provider.Decision.encode(
             Transport.engine(runtime.provider),
             neutral(request),
             runtime.model
           ),
         {:ok, destination} <- Transport.destination(runtime) do
      {:ok,
       %{
         "kind" => "decision",
         "version" => 1,
         "execution" => execution,
         "destination" => destination
       }}
    end
  end

  def valid_binding?(binding, request, scope \\ nil) do
    with :ok <- validate(request),
         true <- keys?(binding, ~w(kind version execution destination)),
         true <- binding["kind"] == "decision" and binding["version"] === 1,
         profile = Map.put(binding["execution"], "destination", binding["destination"]),
         true <-
           Decisions.public_profile?(profile) and profile["id"] == request["profile"] and
             profile["timeout_ms"] <= request["timeout_ms"],
         {:ok, _} <-
           Ipse.Provider.Decision.encode(
             Transport.engine(Decisions.provider(profile["provider"])),
             neutral(request),
             profile["model"]
           ) do
      if is_nil(scope) do
        true
      else
        with {:ok, execution} <- Decisions.execution(scope, request) do
          binding["execution"] === execution and
            binding["destination"] ===
              scope["decision_profiles"][request["profile"]]["destination"]
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

  def delegated_approval?("extension:decision.create", proposed) do
    keys?(
      proposed,
      ~w(extension artifact_sha256 namespace request execution destination effect_binding)
    ) and
      profile_id?(proposed["extension"]) and Ipse.JSON.sha256?(proposed["artifact_sha256"]) and
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
      "type" => "extension_decision_request",
      "version" => 1,
      "binding_sha256" => Ipse.JSON.digest([intent["effect_binding"]]),
      "execution" => execution,
      "admission" => admission
    })
  end

  def valid_source?(source, intent, scope) do
    with true <- keys?(source, @source_keys),
         true <- source["type"] == "extension_decision_request" and source["version"] === 1,
         true <- intent["approval"] in ~w(approved session_allow) and intent["version"] === 2,
         true <- valid_binding?(intent["effect_binding"], intent["request"], scope),
         true <- source["binding_sha256"] == Ipse.JSON.digest([intent["effect_binding"]]),
         true <- source["execution"] === intent["effect_binding"]["execution"],
         true <- source["request_sha256"] == Ipse.JSON.digest([intent["request"]]),
         true <-
           Map.take(source, ~w(operation_id parent_invocation_id identity_sha256 request_sha256)) ==
             Map.take(
               intent,
               ~w(operation_id parent_invocation_id identity_sha256 request_sha256)
             ),
         admission = source["admission"],
         true <- Usage.operation(admission) == "decision" and admission["kind"] == "extension",
         true <-
           admission["request_id"] == source["operation_id"] and
             admission["session_id"] == intent["namespace"],
         true <-
           Usage.valid_request_record?(
             Usage.request_record(%{admission: admission, observation: nil, completion: nil})
           ),
         true <-
           Enum.all?(
             ~w(provider model billing_mode endpoint_sha256),
             &(admission[&1] == source["execution"][&1])
           ),
         true <- admission["selected_profile"] == source["execution"]["id"] do
      admission["service_id"] == source["execution"]["service_id"] and
        admission["expected_model"] == source["execution"]["expected_model"]
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def response(intent, admission, completion, payload) do
    if completion["outcome"] == "completed" and completion["finality"] == "final" and
         completion["request_id"] == admission["request_id"] and
         completion["attempt_id"] == admission["attempt_id"] and
         completion["reported_model"] == payload["reported_model"] and
         Transport.valid_result?(
           payload,
           intent["effect_binding"]["execution"],
           neutral(intent["request"])
         ) do
      event = %{
        "type" => "extension_decision_response",
        "version" => 1,
        "request_id" => admission["request_id"],
        "attempt_id" => admission["attempt_id"],
        "usage" => completion["usage"],
        "request_sha256" => Ipse.JSON.digest([intent["request"]]),
        "payload" => payload,
        "payload_sha256" => Ipse.JSON.digest([payload])
      }

      if valid_response?(event, admission, intent), do: {:ok, event}, else: @error
    else
      @error
    end
  rescue
    _ -> @error
  end

  def valid_response?(event, admission, intent) do
    keys?(
      event,
      ~w(type version request_id attempt_id usage request_sha256 payload payload_sha256)
    ) and
      event["type"] == "extension_decision_response" and event["version"] === 1 and
      event["request_id"] == admission["request_id"] and
      event["request_id"] == intent["operation_id"] and
      event["attempt_id"] == admission["attempt_id"] and
      Usage.operation(admission) == "decision" and admission["session_id"] == intent["namespace"] and
      admission["service_id"] == intent["effect_binding"]["execution"]["service_id"] and
      admission["expected_model"] == intent["effect_binding"]["execution"]["expected_model"] and
      Usage.valid_usage?(event["usage"], "decision") and
      valid_binding?(intent["effect_binding"], intent["request"]) and
      event["request_sha256"] == Ipse.JSON.digest([intent["request"]]) and
      event["payload_sha256"] == Ipse.JSON.digest([event["payload"]]) and
      Transport.valid_result?(
        event["payload"],
        intent["effect_binding"]["execution"],
        neutral(intent["request"])
      )
  rescue
    _ -> false
  end

  def value_from_completion(intent, admission, %{"outcome" => "completed"} = completion, event) do
    if completion["finality"] == "final" and valid_response?(event, admission, intent) and
         completion["request_id"] == admission["request_id"] and
         completion["attempt_id"] == admission["attempt_id"] and
         completion["usage"] === event["usage"] and
         completion["reported_model"] == event["payload"]["reported_model"] do
      {:ok, selection} = selection_sha256(intent)

      value = %{
        "version" => 1,
        "request_id" => admission["request_id"],
        "attempt_id" => admission["attempt_id"],
        "profile" => intent["request"]["profile"],
        "reported_model" => completion["reported_model"],
        "usage" => completion["usage"],
        "result" => event["payload"]["result"],
        "selection_sha256" => selection
      }

      if valid_outcome?(intent["request"], "ok", value, admission["request_id"]),
        do: {:ok, value},
        else: failed("decision_response")
    else
      failed("decision_response")
    end
  rescue
    _ -> failed("decision_response")
  end

  def value_from_completion(_, _, _, _), do: failed("decision_request_failed")

  def valid_result_source?(event, record, response) do
    outcome = event["outcome"]
    intent = Ipse.Extension.Actions.result_intent(event)

    case {outcome["status"], record} do
      {"denied", nil} ->
        event["approval"] == "denied" and is_nil(response)

      {"unknown", _} ->
        is_nil(response) or
          (is_map(record) and valid_response?(response, record.admission, intent) and
             (is_nil(record.completion) or
                (record.completion["outcome"] == "completed" and
                   record.completion["reported_model"] == response["payload"]["reported_model"] and
                   record.completion["usage"] === response["usage"])))

      {"failed", nil} ->
        outcome["value"] == %{"code" => "decision_limit"} and is_nil(response)

      {"ok", %{completion: %{"outcome" => "completed"} = completion, admission: admission}} ->
        value_from_completion(intent, admission, completion, response) == {:ok, outcome["value"]}

      {"failed", %{completion: %{} = completion}} ->
        is_nil(response) and
          case completion["outcome"] do
            "completed" -> outcome["value"]["code"] == "decision_response"
            "cancelled" -> outcome["value"]["code"] in ~w(decision_cancelled decision_timeout)
            _ -> outcome["value"]["code"] == "decision_request_failed"
          end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def selection_sha256(intent) do
    if valid_binding?(intent["effect_binding"], intent["request"]),
      do:
        Decisions.selection_sha256(
          intent["effect_binding"]["execution"],
          intent["effect_binding"]["destination"]
        ),
      else: @error
  rescue
    _ -> @error
  end

  def bound_selection?(event) do
    with {:ok, selection} <- selection_sha256(Ipse.Extension.Actions.result_intent(event)) do
      event["outcome"]["value"]["selection_sha256"] === selection
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def bound_response?(event, response) do
    value = event["outcome"]["value"]

    event["outcome"]["status"] == "ok" and bound_selection?(event) and
      valid_outcome?(event["request"], "ok", value, event["operation_id"]) and
      keys?(
        response,
        ~w(type version request_id attempt_id usage request_sha256 payload payload_sha256)
      ) and
      response["type"] == "extension_decision_response" and response["version"] === 1 and
      response["request_id"] == value["request_id"] and
      response["attempt_id"] == value["attempt_id"] and
      response["request_sha256"] == Ipse.JSON.digest([event["request"]]) and
      response["payload_sha256"] == Ipse.JSON.digest([response["payload"]]) and
      response["usage"] === value["usage"] and response["payload"]["result"] === value["result"] and
      response["payload"]["reported_model"] == value["reported_model"] and
      Transport.valid_result?(
        response["payload"],
        event["effect_binding"]["execution"],
        neutral(event["request"])
      )
  rescue
    _ -> false
  end

  def valid_outcome?(_request, status, value, _) when status in ~w(unknown denied),
    do: value == %{}

  def valid_outcome?(_, "failed", value, _),
    do: keys?(value, ["code"]) and value["code"] in @failures

  def valid_outcome?(request, "ok", value, operation) do
    validate(request) == :ok and
      keys?(
        value,
        ~w(version request_id attempt_id profile reported_model usage result selection_sha256)
      ) and
      value["version"] === 1 and value["request_id"] == operation and id?(value["attempt_id"]) and
      value["profile"] == request["profile"] and is_binary(value["reported_model"]) and
      Ipse.Provider.model_name(value["reported_model"]) == value["reported_model"] and
      Ipse.JSON.sha256?(value["selection_sha256"]) and
      Usage.valid_usage?(value["usage"], "decision") and
      Ipse.Decision.validate_result(neutral(request), value["result"]) == :ok and
      Ipse.Extension.validate(value) == :ok
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def execute(context, intent),
    do:
      Ipse.Extension.Inference.execute(context, intent, :decision, fn selected, request, emit ->
        Transport.request(selected, neutral(request), emit)
      end)

  defp failed(code), do: {:failed, %{"code" => code}}

  defp profile_id?(id),
    do: is_binary(id) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, id)

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
