defmodule Ipse.Extensions.EffectResult do
  @moduledoc "Private complete effect sources and bounded, source-bound UTF-8 windows."

  @source_keys ~w(type version parent_invocation_id operation_id identity_sha256 request_sha256 binding_sha256 kind data data_sha256 source_sha256)
  @descriptor_keys ~w(version operation_id kind source_sha256 byte_count)
  @window_keys ~w(version operation_id kind source_sha256 offset next complete text)
  @error {:error, :invalid_extension_effect_result}
  @refused {:failed, %{"code" => "result_refused"}}

  def operation?(request), do: is_map(request) and request["op"] == "effect.result.read"

  def validate(request) do
    if keys?(request, ~w(op version operation_id source_sha256 offset limit)) and
         operation?(request) and request["version"] === 1 and id?(request["operation_id"]) and
         hash?(request["source_sha256"]) and uint?(request["offset"], 65_536) and
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
        "binding_sha256" => Ipse.Compaction.digest([intent["effect_binding"]]),
        "kind" => "mcp.text",
        "data" => data,
        "data_sha256" => Ipse.Compaction.digest([data])
      })

    event = Map.put(event, "source_sha256", Ipse.Compaction.digest([event]))
    if valid_source?(event, intent), do: {:ok, event}, else: @error
  rescue
    _ -> @error
  end

  def source(_, _, _), do: @error

  def valid_source?(event, intent) do
    source?(event) and is_map(intent) and intent["type"] == "extension_action_intent" and
      intent["version"] === 2 and intent["approval"] in ~w(approved session_allow) and
      Ipse.Extensions.MCPCall.operation?(intent["request"]) and
      Ipse.Extensions.MCPCall.validate(intent["request"]) == :ok and
      is_nil(intent["namespace"]) and
      intent["request_sha256"] == Ipse.Compaction.digest([intent["request"]]) and
      event["binding_sha256"] == Ipse.Compaction.digest([intent["effect_binding"]]) and
      valid_intent_binding?(intent) and
      Map.take(event, ~w(parent_invocation_id operation_id identity_sha256 request_sha256)) ==
        Map.take(intent, ~w(parent_invocation_id operation_id identity_sha256 request_sha256))
  rescue
    _ -> false
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

  def descriptor?(value, operation_id) do
    keys?(value, @descriptor_keys) and value["version"] === 1 and
      id?(operation_id) and value["operation_id"] == operation_id and
      value["kind"] == "mcp.text" and hash?(value["source_sha256"]) and
      uint?(value["byte_count"], 65_536)
  rescue
    _ -> false
  end

  def binding(request) do
    %{
      "kind" => "result",
      "version" => 1,
      "operation_id" => request["operation_id"],
      "source_sha256" => request["source_sha256"]
    }
  end

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

  defp source?(event) do
    keys?(event, @source_keys) and event["type"] == "extension_effect_result" and
      event["version"] === 1 and id?(event["parent_invocation_id"]) and
      id?(event["operation_id"]) and
      Enum.all?(
        ~w(identity_sha256 request_sha256 binding_sha256 data_sha256 source_sha256),
        &hash?(event[&1])
      ) and event["kind"] == "mcp.text" and keys?(event["data"], ["text"]) and
      text?(event["data"]["text"], 65_536) and
      event["data_sha256"] == Ipse.Compaction.digest([event["data"]]) and
      event["source_sha256"] ==
        Ipse.Compaction.digest([Map.delete(event, "source_sha256")]) and
      byte_size(Jason.encode!(event)) <= 262_144
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

    Ipse.Extensions.MCPCall.valid_binding?(binding, intent["request"], identity)
  end

  defp prefix(_, 0), do: ""

  defp prefix(text, bytes) do
    value = binary_part(text, 0, bytes)
    if String.valid?(value), do: value, else: prefix(text, bytes - 1)
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp uint?(value, max), do: is_integer(value) and value >= 0 and value <= max

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) <= max
end
