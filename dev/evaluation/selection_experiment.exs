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
    "abstention_max_increase_percentage_points" => 5,
    "cost_max_ratio" => [4, 5],
    "p95_max_ratio" => [6, 5],
    "critical_recall" => "no_regression",
    "citation_precision" => "no_regression"
  }

  def declare(spec) do
    with true <- exact?(spec, @spec_keys) and spec["version"] in [1, 2],
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
         "version" => spec["version"],
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
    with true <- d["version"] === 1,
         {:ok, baselines} <- verified_first(d, sha, first, first_sha, load),
         {:ok, labels_bytes} <- labels_loader.(),
         true <-
           is_binary(labels_bytes) and byte_size(labels_bytes) <= 1_048_576 and
             JSON.sha256(labels_bytes) === d["spec"]["label_commitment"],
         {:ok, labels} <- JSON.decode_unique(labels_bytes),
         true <- labels?(labels, d) do
      report(d, sha, first, first_sha, baselines, labels)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Validate reference-only bytes for commitment before either answer is produced. Custody and chronology remain caller-owned."
  def commit_references(bytes) do
    with true <- is_binary(bytes) and byte_size(bytes) <= 1_048_576,
         {:ok, references} <- JSON.decode_unique(bytes),
         true <- references?(references) do
      {:ok, JSON.sha256(bytes)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Check version-two committed references before candidate work; no prediction IDs or semantic verdicts are accepted here."
  def verify_references(d, sha, loader) do
    with :ok <- verify(d, sha),
         true <- d["version"] === 2,
         {:ok, bytes} <- loader.(),
         {:ok, commitment} <- commit_references(bytes),
         true <- commitment === d["spec"]["label_commitment"],
         {:ok, references} <- JSON.decode_unique(bytes),
         true <- case_ids(references["rows"], "case_id") === case_ids(d["spec"]["cases"], "id") do
      {:ok, references}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Prepare unmeasured reviews only after verifying the actual first rows and complete baseline blobs. A binding is not proof of independence."
  def prepare_reviews(d, sha, first, first_sha, load) do
    with true <- d["version"] === 2,
         {:ok, baselines} <- verified_first(d, sha, first, first_sha, load) do
      {:ok,
       %{
         "version" => 2,
         "review_binding_sha256" => review_binding(sha, first_sha),
         "semantic" =>
           predictions(baselines, first)
           |> Enum.sort_by(& &1["prediction_id"])
           |> Enum.map(&unmeasured_review/1)
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Score version two with precommitted references and a separate post-prediction review loader. Version one retains score/6."
  def score(d, sha, first, first_sha, reference_loader, review_loader, load) do
    with true <- d["version"] === 2,
         {:ok, baselines} <- verified_first(d, sha, first, first_sha, load),
         {:ok, references} <- verify_references(d, sha, reference_loader),
         {:ok, bytes} <- review_loader.(),
         true <- is_binary(bytes) and byte_size(bytes) <= 1_048_576,
         {:ok, reviews} <- JSON.decode_unique(bytes),
         true <- reviews?(reviews, d, sha, first, first_sha, baselines) do
      by_id = Map.new(reviews["semantic"], &{&1["prediction_id"], &1})
      rows = Map.new(first["rows"], &{&1["case_id"], &1})

      labels = %{
        "rows" =>
          Enum.map(references["rows"], fn r ->
            Map.merge(r, %{
              "baseline" => by_id[baselines[r["case_id"]]["prediction"]["prediction_id"]],
              "candidate" => by_id[get_in(rows, [r["case_id"], "prediction", "prediction_id"])]
            })
          end)
      }

      with {:ok, result} <- report(d, sha, first, first_sha, baselines, labels),
           do: {:ok, Map.put(result, "review_binding_sha256", reviews["review_binding_sha256"])}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp report(d, sha, first, first_sha, baselines, labels) do
    rows = Map.new(first["rows"], &{&1["case_id"], &1})
    {:ok, paired_critical} = paired_critical(d["spec"]["cases"], baselines, rows, labels)

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
      if measured and is_integer(baseline["critical_recalled"]) and
           is_integer(elem(candidate, 1)["critical_recalled"]) do
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
       "paired_critical_observation" =>
         Map.put(paired_critical, "scope", "hash_bound_membership_not_independent_review"),
       "known_rows_complete" => complete,
       "support_and_citations_measured" => measured,
       "engine" => d["spec"]["engine"],
       "first_prediction_sha256" => first_sha,
       "declaration_sha256" => sha,
       "truth_and_independence" => "asserted_not_verified"
     }}
  end

  defp paired_critical(cases, baselines, rows, labels) do
    labels = Map.new(labels["rows"], &{&1["case_id"], &1["critical_members"]})

    queries =
      Enum.map(cases, fn c ->
        %{"query_id" => c["id"], "applicable" => labels[c["id"]] != []}
      end)

    baseline =
      Enum.map(cases, fn c ->
        row = baselines[c["id"]]
        paired_member_row(c["id"], row["prediction"]["status"], row["members"], labels[c["id"]])
      end)

    candidate =
      Enum.flat_map(cases, fn c ->
        case rows[c["id"]] do
          nil -> []
          row -> [paired_member_row(c["id"], row["status"], row["members"], labels[c["id"]])]
        end
      end)

    DecisionMetrics.critical_pairs(queries, baseline, candidate)
  end

  defp paired_member_row(id, "ok", members, critical) do
    %{
      "query_id" => id,
      "status" => "ok",
      "value" => if(Enum.all?(critical, &(&1 in members)), do: 1, else: 0)
    }
  end

  defp paired_member_row(id, _, _, _),
    do: %{"query_id" => id, "status" => "failed", "value" => nil}

  defp verified_first(d, sha, first, first_sha, load) do
    with {:ok, baselines} <- verify_inputs(d, sha, load),
         true <-
           exact?(first, ~w(version declaration_sha256 rows)) and JSON.sha256?(first_sha) and
             JSON.digest([first]) === first_sha,
         {:ok, ^first} <- freeze_rows(d, sha, first["rows"]),
         true <- prediction_populations?(d, baselines, first) do
      {:ok, baselines}
    else
      _ -> @error
    end
  end

  defp references?(r) do
    exact?(r, ~w(version rows)) and r["version"] === 2 and is_list(r["rows"]) and
      length(r["rows"]) in 1..200 and unique?(r["rows"], "case_id") and
      Enum.all?(
        r["rows"],
        &(exact?(&1, ~w(case_id critical_members)) and id?(&1["case_id"]) and
            members?(&1["critical_members"], 16))
      )
  end

  defp prediction_populations?(%{"version" => 1}, _, _), do: true

  defp prediction_populations?(_, baselines, first) do
    values = predictions(baselines, first)

    match?({:ok, _}, Metrics.semantic(values, [])) and
      Enum.all?(values, fn p ->
        JSON.sha256?(p["prediction_id"]) and
          Enum.all?(p["citations"], &JSON.sha256?(&1["citation_id"]))
      end)
  end

  defp predictions(baselines, first),
    do:
      (Map.values(baselines) ++ first["rows"])
      |> Enum.map(& &1["prediction"])
      |> Enum.reject(&is_nil/1)

  defp reviews?(reviews, _d, sha, first, first_sha, baselines) do
    values = predictions(baselines, first)

    exact?(reviews, ~w(version review_binding_sha256 semantic)) and reviews["version"] === 2 and
      reviews["review_binding_sha256"] === review_binding(sha, first_sha) and
      is_list(reviews["semantic"]) and
      case_ids(reviews["semantic"], "prediction_id") === case_ids(values, "prediction_id") and
      match?({:ok, _}, Metrics.semantic(values, reviews["semantic"]))
  end

  defp case_ids(rows, key), do: rows |> Enum.map(& &1[key]) |> Enum.sort()

  defp review_binding(sha, first_sha),
    do: JSON.digest(["ipse-selection-review-binding", 2, sha, first_sha])

  defp unmeasured_review(nil), do: nil

  defp unmeasured_review(p) do
    %{
      "prediction_id" => p["prediction_id"],
      "verdict" => "unmeasured",
      "reviewer_id" => "unassigned",
      "independent" => false,
      "citations" =>
        Enum.map(
          p["citations"],
          &%{"citation_id" => &1["citation_id"], "verdict" => "unmeasured"}
        )
    }
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
         if Enum.all?(critical, &(rows[&1["id"]]["prediction"]["status"] === "ok")) do
           Enum.count(critical, fn c ->
             Enum.all?(label_map[c["id"]]["critical_members"], &(&1 in rows[c["id"]]["members"]))
           end)
         end,
       "citation_total" => semantic["citation"]["total_n"],
       "citation_supported" => semantic["citation"]["supported_n"],
       "p95_ms" => if(Enum.all?(elapsed, &uint?/1), do: p95),
       "cost_nanos" => Metrics.bounded_uint_sum(costs)
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
