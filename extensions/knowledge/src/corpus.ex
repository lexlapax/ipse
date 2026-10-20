defmodule IpseKnowledge.Corpus do
  @behaviour Ipse.Extension
  alias IpseKnowledge.{Adapters, Evidence, Profiles, Store}
  @preset "state-lexical"
  @source_actions %{
    "put" => :put,
    "open" => :open,
    "append" => :append,
    "publish" => :publish,
    "abort" => :abort,
    "forget" => :forget,
    "inspect" => :inspect,
    "export" => :export,
    "import" => :import,
    "collect" => :collect
  }

  def describe do
    %{
      "sdk" => 2,
      "capabilities" => Profiles.capabilities("corpus", @preset),
      "exports" => %{
        "version" => 1,
        "services" => [],
        "commands" => [
          entry("source", "Explicit source lifecycle", source_schema()),
          entry("query", "Read current cited evidence", query_schema()),
          entry("index", "Explicit embedding projection", index_schema())
        ],
        "tools" => [entry("query", "Read current cited evidence", query_schema())]
      }
    }
  end

  def init(options) do
    case Profiles.validate("corpus", @preset, options) do
      {:ok, resolved} ->
        {:ok, %{resolved: resolved, phase: :idle, ctx: nil, cont: nil, pending: nil}}

      {:error, code} ->
        {:ok, %{invalid: code, phase: :idle, ctx: nil, cont: nil, pending: nil}}
    end
  end

  def handle("invoke.command", payload, state), do: invoke(payload, state)
  def handle("invoke.tool", payload, state), do: invoke(payload, state)

  def handle(
        "host.actions",
        %{"outcome" => outcome},
        %{phase: phase, pending: pending, cont: cont} = state
      )
      when phase != :idle do
    result =
      if pending == :store, do: Store.resume(cont, outcome), else: Adapters.resume(cont, outcome)

    advance(result, state)
  end

  def handle(_, _, state), do: finish(state, refused(:invalid_invocation))

  defp invoke(_payload, %{invalid: code} = state), do: finish(state, refused(code))
  defp invoke(%{"id" => "source", "arguments" => args}, state), do: source(args, state)
  defp invoke(%{"id" => "query", "arguments" => args}, state), do: query(args, state)
  defp invoke(%{"id" => "index", "arguments" => args}, state), do: index(args, state)
  defp invoke(_, state), do: finish(state, refused(:invalid_invocation))

  defp source(%{"store" => store, "action" => action, "args" => source_args} = outer, state) do
    with true <- exact?(outer, ~w(store action args)),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", store),
         {:ok, operation} <- Map.fetch(@source_actions, action),
         true <- valid_source_args?(action, source_args) do
      advance(Store.start(store, profile, operation, source_args), %{
        state
        | phase: :source,
          ctx: %{store: store}
      })
    else
      _ -> finish(state, refused(:invalid_source_command))
    end
  end

  defp source(_, state), do: finish(state, refused(:invalid_source_command))

  defp query(args, state) do
    with true <- exact?(args, ~w(store retrieval rerank query top_k as_of_ms)),
         {:ok, store_profile} <- Profiles.lookup(state.resolved, "stores", args["store"]),
         {:ok, retrieval} <- Profiles.lookup(state.resolved, "retrieval", args["retrieval"]),
         {:ok, rerank_profile} <- Profiles.lookup(state.resolved, "rerank", args["rerank"]),
         true <-
           text?(args["query"], 1024) and is_integer(args["top_k"]) and args["top_k"] in 1..10,
         true <-
           args["as_of_ms"] == nil or
             (is_integer(args["as_of_ms"]) and args["as_of_ms"] in 0..9_007_199_254_740_991),
         true <-
           retrieval["kind"] != "mcp_query" or
             (store_profile["kind"] == "mcp_cas" and
                store_profile["partition"] == retrieval["partition"]) do
      at = args["as_of_ms"] || System.system_time(:millisecond)

      ctx = %{
        args: args,
        retrieval: retrieval,
        rerank_profile: rerank_profile,
        store_profile: store_profile,
        as_of_ms: at
      }

      if retrieval["kind"] == "mcp_query" do
        advance(
          Adapters.start(state.resolved, :query_refs, %{
            "profile" => args["retrieval"],
            "query" => args["query"],
            "top_k" => args["top_k"],
            "as_of_ms" => at
          }),
          %{state | phase: :query_refs, ctx: ctx}
        )
      else
        advance(Store.start(args["store"], store_profile, :snapshot, %{}), %{
          state
          | phase: :query_snapshot,
            ctx: ctx
        })
      end
    else
      _ -> finish(state, refused(:invalid_query))
    end
  end

  defp index(args, state) do
    with true <- exact?(args, ~w(store embedding source_id generation action chunks)),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", args["store"]),
         {:ok, embedding} <- Profiles.lookup(state.resolved, "embedding", args["embedding"]),
         true <-
           text?(args["source_id"], 256) and is_integer(args["generation"]) and
             args["generation"] > 0,
         true <- args["action"] in ~w(next inspect abort) and is_list(args["chunks"]),
         true <- length(args["chunks"]) in 1..2 and Enum.all?(args["chunks"], &hash?/1),
         true <- args["action"] != "next" or budgeted_index?(profile, embedding, args["chunks"]) do
      case args["action"] do
        "next" ->
          open = %{
            "source_id" => args["source_id"],
            "generation" => args["generation"],
            "projection_kind" => "vectors",
            "profile" => embedding,
            "chunks" => args["chunks"]
          }

          advance(
            Store.start(args["store"], profile, :projection_open, open),
            %{state | phase: :index_open, ctx: %{args: args, store_profile: profile}}
          )

        "inspect" ->
          advance(
            Store.start(args["store"], profile, :inspect, %{"source_id" => args["source_id"]}),
            %{state | phase: :index_inspect, ctx: %{args: args}}
          )

        "abort" ->
          abort_args = %{
            "source_id" => args["source_id"],
            "generation" => args["generation"],
            "profile" => embedding,
            "chunks" => args["chunks"]
          }

          advance(
            Store.start(args["store"], profile, :projection_abort, abort_args),
            %{state | phase: :index_abort, ctx: %{args: args}}
          )
      end
    else
      _ -> finish(state, refused(:invalid_index))
    end
  end

  defp advance({:call, request, cont}, state) do
    pending =
      if String.starts_with?(Atom.to_string(state.phase), "index_embed") or
           state.phase in [:query_refs, :query_embed, :query_rerank] do
        :adapter
      else
        :store
      end

    call(request, %{state | cont: cont, pending: pending})
  end

  defp advance({:stop, :unknown_effect}, state), do: finish(state, refused(:unknown_effect))
  defp advance({:done, {:error, code, _}}, state), do: finish(state, refused(code))

  defp advance({:done, {:ok, value}}, %{phase: :source} = state),
    do:
      finish(
        state,
        output(
          if(value["status"] == "draft", do: "draft", else: "ok"),
          [],
          [],
          [],
          value,
          value["continuation"]
        )
      )

  defp advance({:done, {:ok, value}}, %{phase: phase} = state)
       when phase in [:index_inspect, :index_abort] do
    if value["generation"] == state.ctx.args["generation"] do
      finish(state, output("ok", [], [], [], value, nil))
    else
      finish(state, output("conflict", [], [], [%{"code" => "generation_changed"}], %{}, nil))
    end
  end

  defp advance({:done, {:ok, snapshot}}, %{phase: :query_snapshot} = state) do
    ctx = Map.put(state.ctx, :snapshot, snapshot)

    model_effects =
      if(ctx.retrieval["kind"] in ~w(dense hybrid), do: 1, else: 0) +
        if(is_map(ctx.rerank_profile) and ctx.rerank_profile["kind"] == "model_complete",
          do: 1,
          else: 0
        )

    read_allowance = if(ctx.retrieval["kind"] in ~w(dense hybrid), do: 8, else: 0)

    if query_plan?(snapshot["coverage"], model_effects, read_allowance),
      do: rank_query(%{state | ctx: ctx}, snapshot),
      else: finish(state, refused(:effect_budget))
  end

  defp advance({:done, {:ok, remote}}, %{phase: :query_refs} = state) do
    selected = %{
      "refs" => remote["refs"],
      "store_generation" => remote["store_generation"],
      "effects_used" => remote["effects_used"],
      "reads_used" => remote["reads_used"],
      "as_of_ms" => state.ctx.as_of_ms
    }

    advance(
      Store.start(state.ctx.args["store"], state.ctx.store_profile, :snapshot_selected, selected),
      %{state | phase: :query_selected_snapshot, ctx: Map.put(state.ctx, :remote, remote)}
    )
  end

  defp advance({:done, {:ok, snapshot}}, %{phase: :query_selected_snapshot} = state) do
    model_effects =
      if(
        is_map(state.ctx.rerank_profile) and
          state.ctx.rerank_profile["kind"] == "model_complete",
        do: 1,
        else: 0
      )

    if query_plan?(snapshot["coverage"], model_effects, 0) do
      case Evidence.rank_remote(
             snapshot["sources"],
             state.ctx.remote["refs"],
             state.ctx.args["top_k"],
             state.ctx.as_of_ms
           ) do
        {:ok, rank} ->
          rank =
            Map.update!(rank, "coverage", &Map.put(&1, "remote", state.ctx.remote["coverage"]))

          ctx = state.ctx |> Map.put(:snapshot, snapshot) |> Map.put(:rank, rank)
          maybe_rerank(%{state | ctx: ctx})

        _ ->
          finish(state, refused(:invalid_remote_selection))
      end
    else
      finish(state, refused(:effect_budget))
    end
  end

  defp advance({:done, {:ok, embedding}}, %{phase: :query_embed} = state) do
    rank_semantic(%{state | ctx: Map.put(state.ctx, :query_vector, hd(embedding["vectors"]))})
  end

  defp advance({:done, {:ok, ranked}}, %{phase: :query_rerank} = state) do
    case Evidence.apply_rerank(state.ctx.rank["evidence"], ranked["order"]) do
      {:ok, candidates} ->
        ctx = %{state.ctx | rank: Map.put(state.ctx.rank, "evidence", candidates)}
        revalidate(%{state | ctx: ctx})

      _ ->
        finish(state, refused(:invalid_model_output))
    end
  end

  defp advance({:done, {:ok, checked}}, %{phase: :query_revalidate} = state) do
    if checked["valid"] == true do
      rank =
        Evidence.query_scope(
          state.ctx.rank,
          state.ctx.snapshot["sources"],
          state.ctx.snapshot["gaps"],
          state.ctx.as_of_ms
        )

      coverage =
        Map.merge(rank["coverage"], %{
          "as_of_ms" => state.ctx.as_of_ms,
          "store" => state.ctx.snapshot["coverage"],
          "final_validation" => checked["coverage"],
          "revalidated" => true
        })

      claims =
        if rank["claims"] == [],
          do: elem(Evidence.classify(rank["evidence"], [], state.ctx.args["query"]), 1),
          else: rank["claims"]

      finish(state, output(rank["status"], rank["evidence"], claims, rank["gaps"], coverage, nil))
    else
      finish(state, output("conflict", [], [], [%{"code" => "snapshot_changed"}], %{}, nil))
    end
  end

  defp advance({:done, {:ok, opened}}, %{phase: :index_open} = state) do
    with true <- is_map(opened["draft"]) and is_list(opened["chunks"]),
         true <- length(opened["chunks"]) in 1..2,
         true <-
           index_plan?(opened["coverage"], state.ctx.store_profile, length(opened["chunks"])) do
      inputs = Enum.map(opened["chunks"], &Map.take(&1, ~w(chunk_id text)))
      ctx = Map.put(state.ctx, :opened, opened)

      advance(
        Adapters.start(state.resolved, :embed, %{
          "profile" => state.ctx.args["embedding"],
          "inputs" => inputs
        }),
        %{state | phase: :index_embed, ctx: ctx}
      )
    else
      _ -> finish(state, refused(:effect_budget))
    end
  end

  defp advance({:done, {:ok, embedded}}, %{phase: :index_embed} = state) do
    args = %{"draft" => state.ctx.opened["draft"], "vectors" => embedded["vectors"]}

    advance(
      Store.start(state.ctx.args["store"], state.ctx.store_profile, :projection_commit, args),
      %{state | phase: :index_commit}
    )
  end

  defp advance({:done, {:ok, committed}}, %{phase: :index_commit} = state),
    do: finish(state, output("ok", [], [], [], committed, nil))

  defp advance(_, state), do: finish(state, refused(:invalid_operation_state))

  defp rank_query(state, snapshot) do
    args = state.ctx.args
    profile = state.ctx.retrieval

    case profile["kind"] do
      "bm25" ->
        case Evidence.rank_lexical(
               snapshot["sources"],
               args["query"],
               args["top_k"],
               state.ctx.as_of_ms
             ) do
          {:ok, ranked} -> maybe_rerank(%{state | ctx: Map.put(state.ctx, :rank, ranked)})
          _ -> finish(state, refused(:invalid_evidence))
        end

      kind when kind in ~w(dense hybrid) ->
        embedding = profile["embedding"]

        advance(
          Adapters.start(state.resolved, :embed, %{
            "profile" => embedding,
            "inputs" => [
              %{"chunk_id" => Evidence.sha256("query:" <> args["query"]), "text" => args["query"]}
            ]
          }),
          %{state | phase: :query_embed}
        )

      "graph" ->
        seed = graph_seed(snapshot, args["query"])

        limits =
          Map.take(profile, ~w(depth max_nodes max_edges)) |> Map.put("top_k", args["top_k"])

        with {:ok, lexical_profile} <-
               Profiles.lookup(state.resolved, "retrieval", profile["lexical"]),
             true <- lexical_profile["kind"] == "bm25",
             {:ok, lexical} <-
               Evidence.rank_lexical(
                 snapshot["sources"],
                 args["query"],
                 args["top_k"],
                 state.ctx.as_of_ms
               ),
             {:ok, graph} <-
               Evidence.traverse(
                 snapshot["sources"],
                 all_facts(snapshot),
                 seed,
                 limits,
                 state.ctx.as_of_ms
               ),
             {:ok, ranked} <- fuse_ranks([{"lexical", lexical}, {"graph", graph}], args["top_k"]) do
          maybe_rerank(%{state | ctx: Map.put(state.ctx, :rank, ranked)})
        else
          _ -> finish(state, refused(:invalid_evidence))
        end

      _ ->
        finish(state, refused(:unsupported_retrieval))
    end
  end

  defp rank_semantic(state) do
    snap = state.ctx.snapshot
    args = state.ctx.args
    {candidates, missing} = dense_candidates(snap, state.ctx.as_of_ms, state.ctx.query_vector)
    policy = state.ctx.retrieval["missing_embedding"]

    dense =
      if missing == 0 or policy == "lexical_with_gap",
        do: Evidence.rank_cosine(candidates, state.ctx.query_vector, args["top_k"]),
        else: {:error, :missing_embedding}

    ranked =
      case {state.ctx.retrieval["kind"], dense} do
        {"dense", {:ok, result}} when missing == 0 ->
          {:ok, result}

        {"hybrid", {:ok, result}} ->
          with {:ok, lexical} <-
                 Evidence.rank_lexical(
                   snap["sources"],
                   args["query"],
                   args["top_k"],
                   state.ctx.as_of_ms
                 ),
               {:ok, graph} <- hybrid_graph(state),
               {:ok, fused} <-
                 fuse_ranks(
                   [{"lexical", lexical}, {"dense", result}, {"graph", graph}],
                   args["top_k"]
                 ) do
            {:ok,
             if(missing == 0,
               do: fused,
               else:
                 Map.update!(
                   fused,
                   "gaps",
                   &[%{"code" => "missing_embedding", "count" => missing} | &1]
                 )
             )}
          end

        {"hybrid", _} ->
          if state.ctx.retrieval["missing_embedding"] == "lexical_with_gap" do
            with {:ok, result} <-
                   Evidence.rank_lexical(
                     snap["sources"],
                     args["query"],
                     args["top_k"],
                     state.ctx.as_of_ms
                   ),
                 {:ok, graph} <- hybrid_graph(state),
                 {:ok, fused} <-
                   fuse_ranks([{"lexical", result}, {"graph", graph}], args["top_k"]) do
              {:ok,
               Map.update!(
                 fused,
                 "gaps",
                 &[%{"code" => "missing_embedding", "count" => missing} | &1]
               )}
            end
          else
            {:error, :missing_embedding}
          end

        _ ->
          dense
      end

    case ranked do
      {:ok, result} -> maybe_rerank(%{state | ctx: Map.put(state.ctx, :rank, result)})
      _ -> finish(state, refused(:missing_embedding))
    end
  end

  defp fuse_ranks(components, top_k) do
    ranks = Enum.map(components, &elem(&1, 1))

    with {:ok, fused} <- Evidence.fuse(Enum.map(ranks, & &1["evidence"]), top_k, 60) do
      coverage =
        Map.merge(fused["coverage"], %{
          "components" => Map.new(components, fn {name, rank} -> {name, rank["coverage"]} end),
          "complete" =>
            fused["coverage"]["complete"] === true and
              Enum.all?(ranks, &(&1["coverage"]["complete"] === true))
        })

      {:ok,
       fused
       |> Map.put("claims", Enum.flat_map(ranks, & &1["claims"]))
       |> Map.put("gaps", fused["gaps"] ++ Enum.flat_map(ranks, & &1["gaps"]))
       |> Map.put("coverage", coverage)}
    end
  end

  defp maybe_rerank(state) do
    if state.ctx.args["rerank"] == nil do
      revalidate(state)
    else
      candidates = Enum.take(state.ctx.rank["evidence"], 16)

      advance(
        Adapters.start(state.resolved, :rerank, %{
          "profile" => state.ctx.args["rerank"],
          "query" => state.ctx.args["query"],
          "candidates" => candidates
        }),
        %{state | phase: :query_rerank}
      )
    end
  end

  defp revalidate(state) do
    args = %{"tokens" => state.ctx.snapshot["tokens"]}

    args =
      if Map.has_key?(state.ctx, :remote) do
        counts = Map.take(state.ctx.snapshot["coverage"], ~w(effects_used reads_used))

        counts =
          if state.phase == :query_rerank and
               is_map(state.ctx.rerank_profile) and
               state.ctx.rerank_profile["kind"] == "model_complete",
             do: Map.update!(counts, "effects_used", &(&1 + 1)),
             else: counts

        Map.merge(args, counts)
      else
        args
      end

    advance(
      Store.start(state.ctx.args["store"], state.ctx.store_profile, :revalidate, args),
      %{state | phase: :query_revalidate}
    )
  end

  defp dense_candidates(snapshot, as_of_ms, query_vector) do
    Enum.reduce(snapshot["sources"], {[], 0}, fn source, {acc, missing} ->
      if Evidence.current?(source, as_of_ms) do
        {:ok, chunks} = Evidence.chunks(source)
        projection = Map.get(snapshot["projections"], source["source_key"], %{})
        vectors = Map.get(projection, "vectors", [])

        Enum.reduce(chunks, {acc, missing}, fn chunk, {hits, gaps} ->
          vector =
            Enum.find(vectors, fn v ->
              v["chunk_id"] == chunk["chunk_id"] and Evidence.compatible_vectors?(v, query_vector)
            end)

          if vector == nil do
            {hits, gaps + 1}
          else
            {quote, _} = Evidence.utf8_prefix(String.slice(chunk["text"], 0, 200), 1024)

            case Evidence.citation(
                   source,
                   chunk,
                   chunk["start_byte"],
                   chunk["start_byte"] + byte_size(quote)
                 ) do
              {:ok, citation} ->
                {[
                   %{
                     "citation" => citation,
                     "score" => 0.0,
                     "method" => "cosine",
                     "vector" => vector
                   }
                   | hits
                 ], gaps}

              _ ->
                {hits, gaps + 1}
            end
          end
        end)
      else
        {acc, missing}
      end
    end)
  end

  defp hybrid_graph(state) do
    case state.ctx.retrieval["graph"] do
      nil ->
        {:ok,
         %{
           "evidence" => [],
           "claims" => [],
           "gaps" => [],
           "coverage" => %{"method" => "none", "complete" => true}
         }}

      name ->
        with {:ok, profile} <- Profiles.lookup(state.resolved, "retrieval", name),
             true <- profile["kind"] == "graph",
             seed = graph_seed(state.ctx.snapshot, state.ctx.args["query"]),
             limits =
               Map.take(profile, ~w(depth max_nodes max_edges))
               |> Map.put("top_k", state.ctx.args["top_k"]),
             {:ok, result} <-
               Evidence.traverse(
                 state.ctx.snapshot["sources"],
                 all_facts(state.ctx.snapshot),
                 seed,
                 limits,
                 state.ctx.as_of_ms
               ) do
          {:ok, result}
        else
          _ -> {:error, :invalid_graph_profile}
        end
    end
  end

  defp all_facts(snapshot),
    do: Enum.flat_map(Map.values(snapshot["projections"]), &(&1["facts"] || []))

  defp graph_seed(snapshot, query) do
    subjects = Enum.map(all_facts(snapshot), & &1["subject"]) |> Enum.uniq() |> Enum.sort()
    Enum.find(subjects, &String.contains?(String.downcase(query), String.downcase(&1))) || query
  end

  defp budgeted_index?(%{"kind" => "state"}, _, chunks), do: length(chunks) <= 2
  defp budgeted_index?(%{"kind" => "mcp_cas"}, _, chunks), do: length(chunks) == 1
  defp budgeted_index?(_, _, _), do: false

  defp index_plan?(coverage, profile, count) do
    is_map(coverage) and budgeted_index?(profile, %{}, List.duplicate("", count)) and
      is_integer(coverage["total_effects"]) and coverage["total_effects"] <= 16 and
      is_integer(coverage["effects_remaining"]) and
      is_integer(coverage["model_effects"]) and
      is_integer(coverage["commit_effects_worst_case"]) and
      coverage["effects_remaining"] >=
        coverage["model_effects"] + coverage["commit_effects_worst_case"]
  end

  defp query_plan?(coverage, model_effects, read_allowance) do
    is_map(coverage) and is_integer(coverage["effects_used"]) and
      is_integer(coverage["revalidate_effects_worst_case"]) and
      coverage["effects_used"] + coverage["revalidate_effects_worst_case"] + model_effects <= 16 and
      is_integer(coverage["reads_used"]) and
      is_integer(coverage["revalidate_reads_worst_case"]) and
      coverage["reads_used"] + coverage["revalidate_reads_worst_case"] + read_allowance <= 512
  end

  defp valid_source_args?(action, args) do
    keys =
      case action do
        "put" ->
          ~w(source_id generation expected_revision title text uri observed_at_ms event_at_ms expires_at_ms)

        "open" ->
          ~w(source_id generation expected_revision title uri observed_at_ms event_at_ms expires_at_ms byte_count content_sha256)

        "append" ->
          ~w(source_id draft_id expected_revision offset text)

        "publish" ->
          ~w(source_id draft_id expected_revision)

        "abort" ->
          ~w(source_id draft_id expected_revision)

        "forget" ->
          ~w(source_id expected_revision)

        "inspect" ->
          ~w(source_id)

        "export" ->
          ~w(source_id cursor limit)

        "import" ->
          ~w(expected_revision export)

        "collect" ->
          ~w(limit)

        _ ->
          []
      end

    exact?(args, keys) or (action == "open" and exact?(args, keys ++ ["historical_import"]))
  end

  defp source_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store action args),
      "properties" => %{
        "store" => string(64),
        "action" => %{"type" => "string", "enum" => Map.keys(@source_actions)},
        "args" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => source_properties()
        }
      }
    }
  end

  defp source_properties do
    %{
      "source_id" => string(256),
      "generation" => integer(1, 1_000_000_000),
      "expected_revision" => integer(0, 1_000_000_000),
      "title" => string(128),
      "text" => string(8192),
      "uri" => string(512),
      "observed_at_ms" => integer(0, 9_000_000_000_000),
      "event_at_ms" => %{"type" => ["integer", "null"]},
      "expires_at_ms" => %{"type" => ["integer", "null"]},
      "byte_count" => integer(1, 65_536),
      "content_sha256" => string(64),
      "draft_id" => string(64),
      "offset" => integer(0, 65_536),
      "cursor" => %{"type" => ["integer", "null"]},
      "limit" => integer(1, 12),
      "export" => %{"type" => "object"},
      "historical_import" => %{"type" => "object"}
    }
  end

  defp query_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store retrieval rerank query top_k as_of_ms),
      "properties" => %{
        "store" => string(64),
        "retrieval" => string(64),
        "rerank" => %{"type" => ["string", "null"]},
        "query" => string(1024),
        "top_k" => integer(1, 10),
        "as_of_ms" => %{"type" => ["integer", "null"]}
      }
    }
  end

  defp index_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store embedding source_id generation action chunks),
      "properties" => %{
        "store" => string(64),
        "embedding" => string(64),
        "source_id" => string(256),
        "generation" => integer(1, 1_000_000_000),
        "action" => %{"type" => "string", "enum" => ~w(next inspect abort)},
        "chunks" => %{"type" => "array", "items" => string(64), "maxItems" => 2}
      }
    }
  end

  defp entry(id, description, schema),
    do: %{
      "id" => id,
      "description" => description,
      "arguments_schema" => schema,
      "result_schema" => %{"type" => "object"}
    }

  defp string(max), do: %{"type" => "string", "minLength" => 1, "maxLength" => max}
  defp integer(min, max), do: %{"type" => "integer", "minimum" => min, "maximum" => max}

  defp call(request, state),
    do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}

  defp finish(state, value) do
    {:ok, reply} =
      case Ipse.Extension.ResultPublication.prepare(value) do
        {:ok, _} = prepared ->
          prepared

        {:error, :invalid_result_document} ->
          Ipse.Extension.ResultPublication.prepare(refused(:result_too_large))
      end

    {:ok, reply, %{state | phase: :idle}}
  end

  defp output(status, evidence, claims, gaps, coverage, continuation),
    do: %{
      "version" => 1,
      "status" => status,
      "evidence" => evidence,
      "claims" => Evidence.public_claims(evidence, claims),
      "gaps" => gaps,
      "coverage" => coverage,
      "continuation" => continuation
    }

  defp refused(code), do: output("refused", [], [], [%{"code" => Atom.to_string(code)}], %{}, nil)
  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..max

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
