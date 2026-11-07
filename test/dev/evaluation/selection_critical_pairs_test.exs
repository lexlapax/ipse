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
    assert refused_report["baseline"]["critical_recalled"] == 1
    assert refused_report["candidate"]["critical_recalled"] == nil
    assert refused_report["comparison"] == nil
    assert refused_report["disposition"] == "unverified"
  end

  test "a refused or failed critical baseline stays unmeasured despite retained members" do
    {d, refs, load, rows} = fixture()
    original = hd(d["spec"]["cases"])
    {:ok, old_bytes} = load.(original["baseline_sha256"])

    for status <- ~w(refused failed timeout) do
      new_bytes =
        old_bytes
        |> Jason.decode!()
        |> update_in(["prediction"], fn prediction ->
          prediction
          |> Map.put("status", status)
          |> Map.put("response_kind", "abstention")
        end)
        |> Jason.encode!()

      new_sha = JSON.sha256(new_bytes)
      new_case = Map.put(original, "baseline_sha256", new_sha)
      cases = [new_case | tl(d["spec"]["cases"])]
      {:ok, revised} = Selection.declare(put_in(d, ["spec", "cases"], cases)["spec"])

      revised_load = fn digest ->
        if digest == new_sha, do: {:ok, new_bytes}, else: load.(digest)
      end

      revised_rows =
        Enum.map(rows, fn row ->
          if row["case_id"] == new_case["id"],
            do: Map.put(row, "baseline_sha256", new_sha),
            else: row
        end)

      assert {:ok, report} = score(revised, refs, revised_load, revised_rows)
      assert report["baseline"]["critical_recalled"] == nil
      assert report["candidate"]["critical_recalled"] == 1
      assert report["paired_critical_observation"]["status"] == "unverified"
      assert report["comparison"] == nil
      assert report["disposition"] == "unverified"
    end
  end

  test "a refused noncritical case does not erase a known critical count" do
    {d, refs, load, [first, second]} = fixture()
    reference = Jason.decode!(refs)
    [a, _b] = reference["rows"]
    reference = put_in(reference, ["rows", Access.at(1), "critical_members"], [])
    bytes = Jason.encode!(reference)

    {:ok, revised} =
      Selection.declare(put_in(d, ["spec", "label_commitment"], JSON.sha256(bytes))["spec"])

    first = Map.put(first, "members", a["critical_members"])

    refused =
      second
      |> Map.put("status", "refused")
      |> Map.update!("prediction", fn prediction ->
        prediction
        |> Map.put("status", "refused")
        |> Map.put("response_kind", "abstention")
      end)

    assert {:ok, report} = score(revised, bytes, load, [first, refused])
    assert report["candidate"]["critical_total"] == 1
    assert report["candidate"]["critical_recalled"] == 1
    assert report["paired_critical_observation"]["status"] == "pass"
    assert report["disposition"] == "unverified"
  end

  test "measured semantic reviews cannot turn refused critical recall into a comparison" do
    {d, refs, load, rows} = fixture()

    with_citation = fn prediction ->
      Map.put(prediction, "citations", [
        %{
          "citation_id" => JSON.sha256(prediction["prediction_id"] <> " citation"),
          "integrity" => "valid"
        }
      ])
    end

    {cases, new_blobs} =
      Enum.map_reduce(d["spec"]["cases"], %{}, fn c, blobs ->
        {:ok, old_bytes} = load.(c["baseline_sha256"])
        b = Jason.decode!(old_bytes) |> update_in(["prediction"], with_citation)
        bytes = Jason.encode!(b)
        sha = JSON.sha256(bytes)
        {Map.put(c, "baseline_sha256", sha), Map.put(blobs, sha, bytes)}
      end)

    revised_spec =
      d["spec"] |> Map.put("cases", cases) |> put_in(["engine", "availability"], "available")

    {:ok, revised} = Selection.declare(revised_spec)
    by_case = Map.new(cases, &{&1["id"], &1})

    revised_load = fn digest ->
      if Map.has_key?(new_blobs, digest), do: Map.fetch(new_blobs, digest), else: load.(digest)
    end

    revised_rows =
      Enum.map(rows, fn row ->
        row =
          row
          |> Map.put("baseline_sha256", by_case[row["case_id"]]["baseline_sha256"])
          |> update_in(["prediction"], with_citation)

        if row["case_id"] == "b" do
          row
          |> Map.put("status", "refused")
          |> update_in(
            ["prediction"],
            &(&1 |> Map.put("status", "refused") |> Map.put("response_kind", "abstention"))
          )
        else
          row
        end
      end)

    sha = JSON.digest([revised])
    {:ok, first} = Selection.freeze_rows(revised, sha, revised_rows)
    first_sha = JSON.digest([first])
    {:ok, template} = Selection.prepare_reviews(revised, sha, first, first_sha, revised_load)

    refused_id =
      Enum.find(revised_rows, &(&1["status"] == "refused"))["prediction"]["prediction_id"]

    reviews =
      update_in(template, ["semantic"], fn entries ->
        Enum.map(entries, fn review ->
          review
          |> Map.put("independent", true)
          |> Map.put("reviewer_id", "synthetic-reviewer")
          |> Map.put(
            "verdict",
            if(review["prediction_id"] == refused_id,
              do: "incorrect_abstention",
              else: "supported"
            )
          )
          |> update_in(
            ["citations"],
            &Enum.map(&1, fn citation -> Map.put(citation, "verdict", "supported") end)
          )
        end)
      end)

    assert {:ok, report} =
             Selection.score(
               revised,
               sha,
               first,
               first_sha,
               fn -> {:ok, refs} end,
               fn -> {:ok, Jason.encode!(reviews)} end,
               revised_load
             )

    assert report["support_and_citations_measured"] == true
    assert report["candidate"]["critical_recalled"] == nil
    assert report["comparison"] == nil
    assert report["paired_critical_observation"]["status"] == "unverified"
    assert report["disposition"] == "unverified"
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

    [first, second] = rows

    refused =
      second
      |> Map.put("status", "refused")
      |> Map.update!("prediction", fn prediction ->
        prediction
        |> Map.put("status", "refused")
        |> Map.put("response_kind", "abstention")
      end)

    {:ok, refused_first} = Selection.freeze_rows(legacy, legacy_sha, [first, refused])

    assert {:ok, refused_report} =
             Selection.score(
               legacy,
               legacy_sha,
               refused_first,
               JSON.digest([refused_first]),
               fn -> {:ok, label_bytes} end,
               load
             )

    assert refused_report["baseline"]["critical_recalled"] == 1
    assert refused_report["candidate"]["critical_recalled"] == nil
    assert refused_report["paired_critical_observation"]["status"] == "unverified"
    assert refused_report["paired_critical_observation"]["regressed_query_ids"] == ["a"]
    assert refused_report["comparison"] == nil
    assert refused_report["disposition"] == "unverified"
  end
end
