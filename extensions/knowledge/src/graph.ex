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
          entry("query", "Traverse current supported facts", query_schema())
        ],
        "tools" => [entry("query", "Traverse current supported facts", query_schema())]
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
      if pending == :store, do: Store.resume(cont, outcome), else: Adapters.resume(cont, outcome)

    advance(result, state)
  end

  def handle(_, _, state), do: finish(state, refused(:invalid_invocation))
  defp invoke(_, %{invalid: code} = state), do: finish(state, refused(code))
  defp invoke(%{"id" => "source", "arguments" => args}, state), do: source(args, state)
  defp invoke(%{"id" => "extract", "arguments" => args}, state), do: extract(args, state)
  defp invoke(%{"id" => "query", "arguments" => args}, state), do: query(args, state)
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
             Enum.all?(args["chunks"], &hash?/1),
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

  defp advance({:call, request, cont}, state) do
    pending = if state.phase == :extract_adapter, do: :adapter, else: :store

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

  defp advance({:done, {:ok, extracted}}, %{phase: :extract_adapter} = state) do
    args = %{"draft" => state.ctx.opened["draft"], "facts" => extracted["facts"]}

    advance(
      Store.start(state.ctx.args["store"], state.ctx.store_profile, :projection_commit, args),
      %{state | phase: :extract_commit}
    )
  end

  defp advance({:done, {:ok, committed}}, %{phase: :extract_commit} = state),
    do: finish(state, output("ok", [], [], [], committed, nil))

  defp advance({:done, {:ok, snapshot}}, %{phase: :query_snapshot} = state) do
    if not query_plan?(snapshot["coverage"]) do
      finish(state, refused(:effect_budget))
    else
      facts = Enum.flat_map(Map.values(snapshot["projections"]), &(&1["facts"] || []))
      limits = Map.take(state.ctx.args, ~w(depth max_nodes max_edges top_k))

      case Evidence.traverse(
             snapshot["sources"],
             facts,
             state.ctx.args["entity"],
             limits,
             state.ctx.as_of_ms
           ) do
        {:ok, ranked} ->
          ctx = state.ctx |> Map.put(:snapshot, snapshot) |> Map.put(:rank, ranked)

          advance(
            Store.start(state.ctx.args["store"], state.ctx.profile, :revalidate, %{
              "tokens" => snapshot["tokens"]
            }),
            %{state | phase: :query_revalidate, ctx: ctx}
          )

        {:error, :graph_context_limit} ->
          finish(state, refused(:graph_context_limit))

        _ ->
          finish(state, refused(:invalid_evidence))
      end
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
          "revalidated" => true
        })

      finish(
        state,
        output(rank["status"], rank["evidence"], rank["claims"], rank["gaps"], coverage, nil)
      )
    else
      finish(state, output("conflict", [], [], [%{"code" => "snapshot_changed"}], %{}, nil))
    end
  end

  defp advance(_, state), do: finish(state, refused(:invalid_operation_state))

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

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp num?(value, min, max), do: is_integer(value) and value in min..max

  defp plan?(coverage) do
    is_map(coverage) and is_integer(coverage["total_effects"]) and
      coverage["total_effects"] <= 16 and is_integer(coverage["effects_remaining"]) and
      is_integer(coverage["model_effects"]) and
      is_integer(coverage["commit_effects_worst_case"]) and
      coverage["effects_remaining"] >=
        coverage["model_effects"] + coverage["commit_effects_worst_case"]
  end

  defp query_plan?(coverage) do
    is_map(coverage) and is_integer(coverage["effects_used"]) and
      is_integer(coverage["revalidate_effects_worst_case"]) and
      coverage["effects_used"] + coverage["revalidate_effects_worst_case"] <= 16 and
      is_integer(coverage["reads_used"]) and
      is_integer(coverage["revalidate_reads_worst_case"]) and
      coverage["reads_used"] + coverage["revalidate_reads_worst_case"] <= 512
  end
end
