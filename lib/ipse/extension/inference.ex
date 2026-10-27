defmodule Ipse.Extension.ModelCall do
  @moduledoc "Explicit one-shot text inference with profile-bound canonical accounting."
  alias Ipse.Usage
  alias Ipse.Config.Profiles
  @wire_bytes 1_048_576

  @providers Ipse.Provider.Registry.atoms()
  @source_keys ~w(type version operation_id parent_invocation_id identity_sha256 request_sha256 execution admission)
  @execution_keys ~w(id provider model billing_mode endpoint_sha256 reasoning_effort max_output_tokens timeout_ms)
  @error {:error, :invalid_extension_model_call}

  def operation?(request), do: is_map(request) and request["op"] == "model.complete"

  @doc "Recognize the host's complete model-egress approval, which owns no filesystem mutation lease."
  def delegated_approval?("extension:model.complete", proposed) do
    keys?(proposed, ~w(extension artifact_sha256 namespace request execution destination)) and
      is_binary(proposed["extension"]) and
      Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, proposed["extension"]) and
      is_binary(proposed["artifact_sha256"]) and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, proposed["artifact_sha256"]) and
      validate(proposed["request"]) == :ok and valid_profile?(proposed["execution"]) and
      proposed["execution"]["timeout_ms"] <= proposed["request"]["timeout_ms"] and
      proposed["execution"]["id"] == proposed["request"]["profile"] and
      proposed["execution"]["provider"] in Ipse.Provider.Registry.chat_ids() and
      supported_response?(proposed["request"], proposed["execution"]["provider"]) and
      Ipse.Provider.valid_destination?(proposed["destination"]) and
      id?(proposed["namespace"])
  rescue
    _ -> false
  end

  def delegated_approval?(_, _), do: false

  def validate(request) do
    version = if is_map(request), do: request["version"]

    schema = %{
      "type" => "object",
      "properties" => %{
        "op" => %{"type" => "string", "enum" => ["model.complete"]},
        "version" => %{"type" => "integer", "enum" => [1, 2, 3]},
        "profile" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
        "instruction" => %{"type" => "string", "maxLength" => 2048},
        "input" => %{"type" => "string", "minLength" => 1, "maxLength" => 4096},
        "max_output_bytes" => %{"type" => "integer", "minimum" => 1, "maximum" => 8192},
        "timeout_ms" => %{
          "type" => "integer",
          "minimum" => 1000,
          "maximum" => if(version === 3, do: 600_000, else: 120_000)
        }
      },
      "required" => ~w(op version profile instruction input max_output_bytes timeout_ms),
      "additionalProperties" => false
    }

    schema =
      if version in [2, 3] do
        schema
        |> put_in(["properties", "response_schema"], %{"type" => "object"})
        |> Map.update!("required", &(&1 ++ ["response_schema"]))
      else
        schema
      end

    with :ok <- Ipse.JSON.validate_arguments(schema, request),
         true <- version in [1, 2, 3],
         :ok <- validate_response_schema(request),
         true <- Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, request["profile"]),
         true <- is_integer(request["timeout_ms"]) and is_integer(request["max_output_bytes"]),
         true <-
           byte_size(Jason.encode!(request)) <= if(version in [2, 3], do: 12_288, else: 8192),
         :ok <- Ipse.Extension.validate(request) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def enabled?(config),
    do: Enum.any?(config[:extensions] || [], &("host.model" in &1.identity["capabilities"]))

  def profiles(config), do: config[:model_profiles] || config[:profiles] || %{}

  def configuration(config) do
    if enabled?(config), do: Profiles.validate(profiles(config), %{}), else: :ok
  end

  def snapshot(config) do
    if enabled?(config) do
      Map.new(profiles(config), fn {id, profile} ->
        {id,
         %{
           "id" => id,
           "provider" => profile["provider"],
           "model" => profile["model"],
           "billing_mode" => Ipse.Usage.billing_mode(@providers[profile["provider"]]),
           "endpoint_sha256" =>
             if(profile["base_url"], do: Ipse.JSON.sha256(profile["base_url"])),
           "reasoning_effort" => profile["reasoning_effort"],
           "max_output_tokens" => profile["max_output_tokens"],
           "timeout_ms" => profile_timeout(profile, config)
         }
         |> Map.merge(Ipse.Provider.Registry.profile_values(profile))}
      end)
    end
  end

  defp profile_timeout(profile, config) do
    case Map.fetch(profile, "model_call_timeout_ms") do
      {:ok, limit} ->
        Enum.min([limit, config[:timeout_ms] || 120_000, 600_000])

      :error ->
        Enum.min([profile["timeout_ms"] || 120_000, config[:timeout_ms] || 120_000, 120_000])
    end
  end

  def execution(scope, request) do
    with :ok <- validate(request),
         profile when is_map(profile) <- (scope["model_profiles"] || %{})[request["profile"]],
         true <- valid_profile?(profile),
         true <-
           profile["id"] == request["profile"] and
             profile["provider"] in Ipse.Provider.Registry.chat_ids(),
         true <- supported_response?(request, profile["provider"]),
         cap =
           Ipse.Provider.narrow_output_tokens(
             scope["max_output_tokens"],
             profile["max_output_tokens"]
           ),
         cap =
           Ipse.Provider.narrow_output_tokens(
             cap,
             get_in(scope, ["budget", "reserve_output_tokens"])
           ),
         :ok <-
           Ipse.Provider.validate_output_limit(%{
             provider: @providers[profile["provider"]],
             max_output_tokens: cap
           }) do
      {:ok,
       %{
         profile
         | "max_output_tokens" => cap,
           "timeout_ms" => min(profile["timeout_ms"], request["timeout_ms"])
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def prepare(config, request) do
    scope = %{
      "model_profiles" => snapshot(config),
      "max_output_tokens" => config[:max_output_tokens],
      "budget" => config[:budget]
    }

    with {:ok, execution} <- execution(scope, request),
         profile = profiles(config)[request["profile"]],
         :ok <- Profiles.validate_profile(profile) do
      selected = Profiles.manifest(request["profile"], profile) |> Map.put(:role, "extension")

      runtime =
        config
        |> Map.take([:budget, :budget_root, :budget_checkpoint, :delegation_origin])
        |> Map.merge(%{
          provider: @providers[profile["provider"]],
          model: profile["model"],
          execution: selected,
          reasoning_effort: profile["reasoning_effort"],
          max_output_tokens: execution["max_output_tokens"],
          max_response_bytes: @wire_bytes,
          timeout_ms: execution["timeout_ms"]
        })
        |> Map.merge(Ipse.Provider.Registry.profile_runtime(profile))

      runtime =
        if request["version"] in [2, 3],
          do: Map.put(runtime, :extension_response_schema, request["response_schema"]),
          else: runtime

      runtime =
        if profile["base_url"],
          do: Map.put(runtime, :base_url, profile["base_url"]),
          else: runtime

      runtime =
        if Ipse.Provider.Registry.auth?(runtime.provider),
          do: Map.put(runtime, :auth_dir, config[:model_auth_dir] || config[:auth_dir]),
          else: runtime

      with {:ok, _destination} <- Ipse.Provider.destination(runtime),
           do: {:ok, runtime, execution}
    end
  end

  def source(intent, admission, execution) do
    Map.merge(
      Map.take(intent, ~w(operation_id parent_invocation_id identity_sha256 request_sha256)),
      %{
        "type" => "extension_model_request",
        "version" => 1,
        "execution" => execution,
        "admission" => admission
      }
    )
  end

  def valid_source?(source, intent, scope) do
    admission = source["admission"]

    with true <- is_map(intent) and keys?(source, @source_keys),
         true <- source["type"] == "extension_model_request" and source["version"] === 1,
         true <-
           operation?(intent["request"]) and intent["approval"] in ~w(approved session_allow),
         true <- intent["request_sha256"] == Ipse.JSON.digest([intent["request"]]),
         true <-
           Map.take(source, ~w(operation_id parent_invocation_id identity_sha256 request_sha256)) ==
             Map.take(
               intent,
               ~w(operation_id parent_invocation_id identity_sha256 request_sha256)
             ),
         {:ok, expected} <- execution(scope, intent["request"]),
         true <- source["execution"] === expected,
         true <-
           admission["kind"] == "extension" and admission["request_id"] == source["operation_id"],
         true <- admission["session_id"] == intent["namespace"],
         true <-
           Usage.valid_request_record?(
             Usage.request_record(%{admission: admission, completion: nil, observation: nil})
           ),
         true <-
           Enum.all?(
             ~w(provider model billing_mode endpoint_sha256),
             &(admission[&1] == expected[&1])
           ),
         true <- admission["selected_profile"] == expected["id"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_outcome?(_request, status, value, _) when status in ~w(unknown denied),
    do: value == %{}

  def valid_outcome?(_request, "failed", value, _),
    do:
      keys?(value, ["code"]) and
        value["code"] in ~w(model_request_failed model_response model_timeout model_cancelled model_limit)

  def valid_outcome?(request, "ok", value, operation) do
    validate(request) == :ok and
      keys?(value, ~w(version request_id attempt_id profile reported_model text usage)) and
      value["version"] === 1 and value["request_id"] == operation and id?(value["attempt_id"]) and
      value["profile"] == request["profile"] and text?(value["text"], request["max_output_bytes"]) and
      matches_response?(request, value["text"]) and
      (is_nil(value["reported_model"]) or
         Ipse.Provider.model_name(value["reported_model"]) == value["reported_model"]) and
      Ipse.Usage.valid_usage?(value["usage"])
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def valid_profile?(profile) do
    keys?(profile, @execution_keys ++ Ipse.Provider.Registry.profile_keys(profile["provider"])) and
      Ipse.Provider.Registry.valid_profile_values?(profile) and
      is_binary(profile["id"]) and
      Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, profile["id"]) and
      profile["provider"] in Map.keys(@providers) and
      is_binary(profile["model"]) and
      Ipse.Provider.model_name(profile["model"]) == profile["model"] and
      profile["billing_mode"] ==
        Ipse.Usage.billing_mode(@providers[profile["provider"]]) and
      (is_nil(profile["endpoint_sha256"]) or
         (is_binary(profile["endpoint_sha256"]) and
            Regex.match?(~r/\A[0-9a-f]{64}\z/, profile["endpoint_sha256"]))) and
      Profiles.reasoning(profile["provider"], profile["model"], profile["reasoning_effort"]) ==
        :ok and
      Ipse.Provider.validate_output_limit(%{
        provider: @providers[profile["provider"]],
        max_output_tokens: profile["max_output_tokens"]
      }) == :ok and
      is_integer(profile["timeout_ms"]) and profile["timeout_ms"] in 1..600_000
  rescue
    _ -> false
  end

  def valid_response?(event, admission) do
    keys?(event, ~w(type version request_id attempt_id assistant assistant_sha256)) and
      event["type"] == "extension_model_response" and event["version"] === 1 and
      event["request_id"] == admission["request_id"] and
      event["attempt_id"] == admission["attempt_id"] and
      is_map(event["assistant"]) and event["assistant"]["role"] == "assistant" and
      response(admission, event["assistant"]) == {:ok, event}
  rescue
    _ -> false
  end

  def valid_result_source?(event, record, response) do
    outcome = event["outcome"]

    case {outcome["status"], record} do
      {"denied", nil} ->
        event["approval"] == "denied"

      {"unknown", _} ->
        true

      {"failed", nil} ->
        outcome["value"] == %{"code" => "model_limit"}

      {"ok", %{completion: %{"outcome" => "completed"} = completion, admission: admission}} ->
        response != nil and
          completion["reported_model"] ==
            Ipse.Provider.model_name(
              get_in(response, ["assistant", "provider_data", "reported_model"])
            ) and
          value_from_record(event["request"], admission, completion, response["assistant"]) ==
            {:ok, outcome["value"]}

      {"failed", %{completion: %{} = completion}} ->
        code = outcome["value"]["code"]

        cond do
          completion["outcome"] == "completed" ->
            code == "model_response" and
              (response == nil or
                 match?(
                   {:failed, _},
                   value_from_record(
                     event["request"],
                     record.admission,
                     completion,
                     response["assistant"]
                   )
                 ))

          completion["outcome"] == "cancelled" ->
            code in ~w(model_cancelled model_timeout)

          true ->
            code == "model_request_failed"
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def response(admission, assistant) do
    true = is_map(assistant) and assistant["role"] == "assistant"

    event = %{
      "type" => "extension_model_response",
      "version" => 1,
      "request_id" => admission["request_id"],
      "attempt_id" => admission["attempt_id"],
      "assistant" => assistant,
      "assistant_sha256" => Ipse.JSON.digest([assistant])
    }

    if byte_size(Jason.encode!(event)) <= 262_144, do: {:ok, event}, else: @error
  rescue
    _ -> @error
  end

  def value_from_completion(
        request,
        admission,
        %{"outcome" => "completed"} = completion,
        assistant
      ),
      do: value_from_record(request, admission, completion, assistant)

  def value_from_completion(_, _, _, _), do: {:failed, %{"code" => "model_request_failed"}}

  def value_from_record(request, admission, record, assistant) do
    if is_map(assistant) and assistant["role"] == "assistant" and
         assistant["tool_calls"] in [nil, []] and
         text?(assistant["content"], request["max_output_bytes"]) and
         matches_response?(request, assistant["content"]) do
      value = %{
        "version" => 1,
        "request_id" => admission["request_id"],
        "attempt_id" => admission["attempt_id"],
        "profile" => request["profile"],
        "reported_model" => record["reported_model"],
        "text" => assistant["content"],
        "usage" => record["usage"]
      }

      if Ipse.Extension.validate(value) == :ok and byte_size(Jason.encode!(value)) <= 12_000,
        do: {:ok, value},
        else: {:failed, %{"code" => "model_response"}}
    else
      {:failed, %{"code" => "model_response"}}
    end
  end

  @doc "Run provider IO in a linked owned task; the Session alone admits and journals it."
  def execute(context, intent) do
    Ipse.Extension.Inference.execute(context, intent, :text, fn selected, request, emit ->
      messages = Ipse.Session.Context.helper_messages(request["instruction"], request["input"])
      Ipse.Provider.request_complete(selected, messages, [], emit)
    end)
  end

  defp text?(text, limit),
    do: is_binary(text) and String.valid?(text) and byte_size(text) <= limit

  defp validate_response_schema(%{"version" => 1}), do: :ok

  defp validate_response_schema(%{
         "version" => version,
         "response_schema" => %{"type" => "object"} = schema
       })
       when version in [2, 3],
       do: Ipse.JSON.validate_schema(schema)

  defp validate_response_schema(_), do: @error

  defp supported_response?(request, provider),
    do: request["version"] == 1 or Ipse.Provider.Registry.supports?(provider, :structured_output?)

  defp matches_response?(%{"version" => 1}, _text), do: true

  defp matches_response?(%{"version" => version} = request, text) when version in [2, 3] do
    with {:ok, object} <- Ipse.JSON.decode_bounded(text, request["max_output_bytes"]),
         :ok <- Ipse.JSON.validate_object(object),
         :ok <- Ipse.JSON.validate_result(request["response_schema"], object) do
      true
    else
      _ -> false
    end
  end

  defp matches_response?(_, _), do: false

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
end

defmodule Ipse.Extension.EmbeddingCall do
  @moduledoc "Explicit selected-profile embeddings with canonical accounting and private results."
  alias Ipse.Config.Profiles
  alias Ipse.Usage
  alias Ipse.Extension.EffectResult
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
    with {:ok, runtime, execution} <- Profiles.prepare_embedding(config, request),
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
         true <- Profiles.public_embedding_profile?(snapshot),
         true <-
           snapshot["id"] == request["profile"] and
             snapshot["timeout_ms"] <= request["timeout_ms"] do
      if is_nil(scope) do
        true
      else
        with {:ok, execution} <- Profiles.embedding_execution(scope, request),
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
      "type" => "extension_embedding_request",
      "version" => 1,
      "binding_sha256" => Ipse.JSON.digest([intent["effect_binding"]]),
      "execution" => execution,
      "admission" => admission
    })
  end

  def valid_source?(source, intent, scope) do
    with true <- keys?(source, @source_keys) and is_map(intent),
         true <- source["type"] == "extension_embedding_request" and source["version"] === 1,
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
               Ipse.Extension.Actions.result_intent(event)
             ) and
             (is_nil(record.completion) or
                (record.completion["outcome"] == "completed" and
                   record.completion["finality"] == "final" and
                   record.completion["usage"] === source["inference"]["usage"] and
                   record.completion["reported_model"] === source["inference"]["reported_model"])))

      {"failed", nil} ->
        outcome["value"] == %{"code" => "embedding_limit"} and is_nil(source)

      {"ok", %{completion: %{"outcome" => "completed"} = completion, admission: admission}} ->
        valid_response?(source, admission, Ipse.Extension.Actions.result_intent(event)) and
          completion["usage"] === source["inference"]["usage"] and
          completion["reported_model"] === source["inference"]["reported_model"] and
          value_from_completion(
            Ipse.Extension.Actions.result_intent(event),
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
      Profiles.embedding_selection_sha256(binding["execution"], binding["destination"])
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
      with {:ok, selection} <- selection_sha256(Ipse.Extension.Actions.result_intent(event)) do
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
      (request["version"] === 1 or Ipse.JSON.sha256?(value["selection_sha256"])) and
      value["request_id"] == operation and id?(value["attempt_id"]) and
      value["profile"] == request["profile"] and is_binary(value["reported_model"]) and
      Ipse.Provider.model_name(value["reported_model"]) == value["reported_model"] and
      Ipse.Usage.valid_usage?(value["usage"], "embedding") and
      EffectResult.descriptor?(value["result"], operation) and value["result"]["version"] === 2 and
      value["result"]["vector_count"] == length(request["inputs"]) and
      Ipse.Extension.validate(value) == :ok
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def execute(context, intent) do
    Ipse.Extension.Inference.execute(context, intent, :embedding, fn config, request, emit ->
      Ipse.Provider.request_embedding(config, request["inputs"], emit)
    end)
  end

  defp failed(code), do: {:failed, %{"code" => code}}
  defp text?(value), do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..4096

  defp profile_id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, value)

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
end

