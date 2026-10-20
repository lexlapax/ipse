defmodule IpseKnowledge.Evidence do
  @moduledoc false
  @source ~w(version source_id partition generation title text uri observed_at_ms event_at_ms expires_at_ms origin source_key content_sha256)
  @attrs @source -- ~w(version source_key content_sha256)
  @citation ~w(version source_id source_key generation content_sha256 chunk_id start_byte end_byte quote quote_sha256 uri observed_at_ms event_at_ms origin)
  @chunk ~w(version source_key generation content_sha256 chunk_id start_byte end_byte text)
  @fact ~w(version fact_id subject predicate object polarity inferred valid_from_ms valid_to_ms extraction citations)
  @vector ~w(version chunk_id input_sha256 profile model dimensions encoding vector_sha256 values)
  @max_store_records 256
  @max_facts_per_manifest 32
  @max_query_fact_rows @max_store_records * @max_facts_per_manifest
  @max_claim_context 256

  def sha256(bytes) when is_binary(bytes),
    do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  def id(tag, parts) when is_binary(tag) and is_list(parts),
    do: sha256(IO.iodata_to_binary(JSON.encode!(["ipse-knowledge", 1, tag, parts])))

  def source(attrs) do
    if exact?(attrs, @attrs) do
      source =
        Map.merge(attrs, %{
          "version" => 1,
          "source_key" => sha256(attrs["source_id"] || ""),
          "content_sha256" => sha256(attrs["text"] || "")
        })

      if valid_source?(source), do: {:ok, source}, else: {:error, :invalid_source}
    else
      {:error, :invalid_source}
    end
  rescue
    _ -> {:error, :invalid_source}
  end

  def valid_source?(s) do
    exact?(s, @source) and s["version"] == 1 and identifier?(s["source_id"], 256) and
      partition?(s["partition"]) and positive?(s["generation"]) and text?(s["title"], 128) and
      text?(s["uri"], 512) and text?(s["text"], 65_536) and timestamp?(s["observed_at_ms"]) and
      optional_time?(s["event_at_ms"]) and optional_time?(s["expires_at_ms"]) and
      origin?(s["origin"]) and s["source_key"] == sha256(s["source_id"]) and
      s["content_sha256"] == sha256(s["text"])
  end

  def current?(s, now),
    do:
      valid_source?(s) and timestamp?(now) and s["observed_at_ms"] <= now and
        (is_nil(s["expires_at_ms"]) or s["expires_at_ms"] > now) and not s["origin"]["historical"]

  def query_scope(rank, sources, store_gaps, now) do
    source_exclusions =
      sources
      |> Enum.reject(&current?(&1, now))
      |> Enum.map(&%{"code" => "stale_source", "source_id" => &1["source_id"]})

    gaps = Enum.uniq(rank["gaps"] ++ store_gaps ++ source_exclusions)

    {exclusions, failures} =
      Enum.split_with(gaps, &(&1["code"] in ~w(suppressed stale_source excluded_fact)))

    complete = rank["coverage"]["complete"] === true and failures == []

    status =
      cond do
        not complete -> "partial"
        rank["evidence"] == [] -> "abstain"
        true -> "ok"
      end

    Map.merge(rank, %{
      "status" => status,
      "gaps" => gaps,
      "coverage" =>
        Map.merge(rank["coverage"], %{"complete" => complete, "exclusions" => exclusions})
    })
  end

  def chunks(source) do
    if valid_source?(source) do
      chunks =
        split_utf8(source["text"], 2048, 0, [])
        |> Enum.map(fn {start, text} ->
          finish = start + byte_size(text)

          %{
            "version" => 1,
            "source_key" => source["source_key"],
            "generation" => source["generation"],
            "content_sha256" => source["content_sha256"],
            "chunk_id" => chunk_id(source, start, finish),
            "start_byte" => start,
            "end_byte" => finish,
            "text" => text
          }
        end)

      if length(chunks) <= 32, do: {:ok, chunks}, else: {:error, :chunk_limit}
    else
      {:error, :invalid_source}
    end
  end

  def citation(source, chunk, start, finish) do
    if valid_source?(source) and exact?(chunk, @chunk) and is_integer(start) and
         is_integer(finish) and start >= chunk["start_byte"] and finish <= chunk["end_byte"] and
         finish > start and finish - start <= 1024 do
      quote = binary_part(source["text"], start, finish - start)

      c =
        Map.take(
          source,
          ~w(source_id source_key generation content_sha256 uri observed_at_ms event_at_ms origin)
        )
        |> Map.merge(%{
          "version" => 1,
          "chunk_id" => chunk["chunk_id"],
          "start_byte" => start,
          "end_byte" => finish,
          "quote" => quote,
          "quote_sha256" => sha256(quote)
        })

      if valid_span?(source, c), do: {:ok, c}, else: {:error, :invalid_span}
    else
      {:error, :invalid_span}
    end
  rescue
    _ -> {:error, :invalid_span}
  end

  def valid_span?(s, c) do
    with true <- valid_source?(s) and citation_shape?(c),
         true <-
           Enum.all?(
             ~w(source_id source_key generation content_sha256 uri observed_at_ms event_at_ms origin),
             &(s[&1] == c[&1])
           ),
         {:ok, chunks} <- chunks(s),
         chunk when is_map(chunk) <- Enum.find(chunks, &(&1["chunk_id"] == c["chunk_id"])),
         true <- c["start_byte"] >= chunk["start_byte"] and c["end_byte"] <= chunk["end_byte"],
         quote <- binary_part(s["text"], c["start_byte"], c["end_byte"] - c["start_byte"]),
         true <- quote == c["quote"] and String.valid?(binary_part(s["text"], 0, c["start_byte"])) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def fact(attrs) do
    if exact?(attrs, @fact -- ~w(version fact_id)) do
      f = Map.merge(attrs, %{"version" => 1, "fact_id" => fact_id(attrs)})
      if valid_fact?(f), do: {:ok, f}, else: {:error, :invalid_fact}
    else
      {:error, :invalid_fact}
    end
  rescue
    _ -> {:error, :invalid_fact}
  end

  def valid_fact?(f) do
    exact?(f, @fact) and f["version"] == 1 and identifier?(f["subject"], 256) and
      identifier?(f["predicate"], 128) and identifier?(f["object"], 256) and
      f["polarity"] in ~w(positive negative) and is_boolean(f["inferred"]) and
      optional_time?(f["valid_from_ms"]) and optional_time?(f["valid_to_ms"]) and
      ordered_times?(f["valid_from_ms"], f["valid_to_ms"]) and extraction?(f["extraction"]) and
      is_list(f["citations"]) and length(f["citations"]) in 1..8 and
      Enum.all?(f["citations"], &citation_shape?/1) and f["fact_id"] == fact_id(f)
  rescue
    _ -> false
  end

  def vector(attrs) do
    with true <-
           exact?(attrs, ["selection_sha256" | @vector -- ~w(version encoding vector_sha256)]),
         values when is_list(values) <- attrs["values"],
         true <- length(values) in 1..4096 and Enum.all?(values, &finite?/1),
         {:ok, canonical, bytes} <- float32(values) do
      v =
        Map.merge(attrs, %{
          "version" => 2,
          "encoding" => "float32le",
          "values" => canonical,
          "vector_sha256" => sha256(bytes)
        })

      if valid_vector?(v), do: {:ok, v}, else: {:error, :invalid_vector}
    else
      _ -> {:error, :invalid_vector}
    end
  end

  def valid_vector?(v) do
    with true <-
           ((exact?(v, @vector) and v["version"] === 1) or
              (exact?(v, ["selection_sha256" | @vector]) and v["version"] === 2 and
                 hash?(v["selection_sha256"]))) and v["encoding"] == "float32le" and
             hash?(v["chunk_id"]) and hash?(v["input_sha256"]) and identifier?(v["profile"], 128) and
             identifier?(v["model"], 128) and is_integer(v["dimensions"]) and
             v["dimensions"] in 1..4096 and is_list(v["values"]) and
             length(v["values"]) == v["dimensions"] and Enum.all?(v["values"], &is_float/1),
         {:ok, canonical, bytes} <- float32(v["values"]),
         true <-
           canonical == v["values"] and Enum.any?(canonical, &(&1 != 0.0)) and
             sha256(bytes) == v["vector_sha256"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def current_vector?(v), do: valid_vector?(v) and v["version"] === 2

  def compatible_vectors?(a, b) do
    current_vector?(a) and current_vector?(b) and
      Enum.all?(~w(selection_sha256 profile model dimensions encoding), &(a[&1] === b[&1]))
  end

  def rank_lexical(sources, query, top_k, now) do
    with :ok <- inputs(sources, top_k, now), true <- text?(query, 1024) do
      active = Enum.filter(sources, &current?(&1, now))

      with {:ok, docs} <- documents(active) do
        terms = tokens(query) |> Enum.uniq()
        n = length(docs)
        avg = if n == 0, do: 1.0, else: max(Enum.sum(Enum.map(docs, &length(&1.tokens))) / n, 1.0)
        dfs = Map.new(terms, fn term -> {term, Enum.count(docs, &(term in &1.tokens))} end)

        ranked =
          Enum.flat_map(docs, fn doc ->
            counts = Enum.frequencies(doc.tokens)

            score =
              Enum.reduce(terms, 0.0, fn term, total ->
                tf = Map.get(counts, term, 0)
                df = dfs[term]

                total +
                  :math.log(1.0 + (n - df + 0.5) / (df + 0.5)) * tf * 2.2 /
                    (tf + 1.2 * (0.25 + 0.75 * length(doc.tokens) / avg))
              end)

            if score > 0, do: [candidate(doc.source, doc.chunk, score, "bm25", query)], else: []
          end)
          |> order()
          |> Enum.take(top_k)

        {:ok,
         result(ranked, [], stale_gaps(sources, now), %{
           "as_of_ms" => now,
           "sources" => length(active),
           "chunks" => n,
           "method" => "bm25",
           "complete" => true
         })}
      end
    else
      false -> {:error, :invalid_query}
      other -> other
    end
  end

  def rank_remote(sources, refs, query, top_k, now) do
    with :ok <- inputs(sources, top_k, now),
         :ok <- if(text?(query, 1024), do: :ok, else: {:error, :invalid_query}),
         true <- is_list(refs) and length(refs) <= top_k and Enum.all?(refs, &remote_ref?/1),
         true <- length(Enum.uniq_by(refs, &{&1["source_key"], &1["chunk_id"]})) == length(refs) do
      if sources |> Enum.map(& &1["partition"]) |> Enum.uniq() |> length() <= 1 do
        by_key = Map.new(sources, &{&1["source_key"], &1})

        Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, acc} ->
          with source when is_map(source) <- by_key[ref["source_key"]],
               true <- current?(source, now),
               true <-
                 Enum.all?(
                   ~w(source_id source_key generation content_sha256),
                   &(source[&1] == ref[&1])
                 ),
               {:ok, chunks} <- chunks(source),
               chunk when is_map(chunk) <- Enum.find(chunks, &(&1["chunk_id"] == ref["chunk_id"])) do
            {:cont, {:ok, [candidate(source, chunk, ref["score"], "mcp_query", query) | acc]}}
          else
            _ -> {:halt, {:error, :invalid_remote_selection}}
          end
        end)
        |> case do
          {:ok, candidates} ->
            {:ok,
             result(order(candidates), [], [], %{
               "method" => "mcp_query",
               "score_provenance" => "server_asserted",
               "as_of_ms" => now,
               "sources" => length(sources),
               "chunks" => length(refs),
               "complete" => true
             })}

          error ->
            error
        end
      else
        {:error, :invalid_remote_selection}
      end
    else
      false -> {:error, :invalid_remote_refs}
      error -> error
    end
  rescue
    _ -> {:error, :invalid_remote_refs}
  end

  defp remote_ref?(ref) do
    exact?(ref, ~w(source_id source_key generation content_sha256 chunk_id score)) and
      identifier?(ref["source_id"], 256) and ref["source_key"] == sha256(ref["source_id"]) and
      positive?(ref["generation"]) and hash?(ref["content_sha256"]) and hash?(ref["chunk_id"]) and
      finite?(ref["score"])
  end

  def rank_cosine(candidates, query_vector, top_k) do
    if is_list(candidates) and length(candidates) <= 1024 and current_vector?(query_vector) and
         top?(top_k) do
      Enum.reduce_while(candidates, {:ok, []}, fn c, {:ok, acc} ->
        v = if is_map(c), do: c["vector"], else: nil

        if exact?(c, ~w(citation score method vector)) and candidate?(Map.delete(c, "vector")) and
             compatible_vectors?(v, query_vector) and
             v["chunk_id"] == c["citation"]["chunk_id"] do
          score = cosine(v["values"], query_vector["values"])

          {:cont,
           {:ok,
            [Map.merge(Map.delete(c, "vector"), %{"score" => score, "method" => "cosine"}) | acc]}}
        else
          {:halt, {:error, :incompatible_vector}}
        end
      end)
      |> case do
        {:ok, ranked} ->
          {:ok,
           result(ranked |> order() |> Enum.take(top_k), [], [], %{
             "method" => "cosine",
             "candidates" => length(candidates),
             "complete" => true
           })}

        error ->
          error
      end
    else
      {:error, :invalid_vector}
    end
  end

  def fuse(lists, top_k, 60) when is_list(lists) and length(lists) <= 8 do
    if top?(top_k) and
         Enum.all?(
           lists,
           &(is_list(&1) and length(&1) <= 1024 and Enum.all?(&1, fn c -> candidate?(c) end))
         ) do
      scores =
        Enum.reduce(lists, %{}, fn list, all ->
          list
          |> Enum.uniq_by(&fusion_key/1)
          |> Enum.with_index(1)
          |> Enum.reduce(all, fn {c, rank}, acc ->
            Map.update(
              acc,
              fusion_key(c),
              {rank, Map.merge(c, %{"score" => 1.0 / (60 + rank), "method" => "rrf"})},
              fn {best_rank, prior} ->
                representative = if rank < best_rank, do: c, else: prior

                {min(rank, best_rank),
                 Map.merge(representative, %{
                   "score" => prior["score"] + 1.0 / (60 + rank),
                   "method" => "rrf"
                 })}
              end
            )
          end)
        end)

      {:ok,
       result(
         scores |> Map.values() |> Enum.map(&elem(&1, 1)) |> order() |> Enum.take(top_k),
         [],
         [],
         %{
           "method" => "rrf",
           "lists" => length(lists),
           "complete" => true
         }
       )}
    else
      {:error, :invalid_ranks}
    end
  end

  def fuse(_, _, _), do: {:error, :invalid_ranks}

  def candidate_id(%{"citation" => citation}),
    do:
      citation["chunk_id"] <>
        ":" <>
        Integer.to_string(citation["start_byte"]) <>
        ":" <>
        Integer.to_string(citation["end_byte"])

  def apply_rerank(candidates, ids) do
    if is_list(candidates) and length(candidates) <= 1024 and Enum.all?(candidates, &candidate?/1) and
         is_list(ids) and length(ids) <= 16 and length(Enum.uniq(ids)) == length(ids) do
      by_id = Map.new(candidates, &{candidate_id(&1), &1})

      if Enum.all?(ids, &Map.has_key?(by_id, &1)) and map_size(by_id) == length(candidates) do
        {:ok,
         Enum.map(ids, &by_id[&1]) ++
           Enum.reject(candidates, &(candidate_id(&1) in ids))}
      else
        {:error, :invalid_rerank}
      end
    else
      {:error, :invalid_rerank}
    end
  end

  def validate_facts(sources, facts, now) do
    with :ok <- inputs(sources, 10, now),
         true <-
           is_list(facts) and length(facts) <= @max_query_fact_rows and
             Enum.all?(facts, &valid_fact?/1) do
      by_id = Map.new(sources, &{&1["source_key"], &1})

      Enum.reduce_while(facts, {:ok, %{"facts" => [], "gaps" => []}}, fn f, {:ok, acc} ->
        checks =
          Enum.map(f["citations"], fn c ->
            case by_id[c["source_key"]] do
              nil ->
                :missing

              s ->
                cond do
                  s["generation"] != c["generation"] or s["content_sha256"] != c["content_sha256"] ->
                    :stale

                  not valid_span?(s, c) ->
                    :forged

                  not current?(s, now) ->
                    :excluded

                  true ->
                    :ok
                end
            end
          end)

        cond do
          :forged in checks ->
            {:halt, {:error, :invalid_span}}

          Enum.any?(checks, &(&1 in [:missing, :stale])) ->
            {:cont,
             {:ok,
              Map.update!(
                acc,
                "gaps",
                &[%{"code" => "stale_fact", "source_id" => hd(f["citations"])["source_id"]} | &1]
              )}}

          :excluded in checks or not fact_current?(f, now) ->
            {:cont,
             {:ok,
              Map.update!(
                acc,
                "gaps",
                &[
                  %{
                    "code" => "excluded_fact",
                    "fact_id" => f["fact_id"],
                    "source_id" => hd(f["citations"])["source_id"]
                  }
                  | &1
                ]
              )}}

          true ->
            {:cont, {:ok, Map.update!(acc, "facts", &[f | &1])}}
        end
      end)
      |> case do
        {:ok, validated} ->
          {:ok,
           validated
           |> Map.update!("facts", &Enum.reverse/1)
           |> Map.update!("gaps", &Enum.reverse/1)}

        error ->
          error
      end
    else
      false -> {:error, :invalid_fact}
      error -> error
    end
  end

  def traverse(sources, facts, seed, limits, now) do
    with true <- identifier?(seed, 256) and limits?(limits),
         {:ok, valid} <- validate_facts(sources, facts, now),
         {selected, nodes, truncated} <-
           walk(
             valid["facts"],
             [String.downcase(seed)],
             MapSet.new([String.downcase(seed)]),
             [],
             limits["depth"],
             limits
           ),
         {:ok, context} <- claim_context(selected, valid["facts"], nodes),
         evidence =
           context
           |> Enum.flat_map(& &1["citations"])
           |> Enum.uniq_by(&span_key/1)
           |> Enum.map(&%{"citation" => &1, "score" => 1.0, "method" => "graph"})
           |> Enum.take(limits["top_k"]),
         {:ok, claims} <- classify(evidence, context, seed) do
      {:ok,
       result(evidence, claims, valid["gaps"], %{
         "as_of_ms" => now,
         "seed" => seed,
         "method" => "graph",
         "nodes" => MapSet.size(nodes),
         "edges" => length(selected),
         "context_facts" => length(context),
         "negative_context" => Enum.count(context, &(&1["polarity"] == "negative")),
         "counterassertions" =>
           Enum.count(context -- selected, fn fact ->
             Enum.any?(selected, &conflicts?(&1, fact))
           end),
         "complete" => not truncated
       })}
    else
      false -> {:error, :invalid_graph_query}
      error -> error
    end
  end

  def graph_seed(sources, facts, query, now) do
    with true <- text?(query, 1024),
         {:ok, valid} <- validate_facts(sources, facts, now) do
      normalized_query = String.downcase(query)

      seed =
        valid["facts"]
        |> Enum.map(& &1["subject"])
        |> Enum.uniq()
        |> Enum.sort_by(&{-String.length(&1), String.downcase(&1), &1})
        |> Enum.find(fn subject ->
          pattern =
            "(?<![\\p{L}\\p{N}])" <>
              Regex.escape(String.downcase(subject)) <> "(?![\\p{L}\\p{N}])"

          Regex.match?(Regex.compile!(pattern, "u"), normalized_query)
        end)

      {:ok, seed || query}
    else
      false -> {:error, :invalid_graph_query}
      error -> error
    end
  end

  def classify(evidence, facts, query) do
    if is_list(evidence) and length(evidence) <= 128 and Enum.all?(evidence, &candidate?/1) and
         is_list(facts) and length(facts) <= @max_claim_context and
         Enum.all?(facts, &valid_fact?/1) and
         text?(query, 1024) do
      claims =
        Enum.map(facts, fn f ->
          conflict = Enum.any?(facts, &conflicts?(f, &1))

          label =
            cond do
              conflict -> "conflict"
              f["inferred"] -> "inference"
              true -> "supported"
            end

          %{
            "fact_id" => f["fact_id"],
            "subject" => f["subject"],
            "predicate" => f["predicate"],
            "object" => f["object"],
            "polarity" => f["polarity"],
            "label" => label,
            "basis" => f["citations"],
            "uncertainty" => "predicted_from_attributed_assertion"
          }
        end)

      if claims == [],
        do:
          {:ok,
           [
             %{
               "label" => "open",
               "basis" => Enum.map(evidence, & &1["citation"]),
               "uncertainty" => "semantic_support_unassessed"
             }
           ]},
        else: {:ok, claims}
    else
      {:error, :invalid_claims}
    end
  end

  defp claim_context(selected, facts, nodes) do
    selected = Enum.uniq_by(selected, & &1["fact_id"])
    selected_ids = MapSet.new(selected, & &1["fact_id"])

    additional =
      facts
      |> Enum.reject(&MapSet.member?(selected_ids, &1["fact_id"]))
      |> Enum.filter(fn fact ->
        (fact["polarity"] == "negative" and
           MapSet.member?(nodes, String.downcase(fact["subject"]))) or
          Enum.any?(selected, &conflicts?(&1, fact))
      end)
      |> Enum.uniq_by(& &1["fact_id"])
      |> Enum.sort_by(& &1["fact_id"])

    context = selected ++ additional

    if length(context) <= @max_claim_context,
      do: {:ok, context},
      else: {:error, :graph_context_limit}
  end

  defp conflicts?(fact, other) do
    same_object = String.downcase(other["object"]) == String.downcase(fact["object"])

    other["fact_id"] != fact["fact_id"] and
      String.downcase(other["subject"]) == String.downcase(fact["subject"]) and
      String.downcase(other["predicate"]) == String.downcase(fact["predicate"]) and
      same_object and other["polarity"] != fact["polarity"] and
      overlaps?(fact, other)
  end

  def public_claims(evidence, claims) do
    Enum.map(claims, fn
      %{"label" => "open", "uncertainty" => "semantic_support_unassessed", "basis" => basis} =
          claim ->
        indexes =
          Enum.map(basis, fn citation ->
            Enum.find_index(evidence, &(&1["citation"] == citation))
          end)

        if Enum.all?(indexes, &is_integer/1),
          do: claim |> Map.delete("basis") |> Map.put("evidence_indexes", indexes),
          else: claim

      claim ->
        claim
    end)
  end

  defp walk(facts, frontier, nodes, selected, 0, _),
    do: {selected, nodes, remaining_facts(facts, frontier, selected) != []}

  defp walk(_, [], nodes, selected, _, _), do: {selected, nodes, false}

  defp walk(facts, frontier, nodes, selected, depth, limits) do
    eligible =
      remaining_facts(facts, frontier, selected)
      |> Enum.sort_by(& &1["fact_id"])

    {chosen, new_nodes, next, cut} =
      Enum.reduce(eligible, {selected, nodes, [], false}, fn f, {edges, seen, next, cut} ->
        target = String.downcase(f["object"])

        cond do
          length(edges) >= limits["max_edges"] ->
            {edges, seen, next, true}

          not MapSet.member?(seen, target) and MapSet.size(seen) >= limits["max_nodes"] ->
            {edges, seen, next, true}

          true ->
            {edges ++ [f], MapSet.put(seen, target),
             if(MapSet.member?(seen, target), do: next, else: [target | next]), cut}
        end
      end)

    {edges, seen, later_cut} = walk(facts, next, new_nodes, chosen, depth - 1, limits)
    {edges, seen, cut or later_cut}
  end

  defp remaining_facts(facts, frontier, selected) do
    Enum.filter(
      facts,
      &(&1["polarity"] == "positive" and String.downcase(&1["subject"]) in frontier and
          not Enum.any?(selected, fn f -> f["fact_id"] == &1["fact_id"] end))
    )
  end

  defp fact_id(f) do
    x = f["extraction"]

    citations =
      Enum.map(f["citations"], fn c ->
        Enum.map(
          ~w(source_key generation content_sha256 chunk_id start_byte end_byte quote_sha256),
          &c[&1]
        )
      end)

    id(
      "fact",
      Enum.map(~w(subject predicate object polarity inferred valid_from_ms valid_to_ms), &f[&1]) ++
        [x["kind"], x["profile"], 1, citations]
    )
  end

  defp fact_current?(f, now),
    do:
      (is_nil(f["valid_from_ms"]) or f["valid_from_ms"] <= now) and
        (is_nil(f["valid_to_ms"]) or f["valid_to_ms"] > now)

  defp overlaps?(a, b),
    do:
      (is_nil(a["valid_to_ms"]) or is_nil(b["valid_from_ms"]) or
         a["valid_to_ms"] > b["valid_from_ms"]) and
        (is_nil(b["valid_to_ms"]) or is_nil(a["valid_from_ms"]) or
           b["valid_to_ms"] > a["valid_from_ms"])

  defp documents(sources) do
    Enum.reduce_while(sources, {:ok, []}, fn s, {:ok, acc} ->
      case chunks(s) do
        {:ok, cs} ->
          {:cont,
           {:ok, acc ++ Enum.map(cs, &%{source: s, chunk: &1, tokens: tokens(&1["text"])})}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp candidate(s, chunk, score, method, query) do
    {:ok, citation} = excerpt(s, chunk, query)
    %{"citation" => citation, "score" => score, "method" => method}
  end

  def excerpt(source, chunk, query) do
    if text?(query, 1024) do
      text = chunk["text"]

      {start, finish} =
        if byte_size(text) <= 1024 do
          {0, byte_size(text)}
        else
          terms = MapSet.new(tokens(query))

          groups =
            token_offsets(text)
            |> Enum.chunk_by(fn {_, start, finish} -> {start, finish} end)
            |> Enum.flat_map(fn [{_, start, finish} | _] = rows ->
              matched =
                rows |> Enum.map(&elem(&1, 0)) |> MapSet.new() |> MapSet.intersection(terms)

              if finish - start <= 1024 and MapSet.size(matched) > 0,
                do: [{start, finish, matched}],
                else: []
            end)

          excerpt_context(text, text_units(text), coverage_core(groups))
        end

      citation(source, chunk, chunk["start_byte"] + start, chunk["start_byte"] + finish)
    else
      {:error, :invalid_query}
    end
  rescue
    _ -> {:error, :invalid_span}
  end

  defp coverage_core([]), do: nil

  defp coverage_core(groups) do
    {_, _, coverage} =
      Enum.reduce(groups, {:queue.new(), %{}, 0}, fn group, {queue, counts, best} ->
        {queue, counts} = add_group(group, queue, counts)
        {queue, counts, max(best, map_size(counts))}
      end)

    {_, _, best} =
      Enum.reduce(groups, {:queue.new(), %{}, nil}, fn group, {queue, counts, best} ->
        {queue, counts} = add_group(group, queue, counts)
        shortest_core(queue, counts, coverage, best)
      end)

    {_, start, finish} = best
    {start, finish}
  end

  defp add_group({_, finish, terms} = group, queue, counts) do
    queue = :queue.in(group, queue)
    counts = term_counts(counts, terms, 1)
    trim_core(queue, counts, finish)
  end

  defp trim_core(queue, counts, finish) do
    {:value, {start, _, _}} = :queue.peek(queue)

    if finish - start <= 1024 do
      {queue, counts}
    else
      {queue, counts} = remove_group(queue, counts)
      trim_core(queue, counts, finish)
    end
  end

  defp shortest_core(queue, counts, coverage, best) when map_size(counts) < coverage,
    do: {queue, counts, best}

  defp shortest_core(queue, counts, coverage, best) do
    {:value, {start, _, _}} = :queue.peek(queue)
    {:value, {_, finish, _}} = :queue.peek_r(queue)
    trial = {finish - start, start, finish}
    best = if best == nil or trial < best, do: trial, else: best
    {queue, counts} = remove_group(queue, counts)
    shortest_core(queue, counts, coverage, best)
  end

  defp remove_group(queue, counts) do
    {{:value, {_, _, terms}}, queue} = :queue.out(queue)
    {queue, term_counts(counts, terms, -1)}
  end

  defp term_counts(counts, terms, delta) do
    Enum.reduce(terms, counts, fn term, acc ->
      case Map.get(acc, term, 0) + delta do
        0 -> Map.delete(acc, term)
        n -> Map.put(acc, term, n)
      end
    end)
  end

  defp text_units(text) do
    boundaries =
      Regex.scan(
        ~r/[.!?](?=[\t\n\v\f\r ]|\z)[\t\n\v\f\r ]*|\n[\t\n\v\f\r ]*/,
        text,
        return: :index
      )

    {start, spans} =
      Enum.reduce(boundaries, {0, []}, fn [{offset, size}], {start, acc} ->
        finish = offset + size
        {finish, [{start, finish} | acc]}
      end)

    spans = if start < byte_size(text), do: [{start, byte_size(text)} | spans], else: spans
    Enum.reverse(spans)
  end

  defp excerpt_context(text, units, nil) do
    complete = Enum.take_while(units, fn {_, finish} -> finish <= 1024 end)

    case List.last(complete) do
      nil ->
        {quote, _} = utf8_prefix(text, 1024)
        {0, byte_size(quote)}

      {_, finish} ->
        {0, finish}
    end
  end

  defp excerpt_context(text, units, {start, finish} = core) do
    {before, rest} = Enum.split_while(units, fn {_, last} -> last <= start end)
    {hull, after_units} = Enum.split_while(rest, fn {first, _} -> first < finish end)
    {first, _} = hd(hull)
    {_, last} = List.last(hull)

    if last - first <= 1024 do
      first =
        case Enum.find(before, fn {previous, _} -> last - previous <= 1024 end) do
          {previous, _} -> previous
          _ -> first
        end

      last =
        case after_units
             |> Enum.take_while(fn {_, next} -> next - first <= 1024 end)
             |> List.last() do
          {_, next} -> next
          _ -> last
        end

      {first, last}
    else
      centered_span(text, core)
    end
  end

  defp centered_span(text, {start, finish}) do
    first = max(0, start - div(1024 - (finish - start), 2))
    last = min(byte_size(text), first + 1024)
    first = max(0, last - 1024)
    {codepoint_boundary(text, first, 1), codepoint_boundary(text, last, -1)}
  end

  defp codepoint_boundary(text, offset, direction) when offset < byte_size(text) do
    byte = :binary.at(text, offset)

    if byte >= 128 and byte < 192,
      do: codepoint_boundary(text, offset + direction, direction),
      else: offset
  end

  defp codepoint_boundary(_, offset, _), do: offset

  defp candidate?(c),
    do:
      exact?(c, ~w(citation score method)) and citation_shape?(c["citation"]) and
        finite?(c["score"]) and c["method"] in ~w(bm25 cosine rrf graph mcp_query)

  defp candidate_key(c), do: span_key(c["citation"])

  defp fusion_key(%{"citation" => c}),
    do:
      [c["origin"]["store_profile"], c["origin"]["partition_or_scope"]] ++
        Enum.map(~w(source_key generation content_sha256 chunk_id), &c[&1])

  defp span_key(c),
    do: Enum.map(~w(source_key generation content_sha256 chunk_id start_byte end_byte), &c[&1])

  defp order(candidates),
    do: Enum.sort_by(candidates, &{-&1["score"], candidate_key(&1), fusion_key(&1)})

  defp result(evidence, claims, gaps, coverage),
    do: %{"evidence" => evidence, "claims" => claims, "gaps" => gaps, "coverage" => coverage}

  defp stale_gaps(sources, now),
    do:
      sources
      |> Enum.reject(&current?(&1, now))
      |> Enum.map(&%{"code" => "stale_source", "source_id" => &1["source_id"]})

  defp inputs(sources, k, now) do
    if is_list(sources) and length(sources) <= 32 and Enum.all?(sources, &valid_source?/1) and
         length(Enum.uniq_by(sources, & &1["source_key"])) == length(sources) and top?(k) and
         timestamp?(now) do
      :ok
    else
      {:error, :invalid_sources}
    end
  end

  defp limits?(l),
    do:
      exact?(l, ~w(depth max_nodes max_edges top_k)) and is_integer(l["depth"]) and
        l["depth"] in 0..4 and is_integer(l["max_nodes"]) and l["max_nodes"] in 1..128 and
        is_integer(l["max_edges"]) and l["max_edges"] in 1..256 and top?(l["top_k"])

  defp top?(k), do: is_integer(k) and k in 1..10
  defp tokens(text), do: Enum.map(token_offsets(text), &elem(&1, 0))

  defp token_offsets(text) do
    Regex.scan(~r/[\p{L}\p{N}]+/u, text, return: :index)
    |> Enum.flat_map(fn [{start, length}] ->
      normalized = String.downcase(binary_part(text, start, length))

      Regex.scan(~r/[\p{L}\p{N}]+/u, normalized)
      |> Enum.map(fn [term] -> {term, start, start + length} end)
    end)
  end

  defp chunk_id(s, start, finish),
    do: id("chunk", [s["source_key"], s["generation"], s["content_sha256"], 1, start, finish])

  defp split_utf8("", _, _, acc), do: Enum.reverse(acc)

  defp split_utf8(text, max, start, acc) do
    {part, rest} = utf8_prefix(text, max)
    split_utf8(rest, max, start + byte_size(part), [{start, part} | acc])
  end

  @doc false
  def utf8_prefix(text, max) when byte_size(text) <= max, do: {text, ""}

  def utf8_prefix(text, max) do
    part = binary_part(text, 0, max)

    if String.valid?(part),
      do: {part, binary_part(text, max, byte_size(text) - max)},
      else: utf8_prefix(text, max - 1)
  end

  defp cosine(a, b) do
    dot = Enum.zip_with(a, b, &(&1 * &2)) |> Enum.sum()
    dot / :math.sqrt(Enum.sum(Enum.map(a, &(&1 * &1))) * Enum.sum(Enum.map(b, &(&1 * &1))))
  end

  defp float32(values) do
    if Enum.all?(values, &(finite?(&1) and abs(&1) <= 3.4028234663852886e38)) do
      bytes = for v <- values, into: <<>>, do: <<v::little-float-size(32)>>
      canonical = for <<v::little-float-size(32) <- bytes>>, do: v
      {:ok, canonical, bytes}
    else
      {:error, :invalid_vector}
    end
  rescue
    _ -> {:error, :invalid_vector}
  end

  defp citation_shape?(c),
    do:
      exact?(c, @citation) and c["version"] == 1 and identifier?(c["source_id"], 256) and
        hash?(c["source_key"]) and positive?(c["generation"]) and hash?(c["content_sha256"]) and
        hash?(c["chunk_id"]) and is_integer(c["start_byte"]) and c["start_byte"] >= 0 and
        is_integer(c["end_byte"]) and c["end_byte"] > c["start_byte"] and text?(c["quote"], 1024) and
        byte_size(c["quote"]) == c["end_byte"] - c["start_byte"] and
        sha256(c["quote"]) == c["quote_sha256"] and text?(c["uri"], 512) and
        timestamp?(c["observed_at_ms"]) and optional_time?(c["event_at_ms"]) and
        origin?(c["origin"])

  defp origin?(o),
    do:
      exact?(o, ~w(kind store_profile partition_or_scope receipt historical)) and
        o["kind"] in ~w(provided fetch import) and nullable_text?(o["store_profile"], 256) and
        nullable_text?(o["partition_or_scope"], 256) and
        (is_nil(o["receipt"]) or (is_map(o["receipt"]) and json_bounded?(o["receipt"], 8192))) and
        is_boolean(o["historical"])

  defp extraction?(x),
    do:
      exact?(x, ~w(kind profile version)) and x["kind"] in ~w(explicit model_complete) and
        nullable_text?(x["profile"], 128) and x["version"] == 1

  defp exact?(map, keys),
    do: is_map(map) and map_size(map) == length(keys) and Enum.all?(keys, &Map.has_key?(map, &1))

  defp partition?(s), do: is_binary(s) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,64}\z/, s)

  defp identifier?(s, max),
    do: text?(s, max) and byte_size(s) > 0 and not Regex.match?(~r/[\x00-\x1F\x7F]/u, s)

  defp text?(s, max), do: is_binary(s) and byte_size(s) <= max and String.valid?(s)
  defp nullable_text?(nil, _), do: true
  defp nullable_text?(s, max), do: text?(s, max)
  defp hash?(s), do: is_binary(s) and Regex.match?(~r/\A[0-9a-f]{64}\z/, s)
  defp positive?(n), do: is_integer(n) and n > 0
  defp timestamp?(n), do: is_integer(n) and n >= 0
  defp optional_time?(nil), do: true
  defp optional_time?(n), do: timestamp?(n)
  defp ordered_times?(a, b), do: is_nil(a) or is_nil(b) or a <= b
  defp finite?(n), do: is_number(n) and n == n and abs(n) <= 1.7976931348623157e308

  defp json_bounded?(value, limit) do
    valid_json?(value, 0) and byte_size(IO.iodata_to_binary(JSON.encode!(value))) <= limit
  rescue
    _ -> false
  end

  defp valid_json?(_, depth) when depth > 16, do: false
  defp valid_json?(v, _) when is_binary(v), do: String.valid?(v) and byte_size(v) <= 8192
  defp valid_json?(v, _) when is_number(v), do: finite?(v)
  defp valid_json?(v, _) when is_boolean(v) or is_nil(v), do: true

  defp valid_json?(v, depth) when is_map(v),
    do:
      map_size(v) <= 128 and
        Enum.all?(v, fn {k, x} ->
          is_binary(k) and valid_json?(k, depth + 1) and valid_json?(x, depth + 1)
        end)

  defp valid_json?(v, depth) when is_list(v),
    do: length(v) <= 128 and Enum.all?(v, &valid_json?(&1, depth + 1))

  defp valid_json?(_, _), do: false
end
