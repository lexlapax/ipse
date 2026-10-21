defmodule IpseKnowledge.Research do
  @behaviour Ipse.Extension
  alias IpseKnowledge.{Adapters, Evidence, Profiles}
  @preset "offline"
  @max_sources 10

  def describe do
    %{
      "sdk" => 2,
      "capabilities" => Profiles.capabilities("research", @preset),
      "exports" => %{
        "version" => 1,
        "services" => [],
        "commands" => [
          entry("investigate", "Explicit bounded source investigation", investigate_schema()),
          entry("ledger", "Inspect or assert a provided claim ledger", ledger_schema())
        ],
        "tools" => [
          entry("investigate", "Explicit bounded source investigation", investigate_schema())
        ]
      }
    }
  end

  def init(options) do
    case Profiles.validate("research", @preset, options) do
      {:ok, resolved} -> {:ok, %{resolved: resolved, phase: :idle, ctx: nil, cont: nil}}
      {:error, code} -> {:ok, %{invalid: code, phase: :idle, ctx: nil, cont: nil}}
    end
  end

  def handle("invoke.command", payload, state), do: invoke(payload, state)
  def handle("invoke.tool", payload, state), do: invoke(payload, state)

  def handle("host.actions", %{"outcome" => outcome}, %{phase: phase, cont: cont} = state)
      when phase != :idle do
    advance(Adapters.resume(cont, outcome), state)
  end

  def handle(_, _, state), do: finish(state, refused(:invalid_invocation))
  defp invoke(_, %{invalid: code} = state), do: finish(state, refused(code))
  defp invoke(%{"id" => "investigate", "arguments" => args}, state), do: investigate(args, state)
  defp invoke(%{"id" => "ledger", "arguments" => args}, state), do: ledger(args, state)
  defp invoke(_, state), do: finish(state, refused(:invalid_invocation))

  defp investigate(args, state) do
    with true <-
           exact?(
             Map.delete(args, "as_of_ms"),
             ~w(search fetch retrieval rerank query limits sources)
           ),
         true <-
           not Map.has_key?(args, "as_of_ms") or Evidence.safe_uint?(args["as_of_ms"]),
         {:ok, search_profile} <- Profiles.lookup(state.resolved, "search", args["search"]),
         {:ok, fetch_profile} <- Profiles.lookup(state.resolved, "fetch", args["fetch"]),
         {:ok, retrieval} <- Profiles.lookup(state.resolved, "retrieval", args["retrieval"]),
         {:ok, _} <- Profiles.lookup(state.resolved, "rerank", args["rerank"]),
         true <- text?(args["query"], 1024) and limits?(args["limits"]),
         true <- is_list(args["sources"]) and length(args["sources"]) <= @max_sources,
         true <- search_profile["kind"] == fetch_profile["kind"],
         true <- search_profile["kind"] == "provided" or args["sources"] == [],
         true <- retrieval["kind"] == "bm25" do
      at = System.system_time(:millisecond)

      base = %{
        args: args,
        at: at,
        profile: search_profile,
        fetch_profile: fetch_profile,
        sources: [],
        receipts: [],
        hits: [],
        remaining: [],
        bytes: 0,
        started: System.monotonic_time(:millisecond)
      }

      case search_profile["kind"] do
        "provided" ->
          with true <- length(args["sources"]) <= args["limits"]["max_sources"],
               true <- Enum.all?(args["sources"], &provided_source?/1),
               true <-
                 Enum.sum(Enum.map(args["sources"], &byte_size(&1["text"]))) <=
                   args["limits"]["max_body_bytes"],
               {:ok, sources} <- build_provided(args["sources"]) do
            bytes = Enum.sum(Enum.map(sources, &byte_size(&1["text"])))
            rank(%{state | phase: :rank, ctx: %{base | sources: sources, bytes: bytes}})
          else
            _ -> finish(state, refused(:invalid_provided_sources))
          end

        "mcp" ->
          advance(
            Adapters.start(state.resolved, :search, %{
              "profile" => args["search"],
              "query" => args["query"],
              "limit" => args["limits"]["max_sources"],
              "timeout_ms" => args["limits"]["timeout_ms"]
            }),
            %{state | phase: :search, ctx: base}
          )

        _ ->
          finish(state, refused(:unsupported_search))
      end
    else
      _ -> finish(state, refused(:invalid_investigation))
    end
  end

  defp ledger(%{"action" => action, "args" => args} = outer, state) do
    with true <- exact?(outer, ~w(action args)),
         true <- action in ~w(inspect assert export),
         true <- is_map(args) and is_list(args["ledger"]) and length(args["ledger"]) <= 32,
         true <- Enum.all?(args["ledger"], &ledger_entry?/1),
         true <-
           (action != "assert" and exact?(args, ["ledger"])) or
             (action == "assert" and exact?(args, ~w(ledger claims)) and is_list(args["claims"]) and
                length(args["claims"]) <= 8 and Enum.all?(args["claims"], &claim_input?/1)),
         true <- byte_size(JSON.encode!(args)) <= 12_000 do
      rows =
        Enum.map(args["ledger"], &provided_row/1) ++
          if(action == "assert", do: supplied_claims(args["claims"]), else: [])

      if length(rows) <= 32 do
        result =
          output(
            "ok",
            [],
            rows,
            [],
            %{
              "kind" => "provided_ledger",
              "durable" => false,
              "native_receipt" => false,
              "action" => action
            },
            nil
          )

        finish(state, result)
      else
        finish(state, refused(:ledger_limit))
      end
    else
      _ -> finish(state, refused(:invalid_ledger))
    end
  end

  defp ledger(_, state), do: finish(state, refused(:invalid_ledger))

  defp supplied_claims(claims) do
    Enum.map(claims, fn claim ->
      %{
        "label" => "open",
        "claim" => claim["claim"],
        "basis" => claim["basis"],
        "origin" => "provided",
        "native_receipt" => false
      }
    end)
  end

  defp provided_row(row),
    do: %{
      "label" => "open",
      "provided_label" => row["label"],
      "claim" => row["claim"],
      "basis" => row["basis"],
      "origin" => "provided",
      "native_receipt" => false
    }

  defp provided_source?(source),
    do:
      exact?(
        source,
        ~w(source_id generation title text uri observed_at_ms event_at_ms expires_at_ms)
      ) and
        text?(source["source_id"], 256) and text?(source["title"], 128) and
        text?(source["text"], 65_536) and text?(source["uri"], 512) and
        Evidence.safe_positive?(source["generation"]) and
        Evidence.safe_uint?(source["observed_at_ms"]) and
        Enum.all?(~w(event_at_ms expires_at_ms), fn k ->
          source[k] == nil or
            Evidence.safe_uint?(source[k])
        end)

  defp build_provided(sources) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, acc} ->
      attrs =
        source
        |> Map.put("partition", "research-provided")
        |> Map.put("origin", %{
          "kind" => "provided",
          "store_profile" => nil,
          "partition_or_scope" => nil,
          "receipt" => nil,
          "historical" => false
        })

      case Evidence.source(attrs) do
        {:ok, built} -> {:cont, {:ok, [built | acc]}}
        _ -> {:halt, {:error, :invalid_provided_sources}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp advance({:call, request, cont}, state),
    do:
      {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request},
       %{state | cont: cont}}

  defp advance({:stop, :unknown_effect}, state), do: finish(state, refused(:unknown_effect))
  defp advance({:done, {:error, code, _}}, state), do: finish(state, refused(code))

  defp advance({:done, {:ok, found}}, %{phase: :search} = state) do
    hits = found["hits"]

    if is_list(hits) and length(hits) <= state.ctx.args["limits"]["max_sources"] do
      ctx = %{state.ctx | hits: hits, remaining: hits, receipts: [found["receipt"]]}
      next_fetch(%{state | ctx: ctx})
    else
      finish(state, refused(:invalid_remote_result))
    end
  end

  defp advance({:done, {:ok, fetched}}, %{phase: :fetch} = state) do
    hit = hd(state.ctx.remaining)
    source_input = fetched["source"]

    attrs = %{
      "source_id" => hit["source_id"],
      "partition" => "research-provided",
      "generation" => 1,
      "title" => hit["title"],
      "text" => source_input["text"],
      "uri" => source_input["observed_uri"],
      "observed_at_ms" => source_input["observed_at_ms"],
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "origin" => %{
        "kind" => "fetch",
        "store_profile" => state.ctx.args["fetch"],
        "partition_or_scope" => nil,
        "receipt" => %{
          "descriptor" => fetched["receipt"],
          "requested_uri" => hit["uri"],
          "observed_uri" => source_input["observed_uri"],
          "body_sha256" => source_input["body_sha256"],
          "media_type" => source_input["media_type"],
          "coordinates" => "captured_text",
          "coverage" => fetched["coverage"]
        },
        "historical" => false
      }
    }

    with true <- source_input["requested_uri"] == hit["uri"],
         true <-
           state.ctx.bytes + byte_size(source_input["text"]) <=
             state.ctx.args["limits"]["max_body_bytes"],
         {:ok, source} <- Evidence.source(attrs) do
      ctx = %{
        state.ctx
        | remaining: tl(state.ctx.remaining),
          sources: state.ctx.sources ++ [source],
          bytes: state.ctx.bytes + byte_size(source_input["text"]),
          receipts: state.ctx.receipts ++ [fetched["receipt"]]
      }

      next_fetch(%{state | ctx: ctx})
    else
      _ -> finish(state, refused(:invalid_fetch_source))
    end
  end

  defp advance({:done, {:ok, reranked}}, %{phase: :rerank} = state) do
    case Evidence.apply_rerank(state.ctx.ranked["evidence"], reranked["order"]) do
      {:ok, candidates} ->
        ctx = %{state.ctx | ranked: Map.put(state.ctx.ranked, "evidence", candidates)}
        publish(%{state | ctx: ctx})

      _ ->
        finish(state, refused(:invalid_model_output))
    end
  end

  defp advance(_, state), do: finish(state, refused(:invalid_operation_state))

  defp next_fetch(%{ctx: %{remaining: []}} = state), do: rank(state)

  defp next_fetch(state) do
    remaining = remaining_ms(state.ctx)

    cond do
      remaining < 1000 ->
        finish(state, refused(:time_limit))

      true ->
        hit = hd(state.ctx.remaining)

        advance(
          Adapters.start(state.resolved, :fetch, %{
            "profile" => state.ctx.args["fetch"],
            "uri" => hit["uri"],
            "timeout_ms" => remaining
          }),
          %{state | phase: :fetch}
        )
    end
  end

  defp rank(state) do
    state = %{
      state
      | ctx: %{
          state.ctx
          | at: Map.get(state.ctx.args, "as_of_ms", System.system_time(:millisecond))
        }
    }

    case Evidence.rank_lexical(state.ctx.sources, state.ctx.args["query"], 10, state.ctx.at) do
      {:ok, ranked} ->
        ctx = Map.put(state.ctx, :ranked, ranked)

        if state.ctx.args["rerank"] == nil do
          publish(%{state | ctx: ctx})
        else
          remaining = remaining_ms(ctx)

          if remaining < 1000 do
            finish(state, refused(:time_limit))
          else
            advance(
              Adapters.start(state.resolved, :rerank, %{
                "profile" => state.ctx.args["rerank"],
                "query" => state.ctx.args["query"],
                "candidates" => Enum.take(ranked["evidence"], 16),
                "timeout_ms" => remaining
              }),
              %{state | phase: :rerank, ctx: ctx}
            )
          end
        end

      _ ->
        finish(state, refused(:invalid_evidence))
    end
  end

  defp publish(state) do
    ranked = state.ctx.ranked

    coverage =
      Map.merge(ranked["coverage"], %{
        "as_of_ms" => state.ctx.at,
        "source_count" => length(state.ctx.sources),
        "bytes" => state.ctx.bytes,
        "kind" => state.ctx.profile["kind"],
        "native_ledger" => false
      })

    status = if ranked["evidence"] == [], do: "abstain", else: "ok"

    claims =
      if ranked["claims"] == [],
        do: elem(Evidence.classify(ranked["evidence"], [], state.ctx.args["query"]), 1),
        else: ranked["claims"]

    finish(
      state,
      output(status, ranked["evidence"], claims, ranked["gaps"], coverage, nil)
    )
  end

  defp investigate_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(search fetch retrieval rerank query limits sources),
      "properties" => %{
        "search" => string(64),
        "fetch" => string(64),
        "retrieval" => string(64),
        "rerank" => %{"type" => ["string", "null"]},
        "query" => string(1024),
        "as_of_ms" => integer(0, Evidence.safe_integer_max()),
        "limits" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ~w(max_sources max_body_bytes timeout_ms),
          "properties" => %{
            "max_sources" => integer(1, @max_sources),
            "max_body_bytes" => integer(1, 49_152),
            "timeout_ms" => integer(1000, 30_000)
          }
        },
        "sources" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "generation" => integer(1, Evidence.safe_integer_max()),
              "observed_at_ms" => integer(0, Evidence.safe_integer_max()),
              "event_at_ms" =>
                Map.put(integer(0, Evidence.safe_integer_max()), "type", ["integer", "null"]),
              "expires_at_ms" =>
                Map.put(integer(0, Evidence.safe_integer_max()), "type", ["integer", "null"])
            }
          },
          "maxItems" => @max_sources
        }
      }
    }
  end

  defp ledger_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(action args),
      "properties" => %{
        "action" => %{"type" => "string", "enum" => ~w(inspect assert export)},
        "args" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["ledger"],
          "properties" => %{
            "ledger" => %{"type" => "array", "items" => %{"type" => "object"}, "maxItems" => 32},
            "claims" => %{"type" => "array", "items" => %{"type" => "object"}, "maxItems" => 8}
          }
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

  defp limits?(limits),
    do:
      exact?(limits, ~w(max_sources max_body_bytes timeout_ms)) and
        num?(limits["max_sources"], 1, @max_sources) and num?(limits["max_body_bytes"], 1, 49_152) and
        num?(limits["timeout_ms"], 1000, 30_000)

  defp remaining_ms(ctx),
    do:
      max(
        0,
        ctx.args["limits"]["timeout_ms"] -
          (System.monotonic_time(:millisecond) - ctx.started)
      )

  defp ledger_entry?(entry),
    do:
      exact?(entry, ~w(claim basis label)) and
        text?(entry["claim"], 1024) and entry["label"] in ~w(supported inference conflict open) and
        basis?(entry["basis"])

  defp claim_input?(entry),
    do:
      exact?(entry, ~w(claim basis)) and
        text?(entry["claim"], 1024) and basis?(entry["basis"])

  defp basis?(basis),
    do:
      is_list(basis) and length(basis) <= 8 and
        Enum.all?(basis, &text?(&1, 1024))

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
end
