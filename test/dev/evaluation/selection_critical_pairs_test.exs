Code.require_file("../../../dev/evaluation/selection_experiment.exs", __DIR__)

defmodule Ipse.Development.Evaluation.SelectionCriticalPairsTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Evaluation.SelectionExperiment, as: Selection
  alias Ipse.JSON

  defp prediction(case_id, branch) do
    %{
      "prediction_id" => JSON.sha256(case_id <> branch),
      "query_id" => case_id,
      "status" => "ok",
      "response_kind" => "answer",
      "expected_refusal" => false,
      "citations" => []
    }
  end

  defp fixture() do
    keys = Map.new(~w(a b), &{&1, "note." <> JSON.sha256(&1)})
    input = Jason.encode!(%{"query" => "synthetic"})
    source = Jason.encode!(%{"scope" => "unverified fixture"})

    baselines =
      for id <- ~w(a b) do
        baseline = %{
          "case_id" => id,
          "input_sha256" => JSON.sha256(input),
          "source_receipt_sha256" => JSON.sha256(source),
          "prediction" => prediction(id, "baseline"),
          "members" => if(id == "a", do: [keys[id]], else: []),
          "elapsed_ms" => nil,
          "cost_nanos" => nil
        }

        bytes = Jason.encode!(baseline)

        {%{
           "id" => id,
           "input_sha256" => JSON.sha256(input),
           "source_receipt_sha256" => JSON.sha256(source),
           "baseline_sha256" => JSON.sha256(bytes)
         }, bytes}
      end

    references =
      Jason.encode!(%{
        "version" => 2,
        "rows" => for(id <- ~w(a b), do: %{"case_id" => id, "critical_members" => [keys[id]]})
      })

    hash = JSON.sha256("synthetic")

    {:ok, declaration} =
      Selection.declare(%{
        "version" => 2,
        "source_sha256" => hash,
        "runtime_sha256" => hash,
        "artifact_sha256" => hash,
        "main_route_sha256" => hash,
        "policy_sha256" => hash,
        "label_commitment" => JSON.sha256(references),
        "shared_limits" => %{
          "operations" => 1,
          "model_calls" => 1,
          "input_bytes" => 1,
          "output_bytes" => 1,
          "download_bytes" => 0,
          "cost_nanos" => 0
        },
        "cases" => Enum.map(baselines, &elem(&1, 0)),
        "engine" => %{
          "id" => "loopback",
          "availability" => "synthetic_protocol_only",
          "route_sha256" => hash
        }
      })

    blobs = Map.new([input, source | Enum.map(baselines, &elem(&1, 1))], &{JSON.sha256(&1), &1})

    rows =
      Enum.map(declaration["spec"]["cases"], fn c ->
        id = c["id"]

        Map.take(c, ~w(input_sha256 source_receipt_sha256 baseline_sha256))
        |> Map.merge(%{
          "case_id" => id,
          "status" => "ok",
          "selection_output_sha256" => hash,
          "prediction" => prediction(id, "candidate"),
          "members" => if(id == "b", do: [keys[id]], else: []),
          "elapsed_ms" => nil,
          "cost_nanos" => nil
        })
      end)

    {declaration, references, &Map.fetch(blobs, &1), rows}
  end

  defp score(d, refs, load, rows) do
    sha = JSON.digest([d])
    {:ok, first} = Selection.freeze_rows(d, sha, rows)
    first_sha = JSON.digest([first])
    {:ok, reviews} = Selection.prepare_reviews(d, sha, first, first_sha, load)

    Selection.score(
      d,
      sha,
      first,
      first_sha,
      fn -> {:ok, refs} end,
      fn -> {:ok, Jason.encode!(reviews)} end,
      load
    )
  end

  test "reports a critical loss even when a gain offsets its aggregate" do
    {d, refs, load, rows} = fixture()
    assert {:ok, report} = score(d, refs, load, rows)
    assert report["baseline"]["critical_recalled"] == 1
    assert report["candidate"]["critical_recalled"] == 1

    assert report["paired_critical_observation"] == %{
             "status" => "fail",
             "eligible" => 2,
             "unverified" => 0,
             "regressed_query_ids" => ["a"],
             "scope" => "hash_bound_membership_not_independent_review"
           }

    assert report["disposition"] == "unverified" and report["qualification"] == "none"
  end

  test "missing candidate rows stay unverified while known losses remain visible" do
    {d, refs, load, [first | _]} = fixture()
    assert {:ok, report} = score(d, refs, load, [first])
    assert report["candidate"] == nil and report["disposition"] == "unverified"
    assert report["paired_critical_observation"]["status"] == "unverified"
    assert report["paired_critical_observation"]["unverified"] == 1
    assert report["paired_critical_observation"]["regressed_query_ids"] == ["a"]
  end

  test "unknown rows and an empty critical population never become a pass" do
    {d, refs, load, [first, second]} = fixture()

    unknown = %{
      second
      | "status" => "unknown",
        "selection_output_sha256" => nil,
        "prediction" => nil,
        "members" => []
    }

    assert {:ok, report} = score(d, refs, load, [first, unknown])
    assert report["paired_critical_observation"]["status"] == "unverified"
    assert report["paired_critical_observation"]["unverified"] == 1
    assert report["paired_critical_observation"]["regressed_query_ids"] == ["a"]

    no_critical =
      refs
      |> Jason.decode!()
      |> update_in(["rows"], &Enum.map(&1, fn row -> Map.put(row, "critical_members", []) end))
      |> Jason.encode!()

    {:ok, empty_d} =
      Selection.declare(put_in(d, ["spec", "label_commitment"], JSON.sha256(no_critical))["spec"])

    assert {:ok, empty_report} = score(empty_d, no_critical, load, [first, second])
    assert empty_report["paired_critical_observation"]["status"] == "unverified"
    assert empty_report["paired_critical_observation"]["eligible"] == 0
  end

  test "matched critical successes remain observations and refused rows stay unverified" do
    {d, refs, load, [first, second]} = fixture()
    keys = Jason.decode!(refs)["rows"] |> Map.new(&{&1["case_id"], hd(&1["critical_members"])})
    matched_first = Map.put(first, "members", [keys["a"]])
    assert {:ok, report} = score(d, refs, load, [matched_first, second])
    assert report["paired_critical_observation"]["status"] == "pass"
    assert report["disposition"] == "unverified" and report["qualification"] == "none"

    refused =
      second
      |> Map.put("status", "refused")
      |> Map.update!("prediction", fn prediction ->
        prediction
        |> Map.put("status", "refused")
        |> Map.put("response_kind", "abstention")
      end)

    assert {:ok, refused_report} = score(d, refs, load, [matched_first, refused])
    assert refused_report["paired_critical_observation"]["status"] == "unverified"
    assert refused_report["paired_critical_observation"]["unverified"] == 1
    assert refused_report["disposition"] == "unverified"
  end

  test "a case recalls its critical set only when every member is present" do
    {d, refs, load, [first, second]} = fixture()
    reference = Jason.decode!(refs)
    [a, b] = reference["rows"]

    expanded =
      put_in(
        reference,
        ["rows", Access.at(0), "critical_members"],
        a["critical_members"] ++ b["critical_members"]
      )

    expanded_bytes = Jason.encode!(expanded)

    {:ok, expanded_d} =
      Selection.declare(
        put_in(d, ["spec", "label_commitment"], JSON.sha256(expanded_bytes))["spec"]
      )

    assert {:ok, report} = score(expanded_d, expanded_bytes, load, [first, second])
    assert report["paired_critical_observation"]["status"] == "pass"
    assert report["paired_critical_observation"]["regressed_query_ids"] == []
    assert report["baseline"]["critical_recalled"] == 0
    assert report["candidate"]["critical_recalled"] == 1
  end

  test "legacy version-one labels expose the same paired loss" do
    {d, refs, load, rows} = fixture()
    sha = JSON.digest([d])
    {:ok, first} = Selection.freeze_rows(d, sha, rows)
    {:ok, reviews} = Selection.prepare_reviews(d, sha, first, JSON.digest([first]), load)
    by_id = Map.new(reviews["semantic"], &{&1["prediction_id"], &1})

    labels = %{
      "version" => 1,
      "rows" =>
        Enum.map(Jason.decode!(refs)["rows"], fn reference ->
          id = reference["case_id"]

          Map.merge(reference, %{
            "baseline" => by_id[prediction(id, "baseline")["prediction_id"]],
            "candidate" => by_id[prediction(id, "candidate")["prediction_id"]]
          })
        end)
    }

    label_bytes = Jason.encode!(labels)

    spec =
      d["spec"] |> Map.put("version", 1) |> Map.put("label_commitment", JSON.sha256(label_bytes))

    {:ok, legacy} = Selection.declare(spec)
    legacy_sha = JSON.digest([legacy])
    {:ok, legacy_first} = Selection.freeze_rows(legacy, legacy_sha, rows)

    assert {:ok, report} =
             Selection.score(
               legacy,
               legacy_sha,
               legacy_first,
               JSON.digest([legacy_first]),
               fn ->
                 {:ok, label_bytes}
               end,
               load
             )

    assert report["paired_critical_observation"]["status"] == "fail"
    assert report["paired_critical_observation"]["regressed_query_ids"] == ["a"]
    assert report["disposition"] == "unverified"
  end
end
