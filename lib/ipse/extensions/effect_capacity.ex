defmodule Ipse.Extensions.EffectCapacity do
  @moduledoc "Canonical per-record admission for complete embedding and MCP effect receipts."
  alias Ipse.Extensions.{Actions, EffectResult, EmbeddingCall}
  alias Ipse.Usage
  @safe_integer 9_007_199_254_740_991

  def embedding(intent, admission, execution) do
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

  def mcp(intent) do
    {:ok, empty} = EffectResult.source(intent, "mcp.text", %{"text" => ""})
    overhead = byte_size(Jason.encode!(empty))
    target = min(EffectResult.source_record_limit(), overhead + 6 * 65_536) - overhead
    # Mix six-byte JSON escapes and ASCII within the existing raw-text limit.
    controls = max(div(target - 65_536 + 4, 5), 0)
    text = :binary.copy(<<0>>, controls) <> :binary.copy("a", target - controls * 6)
    {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => text})

    descriptor = EffectResult.descriptor(source) |> Map.put("byte_count", 65_536)
    {:ok, result} = Actions.result(intent, %{"status" => "ok", "value" => descriptor})
    capacity([intent, source, result])
  rescue
    _ -> {:error, :effect_record_capacity}
  end

  defp usage_inputs("openai") do
    limit = Usage.Normalizer.limit()
    [%{"prompt_tokens" => limit}, %{"prompt_tokens" => "invalid"}]
  end

  defp usage_inputs("ollama") do
    limit = Usage.Normalizer.limit()

    [
      %{"prompt_eval_count" => limit, "total_duration" => limit},
      %{"prompt_eval_count" => "invalid"}
    ]
  end

  defp capacity(records) do
    {:ok, %{max_record_bytes: records |> Enum.map(&byte_size(Jason.encode!(&1))) |> Enum.max()}}
  end
end
