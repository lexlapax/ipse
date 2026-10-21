Code.require_file("../dev/evaluation/score.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationScoreTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Evaluation.Score, as: Score

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp body, do: "..........a café z.........."

  defp corpus do
    document =
      Map.merge(source(), %{
        "document_id" => "doc",
        "title" => "Source",
        "text" => body(),
        "byte_length" => byte_size(body()),
        "created_at" => "2026-01-01T00:00:00Z",
        "observed_at" => "2026-01-01T00:00:00Z",
        "state" => "current",
        "media_type" => "text/plain"
      })

    JSON.encode!(%{"schema_version" => 1, "documents" => [document]})
  end

  defp score_with_corpus(freeze, blobs, labels, reviews),
    do: Score.score(freeze, blobs, labels, reviews, fn -> {:ok, corpus()} end)

  defp source(project \\ "p"),
    do: %{
      "project" => project,
      "source_id" => "source",
      "generation" => 1,
      "version" => 1,
      "sha256" => sha(body())
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
      "version" => 2,
      "context_sha256" => sha("synthetic scoring context"),
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
      assert {:error, :invalid_prediction} = score_with_corpus(freeze, blobs, loader, loader)
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
        "version" => 2,
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
    review = bind_fixture_review(freeze, blobs, review)
    score_with_corpus(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review} end)
  end

  defp bind_fixture_review(freeze, blobs, review) do
    {:ok, verified} = Score.verified_predictions(freeze, blobs)
    Map.put(review, "review_binding_sha256", verified["review_binding_sha256"])
  end

  defp qualification_inputs(support \\ 45, citations \\ 95) do
    variants = ~w(lexical graph_explicit graph_model dense hybrid rerank research)
    queries = for i <- 1..50, do: %{"query_id" => "q#{i}", "project" => "p"}

    rows =
      for variant <- variants, q <- queries do
        prediction(%{
          "prediction_id" => variant <> "-" <> q["query_id"],
          "variant" => variant,
          "query_id" => q["query_id"],
          "claims" => [
            %{"claim_id" => "c1", "text" => "A café."},
            %{"claim_id" => "c2", "text" => "A café."}
          ],
          "citations" => [
            %{"citation_id" => "pair1", "claim_id" => "c1", "span_id" => "s"},
            %{"citation_id" => "pair2", "claim_id" => "c2", "span_id" => "s"}
          ]
        })
      end

    {old, blobs} = inputs(rows, queries, variants)

    freeze =
      old
      |> Map.put("version", 3)
      |> Map.put("baseline", "lexical")
      |> Map.put("contracts", %{
        "outputs" => %{
          "answer" => "json_schema_v2",
          "extract" => "json_schema_v2",
          "rerank" => "json_schema_v2"
        },
        "selection" => "per_strategy_eligibility_v1"
      })

    label = %{
      labels()
      | "queries" =>
          Enum.map(queries, &Map.put(hd(labels()["queries"]), "query_id", &1["query_id"]))
    }

    semantic =
      for row <- rows do
        index = row["query_id"] |> String.trim_leading("q") |> String.to_integer()

        verdict =
          if row["variant"] == "lexical" and index <= support,
            do: "supported",
            else: "unsupported"

        pairs =
          for pair <- 1..2 do
            positive = row["variant"] == "lexical" and (index - 1) * 2 + pair <= citations

            %{
              "citation_id" => "pair#{pair}",
              "verdict" => if(positive, do: "supported", else: "unsupported")
            }
          end

        %{
          hd(reviews()["semantic"])
          | "prediction_id" => row["prediction_id"],
            "verdict" => verdict,
            "citations" => pairs
        }
      end

    review =
      reviews(%{"integrity" => [], "semantic" => semantic})
      |> then(&bind_fixture_review(freeze, blobs, &1))

    {freeze, blobs, label, review, rows}
  end

  test "individual qualification keeps all350 firsts and rejects weaker strategies at inclusive thresholds" do
    {freeze, blobs, label, review, _} = qualification_inputs()

    assert {:ok, report} =
             score_with_corpus(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review} end)

    assert report["version"] == 2 and
             report["quality_gate_scope"] == "per_strategy_eligibility_v1"

    assert report["complete_first_grid"] and report["complete_review"] and
             report["quality_gates_passed"]

    assert report["eligible_variants"] == ["lexical"]
    assert Enum.map(report["disqualified_variants"], & &1["variant"]) == tl(freeze["variants"])
    assert Enum.sum(Enum.map(report["variants"], &length(&1["rows"]))) == 350
    [lexical | _] = report["variants"]
    assert lexical["gates"]["support"]["value"] == 0.90
    assert lexical["gates"]["citation"]["value"] == 0.95
    assert report["gates"]["support"]["status"] == "fail"
    assert report["gates"]["citation"]["status"] == "fail"
    refute Map.has_key?(report, "selected_variant")

    old = freeze |> Map.put("version", 2) |> Map.delete("contracts")
    old_review = bind_fixture_review(old, blobs, review)

    assert {:ok, historical} =
             score_with_corpus(old, blobs, fn -> {:ok, label} end, fn -> {:ok, old_review} end)

    assert historical["version"] == 1 and
             historical["quality_gate_scope"] == "complete_frozen_grid"

    refute historical["quality_gates_passed"]

    for {support, citations} <- [{44, 95}, {45, 94}] do
      {freeze, blobs, label, review, _} = qualification_inputs(support, citations)

      assert {:ok, failed} =
               score_with_corpus(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review} end)

      assert failed["complete_first_grid"] and failed["complete_review"]
      assert failed["eligible_variants"] == []
      refute failed["quality_gates_passed"]
    end
  end

  test "a qualifier cannot hide missing first outcomes or unmeasured weaker-strategy answers" do
    {freeze, _, label, review, rows} = qualification_inputs()

    for changed <- [
          Enum.drop(rows, -1),
          List.update_at(rows, -1, &Map.put(&1, "status", "missing"))
        ] do
      {declared, blobs} = inputs(changed, freeze["queries"], freeze["variants"])
      declared = Map.merge(declared, Map.take(freeze, ~w(version contracts baseline)))
      ids = MapSet.new(changed, & &1["prediction_id"])

      filtered =
        update_in(
          review,
          ["semantic"],
          &Enum.filter(&1, fn row -> MapSet.member?(ids, row["prediction_id"]) end)
        )

      bound = bind_fixture_review(declared, blobs, filtered)

      assert {:ok, report} =
               score_with_corpus(declared, blobs, fn -> {:ok, label} end, fn -> {:ok, bound} end)

      assert report["eligible_variants"] == ["lexical"]
      refute report["complete_first_grid"] or report["quality_gates_passed"]
      assert Enum.sum(Enum.map(report["variants"], &length(&1["rows"]))) == 350
    end

    {freeze, blobs, label, review, _} = qualification_inputs()

    unmeasured =
      update_in(review, ["semantic", Access.at(-1), "verdict"], fn _ -> "unmeasured" end)

    assert {:ok, report} =
             score_with_corpus(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, unmeasured} end)

    assert report["eligible_variants"] == ["lexical"] and report["complete_first_grid"]
    refute report["complete_review"] or report["quality_gates_passed"]
  end

  defp qualification_failures(count) do
    {freeze, _, label, review, rows} = qualification_inputs(50, 100)

    changed =
      Enum.with_index(rows, fn row, index ->
        if index < count do
          Map.merge(row, %{
            "status" => "failed",
            "predicted_class" => nil,
            "response_kind" => "retrieval_only",
            "answer" => nil,
            "claims" => [],
            "citations" => [],
            "context_evidence" => []
          })
        else
          row
        end
      end)

    {declared, blobs} = inputs(changed, freeze["queries"], freeze["variants"])
    declared = Map.merge(declared, Map.take(freeze, ~w(version contracts baseline)))

    review =
      update_in(
        review,
        ["semantic"],
        &Enum.with_index(&1, fn row, index ->
          if index < count,
            do: Map.merge(row, %{"verdict" => "unmeasured", "citations" => []}),
            else: row
        end)
      )

    {declared, blobs, label, bind_fixture_review(declared, blobs, review)}
  end

  test "reviewed first failures contribute zero support with the declared50 outcome denominator" do
    for count <- [1, 5, 6] do
      {declared, blobs, label, review} = qualification_failures(count)

      assert {:ok, report} =
               score_with_corpus(declared, blobs, fn -> {:ok, label} end, fn -> {:ok, review} end)

      assert report["complete_first_grid"] and report["complete_review"]
      assert report["eligible_variants"] == if(count <= 5, do: ["lexical"], else: [])
      assert report["quality_gates_passed"] == count <= 5
      [lexical | _] = report["variants"]
      assert lexical["gates"]["support"]["value"] == (50 - count) / 50
      assert lexical["semantic"]["support"]["accuracy"] == nil
    end
  end

  test "failure support still requires independent review of every first and actual answer" do
    {declared, blobs, label, review} = qualification_failures(5)

    for changed <- [
          update_in(review, ["semantic"], &tl/1),
          put_in(review, ["semantic", Access.at(0), "independent"], false),
          put_in(review, ["semantic", Access.at(5), "verdict"], "unmeasured")
        ] do
      assert {:ok, report} =
               score_with_corpus(declared, blobs, fn -> {:ok, label} end, fn -> {:ok, changed} end)

      assert report["complete_first_grid"]
      refute report["complete_review"] or report["quality_gates_passed"]
      assert report["eligible_variants"] == []
      assert hd(report["variants"])["gates"]["support"]["status"] == "unmeasured"
    end
  end

  test "new declaration identity cannot reuse a review after downgrade or query-order substitution" do
    {freeze, blobs, _, review, _} = qualification_inputs()
    owner = self()

    unopened = fn ->
      send(owner, :reference_opened)
      {:error, :forbidden}
    end

    for changed <- [
          freeze |> Map.put("version", 2) |> Map.delete("contracts"),
          Map.update!(freeze, "queries", &Enum.reverse/1)
        ] do
      assert {:error, :review_binding_mismatch} =
               Score.score(changed, blobs, unopened, fn -> {:ok, review} end, unopened)

      refute_received :reference_opened
    end

    altered = put_in(freeze, ["contracts", "outputs", "answer"], "text_v1")
    assert {:error, :invalid_freeze} = Score.score(altered, blobs, unopened, unopened, unopened)
    refute_received :reference_opened
  end

  test "reviewer flags cannot validate fabricated bytes or invalidate genuine bytes" do
    fabricated = put_in(prediction(), ["evidence", Access.at(0), "quote"], "a fake zz")
    assert {:ok, report} = score([fabricated])
    [row] = hd(report["variants"])["rows"]
    assert hd(row["integrity"])["verdict"] == "invalid"
    assert hd(row["integrity"])["reviewer_id"] == "source-bytes-v1"
    refute report["quality_gates_passed"]

    false_flags = put_in(reviews(), ["integrity", Access.at(0), "verdict"], "invalid")
    assert {:ok, report} = score([prediction()], labels(), false_flags)
    assert report["quality_gates_passed"]
  end

  test "corpus loading follows binding verification and hash validation precedes label access" do
    {freeze, blobs} = inputs()
    review = bind_fixture_review(freeze, blobs, reviews())
    unopened = fn -> flunk("must not open unverified context") end

    assert {:error, :review_binding_mismatch} =
             Score.score(
               Map.put(freeze, "context_sha256", sha("changed")),
               blobs,
               unopened,
               fn -> {:ok, review} end,
               unopened
             )

    corrupt = JSON.decode!(corpus()) |> put_in(["documents", Access.at(0), "text"], "changed")

    assert {:error, :invalid_corpus} =
             Score.score(freeze, blobs, unopened, fn -> {:ok, review} end, fn ->
               {:ok, JSON.encode!(corrupt)}
             end)
  end

  test "scoring requires a closed version-two declaration with caller-owned context" do
    {freeze, blobs} = inputs()

    unopened = fn ->
      send(self(), :opened_data)
      {:error, :must_not_open}
    end

    for invalid <- [
          Map.put(freeze, "version", 1),
          Map.delete(freeze, "context_sha256"),
          Map.put(freeze, "context_sha256", nil),
          Map.put(freeze, "context_sha256", "not-a-hash"),
          Map.put(freeze, "extra", true)
        ] do
      assert {:error, :invalid_freeze} = score_with_corpus(invalid, blobs, unopened, unopened)
      refute_received :opened_data
    end
  end

  test "review binding refuses changed predictions or context before opening labels" do
    {freeze, blobs} = inputs()
    review = bind_fixture_review(freeze, blobs, reviews())

    loader = fn ->
      send(self(), :labels_opened)
      {:ok, labels()}
    end

    changed =
      prediction(%{
        "answer" => "Different answer.",
        "claims" => [%{"claim_id" => "c", "text" => "Different answer."}]
      })

    {other, other_blobs} = inputs([changed])

    for {declaration, values} <- [
          {other, other_blobs},
          {Map.put(freeze, "context_sha256", sha("different context")), blobs}
        ] do
      assert {:error, :review_binding_mismatch} =
               score_with_corpus(declaration, values, loader, fn -> {:ok, review} end)

      refute_received :labels_opened
    end

    for invalid <- [
          Map.delete(review, "review_binding_sha256"),
          Map.put(review, "version", 1),
          Map.put(review, "review_binding_sha256", "invalid"),
          Map.put(review, "extra", true)
        ] do
      assert {:error, :invalid_reviews} =
               score_with_corpus(freeze, blobs, loader, fn -> {:ok, invalid} end)

      refute_received :labels_opened
    end

    assert {:ok, report} = score_with_corpus(freeze, blobs, loader, fn -> {:ok, review} end)
    assert_received :labels_opened
    assert report["quality_gates_passed"]
    assert report["review"]["review_binding_sha256"] == review["review_binding_sha256"]
  end

  test "review bindings canonically cover every file identity" do
    first = prediction()
    second = prediction(%{"prediction_id" => "other", "variant" => "other"})

    {freeze, _} =
      inputs([first, second], [%{"query_id" => "q", "project" => "p"}], ~w(base other))

    blobs = %{"a" => JSON.encode!(first) <> "\n", "b" => JSON.encode!(second) <> "\n"}
    files = Enum.map(~w(a b), &%{"id" => &1, "sha256" => sha(blobs[&1])})
    freeze = Map.put(freeze, "files", files)
    assert {:ok, verified} = Score.verified_predictions(freeze, blobs)

    assert {:ok, reordered} =
             Score.verified_predictions(Map.put(freeze, "files", Enum.reverse(files)), blobs)

    assert reordered["review_binding_sha256"] == verified["review_binding_sha256"]

    renamed = put_in(freeze, ["files", Access.at(0), "id"], "renamed")

    assert {:ok, different} =
             Score.verified_predictions(
               renamed,
               blobs |> Map.put("renamed", blobs["a"]) |> Map.delete("a")
             )

    refute different["review_binding_sha256"] == verified["review_binding_sha256"]

    changed_blobs =
      Map.put(blobs, "b", JSON.encode!(Map.put(second, "answer", "Changed second file.")) <> "\n")

    changed = put_in(freeze, ["files", Access.at(1), "sha256"], sha(changed_blobs["b"]))
    assert {:ok, different} = Score.verified_predictions(changed, changed_blobs)
    refute different["review_binding_sha256"] == verified["review_binding_sha256"]
  end

  test "a complete 350-row grid retains escaped citation quotes above sixteen MiB" do
    variants = ~w(lexical graph_explicit graph_model dense hybrid rerank research)

    queries =
      for number <- 1..50,
          do: %{
            "query_id" => "q#{number}",
            "project" => if(number <= 25, do: "alpha", else: "beta")
          }

    quote = "word" <> String.duplicate(<<1>>, 1020)

    rows =
      for variant <- variants, query <- queries do
        evidence =
          for number <- 1..10 do
            %{
              "span_id" => "r#{number}",
              "source" =>
                source(query["project"])
                |> Map.put("source_id", Integer.to_string(number) <> String.duplicate("\"", 254))
                |> Map.put("version", String.duplicate(<<1>>, 64))
                |> Map.put("sha256", sha(quote)),
              "start_byte" => 0,
              "end_byte" => byte_size(quote),
              "quote" => quote
            }
          end

        prediction(%{
          "prediction_id" => "p-" <> sha(variant <> query["query_id"]),
          "variant" => variant,
          "query_id" => query["query_id"],
          "project" => query["project"],
          "predicted_class" => "abstain",
          "response_kind" => "abstention",
          "answer" => "Insufficient evidence.",
          "claims" => [],
          "evidence" => evidence,
          "citations" => []
        })
      end

    {freeze, blobs} = inputs(rows, queries, variants)
    freeze = Map.put(freeze, "baseline", "lexical")
    assert byte_size(blobs["predictions"]) > 16 * 1024 * 1024
    assert byte_size(blobs["predictions"]) < 64 * 1024 * 1024
    assert {:ok, verified} = Score.verified_predictions(freeze, blobs)
    assert verified["rows"] == rows

    changed = Map.update!(blobs, "predictions", &(&1 <> " "))
    assert {:error, :prediction_hash_mismatch} = Score.verified_predictions(freeze, changed)
  end

  test "single-file and combined prediction bounds refuse before reference loaders" do
    {freeze, _} = inputs()

    loader = fn ->
      send(self(), :reference_opened)
      {:error, :must_not_open}
    end

    for {count, size} <- [{1, 64 * 1024 * 1024 + 1}, {2, 32 * 1024 * 1024 + 1}] do
      bytes = String.duplicate("x", size)
      files = for number <- 1..count, do: %{"id" => "f#{number}", "sha256" => sha(bytes)}
      bounded_freeze = Map.put(freeze, "files", files)
      blobs = Map.new(files, &{&1["id"], bytes})

      assert {:error, :prediction_size_limit} =
               score_with_corpus(bounded_freeze, blobs, loader, loader)

      refute_received :reference_opened
    end
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
             score_with_corpus(freeze, Map.put(blobs, "predictions", "{}\n"), loader, review)

    refute_received :labels_opened
    refute_received :reviews_opened

    malformed =
      String.replace(blobs["predictions"], "\"attempt\":1", "\"attempt\":1,\"attempt\":1")

    frozen = put_in(freeze, ["files", Access.at(0), "sha256"], sha(malformed))

    assert {:error, :duplicate_prediction_key} =
             score_with_corpus(frozen, %{"predictions" => malformed}, loader, review)

    refute_received :labels_opened
    refute_received :reviews_opened

    {duplicates, raw} = inputs([prediction(), prediction()])
    assert {:error, :duplicate_prediction} = score_with_corpus(duplicates, raw, loader, review)
    refute_received :labels_opened
    {second, raw} = inputs([prediction(%{"attempt" => 2})])
    assert {:error, :invalid_prediction} = score_with_corpus(second, raw, loader, review)
    refute_received :labels_opened
    {reserved, raw} = inputs([prediction(%{"prediction_id" => "missing:collision"})])
    assert {:error, :invalid_prediction} = score_with_corpus(reserved, raw, loader, review)
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
             score_with_corpus(freeze, blobs, fn -> {:ok, label} end, fn ->
               {:ok, bind_fixture_review(freeze, blobs, reviews())}
             end)

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
        "version" => 2,
        "review_binding_sha256" =>
          bind_fixture_review(freeze, blobs, reviews())["review_binding_sha256"],
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
             score_with_corpus(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review.(1)} end)

    assert passed["quality_gate_scope"] == "complete_frozen_grid"
    assert passed["quality_gates_passed"] and passed["semantic"]["support"]["total_n"] == 20
    assert passed["gates"]["citation"]["value"] == 0.95
    assert List.last(passed["variants"])["gates"]["citation"]["status"] == "fail"

    assert {:ok, failed} =
             score_with_corpus(freeze, blobs, fn -> {:ok, label} end, fn -> {:ok, review.(2)} end)

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
    assert {:error, :invalid_prediction} = score_with_corpus(freeze, blobs, loader, loader)

    {freeze, _} = inputs()

    bytes =
      ~s({"extra":) <> String.duplicate("[", 13) <> "0" <> String.duplicate("]", 13) <> "}\n"

    freeze = put_in(freeze, ["files", Access.at(0), "sha256"], sha(bytes))

    assert {:error, :prediction_depth_limit} =
             score_with_corpus(freeze, %{"predictions" => bytes}, loader, loader)
  end

  test "coordinate mismatch, foreign evidence and absent independent review never gain support from a quote" do
    wrong_coordinates =
      put_in(labels(), ["queries", Access.at(0), "relevance", Access.at(0), "start_byte"], 11)
      |> put_in(["queries", Access.at(0), "relevance", Access.at(0), "end_byte"], 16)

    assert {:error, :invalid_reference_integrity} = score([prediction()], wrong_coordinates)

    foreign = put_in(prediction(), ["evidence", Access.at(0), "source"], source("other"))
    assert {:ok, report} = score([foreign])
    [variant] = report["variants"]
    assert hd(hd(variant["rows"])["integrity"])["verdict"] == "invalid"
    assert variant["gates"]["citation"]["status"] == "fail"

    assert {:ok, report} =
             score([prediction()], labels(), reviews(%{"semantic" => [], "integrity" => []}))

    [variant] = report["variants"]
    assert hd(variant["rows"])["spans"]["contained_recall"] == 1.0
    assert variant["gates"]["citation"]["status"] == "unmeasured"
    assert variant["gates"]["support"]["status"] == "unmeasured"
  end
end
