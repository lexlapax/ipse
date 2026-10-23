defmodule IpseEmbeddingExample.Embed do
  @behaviour Ipse.Extension

  def describe do
    %{
      "sdk" => 1,
      "capabilities" =>
        ~w(invoke.command host.actions host.embedding host.results host.actions.mixed),
      "exports" => %{
        "version" => 1,
        "tools" => [],
        "services" => [],
        "commands" => [
          %{
            "id" => "embed",
            "description" =>
              "Explicit embedding with independently reconstructed coordinate pages",
            "arguments_schema" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" => ~w(profile inputs timeout_ms),
              "properties" => %{
                "profile" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
                "inputs" => %{
                  "type" => "array",
                  "minItems" => 1,
                  "maxItems" => 8,
                  "items" => %{"type" => "string", "minLength" => 1, "maxLength" => 4096}
                },
                "timeout_ms" => %{"type" => "integer", "minimum" => 1000, "maximum" => 120_000}
              }
            },
            "result_schema" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" => ~w(status vectors request_id reported_model usage),
              "properties" => %{
                "status" => %{"type" => "string"},
                "vectors" => %{"type" => "array", "items" => %{"type" => "object"}},
                "request_id" => %{"type" => ["string", "null"]},
                "reported_model" => %{"type" => ["string", "null"]},
                "usage" => %{"type" => "object"}
              }
            }
          }
        ]
      }
    }
  end

  def init(options), do: {:ok, options}

  def handle("invoke.command", payload, _options) do
    state = %{
      phase: :embedding,
      descriptor: nil,
      inference: nil,
      index: 0,
      offset: 0,
      bytes: <<>>,
      vectors: [],
      pages: 0
    }

    call(Map.merge(payload["arguments"], %{"op" => "embedding.create", "version" => 1}), state)
  end

  def handle("host.actions", payload, %{phase: :embedding} = state) do
    outcome = payload["outcome"]

    if outcome["status"] == "ok" do
      inference = outcome["value"]
      descriptor = inference["result"]
      true = descriptor["version"] === 2 and descriptor["kind"] == "embedding.f32le"
      true = descriptor["encoding"] == "float32le.base64"
      read(%{state | phase: :reading, descriptor: descriptor, inference: inference})
    else
      finish(state, outcome["status"])
    end
  end

  def handle("host.actions", payload, %{phase: :reading} = state) do
    outcome = payload["outcome"]

    if outcome["status"] == "ok" do
      page = outcome["value"]
      true = page["version"] === 2 and page["kind"] == "embedding.f32le"
      true = page["encoding"] == "float32le.base64"
      true = page["vector_index"] === state.index and page["offset"] === state.offset
      true = page["dimensions"] === state.descriptor["dimensions"]
      true = page["operation_id"] == state.descriptor["operation_id"]
      true = page["source_sha256"] == state.descriptor["source_sha256"]
      chunk = Base.decode64!(page["values"])
      true = Base.encode64(chunk) == page["values"]
      true = rem(byte_size(chunk), 4) == 0 and byte_size(chunk) <= 768 * 4
      bytes = state.bytes <> chunk
      state = %{state | bytes: bytes, pages: state.pages + 1}

      if page["complete"] do
        true = page["next"] == nil and byte_size(bytes) == page["dimensions"] * 4
        sha256 = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
        true = sha256 == page["vector_sha256"]

        vector = %{
          "index" => state.index,
          "bytes" => byte_size(bytes),
          "sha256" => sha256,
          "input_sha256" => page["input_sha256"],
          "pages" => state.pages
        }

        state = %{
          state
          | vectors: state.vectors ++ [vector],
            index: state.index + 1,
            offset: 0,
            bytes: <<>>,
            pages: 0
        }

        if state.index == state.descriptor["vector_count"],
          do: finish(state, "ok"),
          else: read(state)
      else
        true = page["next"] === state.offset + div(byte_size(chunk), 4)
        read(%{state | offset: page["next"]})
      end
    else
      finish(state, outcome["status"])
    end
  end

  defp read(state) do
    call(
      %{
        "op" => "effect.result.read",
        "version" => 2,
        "operation_id" => state.descriptor["operation_id"],
        "source_sha256" => state.descriptor["source_sha256"],
        "vector_index" => state.index,
        "offset" => state.offset,
        "limit" => 768
      },
      state
    )
  end

  defp call(request, state),
    do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}

  defp finish(state, status) do
    inference = state.inference || %{}

    value = %{
      "status" => status,
      "vectors" => state.vectors,
      "request_id" => inference["request_id"],
      "reported_model" => inference["reported_model"],
      "usage" => inference["usage"] || %{}
    }

    {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
  end
end
