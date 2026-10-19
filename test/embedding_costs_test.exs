defmodule Ipse.EmbeddingCostsTest do
  use ExUnit.Case, async: true
  alias Ipse.Usage
  alias Ipse.Usage.Normalizer
  alias Ipse.Extensions.Costs
  alias Ipse.Budget.{Policy, Ledger}

  defp row(operation \\ "embedding") do
    %{
      "id" => operation,
      "operation" => operation,
      "provider" => "openai",
      "billing_mode" => "api",
      "basis" => "api_estimate",
      "model" => "fixture",
      "endpoint_sha256" => nil,
      "from" => "2026-01-01",
      "until" => "2027-01-01",
      "input_min" => 0,
      "input_max" => nil,
      "input_mode" => "flat",
      "rates" =>
        if(operation == "embedding",
          do: %{"input" => "2"},
          else: %{"input" => "2", "output" => "10"}
        )
    }
  end

  defp card(rows \\ [row()]) do
    %{
      "version" => 2,
      "id" => "operation-rates",
      "revision" => "synthetic-1",
      "currency" => "USD",
      "source" => "operator:embedding-accounting-fixture",
      "published_on" => "2026-10-19",
      "rows" => rows
    }
  end

  defp request(raw \\ %{"prompt_tokens" => 7, "total_tokens" => 7}) do
    %{
      "operation" => "embedding",
      "provider" => "openai",
      "billing_mode" => "api",
      "model" => "fixture",
      "reported_model" => "fixture",
      "endpoint_sha256" => nil,
      "admitted_at_ms" => DateTime.to_unix(~U[2026-10-19 00:00:00Z], :millisecond),
      "outcome" => "completed",
      "finality" => "final",
      "usage" => Normalizer.normalize(:openai, "embedding", raw)
    }
  end

  defp embedding(session, extra \\ %{}) do
    config =
      Map.merge(
        %{provider: :openai, model: "fixture", operation: :embedding, execution: %{id: "embed"}},
        extra
      )

    Usage.admission(session, config, "extension", Usage.id())
  end

  defp completed(admission, raw \\ %{"prompt_tokens" => 7}) do
    Usage.completion(admission, {:ok, %{"reported_model" => "fixture"}, raw}, 1, nil)
  end

  defp policy do
    %{
      "version" => 1,
      "max_requests" => 3,
      "max_input_tokens" => 100,
      "reserve_input_tokens" => 40,
      "max_output_tokens" => 20,
      "reserve_output_tokens" => 10
    }
  end

  defp ledger(policy, session) do
    root = %{"session_id" => session}
    assert {:ok, state} = Ledger.restore([Ledger.header(root, policy)], root, policy)
    state
  end

  defp dispatch(state, admission) do
    assert {:ok, _, reserved} = Ledger.reserve(state, admission)

    assert {:ok, dispatched} =
             Ledger.apply_event(reserved, %{
               "type" => "dispatch_intent",
               "request_id" => admission["request_id"],
               "attempt_id" => admission["attempt_id"]
             })

    dispatched
  end

  defp observe(state, admission, usage) do
    Ledger.apply_event(state, %{
      "type" => "observed",
      "request_id" => admission["request_id"],
      "attempt_id" => admission["attempt_id"],
      "usage" => usage
    })
  end

  test "operation-specific rows price embedding input without fabricating generated output" do
    assert :ok = Costs.validate(card())
    assert {:ok, estimate} = Costs.estimate(card(), request())
    assert estimate["version"] === 2 and estimate["operation"] == "embedding"
    assert estimate["scope"] == "embedding_tokens_and_reported_duration"
    assert estimate["status"] == "estimated" and estimate["amount_nanos"] == 14_000
    assert estimate["missing"] == []
    assert [%{"unit" => "input", "count" => 7, "rate" => "2"}] = estimate["components"]
    assert request()["usage"]["counts"]["output_tokens"] == nil
    assert {:ok, zero} = Costs.estimate(card(), request(%{"prompt_tokens" => 0}))
    assert zero["amount_nanos"] === 0
    assert {:ok, missing} = Costs.estimate(card(), request(%{}))
    assert missing["amount_nanos"] == nil and missing["known_amount_nanos"] == nil
    assert "count:input" in missing["missing"]
  end

  test "reported positive duration requires an explicit rate and is never silently discarded" do
    local_row =
      row()
      |> Map.merge(%{
        "provider" => "ollama",
        "billing_mode" => "local",
        "basis" => "local_estimate"
      })

    local_request =
      request()
      |> Map.merge(%{
        "provider" => "ollama",
        "billing_mode" => "local",
        "usage" =>
          Normalizer.normalize(:ollama, "embedding", %{
            "prompt_eval_count" => 7,
            "total_duration" => 2_000_000_000
          })
      })

    assert {:ok, partial} = Costs.estimate(card([local_row]), local_request)
    assert partial["status"] == "partial" and partial["amount_nanos"] == nil
    assert partial["known_amount_nanos"] == 14_000
    assert partial["missing"] == ["rate:duration_second"]
    with_duration = put_in(local_row, ["rates", "duration_second"], "0.25")
    assert {:ok, measured} = Costs.estimate(card([with_duration]), local_request)
    assert measured["status"] == "estimated" and measured["amount_nanos"] == 500_014_000

    assert Enum.any?(
             measured["components"],
             &(&1["unit"] == "duration_second" and &1["count"] == 2_000_000_000)
           )

    only_duration =
      put_in(
        local_request,
        ["usage"],
        Normalizer.normalize(:ollama, "embedding", %{"total_duration" => 2_000_000_000})
      )

    assert {:ok, partial} = Costs.estimate(card([with_duration]), only_duration)
    assert partial["amount_nanos"] == nil and partial["known_amount_nanos"] == 500_000_000
    assert partial["missing"] == ["count:input"]

    zero_duration =
      put_in(
        local_request,
        ["usage"],
        Normalizer.normalize(:ollama, "embedding", %{
          "prompt_eval_count" => 7,
          "total_duration" => 0
        })
      )

    assert {:ok, measured_zero} = Costs.estimate(card([local_row]), zero_duration)
    assert measured_zero["status"] == "estimated"
  end

  test "v1 text cards cannot price embeddings and v2 rows distinguish overlapping operations" do
    legacy = card([Map.delete(row("text"), "operation")]) |> Map.put("version", 1)
    assert :ok = Costs.validate(legacy)
    assert {:ok, unpriced} = Costs.estimate(legacy, request())
    assert unpriced["status"] == "unpriced" and unpriced["amount_nanos"] == nil
    assert unpriced["missing"] == ["operation_rate_unavailable"]
    combined = card([row("text"), row("embedding")])
    assert :ok = Costs.validate(combined)
    assert {:ok, embedding} = Costs.estimate(combined, request())
    assert embedding["row_id"] == "embedding"

    text =
      request()
      |> Map.delete("operation")
      |> Map.put(
        "usage",
        Normalizer.normalize(:openai, %{"input_tokens" => 7, "output_tokens" => 2})
      )

    assert {:ok, old} = Costs.estimate(legacy, text)
    assert old["version"] === 1 and old["amount_nanos"] == 34_000
    refute Map.has_key?(old, "operation")
    assert {:ok, new} = Costs.estimate(combined, Map.put(text, "operation", "text"))

    assert new["version"] === 2 and new["operation"] == "text" and
             new["amount_nanos"] == old["amount_nanos"]

    assert new["row_id"] == "text"

    assert {:error, :invalid_rate_card} =
             Costs.validate(card([row(), %{row() | "id" => "overlap"}]))

    assert {:error, :invalid_cost_request} =
             Costs.estimate(combined, Map.delete(request(), "operation"))

    assert {:error, :invalid_cost_request} =
             Costs.estimate(combined, Map.put(text, "operation", "embedding"))
  end

  test "embedding rows are flat input and optional duration with strict decimal/date/endpoint bands" do
    for invalid <- [
          Map.put(row(), "input_mode", "cache_split"),
          put_in(row(), ["rates", "output"], "1"),
          put_in(row(), ["rates", "input_cached"], "1"),
          put_in(row(), ["rates", "web_search"], "1"),
          put_in(row(), ["rates", "input"], "1e-3"),
          Map.put(row(), "operation", "rerank"),
          Map.put(row(), "provider", "chatgpt"),
          Map.delete(row(), "operation")
        ] do
      assert {:error, :invalid_rate_card} = Costs.validate(card([invalid]))
    end

    for changed <- [
          Map.put(request(), "reported_model", "different"),
          Map.put(request(), "endpoint_sha256", String.duplicate("a", 64)),
          Map.put(
            request(),
            "admitted_at_ms",
            DateTime.to_unix(~U[2027-01-01 00:00:00Z], :millisecond)
          )
        ] do
      assert {:ok, unavailable} = Costs.estimate(card(), changed)
      assert unavailable["amount_nanos"] == nil
    end

    upper = %{row() | "input_max" => 7}
    lower = %{row() | "id" => "upper-band", "input_min" => 7}
    assert :ok = Costs.validate(card([upper, lower]))
    assert {:ok, at_boundary} = Costs.estimate(card([upper, lower]), request())
    assert at_boundary["row_id"] == "upper-band"
    assert {:ok, unknown_band} = Costs.estimate(card([upper, lower]), request(%{}))
    assert unknown_band["missing"] == ["input_band_unknown"]
  end

  test "embedding arithmetic uses exact sub-nano ceiling and refuses amount overflow" do
    tiny = put_in(row(), ["rates", "input"], "0.000000001")
    assert {:ok, result} = Costs.estimate(card([tiny]), request(%{"prompt_tokens" => 1}))
    assert result["amount_nanos"] == 1
    huge = put_in(row(), ["rates", "input"], "999999999")

    assert {:ok, overflow} =
             Costs.estimate(card([huge]), request(%{"prompt_tokens" => Normalizer.limit()}))

    assert overflow["amount_nanos"] == nil and overflow["known_amount_nanos"] == nil
    assert "amount_overflow" in overflow["missing"]
  end

  test "embedding admission bypasses text limits while output liability is semantically zero" do
    p = %{policy() | "max_output_tokens" => 0}
    runtime = %{provider: :openai, model: "fixture", operation: :embedding, budget: p}
    assert :ok = Policy.validate(p)
    assert {:ok, ^runtime} = Policy.request_config(runtime)
    refute Map.has_key?(runtime, :max_output_tokens)
    session = Usage.id()
    a = embedding(session)
    assert Policy.reservation(p, a)["output_tokens"] === 0
    assert Policy.reservation(p, a)["input_tokens"] == 40

    assert Policy.known(p, a, Normalizer.normalize(:openai, "embedding", nil), nil)[
             "output_tokens"
           ] === 0

    state = dispatch(ledger(p, session), a)
    assert Ledger.totals(state)["output_tokens"] === 0

    assert {:ok, settled} =
             Ledger.apply_event(state, %{"type" => "settled", "completion" => completed(a)})

    assert Ledger.totals(settled)["output_tokens"] === 0
    assert Ledger.totals(settled)["input_tokens"] == 7
    assert completed(a)["usage"]["counts"]["output_tokens"] == nil
    text = Usage.admission(session, %{provider: :openai, model: "text"}, "model", Usage.id())
    assert {:error, :budget_exhausted} = Ledger.reserve(ledger(p, session), text)
  end

  test "shared parent and embedding child consume one request root and retain unknown liabilities" do
    session = Usage.id()
    p = %{policy() | "max_requests" => 2}
    state = ledger(p, session)
    parent = Usage.admission(session, %{provider: :openai, model: "main"}, "model", Usage.id())
    state = dispatch(state, parent)
    origin = %{"parent_session_id" => session, "parent_request_id" => parent["request_id"]}
    child = embedding(Usage.id(), %{delegation_origin: origin})
    state = dispatch(state, child)
    assert Ledger.totals(state) == %{"requests" => 2, "input_tokens" => 80, "output_tokens" => 10}
    assert {:error, :budget_exhausted} = Ledger.reserve(state, embedding(session))
    usage = Normalizer.normalize(:openai, "embedding", %{"prompt_tokens" => 5})
    assert {:ok, observed} = observe(state, child, usage)
    failed = Usage.completion(child, :cancelled, 1, usage)

    assert {:ok, cancelled} =
             Ledger.apply_event(observed, %{"type" => "settled", "completion" => failed})

    assert Ledger.liability(cancelled, child["request_id"]) == %{
             "requests" => 1,
             "input_tokens" => 40,
             "output_tokens" => 0
           }

    assert Ledger.totals(cancelled)["requests"] == 2
    foreign_origin = %{origin | "parent_request_id" => Usage.id()}

    assert {:error, :invalid_budget_admission} =
             Ledger.reserve(
               ledger(p, session),
               embedding(Usage.id(), %{delegation_origin: foreign_origin})
             )
  end

  test "ledger refuses cross-operation observations and completions and retains measured peaks" do
    session = Usage.id()
    a = embedding(session)
    state = dispatch(ledger(policy(), session), a)
    text_usage = Normalizer.normalize(:openai, %{"input_tokens" => 60, "output_tokens" => 0})
    assert {:error, :invalid_budget_ledger} = observe(state, a, text_usage)
    usage = Normalizer.normalize(:openai, "embedding", %{"prompt_tokens" => 60})
    assert {:ok, observed} = observe(state, a, usage)
    assert Ledger.totals(observed)["input_tokens"] == 60
    wrong_version = completed(a) |> Map.delete("operation") |> Map.put("version", 1)

    assert {:error, :invalid_budget_ledger} =
             Ledger.apply_event(observed, %{"type" => "settled", "completion" => wrong_version})

    wrong_usage = put_in(completed(a), ["usage"], text_usage)

    assert {:error, :invalid_budget_ledger} =
             Ledger.apply_event(observed, %{"type" => "settled", "completion" => wrong_usage})

    assert {:ok, settled} =
             Ledger.apply_event(observed, %{
               "type" => "settled",
               "completion" => completed(a, %{"prompt_tokens" => 5})
             })

    assert Ledger.totals(settled)["input_tokens"] == 60
    assert Ledger.totals(settled)["output_tokens"] === 0
    text = Usage.admission(session, %{provider: :openai, model: "fixture"}, "model", Usage.id())
    text_state = dispatch(ledger(policy(), session), text)
    assert {:error, :invalid_budget_ledger} = observe(text_state, text, usage)
  end

  test "page and accumulated reports preserve operation and inapplicable output" do
    session = Usage.id()
    embedding = embedding(session)

    vector_record =
      Usage.request_record(%{
        admission: embedding,
        completion: completed(embedding),
        observation: nil
      })

    text = Usage.admission(session, %{provider: :openai, model: "fixture"}, "model", Usage.id())

    text_finish =
      Usage.completion(
        text,
        {:ok, %{"provider_data" => %{"reported_model" => "fixture"}},
         %{"input_tokens" => 7, "output_tokens" => 2}},
        1,
        nil
      )

    text_record =
      Usage.request_record(%{admission: text, completion: text_finish, observation: nil})

    rates = card([row(), row("text")])
    {:ok, state} = Ipse.Extensions.CostSummary.new(rates)
    {:ok, state} = Ipse.Extensions.CostSummary.put(state, vector_record)
    {:ok, state} = Ipse.Extensions.CostSummary.put(state, text_record)

    snapshot = %{
      "request_count" => 2,
      "legacy_unmetered" => false,
      "source" => %{"session_id" => session}
    }

    report = Ipse.Extensions.CostSummary.report(state, snapshot, true)
    assert report["cost_estimate_complete"]
    assert length(report["groups"]) == 2
    vector_group = Enum.find(report["groups"], &(&1["operation"] == "embedding"))
    assert vector_group["amount_nanos"] == 14_000
    assert vector_group["counts"]["output_tokens"]["not_applicable"]
    assert vector_group["counts"]["output_tokens"]["unknown_count"] == 0
    assert vector_group["counts"]["output_tokens"]["total"] == nil

    assert {:ok, page} =
             Ipse.Extensions.Examples.CostReport.report(
               rates,
               %{
                 "requests" => [vector_record, text_record],
                 "cursor" => 0,
                 "next" => nil,
                 "snapshot" => %{}
               }
             )

    assert length(page["groups"]) == 2

    assert Enum.any?(
             page["groups"],
             &(&1["operation"] == "embedding" and &1["amount_nanos"] == 14_000)
           )
  end

  test "unpriced embedding money stays reserved while explicit operation pricing settles exactly" do
    legacy = card([Map.delete(row("text"), "operation")]) |> Map.put("version", 1)

    p =
      Map.merge(policy(), %{
        "rate_card" => legacy,
        "money" => [
          %{"basis" => "api_estimate", "limit_nanos" => 1_000_000, "reserve_nanos" => 250_000}
        ]
      })

    session = Usage.id()
    a = embedding(session)
    state = dispatch(ledger(p, session), a)

    assert {:ok, unpriced} =
             Ledger.apply_event(state, %{"type" => "settled", "completion" => completed(a)})

    assert Ledger.totals(unpriced)["money:api_estimate"] == 250_000
    assert Policy.known(p, a, nil, completed(a))["money:api_estimate"] == nil
    priced_policy = Map.put(p, "rate_card", card())
    priced_state = dispatch(ledger(priced_policy, session), a)

    assert {:ok, priced} =
             Ledger.apply_event(priced_state, %{"type" => "settled", "completion" => completed(a)})

    assert Ledger.totals(priced)["money:api_estimate"] == 14_000
    assert Ledger.snapshot(priced)["unknown_liability_count"] == 0
    missing = embedding(session)
    missing_state = dispatch(ledger(priced_policy, session), missing)

    assert {:ok, unknown} =
             Ledger.apply_event(missing_state, %{
               "type" => "settled",
               "completion" => completed(missing, %{})
             })

    assert Ledger.totals(unknown)["money:api_estimate"] == 250_000
    assert Ledger.totals(unknown)["input_tokens"] == 40
    assert Ledger.totals(unknown)["output_tokens"] === 0
  end
end
