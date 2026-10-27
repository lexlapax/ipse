defmodule IpseKnowledge.Knowledge do
  @behaviour Ipse.Extension
  alias IpseKnowledge.Profiles
  alias IpseKnowledge.Knowledge.Records
  @preset "native"

  def describe do
    capture =
      entry(
        "capture",
        "Save one exact attributed observation or queue a proposal; permission is checked by the host",
        capture_schema()
      )

    %{
      "sdk" => 2,
      "capabilities" => Profiles.capabilities("knowledge", @preset),
      "exports" => %{
        "version" => 1,
        "services" => [],
        "commands" => [capture],
        "tools" => [capture]
      }
    }
  end

  def init(options) do
    case Profiles.validate("knowledge", @preset, options) do
      {:ok, _} -> {:ok, %{phase: :idle, ctx: nil}}
      {:error, code} -> {:ok, %{phase: :idle, ctx: nil, invalid: code}}
    end
  end

  def handle(stage, payload, %{phase: :idle} = state)
      when stage in ["invoke.tool", "invoke.command"],
      do: invoke(payload, state)

  def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => value}}, state),
    do: advance(state.phase, value, state)

  def handle("host.actions", %{"outcome" => outcome}, state),
    do:
      finish(state, %{
        "status" => "interrupted",
        "outcome" => outcome,
        "retry" => "inspect the operation; do not replay an unknown effect"
      })

  def handle(_, _, state), do: refused(state, :invalid_invocation)

  defp invoke(_, %{invalid: code} = state), do: refused(state, code)

  defp invoke(%{"id" => "capture", "arguments" => args}, state) do
    with true <- exact?(args, ~w(text category reason event_at_ms source)),
         true <- exact?(args["source"], ~w(handle quote)),
         true <- text?(args["source"]["handle"], 2048) and text?(args["source"]["quote"], 1024),
         true <- text?(args["text"], 2048) and text?(args["reason"], 256),
         true <- args["category"] in ~w(ordinary preference current),
         true <- is_nil(args["event_at_ms"]) or uint?(args["event_at_ms"]),
         true <- byte_size(IO.iodata_to_binary(JSON.encode!(args))) <= 6144 do
      ctx = %{args: args, now: System.system_time(:millisecond)}

      call(%{"op" => "source.read", "handle" => args["source"]["handle"]}, %{
        state
        | phase: :source,
          ctx: ctx
      })
    else
      _ -> refused(state, :invalid_capture)
    end
  rescue
    _ -> refused(state, :invalid_capture)
  end

  defp invoke(_, state), do: refused(state, :invalid_invocation)

  defp advance(:source, page, state) do
    call(
      %{
        "op" => "source.quote",
        "handle" => page["handle"],
        "quote" => state.ctx.args["source"]["quote"]
      },
      %{state | phase: :quote, ctx: Map.put(state.ctx, :page, page)}
    )
  end

  defp advance(:quote, quote, state) do
    with {:ok, proof} <-
           Ipse.Extension.source_proof(state.ctx.page, quote, state.ctx.args["source"]["quote"]),
         true <- Records.proof?(proof) do
      ctx = Map.merge(state.ctx, %{proof: proof, lineage: Records.lineage(proof)})

      collection(%{"op" => "get", "key" => "override." <> ctx.lineage}, %{
        state
        | phase: :override,
          ctx: ctx
      })
    else
      _ -> refused(state, :source_refused)
    end
  end

  defp advance(:override, %{"record" => record}, state) do
    stored = if is_nil(record), do: nil, else: record["value"]

    with {:ok, override} <- Records.saved_override(stored, state.ctx.lineage) do
      args = Map.drop(state.ctx.args, ["source"])

      case Records.capture(args, state.ctx.proof, state.ctx.now, override) do
        {:ok, key, value} ->
          collection(%{"op" => "get", "key" => key}, %{
            state
            | phase: :existing,
              ctx: Map.merge(state.ctx, %{key: key, value: value})
          })

        {:suppressed, _} ->
          finish(state, %{"status" => "suppressed", "lineage" => state.ctx.lineage})

        {:skipped, :expired_lineage} ->
          finish(state, %{"status" => "expired", "lineage" => state.ctx.lineage})

        {:error, code} ->
          refused(state, code)
      end
    else
      _ -> refused(state, :invalid_saved_override)
    end
  end

  defp advance(:existing, %{"record" => record} = snapshot, state) do
    cond do
      not is_nil(record) ->
        finish(state, %{
          "status" => "existing",
          "key" => state.ctx.key,
          "revision" => record["revision"],
          "renewed" => false
        })

      String.starts_with?(state.ctx.key, "pending.") ->
        collection(
          %{
            "op" => "scan",
            "after" => "pending.",
            "generation" => snapshot["generation"],
            "limit" => 4
          },
          %{
            state
            | phase: :pending_capacity,
              ctx:
                Map.merge(state.ctx, %{
                  generation: snapshot["generation"],
                  pending_count: 0,
                  pending_bytes: 0
                })
          }
        )

      true ->
        commit(snapshot["generation"], state)
    end
  end

  defp advance(:pending_capacity, %{"records" => records, "next" => next}, state) do
    pending = Enum.take_while(records, &String.starts_with?(&1["key"], "pending."))

    ctx = %{
      state.ctx
      | pending_count: state.ctx.pending_count + length(pending),
        pending_bytes:
          state.ctx.pending_bytes +
            Enum.reduce(pending, 0, fn row, n ->
              n + byte_size(IO.iodata_to_binary(JSON.encode!(row["value"])))
            end)
    }

    state = %{state | ctx: ctx}

    cond do
      ctx.pending_count >= 64 or
          ctx.pending_bytes + byte_size(IO.iodata_to_binary(JSON.encode!(ctx.value))) > 262_144 ->
        refused(state, :proposal_capacity)

      length(pending) < length(records) or is_nil(next) ->
        commit(ctx.generation, state)

      true ->
        collection(
          %{"op" => "scan", "after" => next, "generation" => ctx.generation, "limit" => 4},
          state
        )
    end
  end

  defp advance(:commit, value, state),
    do:
      finish(state, %{
        "status" => "saved",
        "key" => state.ctx.key,
        "category" => state.ctx.value["category"] || "pending",
        "receipt" => value
      })

  defp advance(_, _, state), do: refused(state, :invalid_host_response)

  defp commit(generation, state) do
    request = %{
      "op" => "collection.call",
      "request" => %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => false,
        "changes" => [
          %{"key" => state.ctx.key, "expected_revision" => 0, "value" => state.ctx.value}
        ]
      },
      "proofs" => [
        %{"handle" => state.ctx.page["handle"], "quote" => state.ctx.args["source"]["quote"]}
      ]
    }

    if byte_size(IO.iodata_to_binary(JSON.encode!(request))) <= 8192,
      do: call(request, %{state | phase: :commit}),
      else: refused(state, :capture_capacity)
  end

  defp collection(request, state),
    do: call(%{"op" => "collection.call", "request" => request}, state)

  defp call(request, state),
    do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}

  defp refused(state, code),
    do: finish(state, %{"status" => "refused", "code" => Atom.to_string(code)})

  defp finish(state, value) do
    {:ok, reply} = Ipse.Extension.ResultPublication.prepare(value)
    {:ok, reply, %{state | phase: :idle, ctx: nil}}
  end

  defp entry(id, description, schema),
    do: %{
      "id" => id,
      "description" => description,
      "arguments_schema" => schema,
      "result_schema" => %{"type" => "object"}
    }

  defp capture_schema do
    object(%{
      "text" => string(2048),
      "category" => %{"type" => "string", "enum" => ~w(ordinary preference current)},
      "reason" => string(256),
      "event_at_ms" => %{
        "type" => ["integer", "null"],
        "minimum" => 0,
        "maximum" => 9_007_199_254_740_991
      },
      "source" => object(%{"handle" => string(2048), "quote" => string(1024)})
    })
  end

  defp object(properties),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => Enum.sort(Map.keys(properties)),
      "properties" => properties
    }

  defp string(max), do: %{"type" => "string", "minLength" => 1, "maxLength" => max}
  defp exact?(v, keys), do: is_map(v) and Enum.sort(Map.keys(v)) == Enum.sort(keys)
  defp text?(v, max), do: is_binary(v) and String.valid?(v) and byte_size(v) in 1..max
  defp uint?(v), do: is_integer(v) and v in 0..9_007_199_254_740_991
end
