Code.require_file("../../../dev/evaluation/candidate_assessment.exs", __DIR__)

defmodule Ipse.Development.Evaluation.CandidateAssessmentTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Evaluation.CandidateAssessment, as: A
  alias Ipse.JSON

  defp score(d, sha, rows, labels, load) do
    with {:ok, predictions} <- A.freeze_rows(d, sha, rows) do
      A.score(d, sha, predictions, JSON.digest([predictions]), fn -> {:ok, labels} end, load)
    end
  end

  defp fixture(
         strata \\ ["observed_durable", "observed_durable"],
         timings \\ %{baseline: 100, candidate: 110}
       ) do
    cases =
      Enum.with_index(strata, 1)
      |> Enum.map(fn {stratum, n} ->
        id = n |> Integer.to_string(16) |> String.pad_leading(32, "0")
        key = if(stratum == "pending", do: "pending.", else: "note.") <> JSON.sha256(id)
        input = "Actual tool bytes are untrusted data: " <> id
        source = "Committed source receipt bytes: " <> id

        c = %{
          "id" => id,
          "stratum" => stratum,
          "candidate_key" => key,
          "input_sha256" => JSON.sha256(input),
          "source_receipt_sha256" => JSON.sha256(source)
        }

        baseline =
          Map.merge(c |> Map.drop(["id"]), %{
            "version" => 1,
            "case_id" => id,
            "baseline" => "keep",
            "admission" => if(stratum == "pending", do: "pending", else: "durable"),
            "journal_sha256" => JSON.sha256("constructed-journal"),
            "operation_id" => id,
            "elapsed_ms" => timings.baseline,
            "cost_nanos" => nil
          })

        bytes = Jason.encode!(baseline)

        {Map.put(c, "baseline_sha256", JSON.sha256(bytes)),
         %{
           JSON.sha256(input) => input,
           JSON.sha256(source) => source,
           JSON.sha256(bytes) => bytes
         }}
      end)

    labels =
      Jason.encode!(%{
        "version" => 1,
        "reviewer_id" => "constructed-test",
        "independent" => true,
        "rows" =>
          Enum.with_index(cases, 1)
          |> Enum.map(fn {{c, _}, n} ->
            %{"case_id" => c["id"], "false" => n == 1, "useful" => n != 1, "critical" => n != 1}
          end)
      })

    s = %{
      "version" => 1,
      "kind" => "candidate_shadow",
      "source_sha256" => JSON.sha256("source"),
      "runtime_sha256" => JSON.sha256("runtime"),
      "artifact_sha256" => JSON.sha256("artifact"),
      "main_route_sha256" => JSON.sha256("main"),
      "policy_sha256" => JSON.sha256("policy"),
      "decision_route" => %{
        "engine" => "compatible_loopback",
        "model" => "unverified-test",
        "rubric_sha256" => JSON.sha256("rubric"),
        "availability" => "unverified_access"
      },
      "label_commitment" => JSON.sha256(labels),
      "shared_limits" =>
        Map.new(
          ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos),
          &{&1, 10}
        ),
      "cases" => Enum.map(cases, &elem(&1, 0))
    }

    {:ok, d} = A.declare(s)
    blobs = Enum.reduce(cases, %{}, &Map.merge(&2, elem(&1, 1)))

    rows =
      Enum.with_index(s["cases"], 1)
      |> Enum.map(fn {c, n} ->
        c
        |> Map.take(~w(input_sha256 baseline_sha256 source_receipt_sha256))
        |> Map.merge(%{
          "case_id" => c["id"],
          "status" => "ok",
          "choice" => if(n == 1, do: "defer_candidate", else: "keep_baseline"),
          "elapsed_ms" => timings.candidate,
          "cost_nanos" => nil,
          "response_sha256" => JSON.sha256("constructed-response-#{n}")
        })
      end)

    %{
      spec: s,
      declaration: d,
      sha: JSON.digest([d]),
      labels: labels,
      rows: rows,
      load: fn sha -> Map.fetch(blobs, sha) end,
      blobs: blobs
    }
  end

  test "closed declaration freezes thresholds and identities before inputs or labels are opened" do
    f = fixture()
    assert :ok = A.verify(f.declaration, f.sha)
    refute f.declaration["execution_enabled"]
    assert {:error, _} = A.declare(Map.put(f.spec, "gates", %{"protocol" => "pass"}))
    assert {:error, _} = A.verify(put_in(f.declaration, ["bars", "p95_max_ratio"], [2, 1]), f.sha)
    assert {:error, _} = A.declare(put_in(f.spec, ["shared_limits", "model_calls"], 0))
    assert {:error, _} = A.declare(put_in(f.spec, ["version"], 1.0))
  end

  test "version two requires a closed decision profile commitment and keeps version one readable" do
    f = fixture()
    assert f.declaration["version"] === 1
    assert :ok = A.verify(f.declaration, f.sha)

    spec =
      f.spec
      |> Map.put("version", 2)
      |> put_in(["decision_route", "profile_sha256"], JSON.sha256("public profile"))

    assert {:ok, current} = A.declare(spec)
    assert current["version"] === 2
    assert :ok = A.verify(current, JSON.digest([current]))

    assert {:error, :invalid_candidate_experiment} =
             A.declare(update_in(spec, ["decision_route"], &Map.delete(&1, "profile_sha256")))

    assert {:error, :invalid_candidate_experiment} =
             A.declare(put_in(spec, ["decision_route", "profile_sha256"], "bad"))
  end

  test "input verification detects changed bytes and a mismatched ordinary observation" do
    f = fixture()
    assert {:ok, bs} = A.verify_inputs(f.declaration, f.sha, f.load)
    assert map_size(bs) == 2

    assert {:error, _} =
             A.verify_inputs(f.declaration, f.sha, fn sha ->
               {:ok, bytes} = f.load.(sha)
               {:ok, bytes <> " "}
             end)
  end

  test "one OFF path uses actual existing tool and commits exact matched input without label exposure" do
    f = fixture()
    c = hd(f.spec["cases"])
    assert {:ok, r} = A.execution(f.declaration, f.sha, c["id"])
    assert r["status"] == "off" and r["tool"] == "ext__knowledge__assess"
    assert r["arguments"] == %{"key" => c["candidate_key"]}
    assert r["input_sha256"] == c["input_sha256"]
    refute Map.has_key?(r, "label_commitment")
    refute Map.has_key?(r, "labels")
    assert {:error, _} = A.execution(f.declaration, f.sha, String.duplicate("f", 32))
  end

  test "favorable constructed arithmetic never qualifies supplied observations or gates" do
    f = fixture()
    assert {:ok, r} = score(f.declaration, f.sha, f.rows, f.labels, f.load)
    assert r["baseline"]["false_durable"] == 1
    assert r["candidate"]["false_durable"] == 0
    assert r["candidate"]["critical_kept"] == 1
    assert r["calculation"]["criteria"]["false_durable_reduction"] == "pass"
    assert r["calculation"]["criteria"]["latency"] == "pass"
    assert r["calculation"]["criteria"]["hard_gates"] == "unverified"
    assert r["disposition"] == "unverified" and r["qualification"] == "none"
    refute r["production_strategy_selectable"]
    assert is_nil(r["observed_cost_nanos"])
  end

  test "observed total cost is exact when representable and unmeasured on overflow or missing cost" do
    f = fixture()
    [first, second] = f.rows
    max = 9_007_199_254_740_991

    for {costs, expected} <- [{[max - 1, 1], max}, {[max, 1], nil}, {[max, nil], nil}] do
      rows = [
        Map.put(first, "cost_nanos", hd(costs)),
        Map.put(second, "cost_nanos", List.last(costs))
      ]

      assert {:ok, report} = score(f.declaration, f.sha, rows, f.labels, f.load)
      assert report["observed_cost_nanos"] === expected
      assert report["disposition"] === "unverified"
    end
  end

  test "pending observations cannot manufacture false durable benefit" do
    f = fixture(["pending", "pending"])
    assert {:ok, r} = score(f.declaration, f.sha, f.rows, f.labels, f.load)
    assert r["pending_cases"] == 2 and r["observed_durable_cases"] == 0
    assert r["baseline"]["false_durable"] == 0 and is_nil(r["calculation"])

    assert {:error, _} =
             A.declare(put_in(f.spec, ["cases", Access.at(0), "stratum"], "observed_durable"))
  end

  test "known durable outcomes preserve missing timing as unverified without losing their rows" do
    for timings <- [
          %{baseline: nil, candidate: nil},
          %{baseline: nil, candidate: 110},
          %{baseline: 100, candidate: nil}
        ] do
      f = fixture(["observed_durable", "observed_durable"], timings)
      assert {:ok, r} = score(f.declaration, f.sha, f.rows, f.labels, f.load)
      assert r["complete_known_rows"]
      assert r["statuses"] == %{"ok" => 2}
      assert r["baseline"]["p95_ms"] === timings.baseline
      assert r["candidate"]["p95_ms"] === timings.candidate
      assert r["calculation"]["criteria"]["latency"] === "unverified"
      assert r["disposition"] === "unverified"
    end
  end

  test "missing and unknown cases stay incomplete and cannot count as successful deferrals" do
    f = fixture()

    unknown =
      hd(f.rows)
      |> Map.merge(%{
        "status" => "unknown",
        "choice" => nil,
        "elapsed_ms" => nil,
        "response_sha256" => nil
      })

    assert {:ok, r} = score(f.declaration, f.sha, [unknown], f.labels, f.load)
    refute r["complete_known_rows"]
    assert r["statuses"] == %{"unknown" => 1, "missing" => 1}
    assert is_nil(r["candidate"]) and is_nil(r["calculation"])
    assert r["disposition"] == "unverified"
  end

  test "an actual abstention retains the ordinary baseline instead of silently dropping it" do
    f = fixture()
    [first, second] = f.rows
    first = Map.merge(first, %{"status" => "abstained", "choice" => nil})
    assert {:ok, r} = score(f.declaration, f.sha, [first, second], f.labels, f.load)
    assert r["candidate"]["false_durable"] == r["baseline"]["false_durable"]
    assert r["candidate"]["abstentions"] == 1
    assert r["calculation"]["criteria"]["false_durable_reduction"] == "fail"
  end

  test "an unavailable engine cannot acquire a successful observed row by declaration alone" do
    f = fixture()
    {:ok, d} = A.declare(put_in(f.spec, ["decision_route", "availability"], "unavailable"))
    assert {:error, _} = score(d, JSON.digest([d]), f.rows, f.labels, f.load)

    unavailable =
      Enum.map(
        f.rows,
        &Map.merge(&1, %{
          "status" => "unavailable",
          "choice" => nil,
          "elapsed_ms" => nil,
          "response_sha256" => nil
        })
      )

    assert {:ok, r} = score(d, JSON.digest([d]), unavailable, f.labels, f.load)
    assert r["statuses"] == %{"unavailable" => 2}
    assert is_nil(r["candidate"]) and r["disposition"] == "unverified"
  end

  test "duplicate, foreign and substituted rows refuse rather than being dropped" do
    f = fixture()

    for rows <- [
          [hd(f.rows), hd(f.rows)],
          [put_in(hd(f.rows), ["input_sha256"], JSON.sha256("other"))],
          [Map.put(hd(f.rows), "case_id", String.duplicate("f", 32))]
        ] do
      assert {:error, _} = score(f.declaration, f.sha, rows, f.labels, f.load)
    end
  end

  test "labels remain committed, complete and separate from the prediction recipe" do
    f = fixture()
    assert {:error, _} = score(f.declaration, f.sha, f.rows, f.labels <> " ", f.load)
    labels = Jason.decode!(f.labels) |> Map.put("independent", false) |> Jason.encode!()
    spec = Map.put(f.spec, "label_commitment", JSON.sha256(labels))
    {:ok, d} = A.declare(spec)
    assert {:error, _} = score(d, JSON.digest([d]), f.rows, labels, f.load)
  end

  test "the frozen study refuses contradictory label relationships" do
    f = fixture()

    for changes <- [
          %{"false" => true, "useful" => true, "critical" => false},
          %{"false" => false, "useful" => false, "critical" => true}
        ] do
      labels =
        f.labels
        |> Jason.decode!()
        |> update_in(["rows", Access.at(0)], &Map.merge(&1, changes))
        |> Jason.encode!()

      spec = Map.put(f.spec, "label_commitment", JSON.sha256(labels))
      {:ok, declaration} = A.declare(spec)
      assert {:error, _} = score(declaration, JSON.digest([declaration]), f.rows, labels, f.load)
    end
  end

  test "changed first predictions refuse before the label loader is called" do
    f = fixture()
    {:ok, predictions} = A.freeze_rows(f.declaration, f.sha, f.rows)
    first_sha = JSON.digest([predictions])
    changed = put_in(predictions, ["rows", Access.at(0), "choice"], "keep_baseline")

    labels = fn ->
      send(self(), :labels_opened)
      {:ok, f.labels}
    end

    assert {:error, _} = A.score(f.declaration, f.sha, changed, first_sha, labels, f.load)
    refute_received :labels_opened
    assert {:ok, _} = A.score(f.declaration, f.sha, predictions, first_sha, labels, f.load)
    assert_received :labels_opened
  end
end
