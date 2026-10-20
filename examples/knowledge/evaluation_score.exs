Code.require_file("metrics.exs", __DIR__)

defmodule IpseKnowledge.EvaluationScore do
  @moduledoc """
  Scoring-only library for finalized first-attempt predictions.

  `score/4` verifies all raw prediction hashes and closed JSONL rows before invoking
  either arity-zero loader. Loaders return normalized string-keyed data; the root
  orchestrator owns file access, frozen identities and independent review. This
  boundary cannot prove that a caller has never previously exposed labels.

  Literal annotated-span coverage is coordinate-based and separate from semantic
  support. Semantic verdicts and captured-source integrity are explicit independent
  review inputs. `expected_refusal` comes from labels only after hash verification.
  No predictor receives that annotation. Retrieval-only rows have no answer metrics.

  Limits are 16 variants, 1024 declared queries, 32 files, 64 MiB per file, 64 MiB
  total prediction bytes, 16384 rows, 256 KiB per row, 8192 bytes per body string,
  64 claims, 128 evidence spans and 256 claim/span pairs per prediction. JSON depth
  is 12, objects have at most 128 keys and arrays at most 1024 elements. Normalized
  labels have at most 65536 relevance spans; integrity reviews at most 131072 rows.
  Thresholds are fixed at 0.90 support accuracy and 0.95 semantic citation precision.
  This report does not measure authority, isolation, replay or platform gates.
  """
  alias IpseKnowledge.Metrics
  @statuses ~w(ok partial failed refused timeout unavailable missing cancelled)
  @classes ~w(answer conflict open abstain)
  @source_keys ~w(project source_id generation version sha256)
  @prediction_keys ~w(version prediction_id variant query_id project attempt status top_k predicted_class response_kind answer claims evidence context_evidence citations)
  @safe_integer 9_007_199_254_740_991

  @doc "Verify closed first-attempt rows and raw hashes without loading labels or reviews."
  def verified_predictions(freeze, blobs) do
    try do
      {files, rows} = verified_predictions!(freeze, blobs)
      {:ok, %{"files" => files, "rows" => rows}}
    rescue
      _ -> {:error, :scoring_failed}
    catch
      {:evaluation_score, code} -> {:error, code}
    end
  end

  defp verified_predictions!(freeze, blobs) do
    require!(freeze?(freeze), :invalid_freeze)
    {verify_blobs!(freeze["files"], blobs), decode_predictions!(freeze, blobs)}
  end

  def score(freeze, blobs, labels_loader, review_loader) do
    try do
      require!(freeze?(freeze), :invalid_freeze)
      require!(is_function(labels_loader, 0) and is_function(review_loader, 0), :invalid_loader)
      {verified, saved} = verified_predictions!(freeze, blobs)
      labels = load!(labels_loader, :labels_failed)
      require!(labels?(labels, freeze), :invalid_labels)
      reviews = load!(review_loader, :review_failed)
      require!(reviews?(reviews, saved), :invalid_reviews)
      build_report(freeze, verified, saved, labels["queries"], reviews)
    rescue
      _ -> {:error, :scoring_failed}
    catch
      {:evaluation_score, code} -> {:error, code}
    end
  end

  defp freeze?(f) do
    exact?(f, ~w(version metric_version variants baseline queries files classification_map)) and
      f["version"] === 1 and f["metric_version"] === Metrics.version() and
      bounded_list?(f["variants"], 1, 16) and Enum.all?(f["variants"], &id?/1) and
      unique_values?(f["variants"]) and f["baseline"] in f["variants"] and
      bounded_list?(f["queries"], 1, 1024) and unique?(f["queries"], "query_id") and
      Enum.all?(f["queries"], fn q ->
        exact?(q, ~w(query_id project)) and id?(q["query_id"]) and id?(q["project"])
      end) and
      bounded_list?(f["files"], 1, 32) and unique?(f["files"], "id") and
      Enum.all?(f["files"], fn x ->
        exact?(x, ~w(id sha256)) and id?(x["id"]) and hash?(x["sha256"])
      end) and
      is_map(f["classification_map"]) and map_size(f["classification_map"]) in 1..32 and
      Enum.all?(f["classification_map"], fn {key, value} ->
        id?(key) and (is_nil(value) or value in @classes)
      end)
  end

  defp verify_blobs!(files, blobs) do
    require!(
      is_map(blobs) and Enum.sort(Map.keys(blobs)) == Enum.sort(Enum.map(files, & &1["id"])),
      :invalid_prediction_blobs
    )

    sizes =
      Enum.map(files, fn file ->
        bytes = blobs[file["id"]]

        require!(
          is_binary(bytes) and byte_size(bytes) <= 64 * 1024 * 1024,
          :prediction_size_limit
        )

        byte_size(bytes)
      end)

    require!(Enum.sum(sizes) <= 64 * 1024 * 1024, :prediction_size_limit)

    Enum.map(files, fn file ->
      require!(sha256(blobs[file["id"]]) == file["sha256"], :prediction_hash_mismatch)
      file
    end)
  end

  defp decode_predictions!(freeze, blobs) do
    query_map = Map.new(freeze["queries"], &{&1["query_id"], &1["project"]})

    rows =
      Enum.reduce(freeze["files"], [], fn file, all ->
        bytes = blobs[file["id"]]
        require!(String.valid?(bytes), :invalid_prediction_json)
        lines = String.split(bytes, "\n", parts: 16_386)
        lines = if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
        require!(length(all) + length(lines) <= 16_384, :prediction_row_limit)

        decoded =
          Enum.map(lines, fn line ->
            require!(byte_size(line) in 1..262_144, :prediction_row_limit)
            row = decode_row!(String.trim(line))
            require!(prediction?(row, freeze, query_map), :invalid_prediction)
            row
          end)

        all ++ decoded
      end)

    require!(unique?(rows, "prediction_id"), :duplicate_prediction)

    require!(
      length(rows) == length(Enum.uniq_by(rows, &{&1["variant"], &1["query_id"]})),
      :duplicate_prediction
    )

    rows
  end

  defp decode_row!(line) do
    callbacks = %{
      null: nil,
      string: fn text ->
        require!(text?(text, 8192), :prediction_text_limit)
        text
      end,
      integer: fn bytes ->
        require!(byte_size(bytes) <= 32, :invalid_prediction_json)
        String.to_integer(bytes)
      end,
      float: fn bytes ->
        require!(byte_size(bytes) <= 64, :invalid_prediction_json)
        :erlang.binary_to_float(bytes)
      end,
      object_start: fn parent ->
        require!(parent.depth < 12, :prediction_depth_limit)
        %{depth: parent.depth + 1, values: %{}}
      end,
      object_push: fn key, value, acc ->
        require!(not Map.has_key?(acc.values, key), :duplicate_prediction_key)
        require!(map_size(acc.values) < 128, :prediction_collection_limit)
        %{acc | values: Map.put(acc.values, key, value)}
      end,
      object_finish: fn acc, parent -> {acc.values, parent} end,
      array_start: fn parent ->
        require!(parent.depth < 12, :prediction_depth_limit)
        %{depth: parent.depth + 1, values: [], count: 0}
      end,
      array_push: fn value, acc ->
        require!(acc.count < 1024, :prediction_collection_limit)
        %{acc | values: [value | acc.values], count: acc.count + 1}
      end,
      array_finish: fn acc, parent -> {Enum.reverse(acc.values), parent} end
    }

    try do
      {row, _, rest} = :json.decode(line, %{depth: 0}, callbacks)
      require!(rest == "" and is_map(row), :invalid_prediction_json)
      row
    rescue
      _ -> fail!(:invalid_prediction_json)
    end
  end

  defp prediction?(p, freeze, queries) do
    exact?(p, @prediction_keys) and p["version"] === 2 and id?(p["prediction_id"]) and
      not String.starts_with?(p["prediction_id"], "missing:") and
      p["variant"] in freeze["variants"] and Map.has_key?(queries, p["query_id"]) and
      queries[p["query_id"]] == p["project"] and
      p["attempt"] === 1 and p["status"] in @statuses and integer?(p["top_k"], 1, 128) and
      (is_nil(p["predicted_class"]) or
         Map.has_key?(freeze["classification_map"], p["predicted_class"])) and
      p["response_kind"] in ~w(answer abstention retrieval_only) and
      nullable_text?(p["answer"], 8192) and
      bounded_list?(p["claims"], 0, 64) and unique?(p["claims"], "claim_id") and
      Enum.all?(p["claims"], fn c ->
        exact?(c, ~w(claim_id text)) and id?(c["claim_id"]) and text?(c["text"], 2048)
      end) and
      bounded_list?(p["evidence"], 0, p["top_k"]) and unique?(p["evidence"], "span_id") and
      Enum.all?(p["evidence"], &span?/1) and
      bounded_list?(p["context_evidence"], 0, 10) and
      Enum.all?(p["context_evidence"], fn span ->
        span?(span) and Enum.any?(p["evidence"], &contains?(&1, span))
      end) and unique?(all_spans(p), "span_id") and
      bounded_list?(p["citations"], 0, 256) and unique?(p["citations"], "citation_id") and
      Enum.all?(p["citations"], fn c ->
        exact?(c, ~w(citation_id claim_id span_id)) and id?(c["citation_id"]) and
          Enum.any?(p["claims"], &(&1["claim_id"] == c["claim_id"])) and
          Enum.any?(all_spans(p), &(&1["span_id"] == c["span_id"]))
      end) and
      (p["response_kind"] != "retrieval_only" or
         (p["claims"] == [] and p["citations"] == [] and p["context_evidence"] == [] and
            is_nil(p["answer"])))
  end

  defp labels?(labels, freeze) do
    exact?(labels, ~w(version queries)) and labels["version"] === 1 and is_list(labels["queries"]) and
      length(labels["queries"]) == length(freeze["queries"]) and
      unique?(labels["queries"], "query_id") and
      Enum.sort(Enum.map(labels["queries"], &{&1["query_id"], &1["project"]})) ==
        Enum.sort(Enum.map(freeze["queries"], &{&1["query_id"], &1["project"]})) and
      Enum.all?(labels["queries"], fn q ->
        exact?(q, ~w(query_id project expected_class expected_refusal relevance)) and
          q["expected_class"] in @classes and is_boolean(q["expected_refusal"]) and
          bounded_list?(q["relevance"], 0, 1024) and
          Enum.all?(q["relevance"], fn r ->
            exact?(r, ~w(source grade start_byte end_byte quote)) and source?(r["source"]) and
              r["source"]["project"] == q["project"] and integer?(r["grade"], 0, 30) and
              coordinates?(r)
          end)
      end) and Enum.sum(Enum.map(labels["queries"], &length(&1["relevance"]))) <= 65_536
  end

  defp reviews?(reviews, saved) do
    if exact?(reviews, ~w(version semantic integrity)) and reviews["version"] === 1 and
         bounded_list?(reviews["semantic"], 0, 16_384) and
         bounded_list?(reviews["integrity"], 0, 131_072) do
      predictions = Map.new(saved, &{&1["prediction_id"], &1})

      semantic_shape =
        Enum.all?(reviews["semantic"], fn r ->
          exact?(r, ~w(prediction_id verdict reviewer_id independent citations)) and
            Map.has_key?(predictions, r["prediction_id"]) and
            r["verdict"] in ~w(supported correct_abstention unsupported incorrect_abstention unmeasured) and
            id?(r["reviewer_id"]) and
            is_boolean(r["independent"]) and
            bounded_list?(r["citations"], 0, 256) and
            Enum.all?(r["citations"], fn c ->
              exact?(c, ~w(citation_id verdict)) and id?(c["citation_id"]) and
                c["verdict"] in ~w(supported unsupported invalid unmeasured)
            end)
        end)

      integrity_shape =
        Enum.all?(reviews["integrity"], fn r ->
          exact?(r, ~w(prediction_id span_id verdict reviewer_id independent)) and
            Map.has_key?(predictions, r["prediction_id"]) and
            Enum.any?(
              all_spans(predictions[r["prediction_id"]]),
              &(&1["span_id"] == r["span_id"])
            ) and id?(r["reviewer_id"]) and is_boolean(r["independent"]) and
            r["verdict"] in ~w(valid invalid unmeasured)
        end)

      semantic_shape and integrity_shape and unique?(reviews["semantic"], "prediction_id") and
        length(reviews["integrity"]) ==
          length(Enum.uniq_by(reviews["integrity"], &{&1["prediction_id"], &1["span_id"]}))
    else
      false
    end
  end

  defp build_report(freeze, verified, saved, labels, reviews) do
    saved_map = Map.new(saved, &{{&1["variant"], &1["query_id"]}, &1})
    labels = Map.new(labels, &{&1["query_id"], &1})
    integrity = Map.new(reviews["integrity"], &{{&1["prediction_id"], &1["span_id"]}, &1})
    all_projections = Enum.map(saved, &semantic_projection(&1, labels[&1["query_id"]], integrity))

    require!(
      match?({:ok, _}, Metrics.semantic(all_projections, reviews["semantic"])),
      :invalid_reviews
    )

    variants =
      Enum.map(freeze["variants"], fn variant ->
        rows =
          Enum.map(freeze["queries"], fn query ->
            p = Map.get(saved_map, {variant, query["query_id"]}, missing(variant, query))
            label = labels[query["query_id"]]
            source_qrels = Enum.map(label["relevance"], &Map.take(&1, ~w(source grade)))

            retrieval =
              metric!(
                Metrics.retrieval(
                  %{
                    "status" => p["status"],
                    "ranked_sources" => Enum.map(p["evidence"], & &1["source"]),
                    "top_k" => p["top_k"]
                  },
                  source_qrels
                )
              )

            %{
              "variant" => variant,
              "query_id" => query["query_id"],
              "project" => query["project"],
              "missing" => is_nil(p["prediction_id"]),
              "prediction" => p,
              "retrieval" => retrieval,
              "spans" => span_coverage(p, label, integrity),
              "classification" => classification(p, label, freeze["classification_map"]),
              "integrity" => Enum.map(all_spans(p), &integrity_receipt(p, &1, integrity))
            }
          end)

        projections =
          Enum.map(rows, fn row ->
            semantic_projection(row["prediction"], labels[row["query_id"]], integrity)
          end)

        ids = MapSet.new(Enum.map(projections, & &1["prediction_id"]))

        semantic_reviews =
          Enum.filter(reviews["semantic"], &MapSet.member?(ids, &1["prediction_id"]))

        semantic = metric!(Metrics.semantic(projections, semantic_reviews))

        literal_complete =
          Enum.all?(rows, fn row -> Enum.all?(row["integrity"], & &1["measured"]) end)

        summaries = %{
          "recall_at_5" =>
            macro(rows, fn row -> row["retrieval"]["recall_at_5"] end, fn row ->
              row["retrieval"]["relevant_sources"] > 0
            end),
          "ndcg_at_10" =>
            macro(rows, fn row -> row["retrieval"]["ndcg_at_10"] end, fn row ->
              row["retrieval"]["relevant_sources"] > 0
            end),
          "exact_span_recall" =>
            macro(rows, fn row -> row["spans"]["exact_recall"] end, fn row ->
              row["spans"]["relevant_n"] > 0
            end),
          "contained_span_recall" =>
            macro(rows, fn row -> row["spans"]["contained_recall"] end, fn row ->
              row["spans"]["relevant_n"] > 0
            end)
        }

        %{
          "variant" => variant,
          "rows" => rows,
          "summary" => summaries,
          "classification" => classification_summary(rows),
          "semantic" => semantic,
          "literal_review_complete" => literal_complete,
          "gates" => %{
            "support" =>
              gate(
                semantic["support"]["accuracy"],
                0.90,
                semantic["review_complete"] and literal_complete
              ),
            "citation" =>
              gate(
                semantic["citation"]["precision"],
                0.95,
                semantic["review_complete"] and literal_complete
              )
          }
        }
      end)

    baseline = Enum.find(variants, &(&1["variant"] == freeze["baseline"]))

    paired =
      Enum.map(variants, fn variant ->
        %{
          "variant" => variant["variant"],
          "baseline" => freeze["baseline"],
          "metrics" => paired_metrics(freeze, baseline, variant)
        }
      end)

    complete_grid =
      for variant <- variants,
          row <- variant["rows"],
          do: semantic_projection(row["prediction"], labels[row["query_id"]], integrity)

    semantic = metric!(Metrics.semantic(complete_grid, reviews["semantic"]))
    literal_complete = Enum.all?(variants, & &1["literal_review_complete"])

    gates = %{
      "support" =>
        gate(
          semantic["support"]["accuracy"],
          0.90,
          semantic["review_complete"] and literal_complete
        ),
      "citation" =>
        gate(
          semantic["citation"]["precision"],
          0.95,
          semantic["review_complete"] and literal_complete
        )
    }

    {:ok,
     %{
       "version" => 1,
       "metric_version" => Metrics.version(),
       "verified_prediction_files" => verified,
       "declarations" => freeze,
       "variants" => variants,
       "paired" => paired,
       "review" => reviews,
       "semantic" => semantic,
       "literal_review_complete" => literal_complete,
       "gates" => gates,
       "quality_gate_scope" => "complete_frozen_grid",
       "quality_gates_passed" => Enum.all?(gates, fn {_, gate} -> gate["status"] == "pass" end),
       "thresholds" => %{"support" => 0.90, "citation" => 0.95},
       "outside_scoring" =>
         Map.new(
           ~w(authority scope_isolation automatic_replay suppression_resurrection native installed platforms latency resources),
           &{&1, "unmeasured"}
         )
     }}
  end

  defp semantic_projection(p, label, integrity) do
    span_map = Map.new(all_spans(p), &{&1["span_id"], &1})

    %{
      "prediction_id" => p["prediction_id"] || missing_id(p),
      "query_id" => p["query_id"],
      "status" => p["status"],
      "response_kind" => p["response_kind"],
      "expected_refusal" => label["expected_refusal"],
      "citations" =>
        Enum.map(p["citations"], fn c ->
          %{
            "citation_id" => c["citation_id"],
            "integrity" => integrity_receipt(p, span_map[c["span_id"]], integrity)["verdict"]
          }
        end)
    }
  end

  defp span_coverage(p, label, integrity) do
    annotations =
      label["relevance"] |> Enum.filter(&(&1["grade"] > 0)) |> Enum.uniq_by(&span_identity/1)

    receipts = Enum.map(p["evidence"], &integrity_receipt(p, &1, integrity))
    measured = Enum.all?(receipts, & &1["measured"])

    valid =
      Enum.zip(p["evidence"], receipts)
      |> Enum.filter(fn {_, r} -> r["verdict"] == "valid" and r["measured"] end)
      |> Enum.map(&elem(&1, 0))

    exact =
      Enum.count(annotations, fn a ->
        Enum.any?(valid, &(span_identity(&1) == span_identity(a)))
      end)

    contained = Enum.count(annotations, fn a -> Enum.any?(valid, &contains?(&1, a)) end)
    n = length(annotations)
    observed_exact = if measured and n > 0, do: exact / n
    observed_contained = if measured and n > 0, do: contained / n

    %{
      "relevant_n" => n,
      "exact_hits_n" => exact,
      "contained_hits_n" => contained,
      "integrity_complete" => measured,
      "exact_recall" => span_score(observed_exact, n, p["status"]),
      "contained_recall" => span_score(observed_contained, n, p["status"]),
      "observed_exact_recall" => observed_exact,
      "observed_contained_recall" => observed_contained,
      "reason" =>
        cond do
          n == 0 -> "no_relevant_spans"
          not measured -> "unmeasured_integrity"
          true -> nil
        end
    }
  end

  defp contains?(span, annotation) do
    if unit(span["source"]) == unit(annotation["source"]) and
         span["start_byte"] <= annotation["start_byte"] and
         span["end_byte"] >= annotation["end_byte"] do
      offset = annotation["start_byte"] - span["start_byte"]
      count = annotation["end_byte"] - annotation["start_byte"]
      prefix = binary_part(span["quote"], 0, offset)
      captured = binary_part(span["quote"], offset, count)
      String.valid?(prefix) and String.valid?(captured) and captured == annotation["quote"]
    else
      false
    end
  end

  defp integrity_receipt(p, span, reviews) do
    review = reviews[{p["prediction_id"], span["span_id"]}]
    measured = is_map(review) and review["independent"] and review["verdict"] != "unmeasured"

    verdict =
      cond do
        span["source"]["project"] != p["project"] -> "invalid"
        measured -> review["verdict"]
        true -> "unmeasured"
      end

    %{
      "prediction_id" => p["prediction_id"],
      "span_id" => span["span_id"],
      "verdict" => verdict,
      "measured" => measured,
      "reviewer_id" => if(is_map(review), do: review["reviewer_id"]),
      "independent" => is_map(review) and review["independent"]
    }
  end

  defp classification(p, label, mapping) do
    predicted = if is_nil(p["predicted_class"]), do: nil, else: mapping[p["predicted_class"]]

    execution_ok =
      p["status"] == "ok" or
        (p["status"] == "refused" and label["expected_refusal"] and predicted == "abstain")

    measured = not is_nil(predicted) or not execution_ok

    %{
      "expected" => label["expected_class"],
      "predicted" => predicted,
      "scored_predicted" => if(execution_ok, do: predicted, else: "execution_failure"),
      "measured" => measured,
      "correct" => if(measured, do: execution_ok and predicted == label["expected_class"])
    }
  end

  defp classification_summary(rows) do
    measured = Enum.count(rows, & &1["classification"]["measured"])
    correct = Enum.count(rows, &(&1["classification"]["correct"] == true))

    matrix =
      Enum.reduce(rows, %{}, fn row, acc ->
        c = row["classification"]
        predicted = c["scored_predicted"] || "unmeasured"

        Map.update(acc, c["expected"], %{predicted => 1}, fn inner ->
          Map.update(inner, predicted, 1, &(&1 + 1))
        end)
      end)

    %{
      "total_n" => length(rows),
      "measured_n" => measured,
      "unmeasured_n" => length(rows) - measured,
      "correct_n" => correct,
      "accuracy" => if(measured == length(rows), do: ratio(correct, length(rows))),
      "observed_accuracy" => ratio(correct, measured),
      "confusion" => matrix
    }
  end

  defp paired_metrics(freeze, baseline, variant) do
    specifications = [
      {"recall_at_5", fn r -> r["retrieval"]["recall_at_5"] end,
       fn r -> r["retrieval"]["relevant_sources"] > 0 end},
      {"ndcg_at_10", fn r -> r["retrieval"]["ndcg_at_10"] end,
       fn r -> r["retrieval"]["relevant_sources"] > 0 end},
      {"exact_span_recall", fn r -> r["spans"]["exact_recall"] end,
       fn r -> r["spans"]["relevant_n"] > 0 end},
      {"contained_span_recall", fn r -> r["spans"]["contained_recall"] end,
       fn r -> r["spans"]["relevant_n"] > 0 end}
    ]

    Map.new(specifications, fn {name, value, applicable} ->
      queries =
        Enum.zip(freeze["queries"], baseline["rows"])
        |> Enum.map(fn {q, r} ->
          %{"query_id" => q["query_id"], "applicable" => applicable.(r)}
        end)

      to_rows = fn rows ->
        Enum.map(
          rows,
          &%{
            "query_id" => &1["query_id"],
            "status" => &1["prediction"]["status"],
            "value" => value.(&1)
          }
        )
      end

      {name,
       metric!(Metrics.paired(queries, to_rows.(baseline["rows"]), to_rows.(variant["rows"])))}
    end)
  end

  defp macro(rows, value, applicable) do
    eligible = Enum.filter(rows, applicable)
    values = Enum.map(eligible, value) |> Enum.reject(&is_nil/1)
    complete = length(values) == length(eligible)

    %{
      "total_n" => length(rows),
      "eligible_n" => length(eligible),
      "not_applicable_n" => length(rows) - length(eligible),
      "measured_n" => length(values),
      "unmeasured_n" => length(eligible) - length(values),
      "failed_n" => Enum.count(rows, &(&1["prediction"]["status"] != "ok")),
      "complete" => complete,
      "mean" => if(complete, do: mean(values)),
      "observed_mean" => mean(values)
    }
  end

  defp missing(variant, query),
    do: %{
      "version" => 2,
      "prediction_id" => nil,
      "variant" => variant,
      "query_id" => query["query_id"],
      "project" => query["project"],
      "attempt" => 1,
      "status" => "missing",
      "top_k" => 10,
      "predicted_class" => nil,
      "response_kind" => "retrieval_only",
      "answer" => nil,
      "claims" => [],
      "evidence" => [],
      "context_evidence" => [],
      "citations" => []
    }

  defp all_spans(prediction), do: prediction["evidence"] ++ prediction["context_evidence"]

  defp missing_id(p), do: "missing:" <> sha256(JSON.encode!([p["variant"], p["query_id"]]))

  defp gate(value, threshold, complete),
    do: %{
      "threshold" => threshold,
      "value" => value,
      "status" =>
        cond do
          not complete or is_nil(value) -> "unmeasured"
          value >= threshold -> "pass"
          true -> "fail"
        end
    }

  defp span_score(_, 0, _), do: nil
  defp span_score(_, _, status) when status != "ok", do: 0.0
  defp span_score(value, _, _), do: value
  defp span_identity(s), do: [unit(s["source"]), s["start_byte"], s["end_byte"], s["quote"]]
  defp unit(s), do: Enum.map(@source_keys, &s[&1])

  defp span?(s),
    do:
      exact?(s, ~w(span_id source start_byte end_byte quote)) and id?(s["span_id"]) and
        source?(s["source"]) and coordinates?(s)

  defp coordinates?(s),
    do:
      integer?(s["start_byte"], 0, @safe_integer) and integer?(s["end_byte"], 1, @safe_integer) and
        s["end_byte"] > s["start_byte"] and text?(s["quote"], 8192) and
        s["end_byte"] - s["start_byte"] == byte_size(s["quote"])

  defp source?(s),
    do:
      exact?(s, @source_keys) and id?(s["project"]) and id?(s["source_id"]) and
        integer?(s["generation"], 1, @safe_integer) and
        (integer?(s["version"], 1, @safe_integer) or id?(s["version"])) and hash?(s["sha256"])

  defp load!(loader, code) do
    try do
      case loader.() do
        {:ok, data} -> data
        _ -> fail!(code)
      end
    rescue
      _ -> fail!(code)
    catch
      _kind, _reason -> fail!(code)
    end
  end

  defp metric!({:ok, result}), do: result
  defp metric!(_), do: fail!(:invalid_metric_projection)
  defp require!(true, _), do: :ok
  defp require!(_, code), do: fail!(code)
  defp fail!(code), do: throw({:evaluation_score, code})
  defp sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp hash?(s), do: is_binary(s) and Regex.match?(~r/\A[0-9a-f]{64}\z/, s)

  defp exact?(m, keys),
    do: is_map(m) and map_size(m) == length(keys) and Enum.all?(keys, &Map.has_key?(m, &1))

  defp id?(s), do: text?(s, 256) and byte_size(s) > 0
  defp text?(s, max), do: is_binary(s) and byte_size(s) <= max and String.valid?(s)
  defp nullable_text?(nil, _), do: true
  defp nullable_text?(s, max), do: text?(s, max)
  defp integer?(n, min, max), do: is_integer(n) and n >= min and n <= max

  defp bounded_list?(list, min, max),
    do: is_list(list) and length(list) >= min and length(list) <= max

  defp unique_values?(list), do: length(list) == length(Enum.uniq(list))

  defp unique?(list, key),
    do:
      length(list) ==
        length(Enum.uniq_by(list, fn row -> if is_map(row), do: row[key], else: nil end))

  defp mean([]), do: nil
  defp mean(values), do: Enum.sum(values) / length(values)
  defp ratio(_, 0), do: nil
  defp ratio(n, d), do: n / d
end
