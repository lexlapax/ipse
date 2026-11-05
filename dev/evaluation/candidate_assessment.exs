Code.require_file("decision_metrics.exs", __DIR__)

defmodule Ipse.Development.Evaluation.CandidateAssessment do
  @moduledoc """
  Bounded declaration and arithmetic for a matched candidate shadow experiment.

  This adapter executes no work. Its recipe is OFF; a reviewed Session owner must
  materialize it through the existing shadow artifact and shared Consent ledger.
  Hashes bind observations, not their truth or source authority. Scoring never
  treats a supplied gate or reviewer identity as verified evidence.
  """
  alias Ipse.JSON
  alias Ipse.Development.Evaluation.{DecisionMetrics, Metrics}
  @error {:error, :invalid_candidate_experiment}
  @safe 9_007_199_254_740_991
  @resources ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos)
  @bars %{
    "false_durable_max_ratio" => [4, 5],
    "useful_loss_percentage_points" => 2,
    "critical_loss_percentage_points" => 2,
    "p95_max_ratio" => [6, 5],
    "minimum_probability" => 0.8,
    "minimum_margin" => 0.2
  }
  @spec_fields ~w(version kind source_sha256 runtime_sha256 artifact_sha256 main_route_sha256 decision_route policy_sha256 label_commitment shared_limits cases)
  @case ~w(id stratum candidate_key input_sha256 baseline_sha256 source_receipt_sha256)
  @baseline ~w(version case_id input_sha256 source_receipt_sha256 candidate_key stratum baseline admission journal_sha256 operation_id elapsed_ms cost_nanos)
  @row ~w(case_id input_sha256 baseline_sha256 source_receipt_sha256 status choice elapsed_ms cost_nanos response_sha256)
  @statuses ~w(ok abstained denied refused unknown cancelled unavailable missing)

  def declare(spec) do
    if spec?(spec) do
      {:ok,
       %{
         "version" => 1,
         "kind" => "candidate_shadow_declaration",
         "spec" => spec,
         "bars" => @bars,
         "execution_enabled" => false
       }}
    else
      @error
    end
  rescue
    _ -> @error
  end

  def verify(declaration, expected_sha256) do
    with true <- JSON.sha256?(expected_sha256),
         true <- JSON.digest([declaration]) === expected_sha256,
         {:ok, rebuilt} <- declare(declaration["spec"]),
         true <- rebuilt === declaration do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Resolve only committed input bytes. The caller owns file access and confinement."
  def verify_inputs(declaration, expected_sha256, load) when is_function(load, 1) do
    with :ok <- verify(declaration, expected_sha256) do
      baselines =
        Map.new(declaration["spec"]["cases"], fn c ->
          for key <- ~w(input_sha256 source_receipt_sha256), do: blob!(load, c[key])
          {:ok, baseline} = JSON.decode_unique(blob!(load, c["baseline_sha256"]))
          true = baseline?(baseline, c)
          {c["id"], baseline}
        end)

      {:ok, baselines}
    end
  rescue
    _ -> @error
  end

  def verify_inputs(_, _, _), do: @error

  @doc "One matched existing-artifact invocation recipe; no permission or executable callback."
  def execution(declaration, expected_sha256, case_id) do
    with :ok <- verify(declaration, expected_sha256),
         c when is_map(c) <- Enum.find(declaration["spec"]["cases"], &(&1["id"] === case_id)) do
      {:ok,
       %{
         "status" => "off",
         "declaration_sha256" => expected_sha256,
         "case_id" => case_id,
         "stratum" => c["stratum"],
         "input_sha256" => c["input_sha256"],
         "baseline_sha256" => c["baseline_sha256"],
         "source_receipt_sha256" => c["source_receipt_sha256"],
         "artifact_sha256" => declaration["spec"]["artifact_sha256"],
         "tool" => "ext__knowledge__assess",
         "arguments" => %{"key" => c["candidate_key"]},
         "fixture" => "test/support/shadow_pending_candidate_cli.exs",
         "requires" =>
           ~w(closed_original_source current_source_revalidation separate_native_approval shared_consent_reservation journal_before_egress current_output_release strict_saved idle_no_replay),
         "note_mutation" => "none"
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Arithmetic only. Missing rows remain unverified, and pending rows are not durable claims."
  def freeze_rows(declaration, expected_sha256, rows) do
    with :ok <- verify(declaration, expected_sha256), true <- rows?(rows, declaration) do
      {:ok, %{"version" => 1, "declaration_sha256" => expected_sha256, "rows" => rows}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Expose labels only after rechecking the externally retained first-row commitment."
  def score(declaration, expected_sha256, predictions, prediction_sha256, labels_loader, load)
      when is_function(labels_loader, 0) do
    with {:ok, baselines} <- verify_inputs(declaration, expected_sha256, load),
         true <- exact?(predictions, ~w(version declaration_sha256 rows)),
         true <-
           JSON.sha256?(prediction_sha256) and JSON.digest([predictions]) === prediction_sha256,
         {:ok, ^predictions} <- freeze_rows(declaration, expected_sha256, predictions["rows"]),
         {:ok, labels_bytes} <- labels_loader.(),
         true <- is_binary(labels_bytes) and byte_size(labels_bytes) <= 1_048_576,
         true <- JSON.sha256(labels_bytes) === declaration["spec"]["label_commitment"],
         {:ok, labels} <- JSON.decode_unique(labels_bytes),
         true <- labels?(labels, declaration) do
      rows = predictions["rows"]
      cases = declaration["spec"]["cases"]
      row_map = Map.new(rows, &{&1["case_id"], &1})
      durable = Enum.filter(cases, &(&1["stratum"] === "observed_durable"))
      durable_ids = MapSet.new(durable, & &1["id"])
      label_map = Map.new(labels["rows"], &{&1["case_id"], &1})
      complete = Enum.all?(cases, &known?(row_map[&1["id"]]))
      base = aggregate(durable, baselines, row_map, label_map, :baseline)
      durable_complete = Enum.all?(durable, &known?(row_map[&1["id"]]))

      candidate =
        if durable_complete, do: aggregate(durable, baselines, row_map, label_map, :candidate)

      comparison =
        if durable == [] or not durable_complete do
          nil
        else
          {:ok, value} =
            DecisionMetrics.assessment(base, candidate, %{
              "protocol" => "unverified",
              "matched_workload" => "unverified",
              "finite_cost_cap" => "unverified"
            })

          value
        end

      costs = Enum.map(rows, & &1["cost_nanos"])

      {:ok,
       %{
         "version" => 1,
         "declaration_sha256" => expected_sha256,
         "prediction_sha256" => prediction_sha256,
         "disposition" => "unverified",
         "qualification" => "none",
         "evidence_scope" => "hash_bound_unreviewed_observations",
         "independent_review" => "asserted_not_verified",
         "complete_known_rows" => complete,
         "cases" => length(cases),
         "observed_durable_cases" => MapSet.size(durable_ids),
         "pending_cases" => length(cases) - MapSet.size(durable_ids),
         "statuses" =>
           Enum.frequencies(
             Enum.map(cases, &(get_in(row_map, [&1["id"], "status"]) || "missing"))
           ),
         "baseline" => base,
         "candidate" => candidate,
         "calculation" => comparison,
         "observed_cost_nanos" =>
           if(Enum.all?(costs, &uint?/1) and length(rows) === length(cases), do: Enum.sum(costs)),
         "finite_ledger_authority" => "unverified",
         "production_strategy_selectable" => false
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def score(_, _, _, _, _, _), do: @error

  defp aggregate(cases, baselines, rows, labels, kind) do
    kept = fn c ->
      b = baselines[c["id"]]
      r = rows[c["id"]]

      b["baseline"] === "keep" and
        (kind === :baseline or
           (known?(r) and (r["status"] === "abstained" or r["choice"] === "keep_baseline")))
    end

    elapsed =
      Enum.map(cases, fn c ->
        if kind === :baseline,
          do: baselines[c["id"]]["elapsed_ms"],
          else: get_in(rows, [c["id"], "elapsed_ms"])
      end)

    {:ok, p95} = Metrics.nearest_rank(Enum.filter(elapsed, &uint?/1), 0.95)

    Enum.reduce(
      ~w(false useful critical),
      %{
        "candidates" => length(cases),
        "abstentions" =>
          if(kind === :baseline,
            do: 0,
            else:
              Enum.count(
                cases,
                &(not known?(rows[&1["id"]]) or rows[&1["id"]]["status"] !== "ok")
              )
          ),
        "p95_ms" => if(Enum.all?(elapsed, &uint?/1), do: p95)
      },
      fn label, acc ->
        selected = Enum.filter(cases, &(labels[&1["id"]][label] === true))

        acc
        |> Map.put(label <> "_total", length(selected))
        |> Map.put(
          label <> if(label === "false", do: "_durable", else: "_kept"),
          Enum.count(selected, kept)
        )
      end
    )
  end

  defp blob!(load, digest) do
    {:ok, bytes} = load.(digest)
    true = is_binary(bytes) and byte_size(bytes) in 1..1_048_576
    true = JSON.sha256(bytes) === digest
    bytes
  end

  defp baseline?(b, c) do
    exact?(b, @baseline) and b["version"] === 1 and
      b["case_id"] === c["id"] and
      Enum.all?(~w(input_sha256 source_receipt_sha256 candidate_key stratum), &(b[&1] === c[&1])) and
      b["baseline"] in ~w(keep omit) and JSON.sha256?(b["journal_sha256"]) and
      id?(b["operation_id"]) and
      nullable_uint?(b["elapsed_ms"]) and nullable_uint?(b["cost_nanos"]) and
      ((c["stratum"] === "pending" and b["admission"] === "pending") or
         (c["stratum"] === "observed_durable" and b["admission"] === "durable" and
            b["baseline"] === "keep"))
  end

  defp spec?(s) do
    exact?(s, @spec_fields) and s["version"] === 1 and s["kind"] === "candidate_shadow" and
      Enum.all?(
        ~w(source_sha256 runtime_sha256 artifact_sha256 main_route_sha256 policy_sha256 label_commitment),
        &JSON.sha256?(s[&1])
      ) and
      exact?(s["decision_route"], ~w(engine model rubric_sha256 availability)) and
      s["decision_route"]["engine"] in ~w(openai_decisions typesafe_jev compatible_loopback) and
      text?(s["decision_route"]["model"]) and JSON.sha256?(s["decision_route"]["rubric_sha256"]) and
      s["decision_route"]["availability"] in ~w(unverified_access unavailable available) and
      exact?(s["shared_limits"], @resources) and
      Enum.all?(Map.values(s["shared_limits"]), &uint?/1) and
      s["shared_limits"]["operations"] > 0 and s["shared_limits"]["model_calls"] > 0 and
      is_list(s["cases"]) and length(s["cases"]) in 1..200 and
      Enum.all?(s["cases"], &case?/1) and unique?(s["cases"], "id") and
      unique?(s["cases"], "candidate_key")
  end

  defp case?(c) do
    exact?(c, @case) and id?(c["id"]) and c["stratum"] in ~w(pending observed_durable) and
      is_binary(c["candidate_key"]) and
      Regex.match?(~r/\A(?:pending|note)\.[0-9a-f]{64}\z/, c["candidate_key"]) and
      String.starts_with?(
        c["candidate_key"],
        if(c["stratum"] === "pending", do: "pending.", else: "note.")
      ) and
      Enum.all?(~w(input_sha256 baseline_sha256 source_receipt_sha256), &JSON.sha256?(c[&1]))
  end

  defp labels?(l, d) do
    exact?(l, ~w(version reviewer_id independent rows)) and l["version"] === 1 and
      text?(l["reviewer_id"]) and l["independent"] === true and
      is_list(l["rows"]) and length(l["rows"]) <= 200 and
      Enum.all?(l["rows"], fn r ->
        exact?(r, ~w(case_id false useful critical)) and id?(r["case_id"]) and
          Enum.all?(~w(false useful critical), &is_boolean(r[&1])) and
          not (r["false"] and r["useful"]) and (not r["critical"] or r["useful"])
      end) and unique?(l["rows"], "case_id") and
      Enum.sort(Enum.map(l["rows"], & &1["case_id"])) ===
        Enum.sort(Enum.map(d["spec"]["cases"], & &1["id"]))
  end

  defp rows?(rows, d) do
    cases = Map.new(d["spec"]["cases"], &{&1["id"], &1})

    is_list(rows) and length(rows) <= map_size(cases) and unique?(rows, "case_id") and
      Enum.all?(rows, fn r ->
        c = cases[r["case_id"]]

        exact?(r, @row) and is_map(c) and
          Enum.all?(~w(input_sha256 baseline_sha256 source_receipt_sha256), &(r[&1] === c[&1])) and
          r["status"] in @statuses and
          (d["spec"]["decision_route"]["availability"] !== "unavailable" or
             r["status"] in ~w(unavailable missing)) and nullable_uint?(r["elapsed_ms"]) and
          nullable_uint?(r["cost_nanos"]) and
          (is_nil(r["response_sha256"]) or JSON.sha256?(r["response_sha256"])) and
          if(r["status"] === "ok",
            do:
              r["choice"] in ~w(keep_baseline defer_candidate) and
                JSON.sha256?(r["response_sha256"]),
            else: is_nil(r["choice"])
          )
      end)
  end

  defp known?(r), do: is_map(r) and r["status"] in ~w(ok abstained)
  defp unique?(rows, key), do: length(rows) === length(Enum.uniq_by(rows, & &1[key]))
  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) === Enum.sort(keys)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp text?(v), do: is_binary(v) and byte_size(v) in 1..256 and String.valid?(v)
  defp uint?(v), do: is_integer(v) and v in 0..@safe
  defp nullable_uint?(v), do: is_nil(v) or uint?(v)
end
