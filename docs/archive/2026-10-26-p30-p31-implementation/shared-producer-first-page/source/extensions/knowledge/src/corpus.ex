defmodule IpseKnowledge.Corpus do
  @behaviour Ipse.Extension
  alias IpseKnowledge.{Adapters, Documents, Evidence, Profiles, Store}
  alias IpseKnowledge.Store.Collection, as: CollectionStore
  @preset "state-lexical"
  @source_actions %{
    "put" => :put,
    "put_document" => :put,
    "read_document" => :put,
    "continue_document" => :append,
    "continue_collection_document" => :append,
    "continue_collection_source" => :put,
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
        "commands" =>
          [
            entry("source", "Explicit source lifecycle", source_schema()),
            entry("query", "Read current cited evidence", query_schema()),
            entry("index", "Explicit embedding projection", index_schema())
          ] ++ collection_entries(),
        "tools" =>
          [entry("query", "Read current cited evidence", query_schema())] ++ collection_entries()
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

  def handle("host.actions", payload, %{phase: phase} = state)
      when phase in [:document_read, :document_check], do: document_read(payload, state)

  def handle(
        "host.actions",
        %{"outcome" => outcome},
        %{phase: phase, pending: pending, cont: cont} = state
      )
      when phase != :idle do
    result =
      case pending do
        :store -> Store.resume(cont, outcome)
        :collection -> CollectionStore.resume(cont, outcome)
        :producer -> IpseKnowledge.Store.Collection.Producer.resume(cont, outcome)
        _ -> Adapters.resume(cont, outcome)
      end

    advance(result, state)
  end

  def handle(_, _, state), do: finish(state, refused(:invalid_invocation))

  defp invoke(_payload, %{invalid: code} = state), do: finish(state, refused(code))
  defp invoke(%{"id" => "source", "arguments" => args}, state), do: source(args, state)
  defp invoke(%{"id" => "query", "arguments" => args}, state), do: query(args, state)

  defp invoke(%{"id" => "query_selected", "arguments" => args}, state),
    do: collection_query(args, state)

  defp invoke(%{"id" => "lexical_index", "arguments" => args}, state),
    do: collection_index(args, state)

  defp invoke(%{"id" => "projection_selected", "arguments" => args}, state),
    do: collection_projection(args, state)

  defp invoke(%{"id" => "generation_job", "arguments" => args}, state),
    do: collection_job(args, state)

  defp invoke(%{"id" => "generation_produce", "arguments" => args}, state),
    do: collection_produce(args, state)

  defp invoke(%{"id" => "index", "arguments" => args}, state), do: index(args, state)
  defp invoke(_, state), do: finish(state, refused(:invalid_invocation))

  defp source(%{"store" => store, "action" => action, "args" => source_args} = outer, state) do
    with true <- exact?(outer, ~w(store action args)),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", store),
         {:ok, operation} <- Map.fetch(@source_actions, action),
         true <- valid_source_args?(action, source_args),
         true <-
           action not in ~w(continue_collection_document continue_collection_source) or
             profile["kind"] == "collection",
         true <- profile["kind"] != "collection" or action != "continue_document" do
      cond do
        action in ~w(read_document continue_document continue_collection_document) ->
          acquire_document(store, profile, source_args, action, state)

        action == "continue_collection_source" ->
          input_action = source_args["input_action"]
          input_args = source_args["input_args"]

          if input_action in ~w(put put_document) and valid_source_args?(input_action, input_args),
            do:
              collection_provided(
                state,
                store,
                profile,
                input_action,
                input_args,
                source_args["collection_state"]
              ),
            else: finish(state, refused(:invalid_collection_continuation))

        profile["kind"] == "collection" ->
          if action in ~w(put put_document),
            do: collection_provided(state, store, profile, action, source_args, nil),
            else: finish(state, refused(:collection_lifecycle_unavailable))

        true ->
          case document_args(action, source_args) do
            {:ok, source_args} ->
              advance(Store.start(store, profile, operation, source_args), %{
                state
                | phase: :source,
                  ctx: %{store: store}
              })

            {:error, code} ->
              finish(state, refused(code))
          end
      end
    else
      _ -> finish(state, refused(:invalid_source_command))
    end
  end

  defp source(_, state), do: finish(state, refused(:invalid_source_command))

  defp document_args(action, args), do: document_args(action, args, 1)

  defp document_args("put_document", args, chunking) do
    with true <- text?(args["bytes_base64"], 8192) and text?(args["filename"], 256),
         {:ok, bytes} <- Base.decode64(args["bytes_base64"]),
         {:ok, document} <- Documents.extract(bytes, args["filename"]),
         {:ok, payload} <-
           Documents.source_payload(document, if(chunking == 2, do: 65_536, else: 8192), chunking) do
      {:ok, Map.merge(Map.drop(args, ~w(filename bytes_base64)), payload)}
    else
      {:error, code} when is_atom(code) -> {:error, code}
      _ -> {:error, :document_source_refused}
    end
  end

  defp document_args(_, args, _), do: {:ok, args}

  defp acquire_document(store, profile, args, action, state) do
    with true <-
           state.resolved["preset"] in ~w(state-documents mcp-documents collection-documents collection-dense),
         true <-
           workspace_path?(args["path"]) and
             String.downcase(Path.extname(args["path"])) == ".docx",
         true <-
           Evidence.sha256?(args["expected_sha256"]) or
             (action == "read_document" and is_nil(args["expected_sha256"]) and
                args["expected_revision"] == 0 and
                args["generation"] == 1) do
      call(document_request(args["path"], args["expected_sha256"]), %{
        state
        | phase: :document_read,
          ctx: %{
            store: store,
            profile: profile,
            args: args,
            action: action,
            pieces: [],
            offset: 0,
            sha256: args["expected_sha256"],
            total: nil,
            effects_used: 1
          }
      })
    else
      _ -> finish(state, refused(:document_acquisition_refused))
    end
  end

  defp document_request(path, expected, offset \\ 0) do
    arguments = %{
      "path" => path,
      "encoding" => "base64",
      "max_bytes" => 4096,
      "byte_offset" => offset,
      "file_max_bytes" => 32768
    }

    arguments = if expected, do: Map.put(arguments, "expected_sha256", expected), else: arguments
    %{"op" => "tool.call", "name" => "read", "timeout_ms" => 5000, "arguments" => arguments}
  end

  defp document_read(
         %{
           "outcome" => %{"status" => "ok", "value" => %{"text" => text}},
           "operation_id" => operation
         },
         state
       ) do
    with true <- is_binary(operation) and Regex.match?(~r/\A[0-9a-f]{32}\z/, operation),
         true <- text?(text, 8192),
         value when is_map(value) <- JSON.decode!(text),
         true <-
           exact?(value, ~w(version encoding path byte_count sha256 data offset page_sha256 next)),
         true <-
           value["version"] === 2 and value["encoding"] == "base64",
         true <- value["path"] == state.ctx.args["path"],
         {:ok, bytes} <- Base.decode64(value["data"]),
         count when is_integer(count) and count in 1..32768 <- value["byte_count"],
         offset = if(state.phase == :document_check, do: 0, else: state.ctx.offset),
         true <- value["offset"] === offset and offset < count,
         true <- byte_size(bytes) == min(4096, count - offset),
         true <-
           value["page_sha256"] == Evidence.sha256(bytes) and Evidence.sha256?(value["sha256"]),
         finish = offset + byte_size(bytes),
         true <- value["next"] === if(finish < count, do: finish, else: nil),
         true <-
           is_nil(state.ctx.sha256) or state.ctx.sha256 == value["sha256"],
         true <- is_nil(state.ctx.total) or state.ctx.total === count do
      case state.phase do
        :document_read ->
          ctx = %{
            state.ctx
            | pieces: [bytes | state.ctx.pieces],
              offset: finish,
              sha256: value["sha256"],
              total: count,
              effects_used: state.ctx.effects_used + 1
          }

          if value["next"] do
            call(document_request(value["path"], value["sha256"], finish), %{state | ctx: ctx})
          else
            complete_document_read(%{state | ctx: ctx})
          end

        :document_check ->
          if bytes == state.ctx.first_page do
            receipt =
              state.ctx.payload["document"]
              |> Map.put("version", 2)
              |> Map.put("acquisition", %{
                "kind" => "workspace.read",
                "path" => value["path"],
                "operation_id" => operation
              })

            store_document(state, receipt)
          else
            finish(state, refused(:document_source_changed))
          end
      end
    else
      _ -> finish(state, refused(:document_acquisition_refused))
    end
  rescue
    _ -> finish(state, refused(:document_acquisition_refused))
  end

  defp document_read(_, state), do: finish(state, refused(:document_acquisition_refused))

  defp complete_document_read(state) do
    bytes = state.ctx.pieces |> Enum.reverse() |> IO.iodata_to_binary()
    chunking = if state.ctx.profile["kind"] == "collection", do: 2, else: 1

    with true <-
           byte_size(bytes) == state.ctx.total and Evidence.sha256(bytes) == state.ctx.sha256,
         {:ok, document} <- Documents.extract(bytes, Path.basename(state.ctx.args["path"])),
         {:ok, payload} <- Documents.source_payload(document, 65_536, chunking),
         true <-
           Evidence.valid_document?(
             payload["document"],
             payload["text"],
             if(chunking == 2, do: Evidence.collection_chunking())
           ) do
      ctx =
        state.ctx
        |> Map.drop([:pieces])
        |> Map.merge(%{
          payload: payload,
          first_page: binary_part(bytes, 0, min(4096, byte_size(bytes)))
        })

      call(document_request(state.ctx.args["path"], state.ctx.sha256), %{
        state
        | phase: :document_check,
          ctx: ctx
      })
    else
      {:error, code} -> finish(state, refused(code))
      _ -> finish(state, refused(:document_source_changed))
    end
  end

  defp store_document(state, receipt) do
    if state.ctx.profile["kind"] == "collection",
      do: store_collection_document(state, receipt),
      else: store_legacy_document(state, receipt)
  end

  defp store_legacy_document(state, receipt) do
    ctx = state.ctx

    document = %{
      "document" => receipt,
      "document_text" => ctx.payload["text"],
      "effects_used" => ctx.effects_used
    }

    {operation, args} =
      if ctx.action == "continue_document" do
        offset = ctx.args["offset"]
        text = ctx.payload["text"]

        if is_integer(offset) and offset in 0..byte_size(text) do
          common =
            Map.take(ctx.args, ~w(source_id draft_id expected_revision metadata_offset))
            |> Map.merge(document)

          if offset == byte_size(text),
            do: {:publish, common},
            else:
              {:append,
               Map.merge(common, %{
                 "offset" => offset,
                 "text" => utf8_part(binary_part(text, offset, byte_size(text) - offset), 4096)
               })}
        else
          {:append, %{}}
        end
      else
        common = ctx.args |> Map.drop(~w(path expected_sha256)) |> Map.merge(document)

        if byte_size(ctx.payload["text"]) <= 8192 and
             Evidence.document_storage_receipt!(receipt)["version"] != 4 do
          {:put, Map.delete(common, "document_text") |> Map.put("text", ctx.payload["text"])}
        else
          {:open,
           Map.merge(common, %{
             "byte_count" => byte_size(ctx.payload["text"]),
             "content_sha256" => Evidence.sha256(ctx.payload["text"])
           })}
        end
      end

    advance(Store.start(ctx.store, ctx.profile, operation, args), %{
      state
      | phase: :source,
        ctx: %{store: ctx.store, document_path: ctx.args["path"], document_sha256: ctx.sha256}
    })
  end

  defp collection_provided(state, store, profile, action, original, checkpoint) do
    with {:ok, args} <- document_args(action, original, 2) do
      attrs = collection_attrs(store, profile, args, args["text"], args["document"])

      advance(
        CollectionStore.start(profile, :put, %{
          "source" => attrs,
          "expected_revision" => args["expected_revision"],
          "continuation" => checkpoint
        }),
        %{
          state
          | phase: :collection_source,
            ctx: %{store: store, input_action: action, input_args: original}
        }
      )
    else
      {:error, code} -> finish(state, refused(code))
    end
  end

  defp collection_attrs(store, profile, args, text, document) do
    receipt = if document, do: Evidence.document_storage_receipt!(document)

    attrs =
      args
      |> Map.take(~w(source_id generation title uri observed_at_ms event_at_ms expires_at_ms))
      |> Map.merge(%{
        "partition" => profile["partition"],
        "text" => text,
        "origin" => %{
          "kind" => "provided",
          "store_profile" => store,
          "partition_or_scope" => profile["partition"],
          "receipt" => receipt,
          "historical" => false
        }
      })

    if is_map(receipt) and receipt["version"] == 4,
      do: Map.put(attrs, "document", document),
      else: attrs
  end

  defp store_collection_document(state, receipt) do
    ctx = state.ctx
    opening = ctx.args["opening_acquisition"] || receipt["acquisition"]

    with true <-
           is_map(opening) and opening["kind"] == "workspace.read" and
             opening["path"] == receipt["acquisition"]["path"] and
             is_binary(opening["operation_id"]) and
             Regex.match?(~r/\A[0-9a-f]{32}\z/, opening["operation_id"]) do
      receipt = Map.put(receipt, "acquisition", opening)
      attrs = collection_attrs(ctx.store, ctx.profile, ctx.args, ctx.payload["text"], receipt)

      original =
        ctx.args
        |> Map.drop(~w(collection_state opening_acquisition))
        |> Map.put("expected_sha256", ctx.sha256)

      advance(
        CollectionStore.start(ctx.profile, :put, %{
          "source" => attrs,
          "expected_revision" => ctx.args["expected_revision"],
          "continuation" => ctx.args["collection_state"],
          "effects_used" => ctx.effects_used
        }),
        %{
          state
          | phase: :collection_source,
            ctx: %{store: ctx.store, document_args: original, opening_acquisition: opening}
        }
      )
    else
      _ -> finish(state, refused(:document_acquisition_refused))
    end
  end

  defp collection_query(args, state) do
    with true <- state.resolved["preset"] in ~w(collection-documents collection-dense),
         true <- exact?(args, ~w(store retrieval query top_k as_of_ms source_ids)),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", args["store"]),
         {:ok, %{"kind" => "bm25"}} <-
           Profiles.lookup(state.resolved, "retrieval", args["retrieval"]),
         true <- text?(args["query"], 1024) and args["top_k"] in 1..10,
         at = args["as_of_ms"] || System.system_time(:millisecond),
         true <- Evidence.safe_uint?(at) do
      advance(
        CollectionStore.start(profile, :selected, %{
          "source_ids" => args["source_ids"],
          "as_of_ms" => at
        }),
        %{state | phase: :collection_query, ctx: %{args: args, as_of_ms: at}}
      )
    else
      _ -> finish(state, refused(:invalid_collection_query))
    end
  end

  defp collection_job(args, state) do
    with true <- state.resolved["preset"] in ~w(collection-documents collection-dense),
         true <-
           exact?(
             Map.delete(args, "response"),
             ~w(store action continuation vector_selection fact_selection)
           ),
         true <- Map.get(args, "response", "full") in ~w(full compact_v1),
         true <- args["action"] in ~w(begin inspect abort finalize finalize_paged),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      advance(
        CollectionStore.start(
          profile,
          :generation_job,
          args |> Map.drop(~w(store response)) |> Map.put("group", nil)
        ),
        %{state | phase: :collection_job, ctx: %{args: args}}
      )
    else
      _ -> finish(state, refused(:invalid_generation_job_request))
    end
  end

  defp collection_produce(args, state) do
    with true <- state.resolved["preset"] == "collection-dense",
         true <-
           exact?(
             args,
             ~w(store version action embedding job_id job_revision vector_selection fact_selection)
           ),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      advance(
        IpseKnowledge.Store.Collection.Producer.start(
          state.resolved,
          profile,
          Map.delete(args, "store")
        ),
        %{state | phase: :collection_producer, ctx: %{args: args}}
      )
    else
      _ -> finish(state, refused(:invalid_shared_producer_request))
    end
  end

  defp collection_projection(args, state) do
    with true <- state.resolved["preset"] in ~w(collection-documents collection-dense),
         true <- exact?(args, ~w(store source_ids vector_selection fact_selection as_of_ms top_k)),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]),
         true <- args["top_k"] in 1..8,
         at = args["as_of_ms"] || System.system_time(:millisecond),
         true <- Evidence.safe_uint?(at) do
      advance(
        CollectionStore.start(
          profile,
          :generation_selected,
          args |> Map.drop(~w(store top_k)) |> Map.put("as_of_ms", at)
        ),
        %{state | phase: :collection_projection, ctx: %{args: args, as_of_ms: at}}
      )
    else
      _ -> finish(state, refused(:invalid_shared_selection))
    end
  end

  defp collection_index(args, state) do
    with true <- state.resolved["preset"] in ~w(collection-documents collection-dense),
         true <- exact?(args, ~w(store action continuation)),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      advance(
        CollectionStore.start(profile, :lexical_build, Map.drop(args, ["store"])),
        %{state | phase: :collection_index, ctx: %{args: args}}
      )
    else
      _ -> finish(state, refused(:invalid_lexical_index))
    end
  end

  defp utf8_part(text, limit) do
    part = binary_part(text, 0, min(byte_size(text), limit))
    if String.valid?(part), do: part, else: utf8_part(text, byte_size(part) - 1)
  end

  defp workspace_path?(path) do
    text?(path, 1024) and Path.type(path) == :relative and
      not String.contains?(path, ["\\", <<0>>]) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."]))
  end

  defp query(args, state) do
    with true <- exact?(args, ~w(store retrieval rerank query top_k as_of_ms)),
         {:ok, store_profile} <- Profiles.lookup(state.resolved, "stores", args["store"]),
         {:ok, retrieval} <- Profiles.lookup(state.resolved, "retrieval", args["retrieval"]),
         {:ok, rerank_profile} <- Profiles.lookup(state.resolved, "rerank", args["rerank"]),
         true <-
           text?(args["query"], 1024) and is_integer(args["top_k"]) and args["top_k"] in 1..10,
         true <-
           args["as_of_ms"] == nil or
             Evidence.safe_uint?(args["as_of_ms"]),
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

      cond do
        store_profile["kind"] == "collection" ->
          if retrieval["kind"] == "bm25" and is_nil(rerank_profile) do
            advance(
              CollectionStore.start(store_profile, :lexical_query, %{
                "query" => args["query"],
                "top_k" => args["top_k"],
                "as_of_ms" => at
              }),
              %{state | phase: :collection_namespace, ctx: ctx}
            )
          else
            finish(state, refused(:invalid_collection_query))
          end

        retrieval["kind"] == "mcp_query" ->
          advance(
            Adapters.start(state.resolved, :query_refs, %{
              "profile" => args["retrieval"],
              "query" => args["query"],
              "top_k" => args["top_k"],
              "as_of_ms" => at
            }),
            %{state | phase: :query_refs, ctx: ctx}
          )

        true ->
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
           text?(args["source_id"], 256) and Evidence.safe_positive?(args["generation"]),
         true <- args["action"] in ~w(next inspect abort) and is_list(args["chunks"]),
         true <- length(args["chunks"]) in 1..2,
         true <- Enum.all?(args["chunks"], &Evidence.sha256?/1),
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
      if state.phase in [
           :collection_source,
           :collection_query,
           :collection_projection,
           :collection_job,
           :collection_index,
           :collection_namespace
         ] do
        :collection
      else
        if String.starts_with?(Atom.to_string(state.phase), "index_embed") or
             state.phase in [:query_refs, :query_embed, :query_rerank] do
          :adapter
        else
          :store
        end
      end

    pending = if state.phase == :collection_producer, do: :producer, else: pending
    call(request, %{state | cont: cont, pending: pending})
  end

  defp advance({:stop, :unknown_effect}, state), do: finish(state, refused(:unknown_effect))
  defp advance({:done, {:error, code, _}}, state), do: finish(state, refused(code))

  defp advance({:done, {:continue, value}}, %{phase: :collection_source} = state) do
    {action, args} =
      if Map.has_key?(state.ctx, :document_args),
        do:
          {"continue_collection_document",
           Map.merge(state.ctx.document_args, %{
             "collection_state" => value["continuation"],
             "opening_acquisition" => state.ctx.opening_acquisition
           })},
        else:
          {"continue_collection_source",
           %{
             "input_action" => state.ctx.input_action,
             "input_args" => state.ctx.input_args,
             "collection_state" => value["continuation"]
           }}

    continuation = %{
      "id" => "source",
      "arguments" => %{"store" => state.ctx.store, "action" => action, "args" => args}
    }

    finish(state, output("draft", [], [], [], value, continuation))
  end

  defp advance({:done, {:continue, value}}, %{phase: :collection_job} = state) do
    continuation = %{
      "id" => "generation_job",
      "arguments" => Map.put(state.ctx.args, "continuation", value["continuation"])
    }

    finish(
      state,
      output(
        "draft",
        [],
        [],
        [],
        Map.drop(job_result(state, value), ["continuation"]),
        continuation
      )
    )
  end

  defp advance(
         {:done, {:ok, %{"status" => status} = value}},
         %{phase: :collection_job, ctx: %{args: %{"action" => action}}} = state
       )
       when action in ~w(finalize finalize_paged) and status != "selected" do
    continuation = %{
      "id" => "generation_job",
      "arguments" => Map.put(state.ctx.args, "continuation", value["continuation"])
    }

    finish(
      state,
      output(
        "draft",
        [],
        [],
        [],
        Map.drop(job_result(state, value), ["continuation"]),
        continuation
      )
    )
  end

  defp advance({:done, {:ok, value}}, %{phase: :collection_job} = state),
    do: finish(state, output("ok", [], [], [], job_result(state, value), nil))

  defp advance({:done, {:ok, value}}, %{phase: :collection_producer} = state),
    do: finish(state, output("ok", [], [], [], value, nil))

  defp advance({:done, {:ok, snapshot}}, %{phase: :collection_projection} = state) do
    selected = snapshot["selected"]
    facts = Enum.flat_map(selected, & &1["facts"])
    at = state.ctx.as_of_ms
    eligible = Enum.filter(facts, &Evidence.current_fact?(&1, at))
    claims = Enum.take(eligible, state.ctx.args["top_k"])

    gaps =
      Enum.flat_map(selected, fn item ->
        case Evidence.document_receipt(item["source"]) do
          %{"status" => "partial", "warnings" => warnings} ->
            [
              %{
                "code" => "partial_document",
                "source_key" => item["source"]["source_key"],
                "warnings" => warnings
              }
            ]

          _ ->
            []
        end
      end)

    gaps =
      gaps ++
        Enum.map(facts -- eligible, &%{"code" => "excluded_fact", "fact_id" => &1["fact_id"]})

    complete = not Enum.any?(gaps, &(&1["code"] == "partial_document"))

    coverage =
      Map.merge(snapshot["coverage"], %{
        "sources" => length(selected),
        "vectors" => Enum.sum(Enum.map(selected, &length(&1["vectors"]))),
        "facts" => length(facts),
        "eligible_facts" => length(eligible),
        "complete" => complete,
        "claims_returned" => length(claims),
        "ranking" => "stored_order"
      })

    finish(
      state,
      output(
        if(complete, do: "ok", else: "partial"),
        Enum.flat_map(claims, & &1["citations"]),
        claims,
        gaps,
        coverage,
        nil
      )
    )
  end

  defp advance({:done, {:ok, value}}, %{phase: :collection_source} = state),
    do: finish(state, output("ok", [], [], [], value, nil))

  defp advance({:done, {:continue, value}}, %{phase: :collection_index} = state) do
    continuation =
      %{
        "id" => "lexical_index",
        "arguments" => %{
          "store" => state.ctx.args["store"],
          "action" => "next",
          "continuation" => value["continuation"]
        }
      }

    finish(state, output("draft", [], [], [], Map.drop(value, ["continuation"]), continuation))
  end

  defp advance({:done, {:ok, value}}, %{phase: :collection_index} = state),
    do: finish(state, output("ok", [], [], [], value, nil))

  defp advance({:done, {:ok, rank}}, %{phase: :collection_namespace} = state),
    do:
      finish(
        state,
        output(
          rank["status"],
          rank["evidence"],
          rank["claims"],
          rank["gaps"],
          rank["coverage"],
          nil
        )
      )

  defp advance({:done, {:ok, snapshot}}, %{phase: :collection_query} = state) do
    with {:ok, rank} <-
           Evidence.rank_lexical(
             snapshot["sources"],
             state.ctx.args["query"],
             state.ctx.args["top_k"],
             state.ctx.as_of_ms
           ) do
      rank = Evidence.query_scope(rank, snapshot["sources"], [], state.ctx.as_of_ms)

      coverage =
        rank["coverage"]
        |> Map.delete("complete")
        |> Map.merge(snapshot["coverage"])
        |> Map.put("catalog_generation", snapshot["catalog_generation"])

      finish(
        state,
        output(rank["status"], rank["evidence"], rank["claims"], rank["gaps"], coverage, nil)
      )
    else
      {:error, code} -> finish(state, refused(code))
    end
  end

  defp advance({:done, {:ok, value}}, %{phase: :source} = state) do
    continuation =
      if value["status"] == "draft" and Map.has_key?(state.ctx, :document_path) do
        %{
          "id" => "source",
          "arguments" => %{
            "store" => state.ctx.store,
            "action" => "continue_document",
            "args" =>
              Map.merge(value["continuation"], %{
                "source_id" => value["source_id"],
                "path" => state.ctx.document_path,
                "expected_sha256" => state.ctx.document_sha256
              })
          }
        }
      else
        value["continuation"]
      end

    finish(
      state,
      output(
        if(value["status"] == "draft", do: "draft", else: "ok"),
        [],
        [],
        [],
        value,
        continuation
      )
    )
  end

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
             state.ctx.args["query"],
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
             {:ok, seed} <- graph_seed(snapshot, args["query"], state.ctx.as_of_ms),
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
          {:error, :graph_context_limit} -> finish(state, refused(:graph_context_limit))
          _ -> finish(state, refused(:invalid_evidence))
        end

      _ ->
        finish(state, refused(:unsupported_retrieval))
    end
  end

  defp rank_semantic(state) do
    snap = state.ctx.snapshot
    args = state.ctx.args

    {candidates, missing} =
      dense_candidates(snap, state.ctx.as_of_ms, state.ctx.query_vector, args["query"])

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

        {"hybrid", {:error, :missing_embedding}} ->
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
      {:error, code} -> finish(state, refused(code))
      _ -> finish(state, refused(:invalid_evidence))
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

  defp dense_candidates(snapshot, as_of_ms, query_vector, query) do
    Enum.reduce(snapshot["sources"], {[], 0}, fn source, {acc, missing} ->
      if Evidence.current?(source, as_of_ms) do
        {:ok, chunks} = Evidence.chunks(source)
        projection = Map.get(snapshot["projections"], source["source_key"], %{})
        vectors = Map.get(projection, "vectors", [])

        Enum.reduce(chunks, {acc, missing}, fn chunk, {hits, gaps} ->
          vector =
            Enum.find(vectors, fn v ->
              v["chunk_id"] == chunk["chunk_id"] and Evidence.compatible_vectors?(v, query_vector) and
                Evidence.vector_input_matches_chunk?(v, chunk)
            end)

          if vector == nil do
            {hits, gaps + 1}
          else
            case Evidence.excerpt(source, chunk, query) do
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
             {:ok, seed} <-
               graph_seed(state.ctx.snapshot, state.ctx.args["query"], state.ctx.as_of_ms),
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
          {:error, :unknown_profile} -> {:error, :invalid_graph_profile}
          {:error, code} -> {:error, code}
          _ -> {:error, :invalid_graph_profile}
        end
    end
  end

  defp all_facts(snapshot),
    do: Enum.flat_map(Map.values(snapshot["projections"]), &(&1["facts"] || []))

  defp graph_seed(snapshot, query, as_of_ms),
    do: Evidence.graph_seed(snapshot["sources"], all_facts(snapshot), query, as_of_ms)

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

        "put_document" ->
          ~w(source_id generation expected_revision title filename bytes_base64 uri observed_at_ms event_at_ms expires_at_ms)

        "read_document" ->
          ~w(source_id generation expected_revision title path expected_sha256 uri observed_at_ms event_at_ms expires_at_ms)

        "continue_document" ->
          ~w(source_id draft_id expected_revision offset path expected_sha256)

        "continue_collection_document" ->
          ~w(source_id generation expected_revision title path expected_sha256 uri observed_at_ms event_at_ms expires_at_ms collection_state opening_acquisition)

        "continue_collection_source" ->
          ~w(input_action input_args collection_state)

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

    exact?(args, keys) or (action == "open" and exact?(args, keys ++ ["historical_import"])) or
      (action == "continue_document" and exact?(args, keys ++ ["metadata_offset"]))
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
      "filename" => string(256),
      "bytes_base64" => string(8192),
      "path" => string(1024),
      "expected_sha256" => %{"type" => ["string", "null"], "minLength" => 64, "maxLength" => 64},
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
      "metadata_offset" => integer(0, 16_384),
      "cursor" => %{"type" => ["integer", "null"]},
      "limit" => integer(1, 12),
      "export" => %{"type" => "object"},
      "historical_import" => %{"type" => "object"},
      "collection_state" => %{"type" => "object"},
      "opening_acquisition" => %{"type" => "object"},
      "input_action" => %{"type" => "string", "enum" => ~w(put put_document)},
      "input_args" => %{"type" => "object"}
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
        "as_of_ms" => %{
          "type" => ["integer", "null"],
          "minimum" => 0,
          "maximum" => Evidence.safe_integer_max()
        }
      }
    }
  end

  defp collection_entries do
    if @preset in ~w(collection-documents collection-dense) do
      schema =
        query_schema()
        |> Map.update!("required", &((&1 -- ["rerank"]) ++ ["source_ids"]))
        |> Map.update!(
          "properties",
          &(Map.delete(&1, "rerank")
            |> Map.put("source_ids", %{
              "type" => "array",
              "minItems" => 1,
              "maxItems" => 8,
              "items" => string(256)
            }))
        )

      [
        entry("query_selected", "Read cited evidence from explicit source IDs", schema),
        entry(
          "generation_job",
          "Begin, inspect, finalize or abort a supplied shared projection build",
          %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(store action continuation vector_selection fact_selection),
            "properties" => %{
              "store" => string(64),
              "action" => %{
                "type" => "string",
                "enum" => ~w(begin inspect abort finalize finalize_paged)
              },
              "continuation" => %{"type" => ["object", "null"]},
              "vector_selection" => %{"type" => "object"},
              "fact_selection" => %{"type" => "object"},
              "response" => %{"type" => "string", "enum" => ~w(full compact_v1)}
            }
          }
        ),
        entry(
          "projection_selected",
          "Inspect current supplied shared projections with exact citations",
          %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(store source_ids vector_selection fact_selection as_of_ms top_k),
            "properties" => %{
              "store" => string(64),
              "source_ids" => %{
                "type" => "array",
                "minItems" => 1,
                "maxItems" => 8,
                "items" => string(512)
              },
              "vector_selection" => %{"type" => "object"},
              "fact_selection" => %{"type" => "object"},
              "as_of_ms" => %{"type" => ["integer", "null"]},
              "top_k" => integer(1, 8)
            }
          }
        ),
        entry(
          "lexical_index",
          "Build, rebuild or inspect the catalog-bound namespace lexical index",
          %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(store action continuation),
            "properties" => %{
              "store" => string(64),
              "action" => %{"type" => "string", "enum" => ~w(begin next inspect abort)},
              "continuation" => %{"type" => ["object", "null"]}
            }
          }
        )
      ] ++ producer_entries()
    else
      []
    end
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

  defp producer_entries do
    if @preset == "collection-dense" do
      [
        entry(
          "generation_produce",
          "Claim and infer the first shared vector page; pending work never retries",
          %{
            "type" => "object",
            "additionalProperties" => false,
            "required" =>
              ~w(store version action embedding job_id job_revision vector_selection fact_selection),
            "properties" => %{
              "store" => string(64),
              "version" => %{"type" => "integer", "enum" => [1]},
              "action" => %{"type" => "string", "enum" => ~w(page inspect)},
              "embedding" => string(64),
              "job_id" => string(32),
              "job_revision" => integer(0, Evidence.safe_integer_max()),
              "vector_selection" => %{"type" => "object"},
              "fact_selection" => %{"type" => "object"}
            }
          }
        )
      ]
    else
      []
    end
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

  defp job_result(%{ctx: %{args: %{"response" => "compact_v1"}}}, value),
    do: IpseKnowledge.Store.Collection.Job.compact_result(value)

  defp job_result(_, value), do: value

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
end
