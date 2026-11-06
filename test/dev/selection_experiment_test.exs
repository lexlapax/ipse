Code.require_file("../../dev/evaluation/selection_experiment.exs", __DIR__)

defmodule Ipse.Test.SelectionExperimentTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON
  alias Ipse.Development.Evaluation.SelectionExperiment, as: S

  defp fixture do
    h = JSON.sha256("fixture")
    keys = for n <- 1..6, do: "note." <> JSON.sha256(to_string(n))

    prediction = fn id ->
      %{
        "prediction_id" => id,
        "query_id" => "one",
        "status" => "ok",
        "response_kind" => "answer",
        "expected_refusal" => false,
        "citations" => [%{"citation_id" => id <> "-cite", "integrity" => "valid"}]
      }
    end

    review = fn id ->
      %{
        "prediction_id" => id,
        "verdict" => "supported",
        "reviewer_id" => "independent-fixture-review",
        "independent" => true,
        "citations" => [%{"citation_id" => id <> "-cite", "verdict" => "supported"}]
      }
    end

    input =
      Jason.encode!(%{
        "query" => "fixture query",
        "packs" => [
          %{"id" => "first", "members" => Enum.take(keys, 4)},
          %{"id" => "second", "members" => Enum.drop(keys, 2)}
        ]
      })

    source = Jason.encode!(%{"status" => "unreviewed_fixture"})

    baseline = %{
      "case_id" => "one",
      "input_sha256" => JSON.sha256(input),
      "source_receipt_sha256" => JSON.sha256(source),
      "prediction" => prediction.("baseline"),
      "members" => keys,
      "elapsed_ms" => 100,
      "cost_nanos" => 100
    }

    baseline_bytes = Jason.encode!(baseline)

    labels = %{
      "version" => 1,
      "rows" => [
        %{
          "case_id" => "one",
          "baseline" => review.("baseline"),
          "candidate" => review.("candidate"),
          "critical_members" => Enum.take(keys, 1)
        }
      ]
    }

    label_bytes = Jason.encode!(labels)

    case_row = %{
      "id" => "one",
      "input_sha256" => JSON.sha256(input),
      "source_receipt_sha256" => JSON.sha256(source),
      "baseline_sha256" => JSON.sha256(baseline_bytes)
    }

    spec = %{
      "version" => 1,
      "source_sha256" => h,
      "runtime_sha256" => h,
      "artifact_sha256" => h,
      "main_route_sha256" => h,
      "policy_sha256" => h,
      "engine" => %{"id" => "loopback", "availability" => "available", "route_sha256" => h},
      "label_commitment" => JSON.sha256(label_bytes),
      "shared_limits" =>
        Map.merge(Ipse.Extension.Consent.zero(), %{
          "operations" => 1,
          "model_calls" => 1,
          "input_bytes" => 100_000,
          "output_bytes" => 100_000
        }),
      "cases" => [case_row]
    }

    {:ok, d} = S.declare(spec)

    row =
      Map.take(case_row, ~w(input_sha256 source_receipt_sha256 baseline_sha256))
      |> Map.merge(%{
        "case_id" => "one",
        "status" => "ok",
        "selection_output_sha256" => h,
        "prediction" => prediction.("candidate"),
        "members" => Enum.take(keys, 4),
        "elapsed_ms" => 110,
        "cost_nanos" => 70
      })

    blobs = Map.new([input, source, baseline_bytes], &{JSON.sha256(&1), &1})

    %{
      d: d,
      sha: JSON.digest([d]),
      row: row,
      blobs: blobs,
      labels: label_bytes,
      baseline: baseline,
      keys: keys
    }
  end

  defp load(f), do: fn sha -> Map.fetch(f.blobs, sha) end

  defp score(f, rows) do
    {:ok, first} = S.freeze_rows(f.d, f.sha, rows)
    S.score(f.d, f.sha, first, JSON.digest([first]), fn -> {:ok, f.labels} end, load(f))
  end

  defp version_two do
    f = fixture()

    opaque = fn prediction ->
      prediction
      |> Map.update!("prediction_id", &JSON.sha256/1)
      |> Map.update!(
        "citations",
        fn citations ->
          Enum.map(citations, fn c -> Map.update!(c, "citation_id", &JSON.sha256/1) end)
        end
      )
    end

    baseline = Map.update!(f.baseline, "prediction", opaque)
    baseline_bytes = Jason.encode!(baseline)
    baseline_sha = JSON.sha256(baseline_bytes)
    spec = put_in(f.d["spec"], ["cases", Access.at(0), "baseline_sha256"], baseline_sha)
    row = f.row |> Map.update!("prediction", opaque) |> Map.put("baseline_sha256", baseline_sha)
    f = %{f | baseline: baseline, row: row, blobs: Map.put(f.blobs, baseline_sha, baseline_bytes)}

    references =
      Jason.encode!(%{
        "version" => 2,
        "rows" => [%{"case_id" => "one", "critical_members" => Enum.take(f.keys, 1)}]
      })

    {:ok, commitment} = S.commit_references(references)
    {:ok, d} = S.declare(%{spec | "version" => 2, "label_commitment" => commitment})
    f = Map.merge(f, %{d: d, sha: JSON.digest([d]), references: references})
    {:ok, first} = S.freeze_rows(d, f.sha, [f.row])
    {:ok, reviews} = S.prepare_reviews(d, f.sha, first, JSON.digest([first]), load(f))
    Map.merge(f, %{first: first, reviews: reviews})
  end

  defp score_two(f, reviews, first \\ nil) do
    first = first || f.first

    S.score(
      f.d,
      f.sha,
      first,
      JSON.digest([first]),
      fn -> {:ok, f.references} end,
      fn -> {:ok, Jason.encode!(reviews)} end,
      load(f)
    )
  end

  test "version two commits reference-only labels and refuses prediction verdicts in the commitment" do
    f = version_two()
    assert {:ok, _} = S.verify_references(f.d, f.sha, fn -> {:ok, f.references} end)
    assert {:error, _} = S.commit_references(f.labels)
    reference = Jason.decode!(f.references)

    for changed <- [
          put_in(reference, ["rows", Access.at(0), "prediction_id"], "future"),
          put_in(reference, ["rows", Access.at(0), "critical_members"], ["invalid"]),
          %{reference | "rows" => reference["rows"] ++ reference["rows"]},
          Map.put(reference, "independent", true)
        ] do
      assert {:error, _} = S.commit_references(Jason.encode!(changed))
    end

    bytes = Jason.encode!(put_in(reference, ["rows", Access.at(0), "case_id"], "foreign"))
    {:ok, commitment} = S.commit_references(bytes)
    {:ok, d} = S.declare(%{f.d["spec"] | "label_commitment" => commitment})
    assert {:error, _} = S.verify_references(d, JSON.digest([d]), fn -> {:ok, bytes} end)
  end

  test "later review template binds both actual arms and remains unmeasured with absent measurements" do
    f = version_two()
    by_id = Map.new(f.reviews["semantic"], &{&1["prediction_id"], &1})
    baseline = by_id[f.baseline["prediction"]["prediction_id"]]
    candidate = by_id[f.row["prediction"]["prediction_id"]]
    assert baseline["prediction_id"] === f.baseline["prediction"]["prediction_id"]
    assert candidate["prediction_id"] === f.row["prediction"]["prediction_id"]

    assert candidate["citations"] === [
             %{"citation_id" => JSON.sha256("candidate-cite"), "verdict" => "unmeasured"}
           ]

    assert Enum.sort(Map.keys(f.reviews)) === ~w(review_binding_sha256 semantic version)
    refute baseline["independent"]
    refute candidate["independent"]
    assert {:ok, report} = score_two(f, f.reviews)
    assert report["comparison"] === nil
    assert report["qualification"] === "none"
    refute report["support_and_citations_measured"]

    row = %{f.row | "elapsed_ms" => nil, "cost_nanos" => nil}
    {:ok, first} = S.freeze_rows(f.d, f.sha, [row])
    {:ok, reviews} = S.prepare_reviews(f.d, f.sha, first, JSON.digest([first]), load(f))
    assert {:ok, report} = score_two(f, reviews, first)
    assert report["candidate"]["p95_ms"] === nil and report["candidate"]["cost_nanos"] === nil
  end

  test "review binding, prediction IDs, citation membership and closed populations cannot be substituted" do
    f = version_two()

    for changed <- [
          put_in(f.reviews, ["review_binding_sha256"], JSON.sha256("foreign freeze")),
          put_in(f.reviews, ["semantic", Access.at(0), "prediction_id"], JSON.sha256("foreign")),
          put_in(
            f.reviews,
            ["semantic", Access.at(0), "citations", Access.at(0), "citation_id"],
            JSON.sha256("foreign")
          ),
          put_in(f.reviews, ["semantic", Access.at(0)], nil),
          %{f.reviews | "semantic" => []},
          %{f.reviews | "semantic" => f.reviews["semantic"] ++ f.reviews["semantic"]},
          Map.put(f.reviews, "baseline", %{}),
          Map.put(f.reviews, "independent", true)
        ] do
      assert {:error, _} = score_two(f, changed)
    end

    changed_first = put_in(f.first, ["rows", Access.at(0), "elapsed_ms"], 111)
    assert {:error, _} = score_two(f, f.reviews, changed_first)
    changed_baseline = %{f.baseline | "members" => []}

    assert {:error, _} =
             S.prepare_reviews(f.d, f.sha, f.first, JSON.digest([f.first]), fn _ ->
               {:ok, Jason.encode!(changed_baseline)}
             end)
  end

  test "invalid first rows or committed references refuse before the later review loader" do
    f = version_two()

    assert {:error, _} =
             S.score(
               f.d,
               f.sha,
               f.first,
               JSON.sha256("different"),
               fn -> flunk("reference exposed before first-row verification") end,
               fn -> flunk("review exposed before first-row verification") end,
               load(f)
             )

    assert {:error, _} =
             S.score(
               f.d,
               f.sha,
               f.first,
               JSON.digest([f.first]),
               fn -> {:ok, "{}"} end,
               fn -> flunk("review exposed before reference verification") end,
               load(f)
             )

    assert {:ok, _} =
             S.score(
               f.d,
               f.sha,
               f.first,
               JSON.digest([f.first]),
               fn ->
                 send(self(), :reference_loaded)
                 {:ok, f.references}
               end,
               fn ->
                 assert_received :reference_loaded
                 send(self(), :review_loaded)
                 {:ok, Jason.encode!(f.reviews)}
               end,
               load(f)
             )

    assert_received :review_loaded
  end

  test "unknown and absent candidate predictions require null reviews rather than invented outcomes" do
    f = version_two()

    unknown = %{
      f.row
      | "status" => "unknown",
        "prediction" => nil,
        "selection_output_sha256" => nil,
        "members" => [],
        "elapsed_ms" => nil,
        "cost_nanos" => nil
    }

    for rows <- [[], [unknown]] do
      {:ok, first} = S.freeze_rows(f.d, f.sha, rows)
      {:ok, reviews} = S.prepare_reviews(f.d, f.sha, first, JSON.digest([first]), load(f))

      assert Enum.map(reviews["semantic"], & &1["prediction_id"]) === [
               f.baseline["prediction"]["prediction_id"]
             ]

      assert {:ok, report} = score_two(f, reviews, first)
      assert report["candidate"] === nil and report["comparison"] === nil
      assert {:error, _} = score_two(f, %{reviews | "semantic" => f.reviews["semantic"]}, first)
    end
  end

  test "historical combined labels and new separate-review formats cannot be silently interchanged" do
    f = version_two()

    assert {:error, _} =
             S.score(
               f.d,
               f.sha,
               f.first,
               JSON.digest([f.first]),
               fn -> flunk("v2 must not use historical labels loader") end,
               load(f)
             )

    old = fixture()
    {:ok, first} = S.freeze_rows(old.d, old.sha, [old.row])

    assert {:error, _} =
             S.score(
               old.d,
               old.sha,
               first,
               JSON.digest([first]),
               fn -> flunk("v1 must not use v2 references") end,
               fn -> flunk("v1 must not use v2 reviews") end,
               load(old)
             )

    assert {:ok, _} = score(old, [old.row])
  end

  test "frozen recipe OFF, full six-member baseline and four-member alternative remain distinct" do
    f = fixture()

    assert {:ok, %{"status" => "off", "tool" => "ext__knowledge__select_shadow"}} =
             S.execution(f.d, f.sha, "one")

    assert {:ok, bases} = S.verify_inputs(f.d, f.sha, load(f))
    assert length(bases["one"]["members"]) == 6 and length(f.row["members"]) == 4
    assert {:ok, report} = score(f, [f.row])
    assert report["comparison"]["criteria"]["benefit"] == "pass"
    assert report["disposition"] == "unverified" and report["qualification"] == "none"
  end

  test "changed bars/input/baseline hashes refuse before label loader" do
    f = fixture()
    assert {:error, _} = S.verify(put_in(f.d, ["bars", "cost_max_ratio"], [1, 1]), f.sha)
    {:ok, first} = S.freeze_rows(f.d, f.sha, [f.row])

    assert {:error, _} =
             S.score(
               f.d,
               f.sha,
               first,
               JSON.sha256("changed"),
               fn -> flunk("label exposed") end,
               load(f)
             )

    assert {:error, _} = S.verify_inputs(f.d, f.sha, fn _ -> {:ok, "forged"} end)
  end

  test "missing and unknown rows stay unverified without invented zero measurements" do
    f = fixture()
    assert {:ok, empty} = score(f, [])
    assert empty["candidate"] == nil and empty["comparison"] == nil

    unknown = %{
      f.row
      | "status" => "unknown",
        "prediction" => nil,
        "selection_output_sha256" => nil,
        "members" => [],
        "elapsed_ms" => nil,
        "cost_nanos" => nil
    }

    assert {:ok, report} = score(f, [unknown])
    refute report["known_rows_complete"]
    assert report["comparison"] == nil
  end

  test "known rows with absent timings/cost retain null arithmetic" do
    f = fixture()
    assert {:ok, report} = score(f, [%{f.row | "elapsed_ms" => nil, "cost_nanos" => nil}])
    assert report["candidate"]["p95_ms"] == nil and report["candidate"]["cost_nanos"] == nil
    assert report["comparison"]["criteria"]["latency"] == "unverified"
  end

  test "synthetic protocol replies and unavailable engine never become model quality" do
    for availability <- ~w(synthetic_protocol_only unavailable unverified) do
      f = fixture()
      {:ok, d} = S.declare(put_in(f.d["spec"], ["engine", "availability"], availability))
      f = %{f | d: d, sha: JSON.digest([d])}

      row =
        if availability == "unavailable",
          do: %{
            f.row
            | "status" => "unavailable",
              "prediction" => nil,
              "selection_output_sha256" => nil,
              "members" => [],
              "elapsed_ms" => nil,
              "cost_nanos" => nil
          },
          else: f.row

      assert {:ok, report} = score(f, [row])
      assert report["comparison"] == nil and report["disposition"] == "unverified"
      if availability == "unavailable", do: assert({:error, _} = S.freeze_rows(d, f.sha, [f.row]))
    end
  end

  test "retrieval-only cannot be labeled a supported answer" do
    f = fixture()
    row = put_in(f.row, ["prediction", "response_kind"], "retrieval_only")
    assert {:error, _} = score(f, [row])
  end

  test "explicitly unmeasured retrieval-only preserves the missing-quality reason" do
    f = fixture()
    labels = Jason.decode!(f.labels)

    labels =
      update_in(labels, ["rows", Access.at(0), "candidate"], fn review ->
        review
        |> Map.put("verdict", "unmeasured")
        |> update_in(["citations"], &Enum.map(&1, fn c -> %{c | "verdict" => "unmeasured"} end))
      end)

    bytes = Jason.encode!(labels)
    {:ok, d} = S.declare(%{f.d["spec"] | "label_commitment" => JSON.sha256(bytes)})
    f = %{f | d: d, sha: JSON.digest([d]), labels: bytes}
    row = put_in(f.row, ["prediction", "response_kind"], "retrieval_only")
    assert {:ok, report} = score(f, [row])
    assert report["comparison"] == nil
    assert report["candidate_semantics"]["support"]["unmeasured_n"] == 1
    assert report["candidate_semantics"]["support"]["retrieval_only_n"] == 1
  end

  test "absent baseline total-cost and latency cannot become zero or a benefit" do
    f = fixture()
    baseline = %{f.baseline | "elapsed_ms" => nil, "cost_nanos" => nil}
    bytes = Jason.encode!(baseline)
    digest = JSON.sha256(bytes)
    spec = put_in(f.d["spec"], ["cases", Access.at(0), "baseline_sha256"], digest)
    {:ok, d} = S.declare(spec)
    f = %{f | d: d, sha: JSON.digest([d]), blobs: Map.put(f.blobs, digest, bytes)}
    assert {:ok, report} = score(f, [%{f.row | "baseline_sha256" => digest}])
    assert report["baseline"]["p95_ms"] == nil and report["baseline"]["cost_nanos"] == nil
    assert report["comparison"]["criteria"]["latency"] == "unverified"
    assert report["comparison"]["criteria"]["benefit"] == "unverified"
  end

  test "duplicate rows/foreign case/oversized candidate or contradictory status refuse" do
    f = fixture()

    for rows <- [
          [f.row, f.row],
          [%{f.row | "case_id" => "other"}],
          [%{f.row | "members" => f.keys}],
          [put_in(f.row, ["prediction", "status"], "unknown")]
        ] do
      assert {:error, _} = S.freeze_rows(f.d, f.sha, rows)
    end
  end
end
