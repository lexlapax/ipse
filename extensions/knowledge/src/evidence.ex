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
  @safe 9_007_199_254_740_991
  @collection_chunking %{"version" => 2, "max_bytes" => 4096}
  @document_span_fields ~w(paragraph start_byte end_byte quote_start_byte quote_end_byte table row cell)

  def safe_integer_max, do: @safe
  def safe_uint?(value), do: is_integer(value) and value in 0..@safe
  def safe_positive?(value), do: is_integer(value) and value in 1..@safe

  def sha256(bytes) when is_binary(bytes),
    do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  def sha256?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  def id(tag, parts) when is_binary(tag) and is_list(parts),
    do: sha256(IO.iodata_to_binary(JSON.encode!(["ipse-knowledge", 1, tag, parts])))

  def source(attrs) do
    if exact?(attrs, @attrs) or exact?(attrs, @attrs ++ ["document"]) do
      source =
        Map.merge(attrs, %{
          "version" => if(Map.has_key?(attrs, "document"), do: 2, else: 1),
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

  @doc "Explicit Collection source format; legacy source creation and reads keep recipe one."
  def collection_source(input) do
    attrs =
      if valid_source?(input),
        do: Map.drop(input, ~w(version source_key content_sha256 chunking)),
        else: input

    with true <- exact?(attrs, @attrs) or exact?(attrs, @attrs ++ ["document"]),
         source =
           Map.merge(attrs, %{
             "version" => 3,
             "chunking" => @collection_chunking,
             "source_key" => sha256(attrs["source_id"] || ""),
             "content_sha256" => sha256(attrs["text"] || "")
           }),
         true <- valid_source?(source) do
      {:ok, source}
    else
      _ -> {:error, :invalid_source}
    end
  rescue
    _ -> {:error, :invalid_source}
  end

  def collection_chunking, do: @collection_chunking

  def valid_source?(s), do: source_shape?(s) and document_source?(s)

  @doc "Validate metadata before loading content; this establishes no readable source."
  def source_metadata?(attrs) do
    source =
      Map.merge(attrs, %{
        "version" => 1,
        "source_key" => sha256(attrs["source_id"] || ""),
        "content_sha256" => sha256(attrs["text"] || "")
      })

    exact?(attrs, @attrs) and source_shape?(source) and
      case get_in(source, ["origin", "receipt"]) do
        %{"kind" => "document_extraction", "version" => 4} = receipt ->
          document_reference?(receipt)

        %{"kind" => "document_extraction"} = receipt ->
          document_metadata?(receipt)

        _ ->
          true
      end
  rescue
    _ -> false
  end

  defp source_shape?(s) do
    is_map(s) and
      ((exact?(s, @source) and s["version"] == 1) or
         (exact?(s, @source ++ ["document"]) and s["version"] == 2 and is_map(s["document"])) or
         (s["version"] == 3 and chunking?(s["chunking"]) and
            (exact?(s, @source ++ ["chunking"]) or
               (exact?(s, @source ++ ~w(chunking document)) and is_map(s["document"]))))) and
      identifier?(s["source_id"], 256) and
      partition?(s["partition"]) and positive?(s["generation"]) and text?(s["title"], 128) and
      text?(s["uri"], 512) and text?(s["text"], 65_536) and timestamp?(s["observed_at_ms"]) and
      optional_time?(s["event_at_ms"]) and optional_time?(s["expires_at_ms"]) and
      origin?(s["origin"]) and s["source_key"] == sha256(s["source_id"]) and
      s["content_sha256"] == sha256(s["text"])
  end

  @doc false
  def current_fact?(fact, now),
    do: valid_fact?(fact) and safe_uint?(now) and fact_current?(fact, now)

  def current?(s, now),
    do: valid_source?(s) and current_times?(s, now)

  @doc "Check metadata time selection only; load and validate content before producing evidence."
  def current_metadata?(attrs, now), do: source_metadata?(attrs) and current_times?(attrs, now)

  defp current_times?(s, now),
    do:
      timestamp?(now) and s["observed_at_ms"] <= now and
        (is_nil(s["expires_at_ms"]) or s["expires_at_ms"] > now) and not s["origin"]["historical"]

  def query_scope(rank, sources, store_gaps, now) do
    source_exclusions =
      sources
      |> Enum.reject(&current?(&1, now))
      |> Enum.map(&%{"code" => "stale_source", "source_id" => &1["source_id"]})

    document_gaps =
      for source <- sources,
          receipt = document_receipt(source),
          is_map(receipt) and receipt["kind"] == "document_extraction" and
            receipt["status"] == "partial",
          do: %{
            "code" => "partial_document",
            "source_id" => source["source_id"],
            "warnings" => receipt["warnings"]
          }

    gaps = Enum.uniq(rank["gaps"] ++ store_gaps ++ source_exclusions ++ document_gaps)

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
        chunk_spans(source)
        |> Enum.map(fn {start, text} ->
          finish = start + byte_size(text)

          %{
            "version" => chunk_version(source),
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

  @doc "Exact reusable lexical recipe; changing token selection requires a new recipe."
  def lexical_recipe, do: "ipse.evidence.word_tokens.v1"

  @doc false
  def lexical_query_terms(query) do
    if text?(query, 1024), do: {:ok, tokens(query) |> Enum.uniq()}, else: {:error, :invalid_query}
  end

  @doc "Lossless sorted term frequencies and chunk lengths for a validated source."
  def lexical_run(source) do
    with {:ok, chunks} <- chunks(source) do
      documents = Enum.map(chunks, fn chunk -> {chunk, tokens(chunk["text"])} end)

      terms =
        documents
        |> Enum.with_index()
        |> Enum.reduce(%{}, fn {{_chunk, tokens}, ordinal}, acc ->
          Enum.reduce(Enum.frequencies(tokens), acc, fn {term, count}, acc ->
            Map.update(acc, term, [[ordinal, count]], &(&1 ++ [[ordinal, count]]))
          end)
        end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {term, postings} -> [term, postings] end)

      run = %{
        "version" => if(source["version"] == 3, do: 2, else: 1),
        "recipe" => lexical_recipe(),
        "source_key" => source["source_key"],
        "generation" => source["generation"],
        "content_sha256" => source["content_sha256"],
        "selection" => %{
          "observed_at_ms" => source["observed_at_ms"],
          "expires_at_ms" => source["expires_at_ms"],
          "historical" => source["origin"]["historical"]
        },
        "chunks" =>
          Enum.map(documents, fn {chunk, tokens} ->
            [chunk["chunk_id"], chunk["start_byte"], chunk["end_byte"], length(tokens)]
          end),
        "terms" => terms
      }

      {:ok,
       if(source["version"] == 3, do: Map.put(run, "chunking", source["chunking"]), else: run)}
    end
  end

  @doc "Validate a complete lexical run's order, counts, recipe and local references."
  def valid_lexical_run?(run) do
    with true <-
           (exact?(
              run,
              ~w(version recipe source_key generation content_sha256 selection chunks terms)
            ) and run["version"] === 1) or
             (exact?(
                run,
                ~w(version recipe source_key generation content_sha256 selection chunks terms chunking)
              ) and
                run["version"] === 2 and chunking?(run["chunking"])),
         true <- run["recipe"] == lexical_recipe(),
         true <- sha256?(run["source_key"]) and sha256?(run["content_sha256"]),
         true <- safe_positive?(run["generation"]),
         true <- exact?(run["selection"], ~w(observed_at_ms expires_at_ms historical)),
         true <- timestamp?(run["selection"]["observed_at_ms"]),
         true <- optional_time?(run["selection"]["expires_at_ms"]),
         true <- is_boolean(run["selection"]["historical"]),
         chunks when is_list(chunks) <- run["chunks"],
         true <- length(chunks) in 1..32,
         true <- Enum.all?(chunks, &lexical_chunk?/1),
         true <- length(Enum.uniq_by(chunks, &hd/1)) == length(chunks),
         true <- lexical_chunk_order?(chunks),
         true <-
           Enum.all?(chunks, fn [id, start, finish, _] ->
             id == chunk_id(run, start, finish)
           end),
         terms when is_list(terms) <- run["terms"],
         true <- Enum.all?(terms, &lexical_term?(&1, length(chunks))),
         true <- terms == Enum.sort_by(Enum.uniq_by(terms, &hd/1), &hd/1) do
      actual =
        Enum.reduce(terms, %{}, fn [_, postings], counts ->
          Enum.reduce(postings, counts, fn [ordinal, frequency], counts ->
            Map.update(counts, ordinal, frequency, &(&1 + frequency))
          end)
        end)

      Enum.with_index(chunks)
      |> Enum.all?(fn {[_, _, _, length], ordinal} -> Map.get(actual, ordinal, 0) == length end)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp lexical_chunk?([id, start, finish, count]),
    do:
      sha256?(id) and safe_uint?(start) and safe_positive?(finish) and start < finish and
        finish <= 65_536 and safe_uint?(count) and count <= 65_536

  defp lexical_chunk?(_), do: false

  defp lexical_chunk_order?([_]), do: true

  defp lexical_chunk_order?([[_, _, finish, _], [_, start, _, _] = next | rest]),
    do: finish <= start and lexical_chunk_order?([next | rest])

  defp lexical_term?([term, postings], chunks) do
    is_binary(term) and term != "" and tokens(term) == [term] and is_list(postings) and
      postings != [] and
      Enum.all?(postings, fn
        [ordinal, frequency] ->
          is_integer(ordinal) and ordinal in 0..(chunks - 1) and
            safe_positive?(frequency) and frequency <= 65_536

        _ ->
          false
      end) and postings == Enum.sort_by(Enum.uniq_by(postings, &hd/1), &hd/1)
  end

  defp lexical_term?(_, _), do: false

  def citation(source, chunk, start, finish) do
    case citations(source, [{chunk, start, finish}]) do
      {:ok, [citation]} -> {:ok, citation}
      _ -> {:error, :invalid_span}
    end
  end

  @doc false
  def citations(source, spans) when is_list(spans) and length(spans) in 1..256 do
    with true <- valid_source?(source),
         {:ok, chunks} <- chunks(source) do
      Enum.reduce_while(spans, {:ok, []}, fn
        {chunk, start, finish}, {:ok, acc} ->
          case citation_with_chunks(source, chunk, start, finish, chunks) do
            {:ok, citation} -> {:cont, {:ok, [citation | acc]}}
            _ -> {:halt, {:error, :invalid_span}}
          end

        _, _ ->
          {:halt, {:error, :invalid_span}}
      end)
      |> case do
        {:ok, citations} -> {:ok, Enum.reverse(citations)}
        error -> error
      end
    else
      _ -> {:error, :invalid_span}
    end
  rescue
    _ -> {:error, :invalid_span}
  end

  def citations(_, _), do: {:error, :invalid_span}

  defp citation_with_chunks(source, chunk, start, finish, chunks) do
    if exact?(chunk, @chunk) and is_integer(start) and
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

      c =
        case document_location(source, start, finish) do
          nil -> c
          location -> c |> Map.put("version", 2) |> Map.put("document", location)
        end

      c =
        if source["version"] == 3,
          do: c |> Map.put("version", 3) |> Map.put("chunking", source["chunking"]),
          else: c

      if valid_span_with_chunks?(source, c, chunks), do: {:ok, c}, else: {:error, :invalid_span}
    else
      {:error, :invalid_span}
    end
  rescue
    _ -> {:error, :invalid_span}
  end

  def valid_span?(s, c) do
    valid_spans?(s, [c])
  end

  @doc false
  def valid_spans?(s, citations) do
    with true <- valid_source?(s) and is_list(citations),
         {:ok, chunks} <- chunks(s) do
      Enum.all?(citations, &valid_span_with_chunks?(s, &1, chunks))
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_span_with_chunks?(s, c, chunks) do
    with true <- citation_shape?(c),
         true <-
           if(s["version"] == 3,
             do: c["version"] == 3 and c["chunking"] === s["chunking"],
             else: c["version"] in [1, 2]
           ),
         true <-
           Enum.all?(
             ~w(source_id source_key generation content_sha256 uri observed_at_ms event_at_ms origin),
             &(s[&1] == c[&1])
           ),
         chunk when is_map(chunk) <- Enum.find(chunks, &(&1["chunk_id"] == c["chunk_id"])),
         true <- c["start_byte"] >= chunk["start_byte"] and c["end_byte"] <= chunk["end_byte"],
         true <- document_citation?(s, c),
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
                 sha256?(v["selection_sha256"]))) and v["encoding"] == "float32le" and
             sha256?(v["chunk_id"]) and sha256?(v["input_sha256"]) and
             identifier?(v["profile"], 128) and
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

  @doc "Check a stored vector's input digest against the current raw source chunk."
  def vector_input_matches_chunk?(vector, chunk) when is_map(vector) and is_map(chunk) do
    with true <- vector["chunk_id"] === chunk["chunk_id"],
         true <- is_binary(chunk["text"]),
         {:ok, digest} <- Ipse.Extension.canonical_digest([chunk["text"]]) do
      vector["input_sha256"] === digest
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def vector_input_matches_chunk?(_, _), do: false

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

  @doc "Validate final hydrated chunks against exact index frequencies and global BM25 statistics."
  def rank_indexed(sources, rows, query, stats, top_k, now) do
    with :ok <- inputs(sources, top_k, now),
         {:ok, terms} <- lexical_query_terms(query),
         true <- is_list(rows) and length(rows) <= top_k,
         true <- exact?(stats, ~w(chunks tokens dfs)),
         true <- safe_uint?(stats["chunks"]) and stats["chunks"] <= 10_000,
         true <- safe_uint?(stats["tokens"]) and is_map(stats["dfs"]),
         true <- Enum.sort(Map.keys(stats["dfs"])) == Enum.sort(terms),
         true <-
           Enum.all?(stats["dfs"], fn {_, df} -> safe_uint?(df) and df <= stats["chunks"] end),
         true <- length(Enum.uniq_by(rows, &{hd(&1.summary), &1.chunk})) == length(rows) do
      n = stats["chunks"]
      avg = if n == 0, do: 1.0, else: max(stats["tokens"] / n, 1.0)
      by_key = Map.new(sources, &{&1["source_key"], &1})

      Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, candidates} ->
        with source when is_map(source) <- by_key[hd(row.summary)],
             true <-
               current?(source, now) and source["generation"] == Enum.at(row.summary, 2) and
                 source["content_sha256"] == Enum.at(row.summary, 3),
             {:ok, chunks} <- chunks(source),
             chunk when is_map(chunk) <- Enum.at(chunks, row.chunk),
             tokens = tokens(chunk["text"]),
             true <- length(tokens) == row.length,
             counts = Enum.frequencies(tokens),
             actual = Map.new(terms, &{&1, Map.get(counts, &1, 0)}),
             true <- actual === row.terms do
          score =
            Enum.reduce(terms, 0.0, fn term, total ->
              tf = actual[term]
              df = stats["dfs"][term]

              total +
                :math.log(1.0 + (n - df + 0.5) / (df + 0.5)) * tf * 2.2 /
                  (tf + 1.2 * (0.25 + 0.75 * row.length / avg))
            end)

          if finite?(score) and score == row.score,
            do: {:cont, {:ok, candidates ++ [candidate(source, chunk, score, "bm25", query)]}},
            else: {:halt, {:error, :invalid_index_selection}}
        else
          _ -> {:halt, {:error, :invalid_index_selection}}
        end
      end)
      |> case do
        {:ok, candidates} ->
          {:ok,
           result(order(candidates), [], [], %{
             "as_of_ms" => now,
             "chunks" => n,
             "sources" => length(sources),
             "method" => "bm25",
             "complete" => true
           })}

        error ->
          error
      end
    else
      _ -> {:error, :invalid_index_selection}
    end
  rescue
    _ -> {:error, :invalid_index_selection}
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
      positive?(ref["generation"]) and sha256?(ref["content_sha256"]) and sha256?(ref["chunk_id"]) and
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
    do:
      id("chunk", [
        s["source_key"],
        s["generation"],
        s["content_sha256"],
        chunk_version(s),
        start,
        finish
      ])

  defp chunking?(value), do: value === @collection_chunking
  defp chunk_version(source), do: if(chunking?(Map.get(source, "chunking")), do: 2, else: 1)
  defp chunk_bytes(source), do: if(chunk_version(source) == 2, do: 4096, else: 2048)

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
      ((exact?(c, @citation) and c["version"] == 1) or
         (exact?(c, @citation ++ ["document"]) and c["version"] == 2 and
            document_location?(c["document"])) or
         ((exact?(c, @citation ++ ["chunking"]) or
             (exact?(c, @citation ++ ~w(chunking document)) and document_location?(c["document"]))) and
            c["version"] == 3 and chunking?(c["chunking"]))) and
        identifier?(c["source_id"], 256) and
        sha256?(c["source_key"]) and positive?(c["generation"]) and sha256?(c["content_sha256"]) and
        sha256?(c["chunk_id"]) and is_integer(c["start_byte"]) and c["start_byte"] >= 0 and
        is_integer(c["end_byte"]) and c["end_byte"] > c["start_byte"] and text?(c["quote"], 1024) and
        byte_size(c["quote"]) == c["end_byte"] - c["start_byte"] and
        sha256(c["quote"]) == c["quote_sha256"] and text?(c["uri"], 512) and
        timestamp?(c["observed_at_ms"]) and optional_time?(c["event_at_ms"]) and
        origin?(c["origin"])

  @doc "Validate the bounded typed extraction receipt against the complete provided text."
  def valid_document?(receipt, text), do: valid_document?(receipt, text, nil)

  def valid_document?(receipt, text, chunking) do
    metadata = document_body(receipt)

    (is_nil(chunking) or chunking?(chunking)) and document_metadata?(metadata) and is_binary(text) and
      String.valid?(text) and
      byte_size(text) in 1..65_536 and
      List.last(metadata["segments"])["end_byte"] == byte_size(text) and
      document_segments?(metadata["segments"], text) and
      length(
        chunk_spans(%{
          "text" => text,
          "origin" => %{"receipt" => receipt},
          "chunking" => chunking
        })
      ) <= 32
  rescue
    _ -> false
  end

  @doc "Pack typed document metadata without widening the State transport depth."
  def document_storage_receipt!(receipt) do
    if receipt["version"] in [1, 2] and document_metadata?(receipt) do
      bytes = IO.iodata_to_binary(JSON.encode!(receipt))

      packed =
        if byte_size(bytes) <= 2048 do
          %{
            "kind" => "document_extraction",
            "version" => 3,
            "document" => bytes,
            "sha256" => sha256(bytes)
          }
        else
          receipt
          |> Map.take(
            ~w(kind format original_sha256 original_bytes extraction_version status acquisition)
          )
          |> Map.merge(%{
            "version" => 4,
            "manifest_sha256" => sha256(bytes),
            "manifest_bytes" => byte_size(bytes),
            "segment_count" => length(receipt["segments"]),
            "warning_count" => length(receipt["warnings"]),
            "manifest_ref" => nil
          })
        end

      if json_bounded?(packed, 3072),
        do: packed,
        else: raise(ArgumentError, "document metadata exceeds its storage envelope")
    else
      raise ArgumentError, "invalid document metadata"
    end
  end

  @doc "Read typed metadata only; its receipt supplies no acquisition or current-use authority."
  def document_receipt(source) do
    case get_in(source, ["origin", "receipt"]) do
      %{"version" => 4} = reference ->
        case document_manifest(reference, source["document"]) do
          {:ok, body} -> body
          _ -> nil
        end

      receipt ->
        document_body(receipt)
    end
  end

  @doc "Validate a complete privately assembled manifest against its compact storage descriptor."
  def document_manifest(reference, body) do
    with true <- document_reference?(reference) and document_metadata?(body),
         true <-
           Map.take(
             reference,
             ~w(kind format original_sha256 original_bytes extraction_version status)
           ) ===
             Map.take(
               body,
               ~w(kind format original_sha256 original_bytes extraction_version status)
             ),
         true <-
           get_in(reference, ["acquisition", "path"]) === get_in(body, ["acquisition", "path"]),
         body =
           if(reference["acquisition"],
             do: Map.put(body, "acquisition", reference["acquisition"]),
             else: body
           ),
         bytes = IO.iodata_to_binary(JSON.encode!(body)),
         true <-
           byte_size(bytes) == reference["manifest_bytes"] and
             sha256(bytes) == reference["manifest_sha256"],
         true <-
           length(body["segments"]) == reference["segment_count"] and
             length(body["warnings"]) == reference["warning_count"] do
      {:ok, body}
    else
      _ -> {:error, :invalid_document_manifest}
    end
  rescue
    _ -> {:error, :invalid_document_manifest}
  end

  @doc "Validate only a compact descriptor. Its digest is not a readable extraction manifest."
  def document_reference?(reference) do
    fields =
      ~w(kind version format original_sha256 original_bytes extraction_version status manifest_sha256 manifest_bytes segment_count warning_count manifest_ref)

    fields =
      if Map.has_key?(reference, "acquisition"), do: fields ++ ["acquisition"], else: fields

    exact?(reference, fields) and reference["kind"] == "document_extraction" and
      reference["version"] === 4 and
      reference["format"] == "docx" and sha256?(reference["original_sha256"]) and
      safe_positive?(reference["original_bytes"]) and reference["original_bytes"] <= 16_777_216 and
      identifier?(reference["extraction_version"], 128) and
      Regex.match?(~r/\Aipse-documents-v[1-9][0-9]{0,5}\z/, reference["extraction_version"]) and
      reference["status"] in ~w(complete partial) and
      reference["manifest_bytes"] in 2049..16_384 and sha256?(reference["manifest_sha256"]) and
      reference["segment_count"] in 1..32 and reference["warning_count"] in 0..32 and
      reference["status"] == "complete" == (reference["warning_count"] == 0) and
      (not Map.has_key?(reference, "acquisition") or
         document_acquisition?(reference["acquisition"])) and
      (is_nil(reference["manifest_ref"]) or
         (exact?(reference["manifest_ref"], ~w(key sha256)) and
            Enum.all?(~w(key sha256), &sha256?(reference["manifest_ref"][&1])))) and
      json_bounded?(reference, 3072)
  rescue
    _ -> false
  end

  defp document_body(%{"kind" => "document_extraction", "version" => 3} = receipt) do
    with true <-
           exact?(receipt, ~w(kind version document sha256)) and json_bounded?(receipt, 3072),
         bytes when is_binary(bytes) <- receipt["document"],
         true <- byte_size(bytes) <= 2048 and receipt["sha256"] == sha256(bytes),
         body when is_map(body) <- JSON.decode!(bytes),
         true <- body["version"] in [1, 2] and body["kind"] == "document_extraction",
         true <- IO.iodata_to_binary(JSON.encode!(body)) == bytes do
      body
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp document_body(%{"kind" => "document_extraction", "version" => version} = receipt)
       when version in [1, 2], do: receipt

  defp document_body(_), do: nil

  defp document_metadata?(%{"version" => 3} = receipt),
    do: document_metadata?(document_body(receipt))

  defp document_metadata?(receipt) do
    fields =
      ~w(kind version format original_sha256 original_bytes extraction_version status warnings segments)

    fields = if receipt["version"] == 2, do: fields ++ ["acquisition"], else: fields

    exact?(
      receipt,
      fields
    ) and
      receipt["kind"] == "document_extraction" and receipt["version"] in [1, 2] and
      (receipt["version"] != 2 or document_acquisition?(receipt["acquisition"])) and
      receipt["format"] == "docx" and
      sha256?(receipt["original_sha256"]) and safe_positive?(receipt["original_bytes"]) and
      receipt["original_bytes"] <= 16_777_216 and identifier?(receipt["extraction_version"], 128) and
      Regex.match?(~r/\Aipse-documents-v[1-9][0-9]{0,5}\z/, receipt["extraction_version"]) and
      receipt["status"] in ~w(complete partial) and is_list(receipt["warnings"]) and
      length(receipt["warnings"]) <= 32 and Enum.all?(receipt["warnings"], &is_map/1) and
      receipt["status"] == "complete" == (receipt["warnings"] == []) and
      is_list(receipt["segments"]) and length(receipt["segments"]) in 1..32 and
      json_bounded?(receipt, 16_384) and
      Enum.all?(receipt["segments"], fn segment ->
        exact?(segment, ~w(start_byte end_byte text_sha256 locator)) and
          safe_uint?(segment["start_byte"]) and safe_positive?(segment["end_byte"]) and
          segment["end_byte"] > segment["start_byte"] and segment["end_byte"] <= 65_536 and
          sha256?(segment["text_sha256"]) and
          segment_locator?(segment["locator"], receipt["extraction_version"]) and
          (segment["locator"]["kind"] != "block_group" or
             block_group_bytes(segment["locator"]) ==
               segment["end_byte"] - segment["start_byte"])
      end)
  rescue
    _ -> false
  end

  defp document_acquisition?(acquisition) do
    exact?(acquisition, ~w(kind path operation_id)) and acquisition["kind"] == "workspace.read" and
      identifier?(acquisition["path"], 1024) and Path.type(acquisition["path"]) == :relative and
      not String.contains?(acquisition["path"], "\\") and
      Enum.all?(String.split(acquisition["path"], "/"), &(&1 not in ["", ".", ".."])) and
      is_binary(acquisition["operation_id"]) and
      Regex.match?(~r/\A[0-9a-f]{32}\z/, acquisition["operation_id"])
  end

  defp document_segments?(segments, text) do
    Enum.reduce_while(segments, {:ok, 0}, fn segment, {:ok, offset} ->
      start = segment["start_byte"]
      finish = segment["end_byte"]

      if exact?(segment, ~w(start_byte end_byte text_sha256 locator)) and
           safe_uint?(start) and safe_positive?(finish) and finish > start and
           start == offset and finish <= byte_size(text) and
           segment_locator?(segment["locator"], "ipse-documents-v14") and
           block_group_text?(segment["locator"], binary_part(text, start, finish - start)) and
           sha256?(segment["text_sha256"]) and
           sha256(binary_part(text, start, finish - start)) == segment["text_sha256"] and
           String.valid?(binary_part(text, start, finish - start)) do
        cond do
          finish == byte_size(text) -> {:cont, {:ok, finish}}
          binary_part(text, finish, 1) == "\n" -> {:cont, {:ok, finish + 1}}
          true -> {:halt, :invalid}
        end
      else
        {:halt, :invalid}
      end
    end) == {:ok, byte_size(text)}
  end

  defp locator?(locator) do
    required = ~w(kind part paragraph)
    optional = ~w(table row cell region annotation_id reference_site reference_range)

    is_map(locator) and exact?(Map.drop(locator, optional), required) and
      locator["kind"] in ~w(paragraph table_cell) and identifier?(locator["part"], 256) and
      String.starts_with?(locator["part"], "word/") and
      not String.contains?(locator["part"], ["..", "\\"]) and
      safe_positive?(locator["paragraph"]) and
      (locator["kind"] != "table_cell" or
         Enum.all?(~w(table row cell), &safe_positive?(locator[&1]))) and
      Enum.all?(
        ~w(table row cell),
        &(not Map.has_key?(locator, &1) or safe_positive?(locator[&1]))
      ) and
      (not Map.has_key?(locator, "region") or locator["region"] in ~w(header footer)) and
      (not Map.has_key?(locator, "annotation_id") or identifier?(locator["annotation_id"], 64)) and
      (not Map.has_key?(locator, "reference_site") or
         reference_locator?(locator["reference_site"], ~w(byte_offset))) and
      (not Map.has_key?(locator, "reference_range") or
         reference_locator?(locator["reference_range"], ~w(start_byte end_byte)))
  end

  defp segment_locator?(%{"kind" => "block_group"} = locator, recipe) do
    exact?(locator, ~w(kind part blocks)) and recipe == "ipse-documents-v14" and
      is_list(locator["blocks"]) and length(locator["blocks"]) in 2..64 and
      Enum.reduce_while(locator["blocks"], 0, fn
        [paragraph, bytes | _] = row, prior
        when is_integer(paragraph) and paragraph > prior and
               is_integer(bytes) and bytes in 1..4096 ->
          if locator?(block_locator(locator["part"], row)),
            do: {:cont, paragraph},
            else: {:halt, false}

        _, _ ->
          {:halt, false}
      end) != false
  end

  defp segment_locator?(locator, _), do: locator?(locator)

  defp block_group_bytes(locator),
    do: Enum.sum(Enum.map(locator["blocks"], &Enum.at(&1, 1))) + length(locator["blocks"]) - 1

  defp block_group_text?(%{"kind" => "block_group"} = locator, text) do
    Enum.reduce_while(locator["blocks"], {0, length(locator["blocks"])}, fn [_, bytes | _],
                                                                            {offset, left} ->
      if offset + bytes <= byte_size(text) and String.valid?(binary_part(text, offset, bytes)) and
           (left == 1 or binary_part(text, offset + bytes, 1) == "\n"),
         do: {:cont, {offset + bytes + if(left > 1, do: 1, else: 0), left - 1}},
         else: {:halt, false}
    end) == {byte_size(text), 0}
  end

  defp block_group_text?(_, _), do: true

  defp block_locator(part, [paragraph, _]),
    do: %{"kind" => "paragraph", "part" => part, "paragraph" => paragraph}

  defp block_locator(part, [paragraph, _, table, row, cell]),
    do: %{
      "kind" => "table_cell",
      "part" => part,
      "paragraph" => paragraph,
      "table" => table,
      "row" => row,
      "cell" => cell
    }

  defp block_locator(_, _), do: nil

  defp reference_locator?(locator, offsets) do
    is_map(locator) and Enum.all?(offsets, &safe_uint?(locator[&1])) and
      locator?(Map.drop(locator, offsets)) and
      (offsets != ~w(start_byte end_byte) or locator["end_byte"] > locator["start_byte"])
  end

  defp document_source?(source) do
    case get_in(source, ["origin", "receipt"]) do
      %{"kind" => "document_extraction", "version" => 4} = reference ->
        with true <- source["version"] in [2, 3],
             {:ok, body} <- document_manifest(reference, source["document"]),
             true <- body === source["document"],
             do: valid_document?(body, source["text"], Map.get(source, "chunking")),
             else: (_ -> false)

      %{"kind" => "document_extraction"} = receipt ->
        source["version"] in [1, 3] and not Map.has_key?(source, "document") and
          valid_document?(receipt, source["text"], Map.get(source, "chunking"))

      _ ->
        source["version"] in [1, 3] and not Map.has_key?(source, "document")
    end
  end

  defp chunk_spans(source) do
    case document_receipt(source) do
      %{"kind" => "document_extraction", "segments" => segments} ->
        Enum.flat_map(segments, fn segment ->
          split_utf8(
            binary_part(
              source["text"],
              segment["start_byte"],
              segment["end_byte"] - segment["start_byte"]
            ),
            chunk_bytes(source),
            segment["start_byte"],
            []
          )
        end)

      _ ->
        split_utf8(source["text"], chunk_bytes(source), 0, [])
    end
  end

  defp document_location(source, start, finish) do
    case document_receipt(source) do
      %{"kind" => "document_extraction"} = receipt ->
        case Enum.filter(
               receipt["segments"],
               &(start >= &1["start_byte"] and finish <= &1["end_byte"])
             ) do
          [%{"locator" => %{"kind" => "block_group"}} = segment] ->
            grouped_document_location(receipt, segment, start, finish)

          [segment] ->
            %{
              "version" => 1,
              "original_sha256" => receipt["original_sha256"],
              "extraction_version" => receipt["extraction_version"],
              "status" => receipt["status"],
              "locator" => segment["locator"],
              "start_byte" => start - segment["start_byte"],
              "end_byte" => finish - segment["start_byte"]
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp document_location?(location) do
    if location["version"] == 2 do
      exact?(
        location,
        ~w(version original_sha256 extraction_version status part spans span_fields)
      ) and
        location["span_fields"] === @document_span_fields and
        sha256?(location["original_sha256"]) and
        location["extraction_version"] == "ipse-documents-v14" and
        location["status"] in ~w(complete partial) and is_list(location["spans"]) and
        length(location["spans"]) in 1..64 and ordered_group_spans?(location["spans"]) and
        Enum.all?(location["spans"], fn
          [paragraph, start, finish, quote_start, quote_finish | coordinates] ->
            locator?(block_locator(location["part"], [paragraph, 0 | coordinates])) and
              safe_uint?(start) and safe_uint?(quote_start) and safe_positive?(finish) and
              safe_positive?(quote_finish) and finish > start and quote_finish > quote_start and
              finish - start == quote_finish - quote_start

          _ ->
            false
        end)
    else
      exact?(
        location,
        ~w(version original_sha256 extraction_version status locator start_byte end_byte)
      ) and
        location["version"] == 1 and sha256?(location["original_sha256"]) and
        identifier?(location["extraction_version"], 128) and
        location["status"] in ~w(complete partial) and
        locator?(location["locator"]) and safe_uint?(location["start_byte"]) and
        safe_positive?(location["end_byte"]) and location["end_byte"] > location["start_byte"]
    end
  end

  defp ordered_group_spans?(spans) do
    Enum.reduce_while(spans, {0, nil}, fn
      [paragraph, _, _, start, finish | _], {prior_paragraph, prior_end}
      when is_integer(paragraph) and paragraph > prior_paragraph and is_integer(start) and
             is_integer(finish) ->
        if if(is_nil(prior_end), do: start in 0..1, else: start == prior_end + 1),
          do: {:cont, {paragraph, finish}},
          else: {:halt, false}

      _, _ ->
        {:halt, false}
    end) != false
  end

  defp grouped_document_location(receipt, segment, start, finish) do
    {spans, _} =
      Enum.reduce(segment["locator"]["blocks"], {[], segment["start_byte"]}, fn [
                                                                                  paragraph,
                                                                                  bytes
                                                                                  | coordinates
                                                                                ],
                                                                                {spans, offset} ->
        left = max(start, offset)
        right = min(finish, offset + bytes)

        next =
          if left < right,
            do: [
              [paragraph, left - offset, right - offset, left - start, right - start] ++
                coordinates
              | spans
            ],
            else: spans

        {next, offset + bytes + 1}
      end)

    common = Map.take(receipt, ~w(original_sha256 extraction_version status))

    case Enum.reverse(spans) do
      [[paragraph, left, right, 0, quote_finish | coordinates]]
      when quote_finish == finish - start ->
        Map.merge(common, %{
          "version" => 1,
          "locator" => block_locator(segment["locator"]["part"], [paragraph, 0 | coordinates]),
          "start_byte" => left,
          "end_byte" => right
        })

      [] ->
        nil

      rows ->
        Map.merge(common, %{
          "version" => 2,
          "part" => segment["locator"]["part"],
          "spans" => rows,
          "span_fields" => @document_span_fields
        })
    end
  end

  defp document_citation?(source, citation) do
    case document_location(source, citation["start_byte"], citation["end_byte"]) do
      nil ->
        citation["version"] in [1, 3] and not Map.has_key?(citation, "document") and
          not match?(%{"kind" => "document_extraction"}, get_in(source, ["origin", "receipt"]))

      location ->
        citation["version"] in [2, 3] and citation["document"] === location
    end
  end

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
  defp positive?(n), do: safe_positive?(n)
  defp timestamp?(n), do: safe_uint?(n)
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
