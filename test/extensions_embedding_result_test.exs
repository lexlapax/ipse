defmodule Ipse.Extensions.EmbeddingResultTest do
  use ExUnit.Case, async: true
  alias Ipse.Extensions.{EmbeddingCall, EffectResult}
  alias Ipse.{EmbeddingProfiles, Usage}

  test "embedding operation authority stays separate from legacy text and SDK object bounds" do
    request = request()
    assert EmbeddingCall.validate(request) == :ok
    assert Ipse.Extensions.Operation.capability(request) == "host.embedding"
    assert Ipse.Extensions.Operation.mutating?(request)
    refute Ipse.Extensions.ModelCall.operation?(request)
    assert {:error, _} = Ipse.Extensions.ModelCall.validate(request)

    for changed <- [
          Map.put(request, "version", 1.0),
          Map.put(request, "provider", "openai"),
          Map.put(request, "dimensions", 128),
          Map.put(request, "inputs", []),
          Map.put(request, "inputs", List.duplicate("x", 9)),
          Map.put(request, "inputs", [String.duplicate("a", 4097)]),
          Map.put(request, "inputs", List.duplicate(String.duplicate("a", 4096), 4)),
          Map.put(request, "timeout_ms", 999)
        ],
        do: assert({:error, _} = EmbeddingCall.validate(changed))

    assert {:error, _} = Ipse.Extension.validate(%{"vector" => List.duplicate(1.0, 768)})
  end

  test "complete private embedding source produces an SDK-sized descriptor with exact accounting identity" do
    fixture = fixture(4096, 2)
    source = fixture.source
    assert EffectResult.valid_source?(source, fixture.intent)
    assert EmbeddingCall.valid_response?(source, fixture.admission, fixture.intent)
    assert source["version"] === 2
    assert source["kind"] == "embedding.f32le"
    assert source["inference"]["usage"] == fixture.completion["usage"]
    assert source["inference"]["attempt_id"] == fixture.admission["attempt_id"]
    descriptor = EffectResult.descriptor(source)
    assert EffectResult.descriptor?(descriptor, fixture.intent["operation_id"])
    assert descriptor["dimensions"] == 4096
    assert descriptor["vector_count"] == 2
    assert descriptor["encoding"] == "float32le.base64"
    assert Ipse.Extension.validate(descriptor) == :ok
    refute Map.has_key?(descriptor, "values")
    assert {:error, _} = Ipse.Extension.validate(source)

    assert {:ok, value} =
             EmbeddingCall.value_from_completion(
               fixture.intent,
               fixture.admission,
               fixture.completion,
               source
             )

    assert EmbeddingCall.valid_outcome?(
             fixture.request,
             "ok",
             value,
             fixture.intent["operation_id"]
           )

    assert value["result"] == descriptor
    assert Ipse.Extension.validate(value) == :ok
    refute Map.has_key?(value, "text")
    refute Map.has_key?(value, "assistant")
  end

  test "v2 result authenticates selection from the original approved intent without changing private pages" do
    f = fixture(4096, 2, 2)
    assert EmbeddingCall.validate(f.request) == :ok
    assert {:error, _} = EmbeddingCall.validate(Map.put(f.request, "version", 2.0))

    assert {:ok, value} =
             EmbeddingCall.value_from_completion(f.intent, f.admission, f.completion, f.source)

    assert value["version"] === 2
    assert {:ok, value["selection_sha256"]} == EmbeddingCall.selection_sha256(f.intent)
    assert EmbeddingCall.valid_outcome?(f.request, "ok", value, f.intent["operation_id"])
    assert f.source["version"] === 2
    assert value["result"]["version"] === 2
    refute Map.has_key?(f.source, "selection_sha256")
    assert Ipse.Extension.validate(value) == :ok
    assert Enum.all?(pages(f.source, 0, 0, []), &(&1["version"] === 2))

    for changed <- [
          Map.delete(value, "selection_sha256"),
          Map.put(value, "selection_sha256", "bad"),
          Map.put(value, "version", 1)
        ] do
      refute EmbeddingCall.valid_outcome?(f.request, "ok", changed, f.intent["operation_id"])
    end

    changed_intent = put_in(f.intent, ["effect_binding", "execution", "model"], "substituted")

    assert {:failed, _} =
             EmbeddingCall.value_from_completion(
               changed_intent,
               f.admission,
               f.completion,
               f.source
             )

    legacy = fixture(2, 1)

    assert {:ok, old_value} =
             EmbeddingCall.value_from_completion(
               legacy.intent,
               legacy.admission,
               legacy.completion,
               legacy.source
             )

    assert old_value["version"] === 1
    refute Map.has_key?(old_value, "selection_sha256")
  end

  for dimensions <- [768, 4096] do
    test "#{dimensions}-coordinate vectors reconstruct byte-for-byte through bounded typed pages" do
      fixture = fixture(unquote(dimensions), 2)
      source = fixture.source

      for vector <- source["data"]["vectors"] do
        values = pages(source, vector["index"], 0, [])
        bytes = Enum.map_join(values, &Base.decode64!(&1["values"]))
        assert byte_size(bytes) == unquote(dimensions) * 4
        assert bytes == Base.decode64!(vector["values"])
        assert sha256(bytes) == vector["vector_sha256"]

        assert Enum.all?(
                 values,
                 &(Ipse.Extension.validate(&1) == :ok and byte_size(&1["values"]) <= 4096)
               )

        assert length(values) == div(unquote(dimensions) + 767, 768)
        assert List.last(values)["next"] == nil
        assert List.last(values)["complete"] == true
      end

      assert {:ok, %{"values" => "", "complete" => true, "next" => nil}} =
               EffectResult.read(source, read_request(source, 0, unquote(dimensions), 768))
    end
  end

  test "readers cannot cross legacy text/vector contracts or substitute indices, sources and offsets" do
    fixture = fixture(768, 1)
    source = fixture.source
    request = read_request(source, 0, 0, 768)
    refused = {:failed, %{"code" => "result_refused"}}

    for changed <- [
          Map.put(request, "operation_id", id("a")),
          Map.put(request, "source_sha256", digest("other source")),
          Map.put(request, "vector_index", 1),
          Map.put(request, "offset", 769),
          Map.put(request, "offset", 0.0),
          Map.put(request, "limit", 769),
          Map.put(request, "extra", true)
        ],
        do: assert(EffectResult.read(source, changed) == refused)

    legacy = request |> Map.delete("vector_index") |> Map.put("version", 1)
    assert EffectResult.read(source, legacy) == refused

    fake_text =
      source
      |> Map.put("version", 1)
      |> Map.put("kind", "mcp.text")
      |> Map.put("data", %{"text" => "not a vector"})
      |> rehash()

    assert EffectResult.read(fake_text, request) == refused
    refute EffectResult.valid_source?(fake_text, fixture.intent)
  end

  test "syntactic page validity never substitutes for exact saved-source recomputation" do
    fixture = fixture(4096, 1)
    source = fixture.source
    request = read_request(source, 0, 0, 768)
    {:ok, page} = EffectResult.read(source, request)
    assert EffectResult.valid_outcome?(request, "ok", page, id("a"))
    assert EffectResult.bound_outcome?(source, request, %{"status" => "ok", "value" => page})

    for changed <- [
          Map.put(
            page,
            "values",
            Base.encode64(:binary.copy(<<1.0::float-little-size(32)>>, 768))
          ),
          Map.put(page, "input_sha256", digest("other input")),
          Map.put(page, "vector_sha256", digest("other vector")),
          %{page | "dimensions" => 768, "complete" => true, "next" => nil}
        ] do
      assert EffectResult.valid_outcome?(request, "ok", changed, id("a"))
      refute EffectResult.bound_outcome?(source, request, %{"status" => "ok", "value" => changed})
    end

    for changed <- [
          Map.put(page, "values", "not base64"),
          Map.put(page, "next", 769),
          Map.put(page, "offset", 1),
          Map.put(page, "version", 1),
          Map.put(page, "text", "wrong protocol")
        ],
        do: refute(EffectResult.valid_outcome?(request, "ok", changed, id("a")))
  end

  test "request, identity, binding and intrinsic data hashes all participate in source validation" do
    fixture = fixture(768, 1)
    source = fixture.source

    for changed <- [
          Map.put(source, "identity_sha256", digest("different identity")),
          Map.put(source, "request_sha256", digest("different request")),
          Map.put(source, "parent_invocation_id", id("b")),
          Map.put(source, "binding_sha256", digest("different binding")),
          put_in(
            source,
            ["data", "vectors", Access.at(0), "input_sha256"],
            digest("different input")
          ),
          put_in(
            source,
            ["data", "vectors", Access.at(0), "values"],
            Base.encode64(:binary.copy(<<0::32>>, 768))
          ),
          Map.put(source, "extra", "unrecognized")
        ] do
      refute EffectResult.valid_source?(rehash(changed), fixture.intent)
    end

    refute EffectResult.valid_source?(source, Map.put(fixture.intent, "approval", "denied"))
    refute EffectResult.valid_source?(source, Map.put(fixture.intent, "namespace", nil))

    assert {:error, _} =
             EffectResult.embedding_source(
               Map.put(fixture.intent, "version", 1),
               source["data"],
               source["inference"]
             )
  end

  test "native attempt and canonical completion remain necessary beyond a self-consistent source hash" do
    fixture = fixture(768, 1)
    source = fixture.source
    changed = source |> put_in(["inference", "attempt_id"], id("d")) |> rehash()
    assert EffectResult.valid_source?(changed, fixture.intent)
    refute EmbeddingCall.valid_response?(changed, fixture.admission, fixture.intent)

    text_usage =
      Ipse.Usage.Normalizer.normalize(:ollama, %{"input_tokens" => 7, "output_tokens" => 2})

    changed = source |> put_in(["inference", "usage"], text_usage) |> rehash()
    refute EffectResult.valid_private_source?(changed)

    assert {:ok, value} =
             EmbeddingCall.value_from_completion(
               fixture.intent,
               fixture.admission,
               fixture.completion,
               source
             )

    event =
      fixture.intent
      |> Map.put("type", "extension_action_result")
      |> Map.put("outcome", %{"status" => "ok", "value" => value})

    record = %{admission: fixture.admission, observation: nil, completion: fixture.completion}
    assert EmbeddingCall.valid_result_source?(event, record, source)

    for completion <- [
          nil,
          Map.put(fixture.completion, "outcome", "failed"),
          Map.put(fixture.completion, "reported_model", "other-model"),
          Map.put(fixture.completion, "usage", text_usage)
        ] do
      refute EmbeddingCall.valid_result_source?(event, %{record | completion: completion}, source)
    end

    failure = %{
      event
      | "outcome" => %{"status" => "failed", "value" => %{"code" => "embedding_request_failed"}}
    }

    failed_completion = %{
      fixture.completion
      | "outcome" => "failed",
        "finality" => "partial",
        "reported_model" => nil
    }

    assert EmbeddingCall.valid_result_source?(
             failure,
             %{record | completion: failed_completion},
             nil
           )

    refute EmbeddingCall.valid_result_source?(
             failure,
             %{record | completion: failed_completion},
             source
           )

    assert {:error, _} =
             EmbeddingCall.response(
               fixture.intent,
               fixture.admission,
               failed_completion,
               fixture.payload
             )
  end

  test "metadata selected execution and safe destination constrain otherwise syntactic bindings" do
    fixture = fixture(768, 1)
    binding = fixture.intent["effect_binding"]
    assert EmbeddingCall.valid_binding?(binding, fixture.request, fixture.scope)

    for changed <- [
          put_in(binding, ["destination", "target_sha256"], digest("other route")),
          put_in(binding, ["execution", "model"], "other-model"),
          put_in(binding, ["execution", "timeout_ms"], 1000),
          put_in(binding, ["execution", "dimensions"], 128)
        ] do
      refute EmbeddingCall.valid_binding?(changed, fixture.request, fixture.scope)
    end

    for value <- [nil, [], %{}, 1] do
      refute EffectResult.valid_private_source?(value)
      refute EmbeddingCall.valid_binding?(value, fixture.request, fixture.scope)

      refute EmbeddingCall.valid_outcome?(
               fixture.request,
               "ok",
               value,
               fixture.intent["operation_id"]
             )
    end
  end

  defp pages(source, index, offset, acc) do
    request = read_request(source, index, offset, 768)
    {:ok, page} = EffectResult.read(source, request)
    assert EffectResult.valid_outcome?(request, "ok", page, id("f"))
    assert EffectResult.bound_outcome?(source, request, %{"status" => "ok", "value" => page})

    if page["complete"],
      do: Enum.reverse([page | acc]),
      else: pages(source, index, page["next"], [page | acc])
  end

  defp fixture(dimensions, count, version \\ 1) do
    request = %{request() | "inputs" => Enum.map(1..count, &"chunk #{&1}"), "version" => version}

    config = %{
      embedding_profiles: %{
        "vectors" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture",
          "dimensions" => dimensions,
          "dimension_mode" => "native"
        }
      },
      extensions: [%{identity: %{"capabilities" => ~w(host.actions host.embedding)}}]
    }

    scope = %{"embedding_profiles" => EmbeddingProfiles.snapshot(config)}
    {:ok, runtime, execution} = EmbeddingProfiles.prepare(config, request)
    {:ok, binding} = EmbeddingCall.binding(config, request)
    operation = id("2")

    intent = %{
      "type" => "extension_action_intent",
      "version" => 2,
      "parent_invocation_id" => id("1"),
      "operation_id" => operation,
      "identity_sha256" => digest("identity"),
      "request_sha256" => digest(request),
      "request" => request,
      "effect_binding" => binding,
      "namespace" => id("3"),
      "approval" => "approved"
    }

    admission =
      Usage.admission(intent["namespace"], runtime, "extension", id("4"))
      |> Map.put("request_id", operation)

    native = %{
      "model" => "fixture-resolved",
      "embeddings" =>
        Enum.map(1..count, fn index -> [index * 1.0 | List.duplicate(-0.25, dimensions - 1)] end),
      "prompt_eval_count" => 17,
      "total_duration" => 500_000
    }

    {:ok, payload, raw} =
      Ipse.Provider.Embedding.parse(:ollama, Jason.encode!(native), runtime, request["inputs"])

    completion = Usage.completion(admission, {:ok, payload, raw}, 3, nil)
    {:ok, source} = EmbeddingCall.response(intent, admission, completion, payload)

    %{
      request: request,
      scope: scope,
      execution: execution,
      intent: intent,
      admission: admission,
      completion: completion,
      payload: payload,
      source: source
    }
  end

  defp request,
    do: %{
      "op" => "embedding.create",
      "version" => 1,
      "profile" => "vectors",
      "inputs" => ["chunk"],
      "timeout_ms" => 5000
    }

  defp read_request(source, index, offset, limit),
    do: %{
      "op" => "effect.result.read",
      "version" => 2,
      "operation_id" => source["operation_id"],
      "source_sha256" => source["source_sha256"],
      "vector_index" => index,
      "offset" => offset,
      "limit" => limit
    }

  defp rehash(source) do
    source = Map.put(source, "data_sha256", digest(source["data"]))
    Map.put(source, "source_sha256", digest(Map.delete(source, "source_sha256")))
  end

  defp id(char), do: String.duplicate(char, 32)
  defp digest(value), do: Ipse.Compaction.digest([value])
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
