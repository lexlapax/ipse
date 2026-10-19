Code.require_file("../examples/knowledge/metrics.exs", __DIR__)

defmodule Ipse.KnowledgeMetricsTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Metrics, as: M

  defp source(id, extra \\ %{}) do
    Map.merge(
      %{
        "project" => "project-a",
        "source_id" => id,
        "generation" => 1,
        "version" => 1,
        "sha256" => Base.encode16(:crypto.hash(:sha256, id), case: :lower)
      },
      extra
    )
  end

  defp prediction(id, extra \\ %{}) do
    Map.merge(
      %{
        "prediction_id" => id,
        "query_id" => "q-" <> id,
        "status" => "ok",
        "response_kind" => "answer",
        "expected_refusal" => false,
        "citations" => [%{"citation_id" => "pair", "integrity" => "valid"}]
      },
      extra
    )
  end

  defp review(id, extra \\ %{}) do
    Map.merge(
      %{
        "prediction_id" => id,
        "verdict" => "supported",
        "reviewer_id" => "independent-reviewer",
        "independent" => true,
        "citations" => [%{"citation_id" => "pair", "verdict" => "supported"}]
      },
      extra
    )
  end

  test "source ranking collapses duplicate chunks, takes maximum qrel grades and uses full ideal ranking" do
    [a, b, c, d] = Enum.map(~w(a b c d), &source/1)

    qrels = [
      %{"source" => a, "grade" => 1},
      %{"source" => a, "grade" => 3},
      %{"source" => b, "grade" => 2},
      %{"source" => c, "grade" => 0},
      %{"source" => d, "grade" => 1}
    ]

    {:ok, r} =
      M.retrieval(%{"status" => "ok", "ranked_sources" => [a, a, b, c], "top_k" => 10}, qrels)

    assert r["relevant_sources"] == 3 and r["retrieved_sources"] == 3
    assert_in_delta r["recall_at_5"], 2 / 3, 1.0e-12
    expected = (7 + 3 / :math.log2(3)) / (7 + 3 / :math.log2(3) + 1 / :math.log2(4))
    assert_in_delta r["ndcg_at_10"], expected, 1.0e-12
    refute r["failed"]
    wrong_project = Map.put(a, "project", "project-b")
    wrong_generation = Map.put(a, "generation", 2)
    wrong_version = Map.put(a, "version", 2)
    wrong_sha = Map.put(a, "sha256", String.duplicate("0", 64))

    {:ok, foreign} =
      M.retrieval(
        %{
          "status" => "ok",
          "ranked_sources" => [wrong_project, wrong_generation, wrong_version, wrong_sha],
          "top_k" => 10
        },
        [%{"source" => a, "grade" => 1}]
      )

    assert foreign["recall_at_5"] == 0 and foreign["ndcg_at_10"] == 0
  end

  test "empty relevance is N-A and insufficient requested ranks never become nDCG at10" do
    a = source("a")

    for qrels <- [[], [%{"source" => a, "grade" => 0}]] do
      {:ok, r} = M.retrieval(%{"status" => "ok", "ranked_sources" => [a], "top_k" => 10}, qrels)
      assert is_nil(r["recall_at_5"]) and is_nil(r["ndcg_at_10"])
      assert r["recall_reason"] == "no_relevant_sources"
    end

    {:ok, small} =
      M.retrieval(%{"status" => "ok", "ranked_sources" => [a], "top_k" => 5}, [
        %{"source" => a, "grade" => 1}
      ])

    assert small["recall_at_5"] == 1.0
    assert is_nil(small["ndcg_at_10"]) and small["ndcg_reason"] == "insufficient_rank_capacity"

    {:ok, tiny} =
      M.retrieval(%{"status" => "ok", "ranked_sources" => [a], "top_k" => 1}, [
        %{"source" => a, "grade" => 1}
      ])

    assert is_nil(tiny["recall_at_5"])

    assert {:error, :invalid_retrieval_input} =
             M.retrieval(%{"status" => "ok", "ranked_sources" => [a], "top_k" => 10}, [
               %{"source" => a, "grade" => -1}
             ])
  end

  test "failed and partial retrieval rows score zero without discarding observed ranking" do
    a = source("a")

    for status <- ~w(partial failed refused timeout unavailable missing cancelled) do
      {:ok, r} =
        M.retrieval(%{"status" => status, "ranked_sources" => [a], "top_k" => 10}, [
          %{"source" => a, "grade" => 1}
        ])

      assert r["status"] == status and r["failed"]
      assert r["recall_at_5"] == 0 and r["ndcg_at_10"] == 0
      assert r["observed_recall_at_5"] == 1 and r["observed_ndcg_at_10"] == 1
    end
  end

  test "nearest-rank quantiles retain measured failure and timeout lower bounds" do
    assert {:ok, 10} = M.nearest_rank(Enum.to_list(1..20), 0.5)
    assert {:ok, 19} = M.nearest_rank(Enum.to_list(1..20), 0.95)
    assert {:ok, 1} = M.nearest_rank([2, 1], 0.5)
    assert {:ok, nil} = M.nearest_rank([], 0.95)
    assert {:error, :invalid_percentile_input} = M.nearest_rank([1], 0)

    samples = [
      %{"status" => "ok", "elapsed_ms" => 1, "censored" => false},
      %{"status" => "timeout", "elapsed_ms" => 100, "censored" => true},
      %{"status" => "failed", "elapsed_ms" => 200, "censored" => false},
      %{"status" => "unavailable", "elapsed_ms" => nil, "censored" => false}
    ]

    {:ok, r} = M.latency(samples)
    assert r["p50_ms"] == 100 and r["p95_ms"] == 200

    assert Map.take(r, ~w(total_n measured_n censored_n missing_n failed_n)) == %{
             "total_n" => 4,
             "measured_n" => 3,
             "censored_n" => 1,
             "missing_n" => 1,
             "failed_n" => 3
           }

    assert r["quantile_basis"] == "observed_elapsed_including_censored_lower_bounds"
    assert {:ok, %{"p50_ms" => nil, "p95_ms" => nil}} = M.latency([])

    assert {:error, :invalid_latency_input} =
             M.latency([%{"status" => "ok", "elapsed_ms" => -1, "censored" => false}])
  end

  test "paired comparisons keep declared queries, failed saved values, missing rows and N-A" do
    queries =
      Enum.map(~w(q1 q2 q3), &%{"query_id" => &1, "applicable" => true}) ++
        [%{"query_id" => "q4", "applicable" => false}]

    left = [
      %{"query_id" => "q1", "status" => "ok", "value" => 0.8},
      %{"query_id" => "q2", "status" => "partial", "value" => 1.0},
      %{"query_id" => "q3", "status" => "ok", "value" => 0.4}
    ]

    right = [
      %{"query_id" => "q1", "status" => "ok", "value" => 0.5},
      %{"query_id" => "q2", "status" => "ok", "value" => 0.2},
      %{"query_id" => "q4", "status" => "ok", "value" => nil}
    ]

    {:ok, r} = M.paired(queries, left, right)
    assert length(r["rows"]) == 4 and r["eligible_n"] == 3 and r["not_applicable_n"] == 1
    assert r["measured_pairs_n"] == 3 and r["complete"]
    assert_in_delta r["mean_delta"], (-0.3 + 0.2 - 0.4) / 3, 1.0e-12
    [_, partial, missing, na] = r["rows"]
    assert partial["baseline"]["value"] == 1 and partial["baseline"]["scored_value"] == 0
    assert missing["variant"]["status"] == "missing" and missing["delta"] == -0.4
    assert na["reason"] == "not_applicable" and is_nil(na["delta"])
    incomplete = put_in(left, [Access.at(0), "value"], nil)
    {:ok, unmeasured} = M.paired(queries, incomplete, right)
    refute unmeasured["complete"]
    assert is_nil(unmeasured["mean_delta"]) and unmeasured["unmeasured_pairs_n"] == 1
    assert {:error, :invalid_paired_input} = M.paired(queries, left ++ [hd(left)], right)

    assert {:error, :invalid_paired_input} =
             M.paired(queries, left, [%{"query_id" => "foreign", "status" => "ok", "value" => 1}])
  end

  test "independent explicit reviews count failed predictions and invalid literal citations" do
    predictions = [
      prediction("a"),
      prediction("b", %{
        "status" => "partial",
        "citations" => [%{"citation_id" => "pair", "integrity" => "invalid"}]
      }),
      prediction("c", %{
        "status" => "refused",
        "response_kind" => "abstention",
        "expected_refusal" => true,
        "citations" => []
      })
    ]

    reviews = [
      review("a"),
      review("b"),
      review("c", %{"verdict" => "correct_abstention", "citations" => []})
    ]

    {:ok, r} = M.semantic(predictions, reviews)
    assert r["review_complete"] and r["support"]["complete"] and r["citation"]["complete"]
    assert r["support"]["total_n"] == 3 and r["support"]["correct_n"] == 2
    assert_in_delta r["support"]["accuracy"], 2 / 3, 1.0e-12
    assert r["citation"]["total_n"] == 2 and r["citation"]["invalid_n"] == 1
    assert r["citation"]["precision"] == 0.5
    [_, b, _] = r["rows"]
    refute b["support_correct"]
    refute hd(b["citations"])["supported"]
  end

  test "missing or non-independent verdicts and unmeasured integrity prevent complete quality" do
    p = prediction("a")

    for reviews <- [
          [],
          [review("a", %{"independent" => false})],
          [review("a", %{"verdict" => "unmeasured", "citations" => []})]
        ] do
      {:ok, r} = M.semantic([p], reviews)
      assert is_nil(r["support"]["accuracy"]) and is_nil(r["citation"]["precision"])
      assert r["support"]["total_n"] == 1 and r["citation"]["total_n"] == 1
      assert r["support"]["unmeasured_n"] == 1 and r["citation"]["unmeasured_n"] == 1
    end

    unknown = put_in(p, ["citations", Access.at(0), "integrity"], "unmeasured")
    {:ok, r} = M.semantic([unknown], [review("a")])
    assert is_nil(r["citation"]["precision"]) and r["citation"]["unmeasured_n"] == 1
    assert {:error, :invalid_semantic_input} = M.semantic([p], [review("foreign")])

    assert {:error, :invalid_semantic_input} =
             M.semantic([p], [
               review("a", %{
                 "citations" => [%{"citation_id" => "fabricated", "verdict" => "supported"}]
               })
             ])

    assert {:error, :invalid_semantic_input} = M.semantic([p], [review("a"), review("a")])
  end

  test "retrieval-only and empty citations stay unmeasured even with complete review records" do
    p = prediction("a", %{"response_kind" => "retrieval_only", "citations" => []})
    {:ok, r} = M.semantic([p], [review("a", %{"verdict" => "unmeasured", "citations" => []})])
    assert r["review_complete"]
    assert r["support"]["retrieval_only_n"] == 1 and is_nil(r["support"]["accuracy"])
    assert r["citation"]["total_n"] == 0 and is_nil(r["citation"]["precision"])
    assert r["citation"]["reason"] == "no_citation_pairs"

    assert {:error, :invalid_semantic_input} =
             M.semantic([p], [review("a", %{"citations" => []})])

    {:ok, empty} = M.semantic([], [])
    assert empty["support"]["reason"] == "no_predictions"
    assert is_nil(empty["support"]["accuracy"])
  end

  test "an empty failed answer counts as zero with independent review; retrieval-only stays unmeasured" do
    failed = prediction("failed", %{"status" => "failed", "citations" => []})
    judged = review("failed", %{"verdict" => "unsupported", "citations" => []})
    assert {:ok, result} = M.semantic([failed], [judged])
    assert result["support"]["total_n"] == 1
    assert result["support"]["measured_n"] == 1
    assert result["support"]["correct_n"] == 0
    assert result["support"]["accuracy"] == 0.0
    refute result["citation"]["complete"]

    retrieval = %{failed | "response_kind" => "retrieval_only"}
    review = %{judged | "verdict" => "unmeasured"}
    assert {:ok, result} = M.semantic([retrieval], [review])
    assert result["support"]["retrieval_only_n"] == 1
    assert result["support"]["measured_n"] == 0
    assert result["support"]["accuracy"] == nil
  end

  test "separate claim-span pairs are not collapsed when they cite the same passage" do
    p =
      prediction("a", %{
        "citations" => [
          %{"citation_id" => "claim-one-span", "integrity" => "valid"},
          %{"citation_id" => "claim-two-span", "integrity" => "valid"}
        ]
      })

    r =
      review("a", %{
        "citations" => [
          %{"citation_id" => "claim-one-span", "verdict" => "supported"},
          %{"citation_id" => "claim-two-span", "verdict" => "unsupported"}
        ]
      })

    {:ok, metrics} = M.semantic([p], [r])
    assert metrics["citation"]["total_n"] == 2
    assert metrics["citation"]["precision"] == 0.5

    assert {:error, :invalid_semantic_input} =
             M.semantic([p], [Map.put(r, "citations", [hd(r["citations"]), hd(r["citations"])])])
  end
end
