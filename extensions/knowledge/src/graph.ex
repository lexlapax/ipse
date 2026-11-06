defmodule IpseKnowledge.Graph do
  @behaviour Ipse.Extension
  alias IpseKnowledge.{Adapters, Evidence, Profiles, Store}
  @preset "state-explicit"
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
      "capabilities" => Profiles.capabilities("graph", @preset),
      "exports" => %{
        "version" => 1,
        "services" => [],
        "commands" => [
          entry("source", "Explicit graph source lifecycle", source_schema()),
          entry("extract", "Explicit attributable fact projection", extract_schema()),
          entry(
            "identity",
            "Inspect, alias, merge or undo an explicit State graph entity selection",
            identity_schema()
          ),
          entry("query", "Traverse current supported facts", query_schema())
        ],
        "tools" => [
          entry("query", "Traverse current supported facts", query_schema()),
          entry(
            "capture",
            "Capture relationships from unique exact quotes in a current State source; no extra model call",
            capture_schema()
          )
        ]
      }
    }
  end

  def init(options) do
    case Profiles.validate("graph", @preset, options) do
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
      case pending do
        :store -> Store.resume(cont, outcome)
        :state -> IpseKnowledge.Store.State.resume(cont, outcome)
        :adapter -> Adapters.resume(cont, outcome)
      end

    advance(result, state)
  end

  def handle(_, _, state), do: finish(state, refused(:invalid_invocation))
  defp invoke(_, %{invalid: code} = state), do: finish(state, refused(code))
  defp invoke(%{"id" => "source", "arguments" => args}, state), do: source(args, state)
  defp invoke(%{"id" => "extract", "arguments" => args}, state), do: extract(args, state)
  defp invoke(%{"id" => "query", "arguments" => args}, state), do: query(args, state)
  defp invoke(%{"id" => "capture", "arguments" => args}, state), do: capture(args, state)
  defp invoke(%{"id" => "identity", "arguments" => args}, state), do: identity(args, state)
  defp invoke(_, state), do: finish(state, refused(:invalid_invocation))

  defp source(%{"store" => store, "action" => action, "args" => args} = outer, state) do
    with true <- exact?(outer, ~w(store action args)),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", store),
         {:ok, op} <- Map.fetch(@source_actions, action),
         true <- source_args?(action, args) do
      advance(Store.start(store, profile, op, args), %{state | phase: :source, ctx: %{}})
    else
      _ -> finish(state, refused(:invalid_source_command))
    end
  end

  defp source(_, state), do: finish(state, refused(:invalid_source_command))

  defp extract(args, state) do
    with true <- exact?(args, ~w(store extraction source_id generation max_edges chunks facts)),
         {:ok, store_profile} <- Profiles.lookup(state.resolved, "stores", args["store"]),
         {:ok, extraction} <- Profiles.lookup(state.resolved, "extraction", args["extraction"]),
         true <-
           text?(args["source_id"], 256) and Evidence.safe_positive?(args["generation"]),
         true <- is_integer(args["max_edges"]) and args["max_edges"] in 1..32,
         true <-
           is_list(args["chunks"]) and length(args["chunks"]) in 1..2 and
             Enum.all?(args["chunks"], &Evidence.sha256?/1),
         true <- is_list(args["facts"]) and length(args["facts"]) <= args["max_edges"],
         true <-
           extraction["kind"] != "explicit" or Enum.all?(args["facts"], &Evidence.valid_fact?/1),
         true <- extraction["kind"] != "model_complete" or args["facts"] == [],
         true <- store_profile["kind"] != "mcp_cas" or length(args["chunks"]) == 1 do
      open = %{
        "source_id" => args["source_id"],
        "generation" => args["generation"],
        "projection_kind" => "facts",
        "profile" => extraction,
        "chunks" => args["chunks"],
        "max_items" => args["max_edges"]
      }

      open =
        if extraction["kind"] == "explicit", do: Map.put(open, "facts", args["facts"]), else: open

      advance(
        Store.start(args["store"], store_profile, :projection_open, open),
        %{state | phase: :extract_open, ctx: %{args: args, store_profile: store_profile}}
      )
    else
      _ -> finish(state, refused(:invalid_extraction))
    end
  end

  defp capture(args, state) do
    with true <- exact?(args, ~w(store extraction source_id generation relations)),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", args["store"]),
         true <- profile["kind"] == "state",
         {:ok, %{"kind" => "explicit"}} <-
           Profiles.lookup(state.resolved, "extraction", args["extraction"]),
         true <- text?(args["source_id"], 256) and Evidence.safe_positive?(args["generation"]),
         true <- is_list(args["relations"]) and length(args["relations"]) in 1..8,
         true <-
           Enum.all?(args["relations"], fn relation ->
             exact?(
               relation,
               ~w(subject predicate object polarity inferred valid_from_ms valid_to_ms quote)
             ) and
               text?(relation["quote"], 1024)
           end) do
      advance(Store.start(args["store"], profile, :snapshot, %{}), %{
        state
        | phase: :capture_snapshot,
          ctx: %{args: args}
      })
    else
      _ -> finish(state, refused(:invalid_capture))
    end
  end

  defp captured_facts(source, relations, extraction) do
    with {:ok, chunks} <- Evidence.chunks(source) do
      Enum.reduce_while(relations, {:ok, []}, fn relation, {:ok, facts} ->
        with {:ok, start, finish} <-
               Store.provided_quote_range(source["text"], relation["quote"]),
             chunk when is_map(chunk) <-
               Enum.find(chunks, &(start >= &1["start_byte"] and finish <= &1["end_byte"])),
             {:ok, citation} <- Evidence.citation(source, chunk, start, finish),
             {:ok, fact} <-
               Evidence.fact(
                 relation
                 |> Map.delete("quote")
                 |> Map.put("extraction", %{
                   "kind" => "explicit",
                   "profile" => extraction,
                   "version" => 1
                 })
                 |> Map.put("citations", [citation])
               ) do
          {:cont, {:ok, [fact | facts]}}
        else
          _ -> {:halt, {:error, :invalid_capture_support}}
        end
      end)
      |> case do
        {:ok, facts} -> {:ok, Enum.reverse(facts)}
        error -> error
      end
    end
  end

  defp query(args, state) do
    with true <- exact?(args, ~w(store entity depth max_nodes max_edges top_k as_of_ms)),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", args["store"]),
         true <- text?(args["entity"], 256) and num?(args["depth"], 0, 4),
         true <- num?(args["max_nodes"], 1, 128) and num?(args["max_edges"], 1, 256),
         true <- num?(args["top_k"], 1, 10),
         true <-
           args["as_of_ms"] == nil or Evidence.safe_uint?(args["as_of_ms"]) do
      at = args["as_of_ms"] || System.system_time(:millisecond)

      advance(
        Store.start(args["store"], profile, :snapshot, %{}),
        %{state | phase: :query_snapshot, ctx: %{args: args, profile: profile, as_of_ms: at}}
      )
    else
      _ -> finish(state, refused(:invalid_query))
    end
  end

  defp identity(args, state) when is_map(args) do
    fields =
      case args["action"] do
        "inspect" ->
          ~w(store action)

        "undo" ->
          ~w(store action expected_revision operation_id)

        action when action in ~w(alias merge) ->
          ~w(store action expected_revision source_id generation from to quote)

        _ ->
          []
      end

    with true <- exact?(args, fields),
         {:ok, %{"kind" => "state"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]),
         true <- args["action"] === "inspect" or Evidence.safe_uint?(args["expected_revision"]),
         true <- args["action"] !== "undo" or Evidence.sha256?(args["operation_id"]),
         true <-
           args["action"] not in ~w(alias merge) or
             (text?(args["source_id"], 256) and Evidence.safe_positive?(args["generation"]) and
                text?(args["from"], 256) and text?(args["to"], 256) and text?(args["quote"], 1024)) do
      advance(Store.start(args["store"], profile, :snapshot, %{}), %{
        state
        | phase: :identity_snapshot,
          ctx: %{args: args, profile: profile}
      })
    else
      _ -> finish(state, refused(:invalid_graph_identity))
    end
  end

  defp identity(_, state), do: finish(state, refused(:invalid_graph_identity))

  defp identity_record(snapshot, profile) do
    case snapshot["graph_identity"] do
      nil ->
        {:ok, 0,
         %{
           "format" => 1,
           "kind" => "graph_identity",
           "partition" => profile["partition"],
           "steps" => []
         }}

      %{"deleted" => false, "revision" => revision, "value" => value}
      when is_integer(revision) and revision > 0 ->
        if Evidence.valid_graph_identity?(value, profile["partition"]),
          do: {:ok, revision, value},
          else: {:error, :graph_identity_unavailable}

      _ ->
        {:error, :graph_identity_unavailable}
    end
  end

  defp identity_next(args, value, revision, snapshot) do
    with true <- args["expected_revision"] === revision do
      if args["action"] === "undo" do
        with [last | _] <- Enum.reverse(value["steps"]),
             true <- last["operation_id"] === args["operation_id"] do
          {:ok, Map.put(value, "steps", Enum.drop(value["steps"], -1)), nil, args["operation_id"]}
        else
          _ -> {:error, :graph_identity_undo_refused}
        end
      else
        facts = Enum.flat_map(Map.values(snapshot["projections"]), &(&1["facts"] || []))

        with [source] <-
               Enum.filter(
                 snapshot["sources"],
                 &(&1["source_id"] === args["source_id"] and
                     &1["generation"] === args["generation"])
               ),
             {:ok, start, stop} <- Store.provided_quote_range(source["text"], args["quote"]),
             {:ok, chunks} <- Evidence.chunks(source),
             chunk when is_map(chunk) <-
               Enum.find(chunks, &(start >= &1["start_byte"] and stop <= &1["end_byte"])),
             {:ok, citation} <- Evidence.citation(source, chunk, start, stop),
             step =
               Evidence.graph_identity_step(
                 args["action"],
                 args["from"],
                 args["to"],
                 citation,
                 revision
               ),
             next = Map.put(value, "steps", value["steps"] ++ [step]),
             {:ok, _, deadline} <-
               Evidence.graph_identity_resolution(
                 next,
                 snapshot["sources"],
                 facts,
                 System.system_time(:millisecond)
               ) do
          {:ok, next, deadline, step["operation_id"]}
        else
          _ -> {:error, :graph_identity_unavailable}
        end
      end
    else
      _ -> {:error, :graph_identity_conflict}
    end
  end

  defp advance({:call, request, cont}, state) do
    pending =
      cond do
        state.phase === :extract_adapter -> :adapter
        state.phase in [:identity_write, :query_identity_revalidate] -> :state
        true -> :store
      end

    {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request},
     %{state | cont: cont, pending: pending}}
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

  defp advance({:done, {:ok, opened}}, %{phase: :extract_open} = state) do
    with true <- is_map(opened["draft"]) and length(opened["chunks"]) in 1..2,
         true <- plan?(opened["coverage"]) do
      args = %{
        "profile" => state.ctx.args["extraction"],
        "source" => opened["source"],
        "chunks" => opened["chunks"],
        "max_edges" => state.ctx.args["max_edges"],
        "facts" => state.ctx.args["facts"]
      }

      advance(
        Adapters.start(state.resolved, :extract, args),
        %{state | phase: :extract_adapter, ctx: Map.put(state.ctx, :opened, opened)}
      )
    else
      _ -> finish(state, refused(:effect_budget))
    end
  end

  defp advance({:done, {:ok, snapshot}}, %{phase: :capture_snapshot} = state) do
    args = state.ctx.args

    with [source] <- Enum.filter(snapshot["sources"], &(&1["source_id"] == args["source_id"])),
         true <- source["generation"] == args["generation"],
         true <- Evidence.current?(source, System.system_time(:millisecond)),
         {:ok, facts} <- captured_facts(source, args["relations"], args["extraction"]),
         chunks =
           facts |> Enum.flat_map(& &1["citations"]) |> Enum.map(& &1["chunk_id"]) |> Enum.uniq(),
         true <- length(chunks) in 1..2 do
      extract(
        %{
          "store" => args["store"],
          "extraction" => args["extraction"],
          "source_id" => args["source_id"],
          "generation" => args["generation"],
          "max_edges" => length(facts),
          "chunks" => chunks,
          "facts" => facts
        },
        state
      )
    else
      _ -> finish(state, refused(:capture_source_unavailable))
    end
  end

  defp advance({:done, {:ok, extracted}}, %{phase: :extract_adapter} = state) do
    args = %{"draft" => state.ctx.opened["draft"], "facts" => extracted["facts"]}

    advance(
      Store.start(state.ctx.args["store"], state.ctx.store_profile, :projection_commit, args),
      %{state | phase: :extract_commit}
    )
  end

  defp advance({:done, {:ok, committed}}, %{phase: :extract_commit} = state),
    do: finish(state, output("ok", [], [], [], committed, nil))

  defp advance({:done, {:ok, snapshot}}, %{phase: :identity_snapshot} = state) do
    args = state.ctx.args

    with {:ok, revision, value} <- identity_record(snapshot, state.ctx.profile) do
      if args["action"] === "inspect" do
        finish(
          state,
          output(
            "ok",
            [],
            [],
            [],
            %{
              "identity_selection" => %{
                "revision" => revision,
                "steps" => value["steps"],
                "current_source_authority" => false
              }
            },
            nil
          )
        )
      else
        with {:ok, next, deadline, operation} <- identity_next(args, value, revision, snapshot),
             true <- Evidence.valid_graph_identity?(next, state.ctx.profile["partition"]) do
          request = %{
            "key" => Evidence.graph_identity_key(state.ctx.profile["partition"]),
            "expected_revision" => revision,
            "expected_generation" => snapshot["coverage"]["generation"],
            "next_root" => next,
            "write_before_ms" => deadline
          }

          advance(
            IpseKnowledge.Store.State.start(state.ctx.profile, :cas_root, request),
            %{
              state
              | phase: :identity_write,
                ctx: Map.merge(state.ctx, %{next: next, operation: operation})
            }
          )
        else
          {:error, code} -> finish(state, refused(code))
          _ -> finish(state, refused(:invalid_graph_identity))
        end
      end
    else
      _ -> finish(state, refused(:graph_identity_unavailable))
    end
  end

  defp advance({:done, {:ok, written}}, %{phase: :identity_write} = state) do
    finish(
      state,
      output(
        "ok",
        [],
        [],
        [],
        %{
          "identity_selection" => %{
            "revision" => written["record"]["revision"],
            "operation_id" => state.ctx.operation,
            "action" => state.ctx.args["action"],
            "active_steps" => length(state.ctx.next["steps"]),
            "attribution" => "explicit_ordinary_state_choice_not_verified_identity"
          }
        },
        nil
      )
    )
  end

  defp advance({:done, {:ok, snapshot}}, %{phase: :query_snapshot} = state) do
    if not query_plan?(
         snapshot["coverage"],
         if(state.ctx.profile["kind"] === "state", do: 1, else: 0)
       ) do
      finish(state, refused(:effect_budget))
    else
      facts = Enum.flat_map(Map.values(snapshot["projections"]), &(&1["facts"] || []))
      limits = Map.take(state.ctx.args, ~w(depth max_nodes max_edges top_k))

      identity =
        if state.ctx.profile["kind"] === "state",
          do: identity_record(snapshot, state.ctx.profile),
          else:
            if(snapshot["graph_identity"] === nil,
              do:
                {:ok, 0,
                 %{
                   "format" => 1,
                   "kind" => "graph_identity",
                   "partition" => state.ctx.profile["partition"],
                   "steps" => []
                 }},
              else: {:error, :graph_identity_unavailable}
            )

      resolution =
        case identity do
          {:ok, _, %{"steps" => []}} ->
            {:ok, %{}, nil}

          {:ok, _, value} ->
            Evidence.graph_identity_resolution(
              value,
              snapshot["sources"],
              facts,
              state.ctx.as_of_ms
            )

          error ->
            error
        end

      ranked =
        with {:ok, map, _} <- resolution,
             do:
               Evidence.traverse(
                 snapshot["sources"],
                 facts,
                 state.ctx.args["entity"],
                 limits,
                 state.ctx.as_of_ms,
                 map
               )

      case ranked do
        {:ok, ranked} ->
          ctx =
            state.ctx
            |> Map.put(:snapshot, snapshot)
            |> Map.put(:rank, ranked)
            |> Map.put(:identity, identity)

          advance(
            Store.start(state.ctx.args["store"], state.ctx.profile, :revalidate, %{
              "tokens" => snapshot["tokens"],
              "reads_used" => snapshot["coverage"]["reads_used"],
              "effects_used" => snapshot["coverage"]["effects_used"]
            }),
            %{state | phase: :query_revalidate, ctx: ctx}
          )

        {:error, :graph_context_limit} ->
          finish(state, refused(:graph_context_limit))

        {:error, :graph_identity_unavailable} ->
          finish(state, refused(:graph_identity_unavailable))

        _ ->
          finish(state, refused(:invalid_evidence))
      end
    end
  end

  defp advance({:done, {:ok, checked}}, %{phase: :query_revalidate} = state) do
    if checked["valid"] == true do
      if state.ctx.profile["kind"] === "state" do
        if checked["coverage"]["reads_used"] < 512 do
          advance(
            IpseKnowledge.Store.State.start(state.ctx.profile, :get_many, %{
              "keys" => [Evidence.graph_identity_key(state.ctx.profile["partition"])]
            }),
            %{
              state
              | phase: :query_identity_revalidate,
                ctx: Map.put(state.ctx, :checked, checked)
            }
          )
        else
          finish(state, refused(:effect_budget))
        end
      else
        finish_query(state)
      end
    else
      finish(state, output("conflict", [], [], [%{"code" => "snapshot_changed"}], %{}, nil))
    end
  end

  defp advance({:done, {:ok, checked}}, %{phase: :query_identity_revalidate} = state) do
    [record] = checked["records"]
    prior = state.ctx.snapshot["graph_identity"]
    {:ok, _, identity} = state.ctx.identity

    same =
      if prior === nil,
        do: record["revision"] === 0 and record["deleted"] === true and record["value"] === nil,
        else: record === prior

    generation =
      if identity["steps"] !== [],
        do: state.ctx.snapshot["coverage"]["generation"],
        else:
          state.ctx.checked["store_generation"] || state.ctx.snapshot["coverage"]["generation"]

    if same and checked["generation"] === generation,
      do: finish_query(state),
      else:
        finish(
          state,
          output("conflict", [], [], [%{"code" => "graph_identity_changed"}], %{}, nil)
        )
  end

  defp advance(_, state), do: finish(state, refused(:invalid_operation_state))

  defp finish_query(state) do
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
        "store" =>
          if(state.ctx.profile["kind"] === "state",
            do:
              Map.merge(
                state.ctx.snapshot["coverage"],
                Map.update!(state.ctx.checked["coverage"], "reads_used", &(&1 + 1))
              ),
            else: state.ctx.snapshot["coverage"]
          ),
        "revalidated" => true
      })

    {:ok, revision, identity} = state.ctx.identity

    coverage =
      if identity["steps"] === [],
        do: coverage,
        else:
          Map.put(coverage, "identity_selection", %{
            "revision" => revision,
            "steps" => identity["steps"],
            "attribution" => "explicit_ordinary_state_choice_not_verified_identity"
          })

    finish(
      state,
      output(rank["status"], rank["evidence"], rank["claims"], rank["gaps"], coverage, nil)
    )
  end

  defp source_args?(action, args) do
    fields =
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

    exact?(args, fields) or (action == "open" and exact?(args, fields ++ ["historical_import"]))
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
      "event_at_ms" => %{
        "type" => ["integer", "null"],
        "minimum" => 0,
        "maximum" => Evidence.safe_integer_max()
      },
      "expires_at_ms" => %{
        "type" => ["integer", "null"],
        "minimum" => 0,
        "maximum" => Evidence.safe_integer_max()
      },
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

  defp extract_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store extraction source_id generation max_edges chunks facts),
      "properties" => %{
        "store" => string(64),
        "extraction" => string(64),
        "source_id" => string(256),
        "generation" => integer(1, 1_000_000_000),
        "max_edges" => integer(1, 32),
        "chunks" => %{"type" => "array", "items" => string(64), "minItems" => 1, "maxItems" => 2},
        "facts" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" =>
              Map.new(~w(valid_from_ms valid_to_ms), fn field ->
                {field,
                 %{
                   "type" => ["integer", "null"],
                   "minimum" => 0,
                   "maximum" => Evidence.safe_integer_max()
                 }}
              end)
          },
          "maxItems" => 32
        }
      }
    }
  end

  defp capture_schema do
    relation = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" =>
        ~w(subject predicate object polarity inferred valid_from_ms valid_to_ms quote),
      "properties" => %{
        "subject" => string(256),
        "predicate" => string(128),
        "object" => string(256),
        "polarity" => %{"type" => "string", "enum" => ~w(positive negative)},
        "inferred" => %{"type" => "boolean"},
        "quote" => string(1024),
        "valid_from_ms" => nullable_time(),
        "valid_to_ms" => nullable_time()
      }
    }

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store extraction source_id generation relations),
      "properties" => %{
        "store" => string(64),
        "extraction" => string(64),
        "source_id" => string(256),
        "generation" => integer(1, 1_000_000_000),
        "relations" => %{"type" => "array", "minItems" => 1, "maxItems" => 8, "items" => relation}
      }
    }
  end

  defp nullable_time,
    do: %{"type" => ["integer", "null"], "minimum" => 0, "maximum" => Evidence.safe_integer_max()}

  defp query_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store entity depth max_nodes max_edges top_k as_of_ms),
      "properties" => %{
        "store" => string(64),
        "entity" => string(256),
        "depth" => integer(0, 4),
        "max_nodes" => integer(1, 128),
        "max_edges" => integer(1, 256),
        "top_k" => integer(1, 10),
        "as_of_ms" => %{
          "type" => ["integer", "null"],
          "minimum" => 0,
          "maximum" => Evidence.safe_integer_max()
        }
      }
    }
  end

  defp identity_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store action),
      "properties" => %{
        "store" => string(64),
        "action" => %{"type" => "string", "enum" => ~w(inspect alias merge undo)},
        "expected_revision" => integer(0, Evidence.safe_integer_max()),
        "operation_id" => string(64),
        "source_id" => string(256),
        "generation" => integer(1, Evidence.safe_integer_max()),
        "from" => string(256),
        "to" => string(256),
        "quote" => string(1024)
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

  defp num?(value, min, max), do: is_integer(value) and value in min..max

  defp plan?(coverage) do
    is_map(coverage) and is_integer(coverage["total_effects"]) and
      coverage["total_effects"] <= 16 and is_integer(coverage["effects_remaining"]) and
      is_integer(coverage["model_effects"]) and
      is_integer(coverage["commit_effects_worst_case"]) and
      coverage["effects_remaining"] >=
        coverage["model_effects"] + coverage["commit_effects_worst_case"]
  end

  defp query_plan?(coverage, extra_reads) do
    is_map(coverage) and is_integer(coverage["effects_used"]) and
      is_integer(coverage["revalidate_effects_worst_case"]) and
      coverage["effects_used"] + coverage["revalidate_effects_worst_case"] <= 16 and
      is_integer(coverage["reads_used"]) and
      is_integer(coverage["revalidate_reads_worst_case"]) and
      coverage["reads_used"] + coverage["revalidate_reads_worst_case"] + extra_reads <= 512
  end
end