defmodule Ipse.Extension.Inference do
  @moduledoc "Owned inference lifetime shared by explicit text, embedding and decision actions."

  def execute(context, intent, kind, perform) when kind in [:text, :embedding, :decision] do
    case GenServer.call(context.owner, {begin_message(kind), context.job_ref, intent}, :infinity) do
      {:ok, config, admission} ->
        run(context, intent, kind, perform, config, admission, nil)

      {:ok, config, admission, dispatch} ->
        run(context, intent, kind, perform, config, admission, dispatch)

      {:failed, _} = failure ->
        failure

      _ ->
        {:failed, %{"code" => code(kind, :limit)}}
    end
  end

  defp run(context, intent, kind, perform, config, admission, dispatch) do
    coordinator = self()
    upstream = Ipse.Session.Resources.file_effect_owner()
    tag = make_ref()
    monitor = Process.monitor(context.worker)

    task =
      Ipse.Session.Resources.async(fn ->
        :ok = Ipse.Session.Resources.bind_effect_owner(upstream)

        emit = fn
          {:provider_usage, raw} ->
            usage = Ipse.Usage.observation(admission, raw, 1)["usage"]
            send(coordinator, {tag, :usage, usage})

          {event, status} when event in [:inference_service_status, :inference_service_timing] ->
            send(coordinator, {tag, :service_status, {event, status}})

          _ ->
            :ok
        end

        execute = fn selected, guarded_emit, _prepared ->
          result = perform.(selected, intent["request"], guarded_emit)

          case result do
            {:ok, value, raw} ->
              capture = %{value: value, usage: Ipse.Usage.observation(admission, raw, 1)["usage"]}
              if is_nil(dispatch), do: send(coordinator, {tag, :response, capture})
              if kind in [:embedding, :decision], do: guarded_emit.({:provider_usage, raw})

            _ ->
              :ok
          end

          result
        end

        if is_nil(dispatch) do
          Ipse.Usage.Budget.run(config, admission, emit, fn selected, guarded ->
            execute.(selected, guarded, nil)
          end)
        else
          gate = fn facts ->
            nonce = make_ref()
            send(coordinator, {tag, :dispatch_gate, self(), nonce, dispatch, facts})

            receive do
              {^tag, ^nonce, result} -> result
            after
              5_000 -> {:error, :inference_dispatch_refused}
            end
          end

          result =
            Ipse.InferenceDispatch.run(
              dispatch.config,
              config,
              intent["request"]["op"],
              intent["request"]["profile"],
              dispatch,
              emit,
              gate,
              execute
            )

          case result do
            {:ok, value, raw} ->
              send(
                coordinator,
                {tag, :response,
                 %{value: value, usage: Ipse.Usage.observation(admission, raw, 1)["usage"]}}
              )

            _ ->
              :ok
          end

          result
        end
      end)

    deadline =
      System.monotonic_time(:millisecond) + config.timeout_ms +
        if(is_nil(dispatch), do: 0, else: 80_000)

    try do
      {result, capture, reason} = await(task, tag, monitor, context, intent, kind, deadline, nil)

      GenServer.call(
        context.owner,
        {finish_message(kind), context.job_ref, intent, result, capture, reason},
        :infinity
      )
    after
      Process.demonitor(monitor, [:flush])
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp await(task, tag, monitor, context, intent, kind, deadline, capture) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 or not Ipse.Extension.Registry.live?(context.identity) do
      Task.shutdown(task, :brutal_kill)
      capture = drain(tag, context, intent, kind, capture)
      {:cancelled, capture, code(kind, if(remaining <= 0, do: :timeout, else: :cancelled))}
    else
      receive do
        {^tag, :usage, usage} ->
          forward_usage(context, intent, kind, usage)
          await(task, tag, monitor, context, intent, kind, deadline, capture)

        {^tag, :response, response} ->
          await(task, tag, monitor, context, intent, kind, deadline, response)

        {^tag, :service_status, event} ->
          GenServer.call(
            context.owner,
            {:inference_service_status, context.job_ref, event},
            5_000
          )

          await(task, tag, monitor, context, intent, kind, deadline, capture)

        {^tag, :dispatch_gate, worker, nonce, dispatch, facts} when worker == task.pid ->
          result =
            Ipse.Session.InferenceDispatch.gate(context.owner, context.job_ref, dispatch, facts)

          send(worker, {tag, nonce, result})
          await(task, tag, monitor, context, intent, kind, deadline, capture)

        {ref, result} when ref == task.ref ->
          Process.demonitor(ref, [:flush])
          {result, capture, nil}

        {:DOWN, ^monitor, :process, _, _} ->
          Task.shutdown(task, :brutal_kill)
          {:cancelled, drain(tag, context, intent, kind, capture), code(kind, :cancelled)}

        {:DOWN, ref, :process, _, _} when ref == task.ref ->
          {{:error, :provider_down}, capture, nil}
      after
        min(remaining, 100) -> await(task, tag, monitor, context, intent, kind, deadline, capture)
      end
    end
  end

  defp drain(tag, context, intent, kind, capture) do
    receive do
      {^tag, :usage, usage} ->
        forward_usage(context, intent, kind, usage)
        drain(tag, context, intent, kind, capture)

      {^tag, :response, response} ->
        drain(tag, context, intent, kind, response)
    after
      0 -> capture
    end
  end

  defp forward_usage(context, intent, kind, usage) do
    :ok =
      GenServer.call(
        context.owner,
        {usage_message(kind), context.job_ref, intent["operation_id"], usage},
        :infinity
      )
  end

  defp begin_message(:text), do: :extension_model_begin
  defp begin_message(:embedding), do: :extension_embedding_begin
  defp begin_message(:decision), do: :extension_decision_begin
  defp usage_message(:text), do: :extension_model_usage
  defp usage_message(:embedding), do: :extension_embedding_usage
  defp usage_message(:decision), do: :extension_decision_usage
  defp finish_message(:text), do: :extension_model_finish
  defp finish_message(:embedding), do: :extension_embedding_finish
  defp finish_message(:decision), do: :extension_decision_finish
  defp code(:text, :limit), do: "model_limit"
  defp code(:text, :timeout), do: "model_timeout"
  defp code(:text, :cancelled), do: "model_cancelled"
  defp code(:embedding, :limit), do: "embedding_limit"
  defp code(:embedding, :timeout), do: "embedding_timeout"
  defp code(:embedding, :cancelled), do: "embedding_cancelled"
  defp code(:decision, :limit), do: "decision_limit"
  defp code(:decision, :timeout), do: "decision_timeout"
  defp code(:decision, :cancelled), do: "decision_cancelled"
end
