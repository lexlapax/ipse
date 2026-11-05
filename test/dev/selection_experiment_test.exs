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
