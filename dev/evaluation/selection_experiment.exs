Code.require_file("decision_metrics.exs", __DIR__)

defmodule Ipse.Development.Evaluation.SelectionExperiment do
  @moduledoc "Pure frozen selection study records; no actor, authority or model-quality qualification."
  alias Ipse.JSON
  alias Ipse.Development.Evaluation.{DecisionMetrics, Metrics}
  @error {:error, :invalid_selection_experiment}
  @safe 9_007_199_254_740_991
  @spec_keys ~w(version source_sha256 runtime_sha256 artifact_sha256 main_route_sha256 policy_sha256 engine label_commitment shared_limits cases)
  @case_keys ~w(id input_sha256 source_receipt_sha256 baseline_sha256)
  @row_keys ~w(case_id input_sha256 source_receipt_sha256 baseline_sha256 status selection_output_sha256 prediction members elapsed_ms cost_nanos)
  @baseline_keys ~w(case_id input_sha256 source_receipt_sha256 prediction members elapsed_ms cost_nanos)
  @resources ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos)
  @bars %{
    "supported_answer_gain_percentage_points" => 5,
    "cost_max_ratio" => [4, 5],
    "p95_max_ratio" => [6, 5],
    "critical_recall" => "no_regression",
    "citation_precision" => "no_regression"
  }

  def declare(spec) do
    with true <- exact?(spec, @spec_keys) and spec["version"] === 1,
         true <-
           Enum.all?(
             ~w(source_sha256 runtime_sha256 artifact_sha256 main_route_sha256 policy_sha256 label_commitment),
             &JSON.sha256?(spec[&1])
           ),
         true <- exact?(spec["engine"], ~w(id availability route_sha256)),
         true <- spec["engine"]["id"] in ~w(openai_decisions system_one loopback),
         true <-
           spec["engine"]["availability"] in ~w(available unavailable unverified synthetic_protocol_only),
         true <- JSON.sha256?(spec["engine"]["route_sha256"]),
         true <-
           exact?(spec["shared_limits"], @resources) and
             Enum.all?(Map.values(spec["shared_limits"]), &uint?/1),
         true <-
           is_list(spec["cases"]) and length(spec["cases"]) in 1..200 and
             unique?(spec["cases"], "id"),
         true <-
           Enum.all?(
             spec["cases"],
             &(exact?(&1, @case_keys) and id?(&1["id"]) and
                 Enum.all?(~w(input_sha256 source_receipt_sha256 baseline_sha256), fn k ->
                   JSON.sha256?(&1[k])
                 end))
           ) do
      {:ok,
       %{
         "version" => 1,
         "kind" => "selection_shadow_declaration",
         "spec" => spec,
         "bars" => @bars,
         "execution_enabled" => false
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def verify(d, sha) do
    with true <- JSON.sha256?(sha) and JSON.digest([d]) === sha,
         {:ok, rebuilt} <- declare(d["spec"]),
         true <- rebuilt === d,
         do: :ok,
         else: (_ -> @error)
  rescue
    _ -> @error
  end

  def execution(d, sha, id) do
    with :ok <- verify(d, sha),
         c when is_map(c) <- Enum.find(d["spec"]["cases"], &(&1["id"] === id)) do
      {:ok,
       %{
         "status" => "off",
         "tool" => "ext__knowledge__select_shadow",
         "case" => c,
         "declaration_sha256" => sha,
         "artifact_sha256" => d["spec"]["artifact_sha256"],
         "policy_sha256" => d["spec"]["policy_sha256"],
         "engine_availability" => d["spec"]["engine"]["availability"],
         "requires" =>
           ~w(actual_allocation complete_protected_reads original_source_leases native_approval shared_reservation current_release strict_saved no_replay),
         "context_mutation" => "none"
       }}
    else
      _ -> @error
    end
  end

  # Loading is caller-owned and read-only. Content hashes authenticate neither
  # labels nor source authority; native/Session owners must establish those.
  def verify_inputs(d, sha, load) when is_function(load, 1) do
    with :ok <- verify(d, sha) do
      baselines =
        Map.new(d["spec"]["cases"], fn c ->
          for k <- ~w(input_sha256 source_receipt_sha256), do: blob!(load, c[k])
          {:ok, b} = JSON.decode_unique(blob!(load, c["baseline_sha256"]))

          true =
            exact?(b, @baseline_keys) and b["case_id"] === c["id"] and
              b["input_sha256"] === c["input_sha256"] and
              b["source_receipt_sha256"] === c["source_receipt_sha256"]

          true =
            members?(b["members"], 16) and nullable?(b["elapsed_ms"]) and
              nullable?(b["cost_nanos"])

          {:ok, _} = Metrics.semantic([b["prediction"]], [])
          true = b["prediction"]["query_id"] === c["id"]
          {c["id"], b}
        end)

      {:ok, baselines}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def freeze_rows(d, sha, rows) do
    with :ok <- verify(d, sha),
         true <-
           is_list(rows) and length(rows) <= length(d["spec"]["cases"]) and
             unique?(rows, "case_id"),
         true <- Enum.all?(rows, &row?(&1, d)) do
      {:ok, %{"version" => 1, "declaration_sha256" => sha, "rows" => rows}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def score(d, sha, first, first_sha, labels_loader, load) do
    with {:ok, baselines} <- verify_inputs(d, sha, load),
         true <-
           exact?(first, ~w(version declaration_sha256 rows)) and JSON.sha256?(first_sha) and
             JSON.digest([first]) === first_sha,
         {:ok, ^first} <- freeze_rows(d, sha, first["rows"]),
         {:ok, labels_bytes} <- labels_loader.(),
         true <-
           is_binary(labels_bytes) and byte_size(labels_bytes) <= 1_048_576 and
             JSON.sha256(labels_bytes) === d["spec"]["label_commitment"],
         {:ok, labels} <- JSON.decode_unique(labels_bytes),
         true <- labels?(labels, d) do
      rows = Map.new(first["rows"], &{&1["case_id"], &1})

      complete =
        Enum.all?(
          d["spec"]["cases"],
          &(is_map(rows[&1["id"]]) and rows[&1["id"]]["status"] in ~w(ok refused))
        )

      {:ok, baseline, bs} = aggregate(d, baselines, labels, :baseline)
      candidate = if complete, do: aggregate(d, rows, labels, :candidate), else: nil

      measured =
        case candidate do
          {:ok, _, semantic} ->
            d["spec"]["engine"]["availability"] == "available" and
              Enum.all?(baselines, fn {_, b} -> b["prediction"]["status"] in ~w(ok refused) end) and
              semantic["support"]["complete"] and semantic["citation"]["complete"] and
              bs["support"]["complete"] and bs["citation"]["complete"]

          _ ->
            false
        end

      comparison =
        if measured do
          {:ok, value, _} = candidate

          gates =
            Map.new(
              ~w(protocol quality_bars citation_integrity matched_workload finite_resources paired_critical),
              &{&1, "unverified"}
            )

          {:ok, compared} = DecisionMetrics.selection(baseline, value, gates)
          compared
        end

      {:ok,
       %{
         "disposition" => "unverified",
         "qualification" => "none",
         "comparison" => comparison,
         "baseline" => baseline,
         "candidate" => if(candidate, do: elem(candidate, 1)),
         "baseline_semantics" => bs,
         "candidate_semantics" => if(candidate, do: elem(candidate, 2)),
         "known_rows_complete" => complete,
         "support_and_citations_measured" => measured,
         "engine" => d["spec"]["engine"],
         "first_prediction_sha256" => first_sha,
         "declaration_sha256" => sha,
         "truth_and_independence" => "asserted_not_verified"
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp row?(r, d) do
    c = Enum.find(d["spec"]["cases"], &(&1["id"] === r["case_id"]))

    exact?(r, @row_keys) and is_map(c) and
      Enum.all?(~w(input_sha256 source_receipt_sha256 baseline_sha256), &(r[&1] === c[&1])) and
      r["status"] in ~w(ok refused unknown cancelled unavailable missing) and
      members?(r["members"], 4) and nullable?(r["elapsed_ms"]) and nullable?(r["cost_nanos"]) and
      if(r["status"] in ~w(ok refused),
        do:
          JSON.sha256?(r["selection_output_sha256"]) and
            match?({:ok, _}, Metrics.semantic([r["prediction"]], [])) and
            r["prediction"]["query_id"] === c["id"] and r["prediction"]["status"] === r["status"],
        else:
          r["prediction"] == nil and r["selection_output_sha256"] == nil and r["members"] == []
      ) and
      (d["spec"]["engine"]["availability"] != "unavailable" or r["status"] == "unavailable")
  end

  defp labels?(labels, d),
    do:
      exact?(labels, ~w(version rows)) and labels["version"] === 1 and is_list(labels["rows"]) and
        length(labels["rows"]) === length(d["spec"]["cases"]) and
        unique?(labels["rows"], "case_id") and
        Enum.all?(labels["rows"], fn r ->
          exact?(r, ~w(case_id baseline candidate critical_members)) and
            Enum.any?(d["spec"]["cases"], &(&1["id"] === r["case_id"])) and
            members?(r["critical_members"], 16)
        end)

  defp aggregate(d, rows, labels, kind) do
    label_map = Map.new(labels["rows"], &{&1["case_id"], &1})
    values = Enum.map(d["spec"]["cases"], &rows[&1["id"]])
    reviews = Enum.map(d["spec"]["cases"], &label_map[&1["id"]][Atom.to_string(kind)])
    {:ok, semantic} = Metrics.semantic(Enum.map(values, & &1["prediction"]), reviews)
    elapsed = Enum.map(values, & &1["elapsed_ms"])
    {:ok, p95} = Metrics.nearest_rank(Enum.filter(elapsed, &uint?/1), 0.95)
    costs = Enum.map(values, & &1["cost_nanos"])
    critical = Enum.filter(d["spec"]["cases"], &(label_map[&1["id"]]["critical_members"] != []))

    {:ok,
     %{
       "cases" => length(values),
       "supported" => semantic["support"]["correct_n"],
       "abstentions" => Enum.count(values, &(&1["prediction"]["response_kind"] == "abstention")),
       "critical_total" => length(critical),
       "critical_recalled" =>
         Enum.count(critical, fn c ->
           Enum.all?(label_map[c["id"]]["critical_members"], &(&1 in rows[c["id"]]["members"]))
         end),
       "citation_total" => semantic["citation"]["total_n"],
       "citation_supported" => semantic["citation"]["supported_n"],
       "p95_ms" => if(Enum.all?(elapsed, &uint?/1), do: p95),
       "cost_nanos" => if(Enum.all?(costs, &uint?/1), do: Enum.sum(costs))
     }, semantic}
  end

  defp blob!(load, sha) do
    {:ok, bytes} = load.(sha)
    true = is_binary(bytes) and byte_size(bytes) <= 1_048_576 and JSON.sha256(bytes) === sha
    bytes
  end

  defp members?(x, n),
    do:
      is_list(x) and length(x) <= n and length(Enum.uniq(x)) === length(x) and
        Enum.all?(x, &(is_binary(&1) and Regex.match?(~r/\Anote\.[0-9a-f]{64}\z/, &1)))

  defp unique?(x, k), do: length(Enum.uniq_by(x, & &1[k])) === length(x)
  defp exact?(x, k), do: is_map(x) and Enum.sort(Map.keys(x)) === Enum.sort(k)
  defp nullable?(x), do: is_nil(x) or uint?(x)
  defp uint?(x), do: is_integer(x) and x in 0..@safe
  defp id?(x), do: is_binary(x) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}\z/, x)
end
