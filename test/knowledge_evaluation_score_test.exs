Code.require_file("../examples/knowledge/evaluation_score.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationScoreTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.EvaluationScore, as: Score

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp source(project \\ "p"),
    do: %{
      "project" => project,
      "source_id" => "source",
      "generation" => 1,
      "version" => 1,
      "sha256" => sha("source")
    }

  defp span,
    do: %{
      "span_id" => "s",
      "source" => source(),
      "start_byte" => 10,
      "end_byte" => 19,
      "quote" => "a café z"
    }

  defp prediction(extra \\ %{}) do
    Map.merge(
      %{
        "version" => 2,
        "prediction_id" => "prediction",
        "variant" => "base",
        "query_id" => "q",
        "project" => "p",
        "attempt" => 1,
        "status" => "ok",
        "top_k" => 10,
        "predicted_class" => "answer",
        "response_kind" => "answer",
        "answer" => "A café.",
        "claims" => [%{"claim_id" => "c", "text" => "A café."}],
        "evidence" => [span()],
        "context_evidence" => [],
        "citations" => [%{"citation_id" => "pair", "claim_id" => "c", "span_id" => "s"}]
      },
      extra
    )
  end

  defp inputs(
         rows \\ [prediction()],
         queries \\ [%{"query_id" => "q", "project" => "p"}],
         variants \\ ["base"]
       ) do
    bytes = Enum.map_join(rows, "\n", &JSON.encode!/1) <> "\n"

    freeze = %{
      "version" => 1,
      "metric_version" => 1,
      "variants" => variants,
      "baseline" => "base",
      "queries" => queries,
      "files" => [%{"id" => "predictions", "sha256" => sha(bytes)}],
      "classification_map" => Map.new(~w(answer conflict open abstain), &{&1, &1})
    }

    {freeze, %{"predictions" => bytes}}
  end

  test "legacy rows and uncontained context spans refuse before loading labels" do
    cropped = %{
      span()
      | "span_id" => "a",
        "start_byte" => 12,
        "end_byte" => 17,
        "quote" => "café"
    }

    invalid_contexts = [
      %{cropped | "source" => source("foreign")},
      %{cropped | "quote" => "cafX"},
      %{cropped | "start_byte" => 30, "end_byte" => 35},
      %{cropped | "span_id" => "s"}
    ]

    rows = [
      prediction(%{"version" => 1})
      | Enum.map(invalid_contexts, &prediction(%{"context_evidence" => [&1]}))
    ]

    owner = self()

    loader = fn ->
      send(owner, :labels_opened)
      {:error, :must_not_open}
    end

    for row <- rows do
      {freeze, blobs} = inputs([row])
      assert {:error, :invalid_prediction} = Score.score(freeze, blobs, loader, loader)
      refute_received :labels_opened
    end
  end

  defp labels(relevance \\ nil) do
    relevance =
      relevance ||
        [
          %{
            "source" => source(),
            "grade" => 1,
            "start_byte" => 12,
            "end_byte" => 17,
            "quote" => "café"
          }
        ]

    %{
      "version" => 1,
      "queries" => [
        %{
          "query_id" => "q",
          "project" => "p",
          "expected_class" => "answer",
          "expected_refusal" => false,
          "relevance" => relevance
        }
      ]
    }
  end

  defp reviews(extra \\ %{}) do
    Map.merge(
      %{
        "version" => 1,
        "integrity" => [
          %{
            "prediction_id" => "prediction",
            "span_id" => "s",
            "verdict" => "valid",
            "reviewer_id" => "literal-checker",
            "independent" => true
          }
        ],
        "semantic" => [
          %{
            "prediction_id" => "prediction",
            "verdict" => "supported",
            "reviewer_id" => "semantic-reviewer",
            "independent" => true,
            "citations" => [%{"citation_id" => "pair", "verdict" => "supported"}]
          }
        ]
      },
      extra
    )
  end

  defp score(rows \\ [prediction()], label \\ labels(), review \\ reviews()) do
    {freeze, blobs} = inputs(rows)
    Score.score(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review} end)
  end

  test "every raw hash and row is checked before either label or review loader" do
    {freeze, blobs} = inputs()

    loader = fn ->
      send(self(), :labels_opened)
      {:ok, labels()}
    end

    review = fn ->
      send(self(), :reviews_opened)
      {:ok, reviews()}
    end

    assert {:error, :prediction_hash_mismatch} =
             Score.score(freeze, Map.put(blobs, "predictions", "{}\n"), loader, review)

    refute_received :labels_opened
    refute_received :reviews_opened

    malformed =
      String.replace(blobs["predictions"], "\"attempt\":1", "\"attempt\":1,\"attempt\":1")

    frozen = put_in(freeze, ["files", Access.at(0), "sha256"], sha(malformed))

    assert {:error, :duplicate_prediction_key} =
             Score.score(frozen, %{"predictions" => malformed}, loader, review)

    refute_received :labels_opened
    refute_received :reviews_opened

    {duplicates, raw} = inputs([prediction(), prediction()])
    assert {:error, :duplicate_prediction} = Score.score(duplicates, raw, loader, review)
    refute_received :labels_opened
    {second, raw} = inputs([prediction(%{"attempt" => 2})])
    assert {:error, :invalid_prediction} = Score.score(second, raw, loader, review)
    refute_received :labels_opened
    {reserved, raw} = inputs([prediction(%{"prediction_id" => "missing:collision"})])
    assert {:error, :invalid_prediction} = Score.score(reserved, raw, loader, review)
    refute_received :labels_opened
  end

  test "literal coordinate coverage, classification and semantic support remain separate" do
    assert {:ok, report} = score()
    assert report["quality_gates_passed"]
    assert report["semantic"]["support"]["total_n"] == 1
    [variant] = report["variants"]
    [row] = variant["rows"]
    assert row["retrieval"]["recall_at_5"] == 1.0
    assert row["spans"]["exact_recall"] == 0.0
    assert row["spans"]["contained_recall"] == 1.0
    assert variant["classification"]["accuracy"] == 1.0
    assert variant["gates"]["support"]["status"] == "pass"
    assert variant["gates"]["citation"]["status"] == "pass"

    negative =
      put_in(reviews(), ["semantic", Access.at(0), "verdict"], "unsupported")
      |> put_in(["semantic", Access.at(0), "citations", Access.at(0), "verdict"], "unsupported")

    assert {:ok, unsupported} = score([prediction()], labels(), negative)
    [variant] = unsupported["variants"]
    assert hd(variant["rows"])["spans"]["contained_recall"] == 1.0
    assert variant["gates"]["support"]["status"] == "fail"
    assert variant["gates"]["citation"]["status"] == "fail"
    refute unsupported["quality_gates_passed"]
    assert unsupported["outside_scoring"]["authority"] == "unmeasured"
  end

  test "cropped answer citations do not replace the saved retrieval ranking or span measurement" do
    answer_span = %{
      span()
      | "span_id" => "answer",
        "start_byte" => 12,
        "end_byte" => 17,
        "quote" => "café"
    }

    row =
      prediction(%{
        "version" => 2,
        "context_evidence" => [answer_span],
        "citations" => [%{"citation_id" => "pair", "claim_id" => "c", "span_id" => "answer"}]
      })

    review =
      update_in(
        reviews(),
        ["integrity"],
        &(&1 ++
            [
              %{
                "prediction_id" => "prediction",
                "span_id" => "answer",
                "verdict" => "valid",
                "reviewer_id" => "literal-checker",
                "independent" => true
              }
            ])
      )

    assert {:ok, report} = score([row], labels(), review)
    [variant] = report["variants"]
    [measured] = variant["rows"]
    assert measured["prediction"]["evidence"] == [span()]
    assert measured["retrieval"]["recall_at_5"] == 1.0
    assert measured["spans"]["exact_recall"] == 0.0
    assert measured["spans"]["contained_recall"] == 1.0
    assert variant["semantic"]["citation"]["precision"] == 1.0
    assert length(measured["integrity"]) == 2
  end

  test "missing rows and N-A queries stay in the frozen grid and cannot pass semantic gates" do
    queries = [%{"query_id" => "q", "project" => "p"}, %{"query_id" => "empty", "project" => "p"}]
    {freeze, blobs} = inputs([prediction()], queries, ["base", "other"])

    label =
      update_in(
        labels(),
        ["queries"],
        &(&1 ++
            [
              %{
                "query_id" => "empty",
                "project" => "p",
                "expected_class" => "abstain",
                "expected_refusal" => false,
                "relevance" => []
              }
            ])
      )

    assert {:ok, report} =
             Score.score(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, reviews()} end)

    [base, other] = report["variants"]
    assert report["semantic"]["support"]["total_n"] == 4
    refute report["quality_gates_passed"]
    assert length(base["rows"]) == 2 and length(other["rows"]) == 2
    assert hd(other["rows"])["missing"]
    assert hd(other["rows"])["retrieval"]["recall_at_5"] == 0.0
    assert is_nil(List.last(other["rows"])["retrieval"]["recall_at_5"])
    assert other["summary"]["recall_at_5"]["not_applicable_n"] == 1
    assert other["classification"]["confusion"]["answer"]["execution_failure"] == 1
    refute other["gates"]["support"]["status"] == "pass"
    refute base["gates"]["support"]["status"] == "pass"
  end

  test "complete workload citation threshold is inclusive and per-variant negatives remain visible" do
    queries = for i <- 1..10, do: %{"query_id" => "q#{i}", "project" => "p"}

    rows =
      for variant <- ~w(base other),
          q <- queries,
          do:
            prediction(%{
              "prediction_id" => variant <> q["query_id"],
              "variant" => variant,
              "query_id" => q["query_id"]
            })

    {freeze, blobs} = inputs(rows, queries, ~w(base other))

    label = %{
      labels()
      | "queries" =>
          Enum.map(queries, &Map.put(hd(labels()["queries"]), "query_id", &1["query_id"]))
    }

    review = fn negative_count ->
      %{
        "version" => 1,
        "integrity" =>
          Enum.map(rows, fn p ->
            %{hd(reviews()["integrity"]) | "prediction_id" => p["prediction_id"]}
          end),
        "semantic" =>
          rows
          |> Enum.with_index()
          |> Enum.map(fn {p, i} ->
            verdict = if i >= 20 - negative_count, do: "unsupported", else: "supported"

            %{
              hd(reviews()["semantic"])
              | "prediction_id" => p["prediction_id"],
                "verdict" => verdict,
                "citations" => [%{"citation_id" => "pair", "verdict" => verdict}]
            }
          end)
      }
    end

    assert {:ok, passed} =
             Score.score(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review.(1)} end)

    assert passed["quality_gate_scope"] == "complete_frozen_grid"
    assert passed["quality_gates_passed"] and passed["semantic"]["support"]["total_n"] == 20
    assert passed["gates"]["citation"]["value"] == 0.95
    assert List.last(passed["variants"])["gates"]["citation"]["status"] == "fail"

    assert {:ok, failed} =
             Score.score(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review.(2)} end)

    refute failed["quality_gates_passed"]
    assert failed["gates"]["support"]["status"] == "pass"
    assert failed["gates"]["citation"]["status"] == "fail"
  end

  test "failed rankings keep observed metrics but primary utility and classification fail" do
    assert {:ok, report} = score([prediction(%{"status" => "partial"})])
    [variant] = report["variants"]
    [row] = variant["rows"]
    assert row["retrieval"]["recall_at_5"] == 0.0
    assert row["retrieval"]["observed_recall_at_5"] == 1.0
    assert row["spans"]["contained_recall"] == 0.0
    assert row["spans"]["observed_contained_recall"] == 1.0
    assert variant["classification"]["accuracy"] == 0.0
    assert row["classification"]["scored_predicted"] == "execution_failure"
  end

  test "exact spans count once and retrieval-only responses never become supported answers" do
    exact = span() |> Map.delete("span_id") |> Map.put("grade", 1)
    assert {:ok, report} = score([prediction()], labels([exact, exact]))
    [row] = hd(report["variants"])["rows"]
    assert row["spans"]["relevant_n"] == 1
    assert row["spans"]["exact_recall"] == 1.0

    retrieval =
      prediction(%{
        "predicted_class" => nil,
        "response_kind" => "retrieval_only",
        "answer" => nil,
        "claims" => [],
        "citations" => []
      })

    assert {:ok, report} = score([retrieval], labels(), reviews(%{"semantic" => []}))
    [variant] = report["variants"]
    assert hd(variant["rows"])["retrieval"]["recall_at_5"] == 1.0
    assert variant["gates"]["support"]["status"] == "unmeasured"
    assert variant["gates"]["citation"]["status"] == "unmeasured"
  end

  test "foreign rows and nested over-limit JSON refuse before labels are loaded" do
    loader = fn -> flunk("invalid predictions must not open labels") end
    {freeze, blobs} = inputs([prediction(%{"project" => "foreign"})])
    assert {:error, :invalid_prediction} = Score.score(freeze, blobs, loader, loader)

    {freeze, _} = inputs()

    bytes =
      ~s({"extra":) <> String.duplicate("[", 13) <> "0" <> String.duplicate("]", 13) <> "}\n"

    freeze = put_in(freeze, ["files", Access.at(0), "sha256"], sha(bytes))

    assert {:error, :prediction_depth_limit} =
             Score.score(freeze, %{"predictions" => bytes}, loader, loader)
  end

  test "coordinate mismatch, foreign evidence and absent independent review never gain support from a quote" do
    wrong_coordinates =
      put_in(labels(), ["queries", Access.at(0), "relevance", Access.at(0), "start_byte"], 11)
      |> put_in(["queries", Access.at(0), "relevance", Access.at(0), "end_byte"], 16)

    assert {:ok, report} = score([prediction()], wrong_coordinates)
    assert hd(hd(report["variants"])["rows"])["spans"]["contained_recall"] == 0.0

    foreign = put_in(prediction(), ["evidence", Access.at(0), "source"], source("other"))
    assert {:ok, report} = score([foreign])
    [variant] = report["variants"]
    assert hd(hd(variant["rows"])["integrity"])["verdict"] == "invalid"
    assert variant["gates"]["citation"]["status"] == "fail"

    assert {:ok, report} =
             score([prediction()], labels(), reviews(%{"semantic" => [], "integrity" => []}))

    [variant] = report["variants"]
    assert is_nil(hd(variant["rows"])["spans"]["contained_recall"])
    assert variant["gates"]["citation"]["status"] == "unmeasured"
    assert variant["gates"]["support"]["status"] == "unmeasured"
  end
end
