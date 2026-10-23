defmodule Ipse.Extension.EffectResult do
  @moduledoc "Private complete effect sources and bounded, source-bound UTF-8 windows."

  @source_keys ~w(type version parent_invocation_id operation_id identity_sha256 request_sha256 binding_sha256 kind data data_sha256 source_sha256)
  @descriptor_keys ~w(version operation_id kind source_sha256 byte_count)
  @window_keys ~w(version operation_id kind source_sha256 offset next complete text)
  @error {:error, :invalid_extension_effect_result}
  @refused {:failed, %{"code" => "result_refused"}}
  @source_record_limit 262_144

  def source_record_limit, do: @source_record_limit

  def operation?(request), do: is_map(request) and request["op"] == "effect.result.read"

  def validate(%{"version" => 2} = request) do
    if keys?(request, ~w(op version operation_id source_sha256 vector_index offset limit)) and
         operation?(request) and request["version"] === 2 and id?(request["operation_id"]) and
         Ipse.JSON.sha256?(request["source_sha256"]) and uint?(request["vector_index"], 7) and
         uint?(request["offset"], 4096) and is_integer(request["limit"]) and
         request["limit"] in 1..768 and Ipse.Extension.validate(request) == :ok,
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def validate(request) do
    if keys?(request, ~w(op version operation_id source_sha256 offset limit)) and
         operation?(request) and request["version"] === 1 and id?(request["operation_id"]) and
         Ipse.JSON.sha256?(request["source_sha256"]) and uint?(request["offset"], 65_536) and
         is_integer(request["limit"]) and request["limit"] in 1..4096 and
         Ipse.Extension.validate(request) == :ok,
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def source(intent, "mcp.text", data) do
    event =
      intent
      |> Map.take(~w(parent_invocation_id operation_id identity_sha256 request_sha256))
      |> Map.merge(%{
        "type" => "extension_effect_result",
        "version" => 1,
        "binding_sha256" => Ipse.JSON.digest([intent["effect_binding"]]),
        "kind" => "mcp.text",
        "data" => data,
        "data_sha256" => Ipse.JSON.digest([data])
      })

    event = Map.put(event, "source_sha256", Ipse.JSON.digest([event]))
    if valid_source?(event, intent), do: {:ok, event}, else: @error
  rescue
    _ -> @error
  end

  def source(_, _, _), do: @error

  def embedding_source(intent, data, inference) do
    event =
      intent
      |> Map.take(~w(parent_invocation_id operation_id identity_sha256 request_sha256))
      |> Map.merge(%{
        "type" => "extension_effect_result",
        "version" => 2,
        "binding_sha256" => Ipse.JSON.digest([intent["effect_binding"]]),
        "kind" => "embedding.f32le",
        "data" => data,
        "inference" => inference,
        "data_sha256" => Ipse.JSON.digest([data])
      })

    event = Map.put(event, "source_sha256", Ipse.JSON.digest([event]))
    if valid_source?(event, intent), do: {:ok, event}, else: @error
  rescue
    _ -> @error
  end

  def valid_source?(%{"version" => 2} = event, intent) do
    source?(event) and is_map(intent) and intent["type"] == "extension_action_intent" and
      intent["version"] === 2 and intent["approval"] in ~w(approved session_allow) and
      Ipse.Extension.EmbeddingCall.valid_binding?(intent["effect_binding"], intent["request"]) and
      id?(intent["namespace"]) and
      intent["request_sha256"] == Ipse.JSON.digest([intent["request"]]) and
      event["binding_sha256"] == Ipse.JSON.digest([intent["effect_binding"]]) and
      Map.take(event, ~w(parent_invocation_id operation_id identity_sha256 request_sha256)) ==
        Map.take(intent, ~w(parent_invocation_id operation_id identity_sha256 request_sha256)) and
      event["inference"]["request_id"] == event["operation_id"] and
      event["inference"]["profile"] == intent["request"]["profile"] and
      Ipse.Provider.Embedding.valid_data?(
        event["data"],
        intent["request"]["inputs"],
        intent["effect_binding"]["execution"]["dimensions"]
      )
  rescue
    _ -> false
  end

  def valid_source?(event, intent) do
    source?(event) and is_map(intent) and intent["type"] == "extension_action_intent" and
      intent["version"] === 2 and intent["approval"] in ~w(approved session_allow) and
      Ipse.Extension.MCPCall.operation?(intent["request"]) and
      Ipse.Extension.MCPCall.validate(intent["request"]) == :ok and
      is_nil(intent["namespace"]) and
      intent["request_sha256"] == Ipse.JSON.digest([intent["request"]]) and
      event["binding_sha256"] == Ipse.JSON.digest([intent["effect_binding"]]) and
      valid_intent_binding?(intent) and
      Map.take(event, ~w(parent_invocation_id operation_id identity_sha256 request_sha256)) ==
        Map.take(intent, ~w(parent_invocation_id operation_id identity_sha256 request_sha256))
  rescue
    _ -> false
  end

  def descriptor(%{"version" => 2} = source) do
    %{
      "version" => 2,
      "operation_id" => source["operation_id"],
      "kind" => "embedding.f32le",
      "source_sha256" => source["source_sha256"],
      "encoding" => "float32le.base64",
      "vector_count" => length(source["data"]["vectors"]),
      "dimensions" => source["data"]["dimensions"]
    }
  end

  def descriptor(source) do
    %{
      "version" => 1,
      "operation_id" => source["operation_id"],
      "kind" => source["kind"],
      "source_sha256" => source["source_sha256"],
      "byte_count" => byte_size(source["data"]["text"])
    }
  end

  def descriptor?(%{"version" => 2} = value, operation_id) do
    keys?(value, ~w(version operation_id kind source_sha256 encoding vector_count dimensions)) and
      value["version"] === 2 and id?(operation_id) and value["operation_id"] == operation_id and
      value["kind"] == "embedding.f32le" and Ipse.JSON.sha256?(value["source_sha256"]) and
      value["encoding"] == "float32le.base64" and is_integer(value["vector_count"]) and
      value["vector_count"] in 1..8 and is_integer(value["dimensions"]) and
      value["dimensions"] in 1..4096
  end

  def descriptor?(value, operation_id) do
    keys?(value, @descriptor_keys) and value["version"] === 1 and
      id?(operation_id) and value["operation_id"] == operation_id and
      value["kind"] == "mcp.text" and Ipse.JSON.sha256?(value["source_sha256"]) and
      uint?(value["byte_count"], 65_536)
  rescue
    _ -> false
  end

  def binding(request) do
    %{
      "kind" => "result",
      "version" => request["version"],
      "operation_id" => request["operation_id"],
      "source_sha256" => request["source_sha256"]
    }
  end

  def read(%{"version" => 2} = source, %{"version" => 2} = request) do
    with :ok <- validate(request),
         true <- source?(source),
         true <-
           source["operation_id"] == request["operation_id"] and
             source["source_sha256"] == request["source_sha256"],
         embedding_vector when is_map(embedding_vector) <-
           Enum.at(source["data"]["vectors"], request["vector_index"]),
         dimensions = source["data"]["dimensions"],
         offset = request["offset"],
         true <- offset <= dimensions,
         {:ok, bytes} <- Base.decode64(embedding_vector["values"]),
         count = min(request["limit"], dimensions - offset),
         next = offset + count do
      {:ok,
       %{
         "version" => 2,
         "operation_id" => source["operation_id"],
         "kind" => "embedding.f32le",
         "source_sha256" => source["source_sha256"],
         "vector_index" => embedding_vector["index"],
         "input_sha256" => embedding_vector["input_sha256"],
         "vector_sha256" => embedding_vector["vector_sha256"],
         "dimensions" => dimensions,
         "encoding" => "float32le.base64",
         "offset" => offset,
         "next" => if(next == dimensions, do: nil, else: next),
         "complete" => next == dimensions,
         "values" => Base.encode64(binary_part(bytes, offset * 4, count * 4))
       }}
    else
      _ -> @refused
    end
  rescue
    _ -> @refused
  end

  def read(%{"version" => 2}, _), do: @refused
  def read(_, %{"version" => 2}), do: @refused

  def read(source, request) do
    with :ok <- validate(request),
         true <- source?(source),
         true <- source["operation_id"] == request["operation_id"],
         true <- source["source_sha256"] == request["source_sha256"],
         text = source["data"]["text"],
         offset = request["offset"],
         true <- offset <= byte_size(text),
         true <- String.valid?(binary_part(text, 0, offset)),
         remaining = binary_part(text, offset, byte_size(text) - offset),
         window = prefix(remaining, min(request["limit"], byte_size(remaining))),
         true <- window != "" or remaining == "",
         next = offset + byte_size(window),
         complete = next == byte_size(text) do
      {:ok,
       %{
         "version" => 1,
         "operation_id" => source["operation_id"],
         "kind" => source["kind"],
         "source_sha256" => source["source_sha256"],
         "offset" => offset,
         "next" => if(complete, do: nil, else: next),
         "complete" => complete,
         "text" => window
       }}
    else
      _ -> @refused
    end
  rescue
    _ -> @refused
  end

  def execute(context, intent), do: read(context[:effect_source], intent["request"])

  def valid_outcome?(_request, status, value, _) when status in ~w(denied unknown),
    do: value == %{}

  def valid_outcome?(_request, "failed", value, _), do: value === elem(@refused, 1)

  def valid_outcome?(%{"version" => 2} = request, "ok", value, _) do
    with :ok <- validate(request),
         true <-
           keys?(
             value,
             ~w(version operation_id kind source_sha256 vector_index input_sha256 vector_sha256 dimensions encoding offset next complete values)
           ),
         true <-
           value["version"] === 2 and value["kind"] == "embedding.f32le" and
             value["encoding"] == "float32le.base64",
         true <-
           Enum.all?(
             ~w(operation_id source_sha256 vector_index offset),
             &(value[&1] === request[&1])
           ),
         true <-
           Ipse.JSON.sha256?(value["input_sha256"]) and Ipse.JSON.sha256?(value["vector_sha256"]),
         true <- is_integer(value["dimensions"]) and value["dimensions"] in 1..4096,
         true <- is_binary(value["values"]) and byte_size(value["values"]) <= 4096,
         {:ok, bytes} <- Base.decode64(value["values"]),
         true <- Base.encode64(bytes) == value["values"] and rem(byte_size(bytes), 4) == 0,
         count = div(byte_size(bytes), 4),
         next = value["offset"] + count,
         true <- count <= request["limit"] and next <= value["dimensions"],
         true <- value["complete"] === (next == value["dimensions"]),
         true <- value["next"] === if(value["complete"], do: nil, else: next),
         true <- count > 0 or value["complete"] do
      Ipse.Extension.validate(value) == :ok
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_outcome?(request, "ok", value, _) do
    validate(request) == :ok and keys?(value, @window_keys) and value["version"] === 1 and
      value["operation_id"] == request["operation_id"] and value["kind"] == "mcp.text" and
      value["source_sha256"] == request["source_sha256"] and
      value["offset"] === request["offset"] and text?(value["text"], request["limit"]) and
      is_boolean(value["complete"]) and
      if(value["complete"],
        do: is_nil(value["next"]),
        else:
          byte_size(value["text"]) > 0 and uint?(value["next"], 65_536) and
            value["next"] === value["offset"] + byte_size(value["text"])
      ) and value["offset"] + byte_size(value["text"]) <= 65_536 and
      Ipse.Extension.validate(value) == :ok
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def bound_outcome?(source, request, %{"status" => status, "value" => value} = outcome) do
    keys?(outcome, ~w(status value)) and
      case read(source, request) do
        {:ok, expected} -> status == "ok" and value === expected
        {:failed, expected} -> status == "failed" and value === expected
      end
  rescue
    _ -> false
  end

  def bound_outcome?(_, _, _), do: false

  def valid_private_source?(source), do: source?(source)

  defp source?(%{"version" => 2} = event) do
    inference = event["inference"]

    keys?(event, @source_keys ++ ["inference"]) and event["type"] == "extension_effect_result" and
      event["version"] === 2 and event["kind"] == "embedding.f32le" and
      id?(event["parent_invocation_id"]) and id?(event["operation_id"]) and
      Enum.all?(
        ~w(identity_sha256 request_sha256 binding_sha256 data_sha256 source_sha256),
        &Ipse.JSON.sha256?(event[&1])
      ) and
      keys?(
        inference,
        ~w(request_id attempt_id profile reported_model usage provider_response_sha256)
      ) and
      inference["request_id"] == event["operation_id"] and id?(inference["attempt_id"]) and
      is_binary(inference["profile"]) and is_binary(inference["reported_model"]) and
      Ipse.Provider.model_name(inference["reported_model"]) == inference["reported_model"] and
      Ipse.JSON.sha256?(inference["provider_response_sha256"]) and
      Ipse.Usage.valid_usage?(inference["usage"], "embedding") and
      Ipse.Provider.Embedding.valid_data?(event["data"]) and
      event["data_sha256"] == Ipse.JSON.digest([event["data"]]) and
      event["source_sha256"] == Ipse.JSON.digest([Map.delete(event, "source_sha256")]) and
      byte_size(Jason.encode!(event)) <= @source_record_limit
  rescue
    _ -> false
  end

  defp source?(event) do
    keys?(event, @source_keys) and event["type"] == "extension_effect_result" and
      event["version"] === 1 and id?(event["parent_invocation_id"]) and
      id?(event["operation_id"]) and
      Enum.all?(
        ~w(identity_sha256 request_sha256 binding_sha256 data_sha256 source_sha256),
        &Ipse.JSON.sha256?(event[&1])
      ) and event["kind"] == "mcp.text" and keys?(event["data"], ["text"]) and
      text?(event["data"]["text"], 65_536) and
      event["data_sha256"] == Ipse.JSON.digest([event["data"]]) and
      event["source_sha256"] ==
        Ipse.JSON.digest([Map.delete(event, "source_sha256")]) and
      byte_size(Jason.encode!(event)) <= @source_record_limit
  rescue
    _ -> false
  end

  defp valid_intent_binding?(intent) do
    binding = intent["effect_binding"]

    identity = %{
      "scope" => "operator",
      "capabilities" => ["host.actions", "host.mcp"],
      "mcp_bindings" => [%{"alias" => binding["alias"], "tool" => binding["manifest"]["tool_id"]}]
    }

    Ipse.Extension.MCPCall.valid_binding?(binding, intent["request"], identity)
  end

  defp prefix(_, 0), do: ""

  defp prefix(text, bytes) do
    value = binary_part(text, 0, bytes)
    if String.valid?(value), do: value, else: prefix(text, bytes - 1)
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp uint?(value, max), do: is_integer(value) and value >= 0 and value <= max

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) <= max

  alias Ipse.Extension.{Actions, EmbeddingCall}
  alias Ipse.Usage
  @safe_integer 9_007_199_254_740_991

  def embedding_capacity(intent, admission, execution) do
    admission = Map.put(admission, "admitted_at_ms", @safe_integer)
    dimensions = execution["dimensions"]
    bytes = <<1.0::float-little-size(32)>> <> :binary.copy(<<0>>, (dimensions - 1) * 4)

    payload = %{
      "kind" => "embedding",
      "version" => 1,
      "encoding" => "float32le.base64",
      "reported_model" => String.duplicate("a", 200),
      "dimensions" => dimensions,
      "vectors" =>
        Enum.with_index(intent["request"]["inputs"], fn input, index ->
          %{
            "index" => index,
            "input_sha256" => Ipse.JSON.digest([input]),
            "vector_sha256" => Ipse.JSON.sha256(bytes),
            "values" => Base.encode64(bytes)
          }
        end),
      "provider_response_sha256" => String.duplicate("0", 64)
    }

    records =
      Enum.flat_map(usage_inputs(admission["provider"]), fn raw ->
        completion = Usage.completion(admission, {:ok, payload, raw}, @safe_integer, nil)
        {:ok, source} = EmbeddingCall.response(intent, admission, completion, payload)

        {:ok, value} = EmbeddingCall.value_from_completion(intent, admission, completion, source)
        {:ok, result} = Actions.result(intent, %{"status" => "ok", "value" => value})

        [Usage.observation(admission, raw, 64), source, completion, result]
      end)

    capacity([intent, admission, EmbeddingCall.source(intent, admission, execution) | records])
  rescue
    _ -> {:error, :effect_record_capacity}
  end

  def mcp_capacity(intent) do
    {:ok, empty} = source(intent, "mcp.text", %{"text" => ""})
    overhead = byte_size(Jason.encode!(empty))
    target = min(source_record_limit(), overhead + 6 * 65_536) - overhead
    # Mix six-byte JSON escapes and ASCII within the existing raw-text limit.
    controls = max(div(target - 65_536 + 4, 5), 0)
    text = :binary.copy(<<0>>, controls) <> :binary.copy("a", target - controls * 6)
    {:ok, source} = source(intent, "mcp.text", %{"text" => text})

    descriptor = descriptor(source) |> Map.put("byte_count", 65_536)
    {:ok, result} = Actions.result(intent, %{"status" => "ok", "value" => descriptor})
    capacity([intent, source, result])
  rescue
    _ -> {:error, :effect_record_capacity}
  end

  defp usage_inputs("openai") do
    limit = Usage.counter_limit()
    [%{"prompt_tokens" => limit}, %{"prompt_tokens" => "invalid"}]
  end

  defp usage_inputs("ollama") do
    limit = Usage.counter_limit()

    [
      %{"prompt_eval_count" => limit, "total_duration" => limit},
      %{"prompt_eval_count" => "invalid"}
    ]
  end

  defp capacity(records) do
    {:ok, %{max_record_bytes: records |> Enum.map(&byte_size(Jason.encode!(&1))) |> Enum.max()}}
  end
end
