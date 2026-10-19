defmodule Ipse.Extensions.ModelCall do
  @moduledoc "Explicit one-shot text inference with profile-bound canonical accounting."
  alias Ipse.{Usage, Profiles}

  @providers %{
    "chatgpt" => :chatgpt,
    "openai" => :openai,
    "ollama" => :ollama,
    "anthropic" => :anthropic,
    "demo" => :demo
  }
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
      proposed["execution"]["id"] == proposed["request"]["profile"] and
      proposed["execution"]["provider"] in ~w(chatgpt openai ollama anthropic) and
      Ipse.Provider.valid_destination?(proposed["destination"]) and
      id?(proposed["namespace"])
  rescue
    _ -> false
  end

  def delegated_approval?(_, _), do: false

  def validate(request) do
    schema = %{
      "type" => "object",
      "properties" => %{
        "op" => %{"type" => "string", "enum" => ["model.complete"]},
        "version" => %{"type" => "integer", "enum" => [1]},
        "profile" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
        "instruction" => %{"type" => "string", "maxLength" => 2048},
        "input" => %{"type" => "string", "minLength" => 1, "maxLength" => 4096},
        "max_output_bytes" => %{"type" => "integer", "minimum" => 1, "maximum" => 8192},
        "timeout_ms" => %{"type" => "integer", "minimum" => 1000, "maximum" => 120_000}
      },
      "required" => ~w(op version profile instruction input max_output_bytes timeout_ms),
      "additionalProperties" => false
    }

    with :ok <- Ipse.MCP.Schema.validate_arguments(schema, request),
         true <- request["version"] === 1,
         true <- Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, request["profile"]),
         true <- is_integer(request["timeout_ms"]) and is_integer(request["max_output_bytes"]),
         true <- byte_size(Jason.encode!(request)) <= 8192,
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
           "billing_mode" => Ipse.Usage.Normalizer.billing_mode(@providers[profile["provider"]]),
           "endpoint_sha256" =>
             if(profile["base_url"], do: Ipse.Extensions.Manifest.sha256(profile["base_url"])),
           "reasoning_effort" => profile["reasoning_effort"],
           "max_output_tokens" => profile["max_output_tokens"],
           "timeout_ms" =>
             Enum.min([profile["timeout_ms"] || 120_000, config[:timeout_ms] || 120_000, 120_000])
         }}
      end)
    end
  end

  def execution(scope, request) do
    with :ok <- validate(request),
         profile when is_map(profile) <- (scope["model_profiles"] || %{})[request["profile"]],
         true <- valid_profile?(profile),
         true <-
           profile["id"] == request["profile"] and
             profile["provider"] in ~w(chatgpt openai ollama anthropic),
         cap =
           Ipse.Provider.Limits.narrow(scope["max_output_tokens"], profile["max_output_tokens"]),
         cap =
           Ipse.Provider.Limits.narrow(cap, get_in(scope, ["budget", "reserve_output_tokens"])),
         :ok <-
           Ipse.Provider.Limits.validate(%{
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
          max_response_bytes: 65_536,
          timeout_ms: execution["timeout_ms"]
        })

      runtime =
        if profile["base_url"],
          do: Map.put(runtime, :base_url, profile["base_url"]),
          else: runtime

      runtime =
        if runtime.provider == :chatgpt,
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
         true <- intent["request_sha256"] == Ipse.Compaction.digest([intent["request"]]),
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
      (is_nil(value["reported_model"]) or
         Ipse.RuntimeInfo.model_name(value["reported_model"]) == value["reported_model"]) and
      Ipse.Usage.Normalizer.valid?(value["usage"])
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def valid_profile?(profile) do
    keys?(profile, @execution_keys) and
      is_binary(profile["id"]) and
      Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, profile["id"]) and
      profile["provider"] in Map.keys(@providers) and
      is_binary(profile["model"]) and
      Ipse.RuntimeInfo.model_name(profile["model"]) == profile["model"] and
      profile["billing_mode"] ==
        Ipse.Usage.Normalizer.billing_mode(@providers[profile["provider"]]) and
      (is_nil(profile["endpoint_sha256"]) or
         (is_binary(profile["endpoint_sha256"]) and
            Regex.match?(~r/\A[0-9a-f]{64}\z/, profile["endpoint_sha256"]))) and
      Profiles.reasoning(profile["provider"], profile["model"], profile["reasoning_effort"]) ==
        :ok and
      Ipse.Provider.Limits.validate(%{
        provider: @providers[profile["provider"]],
        max_output_tokens: profile["max_output_tokens"]
      }) == :ok and
      is_integer(profile["timeout_ms"]) and profile["timeout_ms"] in 1..120_000
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
            Ipse.RuntimeInfo.model_name(
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
      "assistant_sha256" => Ipse.Compaction.digest([assistant])
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
         text?(assistant["content"], request["max_output_bytes"]) do
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
    Ipse.Extensions.Inference.execute(context, intent, :text, fn selected, request, emit ->
      messages = Ipse.Context.helper_messages(request["instruction"], request["input"])
      Ipse.Provider.Request.complete(selected, messages, [], emit)
    end)
  end

  defp text?(text, limit),
    do: is_binary(text) and String.valid?(text) and byte_size(text) <= limit

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
end
