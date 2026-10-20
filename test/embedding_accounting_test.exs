defmodule Ipse.EmbeddingAccountingTest do
  use ExUnit.Case, async: true
  alias Ipse.{Usage, EmbeddingProfiles}
  alias Ipse.Usage.Normalizer
  alias Ipse.Extensions.{Actions, EmbeddingCall, UsageRead, ChildUsage}

  defp admission(session \\ Usage.id(), extra \\ %{}) do
    config =
      Map.merge(
        %{
          provider: :openai,
          model: "fixture-embedding",
          operation: :embedding,
          execution: %{id: "embed"}
        },
        extra
      )

    Usage.admission(session, config, "extension", Usage.id())
  end

  defp fixture(version \\ 1) do
    request = %{
      "op" => "embedding.create",
      "version" => version,
      "profile" => "embed",
      "inputs" => ["Synthetic source"],
      "timeout_ms" => 5000
    }

    config = %{
      provider: :ollama,
      model: "unused-main",
      extensions: [%{identity: %{"capabilities" => ["host.embedding"]}}],
      embedding_profiles: %{
        "embed" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture-embedding",
          "dimensions" => 2,
          "dimension_mode" => "native",
          "timeout_ms" => 5000
        }
      }
    }

    {:ok, runtime, execution} = EmbeddingProfiles.prepare(config, request)
    {:ok, binding} = EmbeddingCall.binding(config, request)
    admission = Usage.admission(Usage.id(), runtime, "extension", Usage.id())

    intent = %{
      "type" => "extension_action_intent",
      "version" => 2,
      "parent_invocation_id" => Usage.id(),
      "operation_id" => admission["request_id"],
      "step" => 1,
      "identity_sha256" => String.duplicate("a", 64),
      "namespace" => admission["session_id"],
      "context_sha256" => nil,
      "service" => nil,
      "request" => request,
      "request_sha256" => Ipse.Compaction.digest([request]),
      "approval" => "session_allow",
      "effect_binding" => binding
    }

    source = EmbeddingCall.source(intent, admission, execution)

    native = %{
      "model" => "fixture-embedding",
      "embeddings" => [[1.0, -0.5]],
      "prompt_eval_count" => 7,
      "total_duration" => 1000
    }

    {:ok, payload, raw} =
      Ipse.Provider.Embedding.parse(:ollama, Jason.encode!(native), runtime, request["inputs"])

    observed = Usage.observation(admission, raw, 1)
    completion = Usage.completion(admission, {:ok, payload, raw}, 2, observed["usage"])
    {:ok, response} = EmbeddingCall.response(intent, admission, completion, payload)
    {:ok, value} = EmbeddingCall.value_from_completion(intent, admission, completion, response)
    {:ok, result} = Actions.result(intent, %{"status" => "ok", "value" => value})

    metadata = %{
      "type" => "session",
      "metadata" => %{
        "usage_version" => 2,
        "embedding_profiles" => EmbeddingProfiles.snapshot(config)
      }
    }

    %{
      metadata: metadata,
      intent: intent,
      admission: admission,
      source: source,
      observed: observed,
      completion: completion,
      response: response,
      result: result,
      events: [metadata, intent, source, admission, observed, response, completion, result]
    }
  end

  test "native embedding counts distinguish inapplicable output from actual zero and absent input" do
    openai =
      Normalizer.normalize(:openai, "embedding", %{"prompt_tokens" => 7, "total_tokens" => 7})

    assert openai["version"] === 2 and openai["operation"] == "embedding"
    assert openai["quality"] == "totals_known"
    assert openai["counts"]["input_tokens"] == 7 and openai["counts"]["total_tokens"] == 7
    assert openai["counts"]["output_tokens"] == nil
    assert openai["not_applicable_fields"] == ["output_tokens"]
    assert openai["derived_fields"] == []
    assert Normalizer.valid?(openai) and Normalizer.valid?(openai, "embedding")
    refute Normalizer.valid?(openai, "text")

    local =
      Normalizer.normalize(:ollama, :embedding, %{"prompt_eval_count" => 0, "total_duration" => 0})

    assert local["quality"] == "totals_known"
    assert local["counts"]["input_tokens"] === 0 and local["counts"]["total_tokens"] === 0
    assert local["counts"]["provider_duration_ns"] === 0
    assert local["counts"]["output_tokens"] == nil
    assert local["derived_fields"] == ["total_tokens"]

    for raw <- [%{}, %{"prompt_tokens" => nil}, nil] do
      usage = Normalizer.normalize(:openai, "embedding", raw)
      assert usage["quality"] == "unavailable"
      assert Enum.all?(Map.values(usage["counts"]), &is_nil/1)
      assert Normalizer.valid?(usage, "embedding")
    end

    duration = Normalizer.normalize(:ollama, "embedding", %{"total_duration" => 50})
    assert duration["quality"] == "partial" and duration["counts"]["input_tokens"] == nil

    assert Normalizer.normalize(:ollama, "embedding", %{"input_tokens" => 7})["quality"] ==
             "unavailable"

    assert Normalizer.normalize(:openai, "embedding", %{"prompt_tokens" => 3})["derived_fields"] ==
             ["total_tokens"]
  end

  test "embedding normalization refuses inconsistent native counters and closed-record substitutions" do
    for raw <- [
          %{"prompt_tokens" => -1},
          %{"prompt_tokens" => 1.0},
          %{"prompt_tokens" => "7"},
          %{"prompt_tokens" => true},
          %{"prompt_tokens" => Normalizer.limit() + 1},
          %{"prompt_tokens" => 7, "total_tokens" => 8},
          %{"prompt_tokens" => 7, "total_tokens" => -1},
          "invalid"
        ] do
      usage = Normalizer.normalize(:openai, "embedding", raw)
      assert usage["quality"] == "invalid"
      assert Enum.all?(Map.values(usage["counts"]), &is_nil/1)
      assert Normalizer.valid?(usage, "embedding")
    end

    good = Normalizer.normalize(:openai, "embedding", %{"prompt_tokens" => 7})

    for invalid <- [
          Map.put(good, "operation", "text"),
          Map.put(good, "version", 2.0),
          Map.put(good, "not_applicable_fields", []),
          Map.put(good, "secret", "discard"),
          put_in(good, ["counts", "output_tokens"], 0),
          put_in(good, ["counts", "input_cached_tokens"], 0),
          put_in(good, ["counts", "total_tokens"], 8),
          Map.put(good, "derived_fields", ["input_tokens"])
        ] do
      refute Normalizer.valid?(invalid)
    end

    text = Normalizer.normalize(:openai, %{"input_tokens" => 7, "output_tokens" => 0})

    assert text ==
             Normalizer.normalize(:openai, "text", %{"input_tokens" => 7, "output_tokens" => 0})

    assert Normalizer.valid?(text, "text")
    refute Normalizer.valid?(text, "embedding")
  end

  test "admissions, observations and completions preserve their strict operation and legacy projection" do
    embedding = admission()
    assert Usage.operation(embedding) == "embedding"
    assert embedding["version"] === 2 and embedding["operation"] == "embedding"

    for invalid <- [
          Map.delete(embedding, "operation"),
          Map.put(embedding, "operation", "text"),
          Map.put(embedding, "version", 2.0),
          Map.put(embedding, "provider", "chatgpt"),
          Map.put(embedding, "kind", "model"),
          Map.put(embedding, "secret", true)
        ] do
      assert Usage.operation(invalid) == nil
    end

    observation = Usage.observation(embedding, %{"prompt_tokens" => 5}, 1)
    assert observation["version"] === 2 and observation["operation"] == "embedding"

    completed =
      Usage.completion(
        embedding,
        {:ok, %{"reported_model" => "actual-embedding"}, %{"prompt_tokens" => 5}},
        3,
        nil
      )

    assert completed["reported_model"] == "actual-embedding"
    assert completed["usage"]["counts"]["output_tokens"] == nil
    failed = Usage.completion(embedding, {:error, "unsettled"}, 3, observation["usage"])
    assert failed["reported_model"] == nil and failed["usage"] == observation["usage"]
    assert failed["outcome"] == "failed" and failed["finality"] == "partial"

    record =
      Usage.request_record(%{
        admission: embedding,
        observation: observation["usage"],
        completion: failed
      })

    assert Usage.valid_request_record?(record)
    refute Usage.valid_request_record?(Map.delete(record, "operation"))

    refute Usage.valid_request_record?(
             put_in(record, ["usage"], Normalizer.normalize(:openai, %{}))
           )

    text = Usage.admission(Usage.id(), %{provider: :openai, model: "text"}, "model", Usage.id())
    assert Usage.operation(text) == "text" and text["version"] === 1
    refute Map.has_key?(text, "operation")
    assert Usage.operation(Map.put(text, "operation", "text")) == nil

    assert Usage.completion(
             text,
             {:ok, %{"provider_data" => %{"reported_model" => "actual-text"}}, %{}},
             1,
             nil
           )["reported_model"] == "actual-text"
  end

  test "pure recovery binds approved request, vector source, completed measurement and exact result" do
    f = fixture()
    assert {:ok, ledger} = Usage.restore(f.events, f.admission["session_id"])
    assert Usage.snapshot(ledger)["version"] === 2
    refute Usage.snapshot(ledger)["legacy_unmetered"]
    assert {:ok, _} = Usage.restore(Enum.drop(f.events, -2))
    assert {:ok, _} = Usage.restore(Enum.drop(f.events, -3))
    assert {:ok, _} = Usage.restore(List.delete(f.events, f.observed))

    for events <- [
          put_in(f.events, [Access.at(0), "metadata", "usage_version"], 1),
          put_in(f.events, [Access.at(0), "metadata", "usage_version"], nil),
          List.delete(f.events, f.source),
          List.delete(f.events, f.response),
          List.insert_at(f.events, 6, f.response),
          Enum.map(
            f.events,
            &if(&1 == f.response,
              do: put_in(&1, ["inference", "attempt_id"], Usage.id()),
              else: &1
            )
          ),
          Enum.map(
            f.events,
            &if(&1 == f.completion, do: Map.put(&1, "reported_model", "substitution"), else: &1)
          ),
          Enum.map(
            f.events,
            &if(&1 == f.completion,
              do: Map.merge(&1, %{"outcome" => "failed", "finality" => "partial"}),
              else: &1
            )
          ),
          Enum.map(
            f.events,
            &if(&1 == f.observed,
              do: Map.put(&1, "usage", Normalizer.normalize(:ollama, %{})),
              else: &1
            )
          ),
          [
            f.metadata,
            f.intent,
            f.source,
            f.admission,
            f.response,
            Map.merge(f.completion, %{"version" => 1})
          ]
        ] do
      assert {:error, _} = Usage.restore(events)
    end
  end

  test "v2 recovery rejects a changed selection even with a syntactically rehashed action result" do
    f = fixture(2)
    assert {:ok, ledger} = Usage.restore(f.events)
    record = ledger.requests[f.admission["request_id"]]
    assert EmbeddingCall.valid_result_source?(f.result, record, f.response)
    assert Actions.bound_effect?(f.result, %{f.result["operation_id"] => f.response}, [])

    changed =
      put_in(f.result, ["outcome", "value", "selection_sha256"], String.duplicate("b", 64))

    changed = Map.put(changed, "outcome_sha256", Ipse.Compaction.digest([changed["outcome"]]))
    assert Actions.valid_result?(changed)
    refute Actions.bound_effect?(changed, %{f.result["operation_id"] => f.response}, [])
    refute EmbeddingCall.valid_result_source?(changed, record, f.response)
    assert {:error, _} = Usage.restore(List.replace_at(f.events, -1, changed))
  end

  test "unknown action preserves an interrupted prefix but cannot excuse contradictory completed evidence" do
    f = fixture()
    assert {:ok, unknown} = Actions.result(f.intent, %{"status" => "unknown", "value" => %{}})
    assert {:ok, ledger} = Usage.restore(f.events)
    record = ledger.requests[f.admission["request_id"]]
    assert EmbeddingCall.valid_result_source?(unknown, record, f.response)
    assert EmbeddingCall.valid_result_source?(unknown, %{record | completion: nil}, f.response)
    failed = Usage.completion(f.admission, {:error, "settlement refused"}, 3, f.observed["usage"])
    refute EmbeddingCall.valid_result_source?(unknown, %{record | completion: failed}, f.response)
    mismatched = put_in(record, [:completion, "reported_model"], "substituted")
    refute EmbeddingCall.valid_result_source?(unknown, mismatched, f.response)
    assert {:ok, _} = Usage.restore(List.replace_at(f.events, -1, unknown))

    assert {:error, _} =
             Usage.restore([
               f.metadata,
               f.intent,
               f.source,
               f.admission,
               f.observed,
               f.response,
               failed,
               unknown
             ])
  end

  test "metered but unpublished embeddings retain observations without inventing a vector source" do
    f = fixture()
    failed = Usage.completion(f.admission, {:error, "settlement refused"}, 3, f.observed["usage"])

    assert {:ok, failed_action} =
             Actions.result(f.intent, %{
               "status" => "failed",
               "value" => %{"code" => "embedding_request_failed"}
             })

    assert {:ok, ledger} =
             Usage.restore([
               f.metadata,
               f.intent,
               f.source,
               f.admission,
               f.observed,
               failed,
               failed_action
             ])

    request = ledger.requests[f.admission["request_id"]]
    assert request.completion["usage"]["counts"]["input_tokens"] == 7
    assert request.completion["reported_model"] == nil
    assert request.completion["usage"]["counts"]["output_tokens"] == nil

    assert {:ok, bad_publication} =
             Actions.result(f.intent, %{
               "status" => "failed",
               "value" => %{"code" => "embedding_response"}
             })

    assert {:ok, _} =
             Usage.restore([
               f.metadata,
               f.intent,
               f.source,
               f.admission,
               f.observed,
               f.completion,
               bad_publication
             ])
  end

  test "mixed own-session usage pages retain operation and cannot claim legacy page semantics" do
    f = fixture()

    text =
      Usage.admission(
        f.admission["session_id"],
        %{provider: :openai, model: "text"},
        "model",
        Usage.id()
      )

    text_finished =
      Usage.completion(text, {:ok, %{}, %{"input_tokens" => 3, "output_tokens" => 2}}, 1, nil)

    assert {:ok, ledger} = Usage.restore([f.metadata, text, text_finished | tl(f.events)])
    request = %{"op" => "usage.read", "cursor" => 0, "limit" => 4, "snapshot" => nil}

    intent = %{
      "request" => request,
      "operation_id" => Usage.id(),
      "identity_sha256" => String.duplicate("b", 64),
      "namespace" => f.admission["session_id"]
    }

    {:ok, source} = Ipse.Lifecycle.Source.build(intent["namespace"], 0, intent)
    {:ok, reference} = Ipse.Lifecycle.Source.metadata(source)
    assert {:ok, page} = UsageRead.prepare(ledger, %{}, intent, reference)
    assert page["version"] === 2 and page["snapshot"]["version"] === 2
    assert [%{"version" => 1}, %{"version" => 2, "operation" => "embedding"}] = page["requests"]
    assert UsageRead.valid_outcome?(request, "ok", page, intent["operation_id"])

    refute UsageRead.valid_outcome?(
             request,
             "ok",
             Map.put(page, "version", 1),
             intent["operation_id"]
           )

    legacy = page |> Map.put("version", 1) |> put_in(["snapshot", "version"], 1)
    refute UsageRead.valid_outcome?(request, "ok", legacy, intent["operation_id"])
  end

  test "child request pages version their operation-bearing projection independently of discovery" do
    parent = Usage.id()
    child = Usage.id()
    origin = %{"parent_session_id" => parent, "parent_request_id" => Usage.id()}
    embedding = admission(child, %{delegation_origin: origin})

    text =
      Usage.admission(
        child,
        %{provider: :openai, model: "text", delegation_origin: origin},
        "model",
        Usage.id()
      )

    rows =
      Enum.map(
        [text, embedding],
        &Usage.request_record(%{admission: &1, observation: nil, completion: nil})
      )

    request = %{
      "op" => "usage.child.read",
      "child_id" => child,
      "cursor" => 0,
      "limit" => 4,
      "snapshot" => nil
    }

    id = Usage.id()
    {:ok, source} = Ipse.Lifecycle.Source.build(parent, 0, %{})
    {:ok, reference} = Ipse.Lifecycle.Source.metadata(source)

    snapshot = %{
      "version" => 4,
      "source" => reference,
      "operation_id" => id,
      "identity_sha256" => String.duplicate("c", 64),
      "child_id" => child,
      "request_count" => 2,
      "legacy_unmetered" => false,
      "bytes" => 100,
      "sha256" => String.duplicate("d", 64)
    }

    page = %{
      "version" => 2,
      "scope" => "child",
      "coverage" => "canonical_requests",
      "snapshot" => snapshot,
      "cursor" => 0,
      "next" => nil,
      "requests" => rows
    }

    assert ChildUsage.valid_outcome?(request, "ok", page, id)
    legacy = page |> Map.put("version", 1) |> put_in(["snapshot", "version"], 3)
    refute ChildUsage.valid_outcome?(request, "ok", legacy, id)

    refute ChildUsage.valid_outcome?(
             request,
             "ok",
             put_in(page, ["requests", Access.at(1), "parent_session_id"], Usage.id()),
             id
           )
  end
end
