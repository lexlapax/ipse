Code.require_file("../../../dev/evaluation/decision_metrics.exs", __DIR__)

defmodule Ipse.Development.Evaluation.DecisionMetricsTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Evaluation.DecisionMetrics

  defp baseline do
    %{
      "cases" => 100,
      "supported" => 80,
      "abstentions" => 5,
      "critical_total" => 10,
      "critical_recalled" => 9,
      "citation_total" => 100,
      "citation_supported" => 95,
      "cost_nanos" => 1000,
      "p95_ms" => 1000
    }
  end

  defp gates,
    do:
      Map.new(
        ~w(protocol quality_bars citation_integrity matched_workload finite_resources paired_critical),
        &{&1, "pass"}
      )

  test "selection thresholds are inclusive and use either quality or cost benefit" do
    base = baseline()
    candidate = %{base | "supported" => 85, "cost_nanos" => nil, "p95_ms" => 1200}

    assert {:ok,
            %{
              "disposition" => "useful_candidate",
              "abstentions" => %{"baseline" => 5, "candidate" => 5, "denominator" => 100}
            }} =
             DecisionMetrics.selection(base, candidate, gates())

    candidate = %{base | "cost_nanos" => 800, "p95_ms" => 1200}

    assert {:ok, %{"disposition" => "useful_candidate"}} =
             DecisionMetrics.selection(base, candidate, gates())

    candidate = %{candidate | "cost_nanos" => 801}

    assert {:ok, %{"disposition" => "evaluated_rejected", "criteria" => %{"benefit" => "fail"}}} =
             DecisionMetrics.selection(base, candidate, gates())
  end

  test "unknown costs, latency and gate evidence are never treated as success or zero" do
    base = baseline()
    candidate = %{base | "supported" => 84, "cost_nanos" => nil}

    assert {:ok, %{"disposition" => "unverified", "criteria" => %{"benefit" => "unverified"}}} =
             DecisionMetrics.selection(base, candidate, gates())

    candidate = %{base | "supported" => 85, "p95_ms" => nil}

    assert {:ok, %{"disposition" => "unverified", "criteria" => %{"latency" => "unverified"}}} =
             DecisionMetrics.selection(base, candidate, gates())

    assert {:ok, %{"disposition" => "unverified"}} =
             DecisionMetrics.selection(base, %{base | "supported" => 85}, %{
               gates()
               | "protocol" => "unverified"
             })

    assert {:ok,
            %{
              "disposition" => "unverified",
              "gate_details" => %{"finite_resources" => "unverified"}
            }} =
             DecisionMetrics.selection(base, %{base | "supported" => 85, "cost_nanos" => nil}, %{
               gates()
               | "finite_resources" => "unverified"
             })

    assert {:ok, %{"disposition" => "unverified", "criteria" => %{"latency" => "fail"}}} =
             DecisionMetrics.selection(base, %{base | "supported" => 85, "p95_ms" => 1201}, %{
               gates()
               | "protocol" => "unverified"
             })
  end

  test "critical, citation, latency and hard-gate regressions reject even with benefit" do
    base = baseline()
    candidate = %{base | "supported" => 85}

    for changed <- [
          %{candidate | "critical_recalled" => 8},
          %{candidate | "citation_supported" => 94},
          %{candidate | "p95_ms" => 1201}
        ] do
      assert {:ok, %{"disposition" => "evaluated_rejected"}} =
               DecisionMetrics.selection(base, changed, gates())
    end

    assert {:ok, %{"disposition" => "evaluated_rejected"}} =
             DecisionMetrics.selection(base, candidate, %{gates() | "protocol" => "fail"})
  end

  test "mismatched denominators, invalid counts and missing evidence refuse" do
    base = baseline()

    for invalid <- [
          %{base | "cases" => 101},
          %{base | "critical_total" => 9},
          %{base | "citation_supported" => 101},
          %{base | "abstentions" => 101},
          Map.delete(base, "p95_ms"),
          Map.put(base, "extra", true)
        ] do
      assert {:error, :invalid_decision_metrics} =
               DecisionMetrics.selection(base, invalid, gates())
    end

    assert {:error, :invalid_decision_metrics} =
             DecisionMetrics.selection(base, base, Map.delete(gates(), "protocol"))

    assert {:ok, %{"disposition" => "unverified"}} =
             DecisionMetrics.selection(
               %{base | "critical_total" => 0, "critical_recalled" => 0},
               %{base | "critical_total" => 0, "critical_recalled" => 0, "supported" => 85},
               gates()
             )
  end

  test "paired critical outcomes expose a loss hidden by equal aggregate counts" do
    queries = [
      %{"query_id" => "a", "applicable" => true},
      %{"query_id" => "b", "applicable" => true}
    ]

    baseline = [
      %{"query_id" => "a", "status" => "ok", "value" => 1},
      %{"query_id" => "b", "status" => "ok", "value" => 0}
    ]

    candidate = [
      %{"query_id" => "a", "status" => "ok", "value" => 0},
      %{"query_id" => "b", "status" => "ok", "value" => 1}
    ]

    assert {:ok,
            %{"status" => "fail", "regressed_query_ids" => ["a"], "unverified" => 0} = paired} =
             DecisionMetrics.critical_pairs(queries, baseline, candidate)

    assert {:ok,
            %{
              "disposition" => "evaluated_rejected",
              "criteria" => %{"critical_recall" => "pass", "hard_gates" => "fail"}
            }} =
             DecisionMetrics.selection(baseline(), %{baseline() | "supported" => 85}, %{
               gates()
               | "paired_critical" => paired["status"]
             })

    assert {:ok, %{"status" => "pass", "regressed_query_ids" => []}} =
             DecisionMetrics.critical_pairs(queries, baseline, baseline)

    assert {:ok, %{"status" => "unverified", "unverified" => 1}} =
             DecisionMetrics.critical_pairs(queries, baseline, tl(candidate))

    assert {:ok, %{"status" => "unverified"}} =
             DecisionMetrics.critical_pairs(queries, baseline, [
               Map.put(hd(candidate), "status", "timeout") | tl(candidate)
             ])

    assert {:error, :invalid_decision_metrics} =
             DecisionMetrics.critical_pairs(queries, baseline, [hd(candidate), hd(candidate)])

    assert {:error, :invalid_decision_metrics} =
             DecisionMetrics.critical_pairs(queries, baseline, [
               Map.put(hd(candidate), "value", 2),
               List.last(candidate)
             ])
  end

  test "assessment enforces false-durable reduction and capture nonregression at exact thresholds" do
    baseline = %{
      "candidates" => 200,
      "abstentions" => 4,
      "false_total" => 50,
      "false_durable" => 10,
      "useful_total" => 100,
      "useful_kept" => 95,
      "critical_total" => 50,
      "critical_kept" => 45,
      "p95_ms" => 1000
    }

    candidate = %{
      baseline
      | "false_durable" => 8,
        "useful_kept" => 93,
        "critical_kept" => 44,
        "p95_ms" => 1200
    }

    gates = Map.new(~w(protocol matched_workload finite_cost_cap), &{&1, "pass"})

    assert {:ok,
            %{
              "disposition" => "useful_candidate",
              "abstentions" => %{"baseline" => 4, "candidate" => 4, "denominator" => 200}
            }} =
             DecisionMetrics.assessment(baseline, candidate, gates)

    for changed <- [
          %{candidate | "false_durable" => 9},
          %{candidate | "useful_kept" => 92},
          %{candidate | "critical_kept" => 43},
          %{candidate | "p95_ms" => 1201}
        ] do
      assert {:ok, %{"disposition" => "evaluated_rejected"}} =
               DecisionMetrics.assessment(baseline, changed, gates)
    end

    assert {:ok, %{"disposition" => "unverified"}} =
             DecisionMetrics.assessment(baseline, candidate, %{
               gates
               | "finite_cost_cap" => "unverified"
             })

    assert {:error, :invalid_decision_metrics} =
             DecisionMetrics.assessment(baseline, %{candidate | "useful_total" => 101}, gates)

    assert {:ok, %{"disposition" => "unverified"}} =
             DecisionMetrics.assessment(
               %{baseline | "false_durable" => 0},
               %{candidate | "false_durable" => 0},
               gates
             )
  end

  test "assessment accepts independently defined aggregate labels" do
    aggregate = %{
      "candidates" => 100,
      "abstentions" => 0,
      "false_total" => 60,
      "false_durable" => 10,
      "useful_total" => 60,
      "useful_kept" => 20,
      "critical_total" => 80,
      "critical_kept" => 40,
      "p95_ms" => 100
    }

    gates = Map.new(~w(protocol matched_workload finite_cost_cap), &{&1, "pass"})
    assert {:ok, _} = DecisionMetrics.assessment(aggregate, aggregate, gates)
  end
end
