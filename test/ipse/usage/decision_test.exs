defmodule Ipse.DecisionAccountingTest do
  use ExUnit.Case, async: true
  alias Ipse.{Usage, JSON}
  alias Ipse.Config.Decisions
  alias Ipse.Extension.DecisionCall
  alias Ipse.Usage.{Budget, Costs}

  defp fixture do
    request = %{
      "op" => "decision.create",
      "version" => 1,
      "profile" => "test",
      "input" => "self-authored accounting fixture",
      "questions" => [
        %{"id" => "relevant", "type" => "predicate", "instructions" => "Is this relevant?"}
      ],
      "timeout_ms" => 2000
    }

    config = %{
      extensions: [%{identity: %{"capabilities" => ["host.decision"]}}],
      decision_profiles: %{
        "test" => %{
          "operation" => "decision",
          "provider" => "system_one",
          "model" => "jev-latest",
          "expected_model" => "jev-fixture",
          "service_id" => "fixture_service"
        }
      }
    }

    {:ok, runtime, execution} = Decisions.prepare(config, request)
    {:ok, binding} = DecisionCall.binding(config, request)
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
      "request_sha256" => JSON.digest([request]),
      "approval" => "session_allow",
      "effect_binding" => binding
    }

    source = DecisionCall.source(intent, admission, execution)
    raw = %{"input_tokens" => 10, "output_tokens" => 2}

    native = %{
      "model" => "jev-fixture",
      "answers" => %{"relevant" => %{"type" => "noul", "noul" => 0.8}},
      "usage" => raw
    }

    {:ok, payload, ^raw} =
      Ipse.Provider.Decision.Transport.parse(
        runtime,
        DecisionCall.neutral(request),
        Jason.encode!(native)
      )

    observed = Usage.observation(admission, raw, 1)
    completion = Usage.completion(admission, {:ok, payload, raw}, 2, observed["usage"])
    {:ok, response} = DecisionCall.response(intent, admission, completion, payload)
    {:ok, value} = DecisionCall.value_from_completion(intent, admission, completion, response)

    metadata = %{
      "type" => "session",
      "metadata" => %{"usage_version" => 3, "decision_profiles" => Decisions.snapshot(config)}
    }

    %{
      metadata: metadata,
      intent: intent,
      source: source,
      admission: admission,
      observed: observed,
      completion: completion,
      response: response,
      value: value,
      runtime: runtime,
      events: [metadata, intent, source, admission, observed, response, completion]
    }
  end

  test "decision normalization preserves nullable cache partitions and explicit zero independently" do
    for provider <- [:openai, :system_one, :system_one_compatible] do
      usage = Usage.normalize(provider, :decision, %{"input_tokens" => 10, "output_tokens" => 2})
      assert Usage.valid_usage?(usage, "decision")
      assert usage["version"] === 3 and usage["operation"] == "decision"
      assert usage["counts"]["total_tokens"] == 12
      assert usage["counts"]["input_cached_tokens"] == nil
      assert usage["counts"]["input_cache_write_tokens"] == nil
      refute Usage.valid_usage?(usage, "text")
      refute Usage.valid_usage?(usage, "embedding")
      assert Usage.normalize(provider, :decision, nil)["quality"] == "unavailable"
    end

    usage =
      Usage.normalize(:openai, :decision, %{
        "input_tokens" => 10,
        "output_tokens" => 0,
        "input_tokens_details" => %{"cached_tokens" => 0, "cache_write_tokens" => 0},
        "output_tokens_details" => %{"reasoning_tokens" => 0}
      })

    assert usage["counts"]["input_cached_tokens"] === 0
    assert usage["counts"]["input_cache_write_tokens"] === 0
    assert usage["counts"]["output_reasoning_tokens"] === 0
    assert Usage.valid_usage?(usage)
  end

  test "invalid usage is a typed unavailable measurement rather than negative advice or zero" do
    for raw <- [
          %{"input_tokens" => -1},
          %{"output_tokens" => true},
          %{"input_tokens" => Usage.counter_limit() + 1},
          %{"input_tokens" => 10, "output_tokens" => 2, "total_tokens" => 13},
          %{
            "input_tokens" => 10,
            "input_tokens_details" => %{"cached_tokens" => 6, "cache_write_tokens" => 6}
          },
          %{"unexpected" => "remote prose"},
          %{"input_tokens_details" => %{"extra" => 1}}
        ] do
      usage = Usage.normalize(:openai, :decision, raw)
      assert usage["quality"] == "invalid"
      assert Enum.all?(Map.values(usage["counts"]), &is_nil/1)
      assert Usage.valid_usage?(usage, "decision")
    end
  end

  test "version3 reconstruction binds approved source, endpoint, service and exact reported identity" do
    f = fixture()
    assert {:ok, ledger} = Usage.restore(f.events, f.admission["session_id"])
    assert Usage.snapshot(ledger)["version"] === 3

    assert Usage.valid_request_record?(
             Usage.request_record(ledger.requests[f.admission["request_id"]])
           )

    for version <- [nil, 1, 2],
        do:
          assert(
            {:error, _} =
              Usage.restore(
                put_in(f.events, [Access.at(0), "metadata", "usage_version"], version)
              )
          )

    for {index, path, value} <- [
          {2, ["admission", "service_id"], "replacement"},
          {2, ["admission", "expected_model"], "replacement"},
          {2, ["execution", "service_id"], "replacement"},
          {3, ["endpoint_sha256"], String.duplicate("b", 64)},
          {6, ["reported_model"], "replacement"},
          {5, ["attempt_id"], Usage.id()},
          {4, ["usage", "version"], 1}
        ] do
      assert {:error, _} = Usage.restore(put_in(f.events, [Access.at(index) | path], value))
    end

    assert {:error, _} = Usage.restore(List.delete(f.events, f.source))

    changed_usage =
      Usage.normalize(:system_one, :decision, %{"input_tokens" => 20, "output_tokens" => 2})

    assert {:error, _} = Usage.restore(put_in(f.events, [Access.at(6), "usage"], changed_usage))
    assert {:error, _} = Usage.restore(List.insert_at(f.events, 6, f.response))
    assert {:ok, _} = Usage.restore(Enum.take(f.events, 4))
    assert {:ok, _} = Usage.restore(Enum.take(f.events, 6))

    refute Usage.valid_request_record?(
             Map.put(
               Usage.request_record(ledger.requests[f.admission["request_id"]]),
               "service_id",
               nil
             )
           )

    record = Usage.request_record(ledger.requests[f.admission["request_id"]])
    refute Usage.valid_request_record?(Map.put(record, "reported_model", "replacement"))

    result =
      f.intent
      |> Map.put("type", "extension_action_result")
      |> Map.put("outcome", %{"status" => "ok", "value" => f.value})

    assert DecisionCall.valid_result_source?(
             result,
             ledger.requests[f.admission["request_id"]],
             f.response
           )

    assert DecisionCall.bound_selection?(result)
    assert DecisionCall.bound_response?(result, f.response)

    refute DecisionCall.bound_response?(
             result,
             put_in(
               f.response,
               ["payload", "result", "answers", Access.at(0), "probability"],
               0.1
             )
           )

    refute DecisionCall.valid_result_source?(
             put_in(result, ["outcome", "value", "selection_sha256"], String.duplicate("b", 64)),
             ledger.requests[f.admission["request_id"]],
             f.response
           )
  end

  test "cancelled work keeps reservation liability and output-cap budgets refuse before dispatch" do
    f = fixture()

    assert {:error, _} =
             Budget.request_config(
               Map.put(f.runtime, :budget, %{
                 "max_output_tokens" => 100,
                 "reserve_output_tokens" => 10
               })
             )

    policy = %{
      "version" => 1,
      "max_requests" => 1,
      "max_input_tokens" => 100,
      "reserve_input_tokens" => 50
    }

    root = %{"session_id" => f.admission["session_id"]}
    header = Budget.ledger_header(root, policy)
    assert {:ok, state} = Budget.restore_ledger([header], root, policy)
    assert {:ok, _, reserved} = Budget.reserve_request(state, f.admission)

    assert {:ok, dispatched} =
             Budget.apply_reservation_event(reserved, %{
               "type" => "dispatch_intent",
               "request_id" => f.admission["request_id"],
               "attempt_id" => f.admission["attempt_id"]
             })

    cancelled = Usage.completion(f.admission, :cancelled, 1, nil)

    assert {:ok, settled} =
             Budget.apply_reservation_event(dispatched, %{
               "type" => "settled",
               "completion" => cancelled
             })

    snapshot = Budget.ledger_snapshot(settled)
    assert snapshot["unknown_liability_count"] == 1
    assert Enum.find(snapshot["dimensions"], &(&1["unit"] == "input_tokens"))["booked"] == 50

    assert {:error, :budget_exhausted} =
             Budget.reserve_request(settled, %{
               f.admission
               | "request_id" => Usage.id(),
                 "attempt_id" => Usage.id()
             })
  end

  test "own-session and child pages version decision records without weakening earlier pages" do
    f = fixture()
    assert {:ok, ledger} = Usage.restore(f.events)
    request = %{"op" => "usage.read", "cursor" => 0, "limit" => 4, "snapshot" => nil}

    intent = %{
      "request" => request,
      "operation_id" => Usage.id(),
      "identity_sha256" => String.duplicate("b", 64),
      "namespace" => f.admission["session_id"]
    }

    {:ok, source} = Ipse.Journal.source(intent["namespace"], 0, intent)
    {:ok, reference} = Ipse.Journal.source_metadata(source)
    assert {:ok, page} = Ipse.Extension.UsageRead.prepare(ledger, %{}, intent, reference)
    assert page["version"] === 3 and page["snapshot"]["version"] === 3
    assert Ipse.Extension.UsageRead.valid_outcome?(request, "ok", page, intent["operation_id"])
    legacy = page |> Map.put("version", 2) |> put_in(["snapshot", "version"], 2)
    refute Ipse.Extension.UsageRead.valid_outcome?(request, "ok", legacy, intent["operation_id"])
    parent = Usage.id()

    child_request = %{
      "op" => "usage.child.read",
      "child_id" => f.admission["session_id"],
      "cursor" => 0,
      "limit" => 4,
      "snapshot" => nil
    }

    {:ok, parent_source} = Ipse.Journal.source(parent, 0, %{})
    {:ok, parent_reference} = Ipse.Journal.source_metadata(parent_source)

    snapshot =
      page["snapshot"]
      |> Map.merge(%{
        "version" => 5,
        "source" => parent_reference,
        "child_id" => f.admission["session_id"],
        "bytes" => 100,
        "sha256" => String.duplicate("c", 64)
      })

    rows = Enum.map(page["requests"], &Map.put(&1, "parent_session_id", parent))

    child_page =
      page
      |> Map.put("scope", "child")
      |> Map.put("snapshot", snapshot)
      |> Map.put("requests", rows)

    assert Ipse.Extension.ChildUsage.valid_outcome?(
             child_request,
             "ok",
             child_page,
             intent["operation_id"]
           )

    refute Ipse.Extension.ChildUsage.valid_outcome?(
             child_request,
             "ok",
             child_page |> Map.put("version", 2) |> put_in(["snapshot", "version"], 4),
             intent["operation_id"]
           )
  end

  defp card(operation, version \\ 3) do
    %{
      "version" => version,
      "id" => "fixture",
      "revision" => "one",
      "currency" => "USD",
      "source" => "operator:synthetic",
      "published_on" => "2026-01-01",
      "rows" => [
        %{
          "id" => "row",
          "operation" => operation,
          "provider" => "system_one",
          "billing_mode" => "api",
          "basis" => "api_estimate",
          "model" => "jev-fixture",
          "endpoint_sha256" => nil,
          "from" => "2026-01-01",
          "until" => nil,
          "input_min" => 0,
          "input_max" => nil,
          "input_mode" => "flat",
          "rates" => %{"input" => "1", "output" => "0"}
        }
      ]
    }
  end

  test "explicit decision rate cards remain partitioned from text and unknown cache splits stay unpriced" do
    f = fixture()

    record =
      Usage.request_record(%{admission: f.admission, observation: nil, completion: f.completion})

    fields =
      ~w(operation provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)

    assert :ok = Costs.validate(card("decision"))
    assert {:error, _} = Costs.validate(card("decision", 2))
    assert {:ok, quote} = Costs.estimate(card("decision"), Map.take(record, fields))

    assert quote["version"] === 3 and quote["operation"] == "decision" and
             quote["status"] == "estimated"

    assert quote["amount_nanos"] == 10_000

    wrong =
      put_in(card("decision"), ["rows", Access.at(0), "operation"], "text")
      |> put_in(["rows", Access.at(0), "provider"], "openai")

    assert {:ok, quote} = Costs.estimate(wrong, Map.take(record, fields))
    assert quote["amount_nanos"] == nil and quote["missing"] == ["operation_rate_unavailable"]

    split =
      card("decision")
      |> put_in(["rows", Access.at(0), "input_mode"], "cache_split")
      |> put_in(["rows", Access.at(0), "rates"], %{
        "input_uncached" => "1",
        "input_cached" => "0.1",
        "input_cache_write" => "1",
        "output" => "0"
      })

    assert {:ok, quote} = Costs.estimate(split, Map.take(record, fields))
    assert quote["amount_nanos"] == nil and quote["status"] == "partial"
    assert "input_partition_unknown_or_inconsistent" in quote["missing"]
  end
end
