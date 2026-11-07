defmodule IpseKnowledge.Corpus do
  @behaviour Ipse.Extension
  alias IpseKnowledge.{Adapters, Documents, Evidence, Profiles, Store}
  alias IpseKnowledge.Store.Collection, as: CollectionStore
  @preset "state-lexical"
  # Leave room in the 16 KiB SDK argument envelope for a staged-write checkpoint.
  @fact_input_bytes 12_000
  @source_actions %{
    "put" => :put,
    "put_document" => :put,
    "read_document" => :put,
    "continue_document" => :append,
    "continue_collection_document" => :append,
    "continue_collection_source" => :put,
    "abort_collection_draft" => :progress_abort,
    "fact_input" => :fact_input,
    "backup_status" => :backup_status,
    "backup_page" => :backup_page,
    "backup_plan" => :backup_plan,
    "restore_validate_page" => :validate_backup_page,
    "restore_open" => :restore_action,
    "restore_page" => :restore_action,
    "restore_commit" => :restore_action,
    "restore_abort" => :restore_action,
    "restore_rollback" => :restore_action,
    "restore_checkpoint_drop" => :restore_action,
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
            entry("source", "Source", source_schema()),
            entry("query", "Evidence", query_schema()),
            entry("index", "Embeddings", index_schema())
          ] ++ collection_entries(),
        "tools" => [entry("query", "Evidence", query_schema())] ++ collection_entries()
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

  def handle("invoke.command", payload, state),
    do: invoke(payload, state |> Map.delete(:document_budget) |> Map.delete(:collection_query))

  def handle("invoke.tool", %{"id" => "source"}, state),
    do: finish(state, refused(:invalid_invocation))

  def handle("invoke.tool", payload, state),
    do: invoke(payload, state |> Map.delete(:document_budget) |> Map.delete(:collection_query))

  def handle("host.actions", payload, %{phase: phase} = state)
      when phase in [:document_read, :document_check],
      do: document_read(payload, state)

  def handle("host.actions", payload, %{phase: :document_snapshot_open} = state),
    do: document_snapshot_open(payload, state)

  def handle("host.actions", payload, %{phase: :document_snapshot_page} = state),
    do: document_snapshot_page(payload, state)

  def handle("host.actions", payload, %{phase: :document_use_verify} = state),
    do: document_use_verified(payload, state)

  def handle("host.actions", payload, %{phase: :document_use_check} = state),
    do: document_use_checked(payload, state)

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
    with true <- source_outer?(outer, action),
         {:ok, profile} <- Profiles.lookup(state.resolved, "stores", store),
         {:ok, operation} <- Map.fetch(@source_actions, action),
         true <- valid_source_args?(action, source_args),
         true <-
           action not in ~w(continue_collection_document continue_collection_source abort_collection_draft) or
             profile["kind"] == "collection",
         true <- profile["kind"] != "collection" or action != "continue_document" do
      cond do
        action == "fact_input" ->
          collection_fact_input(state, profile, source_args["input"], outer)

        action in ~w(backup_status backup_page backup_plan restore_validate_page restore_open restore_page restore_commit restore_abort restore_rollback restore_checkpoint_drop) ->
          collection_backup_source(state, profile, action, source_args["backup"], outer)

        action == "abort_collection_draft" ->
          advance(
            CollectionStore.start(profile, :progress_abort, source_args),
            %{state | phase: :collection_draft_abort, ctx: %{store: store}}
          )

        action in ~w(read_document continue_document continue_collection_document) ->
          acquire_document(store, profile, source_args, action, state)

        action == "continue_collection_source" ->
          input_action = source_args["input_action"]
          input_args = source_args["input_args"]

          if input_action in ~w(put put_document) and
               valid_source_args?(input_action, input_args),
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

  defp source_outer?(outer, action) do
    extra =
      case action do
        "fact_input" ->
          case outer["args"] do
            %{"input" => %{"mode" => "append"}} -> ["result_input"]
            %{"input" => %{"mode" => "assemble"}} -> ["data_inputs"]
            _ -> []
          end

        "backup_plan" ->
          ["data_inputs"]

        op when op in ~w(restore_validate_page restore_page) ->
          ~w(result_input plan_input)

        "restore_open" ->
          ["result_input"]

        op when op in ~w(restore_commit restore_rollback) ->
          ["plan_input"]

        _ ->
          []
      end

    exact?(outer, ~w(store action args) ++ extra)
  end

  defp collection_fact_input(state, %{"kind" => "collection"} = profile, input, outer) do
    if state.resolved["preset"] === "collection-dense" do
      case input["mode"] do
        "publish" ->
          case Ipse.Extension.ResultPublication.prepare_paged(input["value"]) do
            {:ok, reply} ->
              {:ok, reply, %{state | phase: :idle, ctx: nil, cont: nil, pending: nil}}

            _ ->
              finish(state, refused(:result_too_large))
          end

        "assemble" ->
          refs = outer["data_inputs"]

          with true <- is_list(refs) and length(refs) in 1..8,
               true <- length(Enum.uniq(refs)) === length(refs),
               true <-
                 Enum.all?(refs, fn ref ->
                   match?(
                     {:call, _, _},
                     CollectionStore.start(profile, :selected_fact_result, %{
                       "result_input" => ref
                     })
                   )
                 end),
               true <-
                 Enum.sum(Enum.map(refs, &div(&1["delivery"]["byte_count"] + 6143, 6144))) <= 512 do
            fact_group_assembly_next(%{
              state
              | phase: :fact_group_assembly,
                ctx: %{
                  profile: profile,
                  remaining: refs,
                  reads: 0,
                  reader_start: 0,
                  owner: nil,
                  sources: []
                }
            })
          else
            _ -> finish(state, refused(:invalid_fact_group_assembly))
          end

        "begin" ->
          args = %{
            "action" => "begin",
            "vector_selection" => input["vector_selection"],
            "fact_selection" => input["fact_selection"],
            "continuation" => input["continuation"],
            "group" => nil
          }

          advance(IpseKnowledge.Store.Collection.Job.start_bound(profile, args), %{
            state
            | phase: :fact_group_begin,
              ctx: %{args: outer}
          })

        "append" ->
          advance(
            CollectionStore.start(profile, :selected_fact_result, %{
              "result_input" => outer["result_input"]
            }),
            %{state | phase: :fact_group_read, ctx: %{args: outer, profile: profile}}
          )
      end
    else
      finish(state, refused(:collection_lifecycle_unavailable))
    end
  end

  defp collection_fact_input(state, _, _, _),
    do: finish(state, refused(:collection_lifecycle_unavailable))

  defp fact_group_assembly_next(%{ctx: %{remaining: []} = ctx} = state) do
    value = %{"version" => 1, "kind" => "explicit_fact_group", "sources" => ctx.sources}

    case Ipse.Extension.ResultPublication.prepare_paged(value) do
      {:ok, reply} -> {:ok, reply, %{state | phase: :idle, ctx: nil, cont: nil, pending: nil}}
      _ -> finish(state, refused(:result_too_large))
    end
  end

  defp fact_group_assembly_next(%{ctx: %{remaining: [ref | _]} = ctx} = state) do
    advance(
      CollectionStore.start(ctx.profile, :selected_fact_result, %{"result_input" => ref}),
      %{state | ctx: %{ctx | reader_start: ctx.reads}}
    )
  end

  defp merge_fact_group(existing, incoming) do
    Enum.reduce_while(incoming, {:ok, existing}, fn source, {:ok, sources} ->
      index = Enum.find_index(sources, &(&1["source_key"] === source["source_key"]))

      rows =
        if is_nil(index),
          do: source["facts"],
          else: Enum.at(sources, index)["facts"] ++ source["facts"]

      cond do
        length(rows) > 32 or length(Enum.uniq(rows)) !== length(rows) -> {:halt, :error}
        is_nil(index) and length(sources) >= 8 -> {:halt, :error}
        is_nil(index) -> {:cont, {:ok, sources ++ [source]}}
        true -> {:cont, {:ok, List.update_at(sources, index, &Map.put(&1, "facts", rows))}}
      end
    end)
  end

  defp collection_backup_source(state, profile, action, args, outer) do
    if profile["kind"] === "collection" do
      {operation, input, phase} =
        case action do
          "backup_status" ->
            {:snapshot, %{}, :collection_backup_status}

          "backup_page" ->
            {:backup_page, args, :collection_backup_page}

          "backup_plan" ->
            {:backup_plan, Map.put(args, "data_inputs", outer["data_inputs"]),
             :collection_backup_plan}

          "restore_validate_page" ->
            {:validate_backup_page, Map.take(outer, ~w(result_input plan_input)),
             :collection_backup_validate}

          "restore_" <> mutation ->
            {:restore_action,
             %{
               "action" => mutation,
               "args" => args,
               "result_input" => outer["result_input"],
               "plan_input" => outer["plan_input"]
             }, :collection_restore}
        end

      advance(CollectionStore.start(profile, operation, input), %{state | phase: phase, ctx: %{}})
    else
      finish(state, refused(:collection_lifecycle_unavailable))
    end
  end

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
      collection = profile["kind"] == "collection"

      request =
        if collection,
          do: snapshot_request("start", args["path"], args["expected_sha256"]),
          else: document_request(args["path"], args["expected_sha256"])

      call(request, %{
        state
        | phase: if(collection, do: :document_snapshot_open, else: :document_read),
          ctx: %{
            store: store,
            profile: profile,
            args: args,
            action: action,
            pieces: [],
            offset: 0,
            sha256: args["expected_sha256"],
            total: nil,
            effects_used: 1,
            reads_used: 0
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

  defp snapshot_request(kind, path, expected, handle \\ nil, offset \\ nil) do
    arguments = %{"snapshot" => kind, "path" => path}
    arguments = if expected, do: Map.put(arguments, "expected_sha256", expected), else: arguments

    arguments =
      if handle,
        do: Map.merge(arguments, %{"snapshot_handle" => handle, "byte_offset" => offset}),
        else: arguments

    %{"op" => "tool.call", "name" => "read", "timeout_ms" => 5000, "arguments" => arguments}
  end

  defp document_snapshot_open(
         %{
           "operation_id" => operation,
           "outcome" => %{"status" => "ok", "value" => %{"text" => text}}
         },
         state
       ) do
    with true <- is_binary(operation) and Regex.match?(~r/\A[0-9a-f]{32}\z/, operation),
         true <- text?(text, 8192),
         value when is_map(value) <- JSON.decode!(text),
         true <- exact?(value, ~w(byte_count handle path sha256)),
         true <- value["path"] === state.ctx.args["path"],
         count when is_integer(count) and count in 1..1_048_576 <- value["byte_count"],
         true <- Evidence.sha256?(value["sha256"]),
         true <- is_nil(state.ctx.sha256) or state.ctx.sha256 === value["sha256"],
         handle when is_binary(handle) <- value["handle"],
         true <- Regex.match?(~r/\A[0-9a-f]{32}\z/, handle) do
      ctx =
        Map.merge(state.ctx, %{
          snapshot_handle: handle,
          opening_operation: operation,
          sha256: value["sha256"],
          total: count
        })

      request = snapshot_request("page", value["path"], value["sha256"], handle, 0)
      call(request, %{state | phase: :document_snapshot_page, ctx: ctx})
    else
      _ -> finish(state, refused(:document_acquisition_refused))
    end
  rescue
    _ -> finish(state, refused(:document_acquisition_refused))
  end

  defp document_snapshot_open(_, state), do: finish(state, refused(:document_acquisition_refused))

  defp document_snapshot_page(
         %{
           "operation_id" => operation,
           "outcome" => %{"status" => "ok", "value" => %{"text" => text}}
         },
         state
       ) do
    with true <- is_binary(operation) and Regex.match?(~r/\A[0-9a-f]{32}\z/, operation),
         true <- text?(text, 8192),
         value when is_map(value) <- JSON.decode!(text),
         true <- exact?(value, ~w(byte_count data handle next offset page_sha256 path sha256)),
         true <-
           value["path"] === state.ctx.args["path"] and value["sha256"] === state.ctx.sha256,
         true <-
           value["handle"] === state.ctx.snapshot_handle and
             value["byte_count"] === state.ctx.total,
         true <- value["offset"] === state.ctx.offset and state.ctx.offset < state.ctx.total,
         {:ok, bytes} <- Base.decode64(value["data"]),
         true <- byte_size(bytes) == min(4096, state.ctx.total - state.ctx.offset),
         true <- value["page_sha256"] === Evidence.sha256(bytes),
         finish = state.ctx.offset + byte_size(bytes),
         true <- value["next"] === if(finish < state.ctx.total, do: finish, else: nil) do
      ctx = %{
        state.ctx
        | pieces: [bytes | state.ctx.pieces],
          offset: finish,
          reads_used: state.ctx.reads_used + 1
      }

      if value["next"] do
        request =
          snapshot_request("page", value["path"], value["sha256"], value["handle"], finish)

        call(request, %{state | ctx: ctx})
      else
        complete_document_read(%{state | ctx: ctx})
      end
    else
      _ -> finish(state, refused(:document_acquisition_refused))
    end
  rescue
    _ -> finish(state, refused(:document_acquisition_refused))
  end

  defp document_snapshot_page(_, state), do: finish(state, refused(:document_acquisition_refused))

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

      if Map.has_key?(ctx, :snapshot_handle) do
        receipt =
          payload["document"]
          |> Map.put("version", 2)
          |> Map.put("acquisition", %{
            "kind" => "workspace.read",
            "path" => ctx.args["path"],
            "operation_id" => ctx.opening_operation
          })

        store_document(%{state | ctx: ctx}, receipt)
      else
        call(document_request(state.ctx.args["path"], state.ctx.sha256), %{
          state
          | phase: :document_check,
            ctx: ctx
        })
      end
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
          "effects_used" => ctx.effects_used,
          "reads_used" => ctx.reads_used
        }),
        %{
          state
          | phase: :collection_source,
            ctx: %{
              store: ctx.store,
              document_args: original,
              opening_acquisition: opening,
              workspace_snapshot: Map.has_key?(ctx, :snapshot_handle)
            }
        }
      )
    else
      _ -> finish(state, refused(:document_acquisition_refused))
    end
  end

  defp collection_query(args, state) do
    with true <- state.resolved["preset"] in ~w(collection-documents collection-dense),
         true <- is_map(args),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]),
         {:ok, retrieval} <- Profiles.lookup(state.resolved, "retrieval", args["retrieval"]),
         true <- collection_query_shape?(args, retrieval, state.resolved),
         true <- text?(args["query"], 1024) and args["top_k"] in 1..10,
         true <- query_prefix_valid?(retrieval, args["query"]),
         at = args["as_of_ms"] || System.system_time(:millisecond),
         true <- Evidence.safe_uint?(at) do
      if retrieval["kind"] == "bm25" do
        state = Map.put(state, :collection_query, true)

        advance(
          CollectionStore.start(profile, :selected, %{
            "source_ids" => args["source_ids"],
            "as_of_ms" => at
          }),
          %{state | phase: :collection_query, ctx: %{args: args, as_of_ms: at}}
        )
      else
        state = Map.put(state, :collection_query, true)

        advance(
          CollectionStore.start(
            profile,
            :generation_selected,
            Map.take(args, ~w(source_ids vector_selection fact_selection))
            |> Map.put("as_of_ms", at)
          ),
          %{
            state
            | phase: :collection_semantic_snapshot,
              ctx: %{args: args, as_of_ms: at, retrieval: retrieval, store_profile: profile}
          }
        )
      end
    else
      _ -> finish(state, refused(:invalid_collection_query))
    end
  end

  defp collection_query_shape?(args, %{"kind" => "bm25"}, _),
    do: exact?(args, ~w(store retrieval query top_k as_of_ms source_ids))

  defp collection_query_shape?(args, %{"kind" => kind} = retrieval, resolved)
       when kind in ~w(dense hybrid) do
    with true <- resolved["preset"] == "collection-dense",
         true <-
           exact?(
             args,
             ~w(store retrieval query top_k as_of_ms source_ids vector_selection fact_selection)
           ),
         {:ok, embedding} <- Profiles.lookup(resolved, "embedding", retrieval["embedding"]),
         true <-
           is_map(args["vector_selection"]) and
             embedding["profile"] === args["vector_selection"]["profile"],
         true <-
           kind != "hybrid" or
             (is_nil(retrieval["graph"]) and retrieval["missing_embedding"] == "refuse") do
      true
    else
      _ -> false
    end
  end

  defp collection_query_shape?(_, _, _), do: false

  defp collection_job(args, state) do
    with true <- state.resolved["preset"] in ~w(collection-documents collection-dense),
         true <-
           exact?(
             Map.drop(args, ~w(response guard_sources)),
             ~w(store action continuation vector_selection fact_selection)
           ),
         true <- Map.get(args, "response", "full") in ~w(full compact_v1),
         true <- args["action"] in ~w(begin inspect abort finalize finalize_paged),
         true <- Map.get(args, "guard_sources", false) in [true, false],
         true <-
           Map.get(args, "guard_sources", false) === false or
             (state.resolved["preset"] == "collection-dense" and
                args["action"] in ~w(finalize finalize_paged)),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      advance(
        CollectionStore.start(
          profile,
          if(args["guard_sources"] === true,
            do: :guarded_generation_finalize,
            else: :generation_job
          ),
          args |> Map.drop(~w(store response guard_sources)) |> Map.put("group", nil)
        ),
        %{state | phase: :collection_job, ctx: %{args: args}}
      )
    else
      _ -> finish(state, refused(:invalid_generation_job_request))
    end
  end

  defp collection_produce(args, state) do
    case args["action"] do
      "facts" -> collection_fact_stage(args, state)
      "facts_page" -> collection_fact_page(args, state)
      "facts_commit" -> collection_fact_commit(args, state)
      "facts_slots" -> collection_fact_slots(args, state)
      "append" -> collection_produce_append(args, state)
      _ -> collection_produce_vectors(args, state)
    end
  end

  defp collection_produce_append(args, state) do
    with true <- state.resolved["preset"] == "collection-dense",
         true <-
           exact?(
             args,
             ~w(store version action embedding job_id job_revision vector_selection fact_selection vector_cursor previous_ready continuation)
           ),
         true <- args["version"] === 2 and args["action"] === "append",
         true <- is_nil(args["continuation"]) or is_map(args["continuation"]),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      producer_args = args |> Map.drop(~w(store continuation)) |> Map.put("action", "page")

      advance(
        IpseKnowledge.Store.Collection.Producer.Progress.append_selected(
          state.resolved,
          profile,
          producer_args,
          args["continuation"]
        ),
        %{state | phase: :collection_producer_append, ctx: %{args: args}}
      )
    else
      _ -> finish(state, refused(:invalid_shared_producer_request))
    end
  end

  defp collection_produce_vectors(args, state) do
    with true <- state.resolved["preset"] == "collection-dense",
         true <-
           (args["action"] == "selection" and exact?(args, ~w(store version action embedding))) or
             (args["version"] === 1 and args["action"] in ~w(page inspect) and
                exact?(
                  args,
                  ~w(store version action embedding job_id job_revision vector_selection fact_selection)
                )) or
             (args["version"] === 2 and args["action"] in ~w(page inspect) and
                exact?(
                  args,
                  ~w(store version action embedding job_id job_revision vector_selection fact_selection vector_cursor previous_ready)
                )),
         true <-
           (args["version"] === 1 and args["action"] in ~w(page inspect selection)) or
             (args["version"] === 2 and args["action"] in ~w(page inspect)),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      case args["action"] do
        "page" ->
          advance(
            IpseKnowledge.Store.Collection.Producer.start(
              state.resolved,
              profile,
              Map.delete(args, "store")
            ),
            %{state | phase: :collection_producer, ctx: %{args: args}}
          )

        "selection" ->
          advance(
            IpseKnowledge.Store.Collection.Producer.selection(state.resolved, args["embedding"]),
            %{state | phase: :collection_producer, ctx: %{args: args}}
          )

        "inspect" ->
          advance(
            IpseKnowledge.Store.Collection.Producer.start(
              state.resolved,
              profile,
              Map.delete(args, "store")
            ),
            %{state | phase: :collection_producer, ctx: %{args: args}}
          )
      end
    else
      _ -> finish(state, refused(:invalid_shared_producer_request))
    end
  end

  defp collection_fact_stage(args, state) do
    with true <- state.resolved["preset"] == "collection-dense",
         true <-
           exact?(args, ~w(store version action source_id expected_revision facts continuation)),
         true <- args["version"] === 2 and args["action"] === "facts",
         true <- text?(args["source_id"], 256) and Evidence.safe_uint?(args["expected_revision"]),
         true <- is_list(args["facts"]) and length(args["facts"]) in 0..32,
         true <- is_nil(args["continuation"]) or is_map(args["continuation"]),
         true <- byte_size(JSON.encode!(Map.put(args, "continuation", nil))) <= @fact_input_bytes,
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      advance(
        CollectionStore.start(profile, :selected, %{
          "source_ids" => [args["source_id"]],
          "as_of_ms" => System.system_time(:millisecond)
        }),
        %{state | phase: :collection_fact_source, ctx: %{args: args, profile: profile}}
      )
    else
      _ -> finish(state, refused(:invalid_explicit_fact_stage))
    end
  end

  defp collection_fact_page(args, state) do
    with true <- state.resolved["preset"] == "collection-dense",
         true <-
           exact?(
             args,
             ~w(store version action source_id draft_id manifest page expected_slot_revision)
           ),
         true <- args["version"] === 2 and args["action"] === "facts_page",
         true <-
           text?(args["source_id"], 256) and is_binary(args["draft_id"]) and
             Regex.match?(~r/\A[0-9a-f]{32}\z/, args["draft_id"]),
         true <- Evidence.safe_uint?(args["expected_slot_revision"]),
         true <- is_map(args["manifest"]) and is_map(args["page"]),
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      advance(
        CollectionStore.start(profile, :selected, %{
          "source_ids" => [args["source_id"]],
          "as_of_ms" => System.system_time(:millisecond)
        }),
        %{state | phase: :fact_input_source, ctx: %{args: args, profile: profile}}
      )
    else
      _ -> finish(state, refused(:invalid_fact_input_page))
    end
  end

  defp collection_fact_commit(args, state) do
    with true <- state.resolved["preset"] == "collection-dense",
         true <-
           exact?(
             args,
             ~w(store version action source_id draft_id manifest expected_revision continuation)
           ),
         true <- args["version"] === 2 and args["action"] === "facts_commit",
         true <-
           text?(args["source_id"], 256) and is_binary(args["draft_id"]) and
             Regex.match?(~r/\A[0-9a-f]{32}\z/, args["draft_id"]),
         true <- Evidence.safe_uint?(args["expected_revision"]),
         true <- is_nil(args["continuation"]) or is_map(args["continuation"]),
         true <-
           is_map(args["manifest"]) and is_list(args["manifest"]["page_sha256"]) and
             length(args["manifest"]["page_sha256"]) in 1..8,
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      advance(
        CollectionStore.start(profile, :selected, %{
          "source_ids" => [args["source_id"]],
          "as_of_ms" => System.system_time(:millisecond)
        }),
        %{state | phase: :fact_collect_source, ctx: %{args: args, profile: profile}}
      )
    else
      _ -> finish(state, refused(:invalid_fact_input_set))
    end
  end

  defp collection_fact_slots(args, state) do
    with true <- state.resolved["preset"] == "collection-dense",
         true <- exact?(args, ~w(store version action)),
         true <- args["version"] === 2 and args["action"] === "facts_slots",
         {:ok, %{"kind" => "collection"} = profile} <-
           Profiles.lookup(state.resolved, "stores", args["store"]) do
      ctx = %{profile: profile, ordinal: 0, generation: nil, slots: []}

      advance(
        CollectionStore.start(profile, :value_read, %{"key" => "catalog." <> profile["partition"]}),
        %{state | phase: :fact_slots_boot, ctx: ctx}
      )
    else
      _ -> finish(state, refused(:invalid_fact_input_slots))
    end
  end

  defp fact_collect_next(state) do
    ctx = state.ctx

    if ctx.ordinal < length(ctx.args["manifest"]["page_sha256"]) do
      key = "factdraft.#{ctx.profile["partition"]}.#{ctx.ordinal}"

      advance(
        CollectionStore.start(ctx.profile, :value_read_at, %{
          "key" => key,
          "generation" => ctx.generation
        }),
        %{state | phase: :fact_collect_slot}
      )
    else
      case IpseKnowledge.Store.Collection.Projection.fact_input_rows(
             ctx.source,
             ctx.pages,
             ctx.args["manifest"]
           ) do
        {:ok, %{facts: facts}} ->
          advance(
            CollectionStore.start(ctx.profile, :fact_store, %{
              "source_id" => ctx.args["source_id"],
              "selection" => %{"kind" => "explicit", "profile" => nil, "version" => 1},
              "facts" => facts,
              "expected_revision" => ctx.args["expected_revision"],
              "as_of_ms" => System.system_time(:millisecond),
              "continuation" => ctx.args["continuation"]
            }),
            %{state | phase: :collection_fact_stage}
          )

        _ ->
          finish(state, refused(:invalid_fact_input_set))
      end
    end
  end

  defp collection_projection(args, state) do
    with true <- state.resolved["preset"] in ~w(collection-documents collection-dense),
         true <-
           exact?(args, ~w(store source_ids vector_selection fact_selection as_of_ms top_k)),
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
         true <- query_prefix_valid?(retrieval, args["query"]),
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
            state = Map.put(state, :collection_query, true)

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

  defp query_prefix_valid?(%{"kind" => kind, "query_prefix" => prefix}, query)
       when kind in ~w(dense hybrid),
       do: not String.starts_with?(query, prefix)

  defp query_prefix_valid?(_, _), do: true

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

  defp advance({:call, request, cont}, %{phase: :fact_group_assembly} = state) do
    if CollectionStore.read_request?(request) and
         get_in(request, ["request", "op"]) === "restore.input.read" and state.ctx.reads < 512 do
      call(request, %{
        state
        | ctx: %{state.ctx | reads: state.ctx.reads + 1},
          cont: cont,
          pending: :collection
      })
    else
      finish(state, refused(:collection_backup_read_budget))
    end
  end

  defp advance({:call, request, cont}, state) do
    request =
      if state.phase == :collection_source and state.ctx[:workspace_snapshot] == true and
           request["op"] === "collection.store" and request["request"]["op"] === "commit" and
           cont[:phase] === :published do
        args = state.ctx.document_args
        opening = state.ctx.opening_acquisition

        Map.put(request, "workspace_guard", %{
          "path" => args["path"],
          "original_sha256" => args["expected_sha256"],
          "opening_operation_id" => opening["operation_id"],
          "source_id" => args["source_id"],
          "generation" => args["generation"],
          "bundle_sha256" => cont.source_sha256
        })
      else
        request
      end

    cont =
      if Map.has_key?(request, "workspace_guard"),
        do: Map.put(cont, :request, request),
        else: cont

    state =
      if state.phase == :collection_semantic_embed do
        count = Map.get(state.ctx, :embedding_result_reads, 0)
        added = if request["op"] == "effect.result.read", do: 1, else: 0
        %{state | ctx: Map.put(state.ctx, :embedding_result_reads, count + added)}
      else
        state
      end

    pending =
      if state.phase in [
           :collection_source,
           :collection_draft_abort,
           :collection_backup_status,
           :collection_backup_page,
           :collection_backup_plan,
           :collection_backup_validate,
           :collection_restore,
           :fact_group_begin,
           :fact_group_read,
           :collection_query,
           :collection_projection,
           :collection_semantic_snapshot,
           :collection_semantic_revalidate,
           :document_use_collection,
           :collection_job,
           :collection_index,
           :collection_namespace,
           :collection_fact_source,
           :collection_fact_stage,
           :fact_input_source,
           :fact_input_catalog,
           :fact_input_slot,
           :fact_input_write,
           :fact_collect_source,
           :fact_collect_catalog,
           :fact_collect_slot,
           :fact_slots_boot,
           :fact_slots
         ] do
        :collection
      else
        if String.starts_with?(Atom.to_string(state.phase), "index_embed") or
             state.phase in [
               :query_refs,
               :query_embed,
               :query_rerank,
               :collection_semantic_profile,
               :collection_semantic_embed
             ] do
          :adapter
        else
          :store
        end
      end

    pending =
      if state.phase in [:collection_producer, :collection_producer_append, :fact_group_append],
        do: :producer,
        else: pending

    call(request, %{state | cont: cont, pending: pending})
  end

  defp advance({:stop, :unknown_effect}, state), do: finish(state, refused(:unknown_effect))
  defp advance({:done, {:error, code, _}}, state), do: finish(state, refused(code))

  defp advance({:done, {:ok, snapshot}}, %{phase: :collection_backup_status} = state) do
    with generation when is_integer(generation) and generation >= 0 <- snapshot["generation"],
         {:ok, epoch, status} <- CollectionStore.snapshot_epoch(snapshot) do
      finish(
        state,
        output(
          "ok",
          [],
          [],
          [],
          %{
            "generation" => generation,
            "maintenance_epoch" => epoch,
            "maintenance_status" => status
          },
          nil
        )
      )
    else
      _ -> finish(state, refused(:document_epoch_changed))
    end
  end

  defp advance({:done, {:ok, value}}, %{phase: phase} = state)
       when phase in [
              :collection_backup_page,
              :collection_backup_plan,
              :collection_backup_validate
            ] do
    case Ipse.Extension.ResultPublication.prepare_paged(value) do
      {:ok, reply} -> {:ok, reply, %{state | phase: :idle, ctx: nil, cont: nil, pending: nil}}
      _ -> finish(state, refused(:result_too_large))
    end
  end

  defp advance({:done, {:ok, value}}, %{phase: :collection_restore} = state),
    do: finish(state, output("ok", [], [], [], value, nil))

  defp advance({:done, {:ok, selected}}, %{phase: :fact_group_read} = state) do
    input = state.ctx.args["args"]["input"]

    advance(
      IpseKnowledge.Store.Collection.Producer.Progress.append_result(
        state.resolved,
        state.ctx.profile,
        input["producer"],
        selected,
        input["continuation"]
      ),
      %{state | phase: :fact_group_append}
    )
  end

  defp advance({:done, {:ok, selected}}, %{phase: :fact_group_assembly} = state) do
    ctx = state.ctx
    [ref | remaining] = ctx.remaining
    value = selected["value"]

    with true <- selected["result_input"] === ref,
         true <- selected["reads_used"] === ctx.reads - ctx.reader_start,
         true <- is_nil(ctx.owner) or ctx.owner === selected["owner"],
         true <- fact_group_input?(%{"version" => 1, "mode" => "publish", "value" => value}),
         {:ok, sources} <- merge_fact_group(ctx.sources, value["sources"]) do
      fact_group_assembly_next(%{
        state
        | ctx: %{ctx | remaining: remaining, owner: selected["owner"], sources: sources}
      })
    else
      _ -> finish(state, refused(:invalid_fact_group_assembly))
    end
  end

  defp advance({:done, {:continue, value}}, %{phase: phase} = state)
       when phase in [:fact_group_begin, :fact_group_append] do
    args = put_in(state.ctx.args, ["args", "input", "continuation"], value["continuation"])
    continuation = %{"id" => "source", "arguments" => args}

    compact =
      if is_map(value["job"]),
        do: IpseKnowledge.Store.Collection.Job.compact_result(value),
        else: value

    finish(state, output("draft", [], [], [], Map.delete(compact, "continuation"), continuation))
  end

  defp advance({:done, {:ok, value}}, %{phase: phase} = state)
       when phase in [:fact_group_begin, :fact_group_append] do
    compact = IpseKnowledge.Store.Collection.Job.compact_result(value)
    finish(state, output("ok", [], [], [], compact, nil))
  end

  defp advance(
         {:done, {:ok, %{"native_generation" => generation}}},
         %{phase: :fact_slots_boot} = state
       ) do
    ctx = %{state.ctx | generation: generation}
    key = "factdraft.#{ctx.profile["partition"]}.0"

    advance(
      CollectionStore.start(ctx.profile, :value_stat, %{"key" => key, "generation" => generation}),
      %{state | phase: :fact_slots, ctx: ctx}
    )
  end

  defp advance(
         {:done, {:ok, %{"record" => row, "generation" => generation}}},
         %{phase: :fact_slots} = state
       ) do
    ctx = state.ctx

    if is_nil(ctx.generation) or generation === ctx.generation do
      revision = if is_nil(row), do: 0, else: row["revision"]
      slot = %{"ordinal" => ctx.ordinal, "revision" => revision, "occupied" => not is_nil(row)}
      ctx = %{ctx | generation: generation, slots: ctx.slots ++ [slot], ordinal: ctx.ordinal + 1}

      if ctx.ordinal == 8 do
        finish(state, output("ok", [], [], [], %{"slots" => ctx.slots}, nil))
      else
        key = "factdraft.#{ctx.profile["partition"]}.#{ctx.ordinal}"

        advance(
          CollectionStore.start(ctx.profile, :value_stat, %{
            "key" => key,
            "generation" => generation
          }),
          %{state | ctx: ctx}
        )
      end
    else
      finish(state, refused(:fact_input_changed))
    end
  end

  defp advance(
         {:done, {:ok, %{"sources" => [source], "native_generation" => generation}}},
         %{phase: :fact_collect_source} = state
       ) do
    ctx = Map.merge(state.ctx, %{source: source, generation: generation})

    advance(
      CollectionStore.start(ctx.profile, :value_read_at, %{
        "key" => "catalog." <> ctx.profile["partition"],
        "generation" => generation
      }),
      %{state | phase: :fact_collect_catalog, ctx: ctx}
    )
  end

  defp advance(
         {:done, {:ok, %{"record" => catalog, "native_generation" => generation}}},
         %{phase: :fact_collect_catalog} = state
       )
       when is_map(catalog) do
    if generation === state.ctx.generation do
      fact_collect_next(%{
        state
        | ctx: Map.merge(state.ctx, %{catalog: catalog, pages: [], ordinal: 0})
      })
    else
      finish(state, refused(:fact_input_changed))
    end
  end

  defp advance(
         {:done, {:ok, %{"record" => row, "native_generation" => generation}}},
         %{phase: :fact_collect_slot} = state
       )
       when is_map(row) do
    ctx = state.ctx
    slot = row["value"]

    if generation === ctx.generation and
         exact?(slot, ~w(version kind draft_id source_key catalog_sha256 manifest page)) and
         slot["version"] === 1 and slot["kind"] === "explicit_fact_input_slot" and
         slot["draft_id"] === ctx.args["draft_id"] and
         slot["source_key"] === ctx.source["source_key"] and
         slot["catalog_sha256"] === ctx.catalog["sha256"] and
         slot["manifest"] === ctx.args["manifest"] and
         is_map(slot["page"]) and slot["page"]["ordinal"] === ctx.ordinal do
      fact_collect_next(%{
        state
        | ctx: %{ctx | pages: ctx.pages ++ [slot["page"]], ordinal: ctx.ordinal + 1}
      })
    else
      finish(state, refused(:fact_input_changed))
    end
  end

  defp advance(
         {:done, {:ok, %{"sources" => [source], "native_generation" => generation}}},
         %{phase: :fact_input_source} = state
       ) do
    args = state.ctx.args

    if IpseKnowledge.Store.Collection.Projection.fact_input_page?(
         source,
         args["page"],
         args["manifest"]
       ) do
      ctx = Map.merge(state.ctx, %{source: source, generation: generation})

      advance(
        CollectionStore.start(ctx.profile, :value_read_at, %{
          "key" => "catalog." <> ctx.profile["partition"],
          "generation" => generation
        }),
        %{state | phase: :fact_input_catalog, ctx: ctx}
      )
    else
      finish(state, refused(:invalid_fact_input_page))
    end
  end

  defp advance(
         {:done, {:ok, %{"record" => catalog, "native_generation" => generation}}},
         %{phase: :fact_input_catalog} = state
       )
       when is_map(catalog) do
    ctx = state.ctx
    key = "factdraft.#{ctx.profile["partition"]}.#{ctx.args["page"]["ordinal"]}"

    if generation === ctx.generation do
      advance(
        CollectionStore.start(ctx.profile, :value_read_at, %{
          "key" => key,
          "generation" => generation
        }),
        %{
          state
          | phase: :fact_input_slot,
            ctx: Map.merge(ctx, %{catalog: catalog, slot_key: key})
        }
      )
    else
      finish(state, refused(:fact_input_changed))
    end
  end

  defp advance(
         {:done, {:ok, %{"record" => row, "native_generation" => generation}}},
         %{phase: :fact_input_slot} = state
       ) do
    ctx = state.ctx
    revision = if is_nil(row), do: 0, else: row["revision"]

    if generation === ctx.generation and revision === ctx.args["expected_slot_revision"] do
      value = %{
        "version" => 1,
        "kind" => "explicit_fact_input_slot",
        "draft_id" => ctx.args["draft_id"],
        "source_key" => ctx.source["source_key"],
        "catalog_sha256" => ctx.catalog["sha256"],
        "manifest" => ctx.args["manifest"],
        "page" => ctx.args["page"]
      }

      advance(
        CollectionStore.start(ctx.profile, :fact_input_put_at, %{
          "key" => ctx.slot_key,
          "value" => value,
          "generation" => generation,
          "expected_revision" => revision
        }),
        %{state | phase: :fact_input_write}
      )
    else
      finish(state, refused(:fact_input_changed))
    end
  end

  defp advance({:done, {:ok, %{"record" => record}}}, %{phase: :fact_input_write} = state) do
    finish(
      state,
      output(
        "ok",
        [],
        [],
        [],
        %{
          "status" => "fact_input_staged",
          "slot" => record,
          "draft_id" => state.ctx.args["draft_id"],
          "ordinal" => state.ctx.args["page"]["ordinal"]
        },
        nil
      )
    )
  end

  defp advance(
         {:done, {:ok, %{"sources" => [source]}}},
         %{phase: :collection_fact_source} = state
       ) do
    case IpseKnowledge.Store.Collection.Projection.facts_from_spans(
           source,
           state.ctx.args["facts"]
         ) do
      {:ok, facts} ->
        args = state.ctx.args

        advance(
          CollectionStore.start(state.ctx.profile, :fact_store, %{
            "source_id" => args["source_id"],
            "selection" => %{"kind" => "explicit", "profile" => nil, "version" => 1},
            "facts" => facts,
            "expected_revision" => args["expected_revision"],
            "as_of_ms" => System.system_time(:millisecond),
            "continuation" => args["continuation"]
          }),
          %{state | phase: :collection_fact_stage}
        )

      _ ->
        finish(state, refused(:invalid_explicit_fact_spans))
    end
  end

  defp advance({:done, {:continue, value}}, %{phase: :collection_fact_stage} = state) do
    continuation = %{
      "id" => "generation_produce",
      "arguments" => Map.put(state.ctx.args, "continuation", value["continuation"])
    }

    finish(state, output("draft", [], [], [], Map.delete(value, "continuation"), continuation))
  end

  defp advance({:done, {:ok, value}}, %{phase: :collection_fact_stage} = state),
    do: finish(state, output("ok", [], [], [], value, nil))

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

  defp advance({:done, {:continue, value}}, %{phase: :collection_producer_append} = state) do
    continuation = %{
      "id" => "generation_produce",
      "arguments" => Map.put(state.ctx.args, "continuation", value["continuation"])
    }

    finish(state, output("draft", [], [], [], Map.delete(value, "continuation"), continuation))
  end

  defp advance({:done, {:ok, value}}, %{phase: :collection_producer_append} = state) do
    compact = IpseKnowledge.Store.Collection.Job.compact_result(value)
    finish(state, output("ok", [], [], [], compact, nil))
  end

  defp advance(
         {:done, {:ok, value}},
         %{phase: :collection_producer, ctx: %{args: %{"version" => 2} = args}} = state
       ) do
    continuation =
      case value["continuation"] do
        nil ->
          nil

        next ->
          %{"id" => "generation_produce", "arguments" => Map.put(next, "store", args["store"])}
      end

    finish(state, output("ok", [], [], [], Map.delete(value, "continuation"), continuation))
  end

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
      %{
        state
        | ctx:
            state.ctx
            |> Map.put(:document_generation, snapshot["native_generation"])
            |> Map.put(:document_sources, Enum.map(selected, & &1["source"]))
      },
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
          "action" => if(state.ctx.args["action"] == "abort", do: "abort", else: "next"),
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
        %{
          state
          | ctx:
              state.ctx
              |> Map.put(:document_generation, rank["native_generation"])
              |> Map.put(:document_sources, rank["selected_sources"])
              |> Map.put(:query_time_scope, :collection)
              |> Map.put(:query_time_transition, Map.get(rank, "query_time_transition", :missing))
        },
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
           Evidence.rank_lexical_with_table_context(
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
        %{
          state
          | ctx:
              state.ctx
              |> Map.put(:document_generation, snapshot["native_generation"])
              |> Map.put(:document_sources, snapshot["sources"])
              |> Map.put(:query_time_scope, :collection)
              |> Map.put(
                :query_time_transition,
                next_query_transition(
                  %{"sources" => snapshot["sources"], "projections" => %{}},
                  state.ctx.as_of_ms
                )
              )
        },
        output(rank["status"], rank["evidence"], rank["claims"], rank["gaps"], coverage, nil)
      )
    else
      {:error, code} -> finish(state, refused(code))
    end
  end

  defp advance({:done, {:ok, selected}}, %{phase: :collection_semantic_snapshot} = state) do
    snapshot = %{
      "sources" => Enum.map(selected["selected"], & &1["source"]),
      "projections" =>
        Map.new(
          selected["selected"],
          &{&1["source"]["source_key"], Map.take(&1, ~w(vectors facts))}
        )
    }

    advance(
      Adapters.start(state.resolved, :embedding_profile, %{
        "profile" => state.ctx.retrieval["embedding"]
      }),
      %{
        state
        | phase: :collection_semantic_profile,
          ctx:
            state.ctx
            |> Map.put(:snapshot, snapshot)
            |> Map.put(:selected_snapshot, selected)
            |> Map.put(:query_time_scope, :collection)
            |> Map.put(
              :query_time_transition,
              next_query_transition(snapshot, state.ctx.as_of_ms)
            )
      }
    )
  end

  defp advance({:done, {:ok, configured}}, %{phase: :collection_semantic_profile} = state) do
    selection = state.ctx.args["vector_selection"]

    if state.ctx[:query_time_scope] != :collection or not query_time_valid?(state) do
      finish(state, refused(:query_time_changed))
    else
      if configured["selection_sha256"] === selection["selection_sha256"] and
           configured["profile"]["id"] === selection["profile"] do
        query = state.ctx.args["query"]

        advance(
          Adapters.start(state.resolved, :embed, %{
            "profile" => state.ctx.retrieval["embedding"],
            "expected_selection_sha256" => selection["selection_sha256"],
            "inputs" => [
              %{
                "chunk_id" => Evidence.sha256("query:" <> query),
                "text" => Map.get(state.ctx.retrieval, "query_prefix", "") <> query
              }
            ]
          }),
          %{state | phase: :collection_semantic_embed}
        )
      else
        finish(state, refused(:incompatible_query_embedding))
      end
    end
  end

  defp advance({:done, {:ok, embedding}}, %{phase: :collection_semantic_embed} = state) do
    vector = hd(embedding["vectors"])
    ctx = Map.put(state.ctx, :query_vector, vector)
    state = %{state | ctx: ctx}

    with true <-
           Map.take(vector, ~w(selection_sha256 profile model dimensions encoding)) ===
             ctx.args["vector_selection"],
         {:ok, rank} <- semantic_rank(state) do
      advance(
        CollectionStore.start(ctx.store_profile, :value_read, %{
          "key" => "catalog." <> ctx.store_profile["partition"]
        }),
        %{state | phase: :collection_semantic_revalidate, ctx: Map.put(ctx, :rank, rank)}
      )
    else
      {:error, code} -> finish(state, refused(code))
      _ -> finish(state, refused(:incompatible_query_embedding))
    end
  end

  defp advance({:done, {:ok, checked}}, %{phase: :collection_semantic_revalidate} = state) do
    ctx = state.ctx
    selected = ctx.selected_snapshot
    at = ctx.args["as_of_ms"] || System.system_time(:millisecond)

    if checked["native_generation"] === selected["native_generation"] and
         checked["record"]["sha256"] === selected["catalog_sha256"] and
         Enum.all?(ctx.snapshot["sources"], &Evidence.current?(&1, at)) do
      rank = Evidence.query_scope(ctx.rank, ctx.snapshot["sources"], [], at)

      coverage =
        selected["coverage"]
        |> Map.merge(rank["coverage"])
        |> Map.merge(%{
          "scope" => "explicit_selected_sources",
          "generation" => selected["generation"],
          "catalog_sha256" => selected["catalog_sha256"],
          "as_of_ms" => at,
          "revalidated" => true,
          "query_embedding_calls" => 1,
          "effects_used" => 1,
          "embedding_profile_reads" => 1,
          "embedding_result_reads" => ctx.embedding_result_reads,
          "reads_used" =>
            selected["coverage"]["reads_used"] + checked["coverage"]["reads_used"] +
              ctx.embedding_result_reads + 1
        })

      {:ok, claims} = Evidence.classify(rank["evidence"], [], ctx.args["query"])

      finish(
        %{
          state
          | ctx:
              state.ctx
              |> Map.put(:document_generation, selected["native_generation"])
              |> Map.put(:document_sources, ctx.snapshot["sources"])
        },
        output(rank["status"], rank["evidence"], claims, rank["gaps"], coverage, nil)
      )
    else
      finish(state, output("conflict", [], [], [%{"code" => "snapshot_changed"}], %{}, nil))
    end
  end

  defp advance({:done, {:ok, checked}}, %{phase: phase} = state)
       when phase in [:document_use_collection, :document_use_store] do
    valid =
      if phase == :document_use_collection,
        do: checked["native_generation"] === state.ctx.document_generation,
        else:
          checked["valid"] === true and
            checked["store_generation"] === state.ctx.snapshot["coverage"]["generation"]

    sources =
      Map.get(state.ctx, :document_sources) || get_in(state.ctx, [:snapshot, "sources"]) || []

    at = state.ctx.args["as_of_ms"] || System.system_time(:millisecond)

    if phase === :document_use_store and valid and not query_time_valid?(state) do
      publish_result(state, refused(:query_time_changed))
    else
      if valid and Enum.all?(sources, &Evidence.current?(&1, at)) do
        value =
          update_in(state.ctx.document_use_result, ["coverage"], fn coverage ->
            Map.put(coverage, "workspace_store_revalidation", checked["coverage"])
          end)

        publish_result(state, value)
      else
        publish_result(
          state,
          output("conflict", [], [], [%{"code" => "snapshot_changed"}], %{}, nil)
        )
      end
    end
  end

  defp advance({:done, {:ok, value}}, %{phase: phase} = state)
       when phase in [:source, :collection_draft_abort] do
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
    ctx =
      state.ctx
      |> Map.put(:snapshot, snapshot)
      |> Map.put(:query_time_scope, :full)
      |> Map.put(:query_time_transition, next_query_transition(snapshot, state.ctx.as_of_ms))

    model_effects =
      if(ctx.retrieval["kind"] in ~w(dense hybrid), do: 1, else: 0) +
        if(is_map(ctx.rerank_profile) and ctx.rerank_profile["kind"] == "model_complete",
          do: 1,
          else: 0
        )

    read_allowance = if(ctx.retrieval["kind"] in ~w(dense hybrid), do: 8, else: 0)

    if query_plan?(snapshot, ctx.store_profile, model_effects, read_allowance),
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

    if query_plan?(snapshot, state.ctx.store_profile, model_effects, 0) do
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

          ctx =
            state.ctx
            |> Map.put(:snapshot, snapshot)
            |> Map.put(:rank, rank)
            |> Map.put(:query_time_scope, :remote_selected)
            |> Map.put(
              :query_time_transition,
              next_query_transition(snapshot, state.ctx.as_of_ms)
            )

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
    if checked["valid"] == true and
         checked["store_generation"] === state.ctx.snapshot["coverage"]["generation"] do
      if not query_time_valid?(state) do
        finish(state, refused(:query_time_changed))
      else
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

        finish(
          state,
          output(rank["status"], rank["evidence"], claims, rank["gaps"], coverage, nil)
        )
      end
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

      check_document_use(
        %{state | ctx: Map.put(ctx, :index_inputs, inputs)},
        %{"evidence" => [opened["source"]], "claims" => []},
        :index_embed
      )
    else
      _ -> finish(state, refused(:effect_budget))
    end
  end

  defp advance({:done, {:ok, embedded}}, %{phase: :index_embed} = state) do
    check_document_use(
      %{state | ctx: Map.put(state.ctx, :index_vectors, embedded["vectors"])},
      %{"evidence" => [state.ctx.opened["source"]], "claims" => []},
      :index_commit
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
        case Evidence.rank_lexical_with_table_context(
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
              %{
                "chunk_id" => Evidence.sha256("query:" <> args["query"]),
                "text" => Map.get(profile, "query_prefix", "") <> args["query"]
              }
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
    case semantic_rank(state) do
      {:ok, result} -> maybe_rerank(%{state | ctx: Map.put(state.ctx, :rank, result)})
      {:error, code} -> finish(state, refused(code))
      _ -> finish(state, refused(:invalid_evidence))
    end
  end

  defp semantic_rank(state) do
    snap = state.ctx.snapshot
    args = state.ctx.args

    {candidates, missing} =
      dense_candidates(snap, state.ctx.as_of_ms, state.ctx.query_vector, args["query"])

    policy = state.ctx.retrieval["missing_embedding"]

    dense =
      if missing == 0 or policy == "lexical_with_gap",
        do: Evidence.rank_cosine(candidates, state.ctx.query_vector, args["top_k"]),
        else: {:error, :missing_embedding}

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
      if query_time_valid?(state) do
        candidates = Enum.take(state.ctx.rank["evidence"], 16)
        check_document_use(state, %{"evidence" => candidates, "claims" => []}, :rerank)
      else
        finish(state, refused(:query_time_changed))
      end
    end
  end

  defp revalidate(state) do
    args = %{"tokens" => state.ctx.snapshot["tokens"]}
    budget = Map.get(state, :document_budget, %{effects: 0, reads: 0})
    counts = %{"effects_used" => budget.effects, "reads_used" => budget.reads}

    args = Map.merge(args, counts)

    advance(
      Store.start_fenced_revalidation(state.ctx.args["store"], state.ctx.store_profile, args),
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

  defp next_query_transition(snapshot, selected) do
    times =
      Enum.flat_map(snapshot["sources"], &[&1["observed_at_ms"], &1["expires_at_ms"]]) ++
        Enum.flat_map(all_facts(snapshot), &[&1["valid_from_ms"], &1["valid_to_ms"]])

    times |> Enum.filter(&(is_integer(&1) and &1 > selected)) |> Enum.min(fn -> nil end)
  end

  defp query_time_valid?(%{
         ctx: %{
           query_time_scope: scope,
           query_time_transition: transition,
           as_of_ms: selected,
           args: args
         }
       })
       when scope in [:full, :remote_selected, :collection] and is_integer(selected) and
              selected >= 0 and
              is_map(args) do
    now = System.system_time(:millisecond)

    valid_transition =
      is_nil(transition) or (Evidence.safe_uint?(transition) and transition > selected)

    valid_timestamp =
      Evidence.safe_uint?(selected) and Map.has_key?(args, "as_of_ms") and
        (args["as_of_ms"] === nil or args["as_of_ms"] === selected)

    valid_transition and valid_timestamp and
      (args["as_of_ms"] !== nil or
         (now >= selected and (is_nil(transition) or now < transition)))
  end

  defp query_time_valid?(_), do: false

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

  defp query_plan?(snapshot, profile, model_effects, read_allowance) do
    coverage = snapshot["coverage"]

    {fence_effects, fence_reads} =
      if snapshot["tokens"] === [] do
        if profile["kind"] === "state", do: {0, 1}, else: {1, 15}
      else
        {0, 0}
      end

    is_map(coverage) and is_integer(coverage["effects_used"]) and
      is_integer(coverage["revalidate_effects_worst_case"]) and
      coverage["effects_used"] + coverage["revalidate_effects_worst_case"] + model_effects +
        fence_effects <= 16 and
      is_integer(coverage["reads_used"]) and
      is_integer(coverage["revalidate_reads_worst_case"]) and
      coverage["reads_used"] + coverage["revalidate_reads_worst_case"] + read_allowance +
        fence_reads <= 512
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

        "abort_collection_draft" ->
          ~w(head_id kind)

        "fact_input" ->
          ~w(input)

        op
        when op in ~w(backup_status backup_page backup_plan restore_validate_page restore_open restore_page restore_commit restore_abort restore_rollback restore_checkpoint_drop) ->
          ~w(backup)

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

    (exact?(args, keys) and
       (keys != ["backup"] or backup_args?(action, args["backup"])) and
       (keys != ["input"] or fact_group_input?(args["input"]))) or
      (action == "open" and exact?(args, keys ++ ["historical_import"])) or
      (action == "continue_document" and exact?(args, keys ++ ["metadata_offset"]))
  end

  defp fact_group_input?(%{"version" => 1, "mode" => "publish", "value" => value} = input) do
    exact?(input, ~w(version mode value)) and exact?(value, ~w(version kind sources)) and
      value["version"] === 1 and value["kind"] === "explicit_fact_group" and
      is_list(value["sources"]) and length(value["sources"]) in 1..8 and
      Enum.all?(value["sources"], fn source ->
        exact?(source, ~w(source_key facts)) and Evidence.sha256?(source["source_key"]) and
          is_list(source["facts"]) and length(source["facts"]) <= 32 and
          Enum.all?(source["facts"], &fact_group_row?/1)
      end) and
      length(Enum.uniq_by(value["sources"], & &1["source_key"])) === length(value["sources"])
  end

  defp fact_group_input?(%{"version" => 1, "mode" => "begin"} = input),
    do:
      exact?(input, ~w(version mode vector_selection fact_selection continuation)) and
        IpseKnowledge.Store.Collection.Projection.valid_selection?(input["vector_selection"]) and
        input["vector_selection"]["dimensions"] === 1024 and
        input["fact_selection"] === %{"kind" => "explicit", "profile" => nil, "version" => 1} and
        (is_nil(input["continuation"]) or is_map(input["continuation"]))

  defp fact_group_input?(%{"version" => 1, "mode" => "assemble"} = input),
    do: exact?(input, ~w(version mode))

  defp fact_group_input?(%{"version" => 1, "mode" => "append"} = input) do
    producer = input["producer"]

    exact?(input, ~w(version mode producer continuation)) and
      exact?(
        producer,
        ~w(version action embedding job_id job_revision vector_selection fact_selection vector_cursor previous_ready)
      ) and
      producer["version"] === 2 and producer["action"] === "page" and
      (is_nil(input["continuation"]) or is_map(input["continuation"]))
  end

  defp fact_group_input?(_), do: false

  defp fact_group_row?(row) do
    exact?(row, ~w(subject predicate object polarity inferred valid_from_ms valid_to_ms spans)) and
      is_list(row["spans"]) and length(row["spans"]) in 1..8 and
      Enum.all?(row["spans"], fn
        [ordinal, start, finish] ->
          Enum.all?([ordinal, start, finish], &Evidence.safe_uint?/1) and start < finish

        _ ->
          false
      end)
  end

  defp backup_args?("backup_status", args), do: args === %{}

  defp backup_args?("backup_page", args),
    do:
      exact?(args, ~w(generation offset limit)) and Evidence.safe_uint?(args["generation"]) and
        Evidence.safe_uint?(args["offset"]) and args["offset"] <= 8192 and
        is_integer(args["limit"]) and args["limit"] in 1..8

  defp backup_args?("backup_plan", args),
    do: exact?(args, ~w(generation)) and Evidence.safe_uint?(args["generation"])

  defp backup_args?("restore_validate_page", args), do: args === %{}

  defp backup_args?("restore_" <> action, args) do
    extra =
      case action do
        "open" -> []
        "page" -> ~w(migration_id ordinal)
        "commit" -> ~w(migration_id)
        "abort" -> ~w(migration_id plan_binding_sha256)
        "rollback" -> ~w(checkpoint_id)
        "checkpoint_drop" -> ~w(checkpoint_id plan_binding_sha256)
        _ -> :invalid
      end

    is_list(extra) and exact?(args, ~w(expected_generation expected_epoch) ++ extra) and
      Evidence.safe_uint?(args["expected_generation"]) and
      Evidence.safe_uint?(args["expected_epoch"])
  end

  defp backup_args?(_, _), do: false

  defp source_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(store action args),
      "properties" => %{
        "store" => string(64),
        "action" => %{"type" => "string", "enum" => Map.keys(@source_actions)},
        "result_input" => %{"type" => "object"},
        "plan_input" => %{"type" => "object"},
        "data_inputs" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 8,
          "items" => %{"type" => "object"}
        },
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
      "input" => %{"type" => "object"},
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
      "head_id" => string(32),
      "kind" => %{"type" => "string", "enum" => ~w(source projection)},
      "offset" => integer(0, 65_536),
      "metadata_offset" => integer(0, 16_384),
      "cursor" => %{"type" => ["integer", "null"]},
      "limit" => integer(1, 12),
      "export" => %{"type" => "object"},
      "historical_import" => %{"type" => "object"},
      "collection_state" => %{"type" => "object"},
      "opening_acquisition" => %{"type" => "object"},
      "input_action" => %{"type" => "string", "enum" => ~w(put put_document)},
      "input_args" => %{"type" => "object"},
      "backup" => %{"type" => "object"}
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

      schema =
        if @preset == "collection-dense" do
          Map.update!(schema, "properties", fn properties ->
            Map.merge(properties, %{
              "vector_selection" => %{"type" => "object"},
              "fact_selection" => %{"type" => "object"}
            })
          end)
        else
          schema
        end

      [
        entry("query_selected", "Evidence", schema),
        entry(
          "generation_job",
          "Projection jobs",
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
              "response" => %{"type" => "string", "enum" => ~w(full compact_v1)},
              "guard_sources" => %{"type" => "boolean"}
            }
          }
        ),
        entry(
          "projection_selected",
          "Projections",
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
          "Lexical index",
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
      schema =
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ~w(store version action),
          "properties" => %{
            "store" => string(64),
            "version" => %{"type" => "integer", "enum" => [1, 2]},
            "action" => %{
              "type" => "string",
              "enum" =>
                ~w(page inspect selection facts facts_page facts_commit facts_slots append)
            },
            "embedding" => string(64),
            "job_id" => string(32),
            "job_revision" => integer(0, Evidence.safe_integer_max()),
            "vector_selection" => %{"type" => "object"},
            "fact_selection" => %{"type" => "object"},
            "vector_cursor" => integer(0, 248),
            "previous_ready" => %{"type" => ["object", "null"]},
            "source_id" => string(256),
            "expected_revision" => integer(0, Evidence.safe_integer_max()),
            "continuation" => %{"type" => ["object", "null"]},
            "facts" => %{"type" => "array", "maxItems" => 32, "items" => %{"type" => "object"}},
            "draft_id" => string(32),
            "manifest" => %{"type" => "object"},
            "page" => %{"type" => "object"},
            "expected_slot_revision" => integer(0, Evidence.safe_integer_max())
          }
        }

      [
        entry(
          "generation_produce",
          "Facts and vectors",
          schema
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

  defp snapshot_page_request?(request) do
    args = request["arguments"]

    exact?(request, ~w(op name timeout_ms arguments)) and request["op"] === "tool.call" and
      request["name"] === "read" and request["timeout_ms"] === 5_000 and
      exact?(args, ~w(snapshot path expected_sha256 snapshot_handle byte_offset)) and
      args["snapshot"] === "page" and text?(args["path"], 4096) and
      Evidence.sha256?(args["expected_sha256"]) and
      is_binary(args["snapshot_handle"]) and
      Regex.match?(~r/\A[0-9a-f]{32}\z/, args["snapshot_handle"]) and
      is_integer(args["byte_offset"]) and args["byte_offset"] in 0..1_048_575
  rescue
    _ -> false
  end

  defp call(request, state) do
    budget = Map.get(state, :document_budget, %{effects: 0, reads: 0, guarded: false})

    read =
      request["op"] in ~w(state.get state.list state.scan effect.result.read embedding.profile) or
        (request["op"] == "collection.store" and CollectionStore.read_request?(request)) or
        snapshot_page_request?(request)

    budget =
      if read,
        do: %{budget | reads: budget.reads + 1},
        else: %{budget | effects: budget.effects + 1}

    if budget.guarded and (budget.effects > 16 or budget.reads > 512) do
      publish_result(state, refused(:document_current_check_limit))
    else
      {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request},
       Map.put(state, :document_budget, budget)}
    end
  end

  defp job_result(%{ctx: %{args: %{"response" => "compact_v1"}}}, value),
    do: IpseKnowledge.Store.Collection.Job.compact_result(value)

  defp job_result(_, value), do: value

  defp finish(state, value), do: check_document_use(state, value, :publish)

  defp check_document_use(state, value, action) do
    citations =
      Enum.map(value["evidence"] || [], fn item ->
        if is_map(item), do: Map.get(item, "citation", item), else: %{}
      end) ++
        Enum.flat_map(value["claims"] || [], fn claim ->
          (claim["basis"] || []) ++ (claim["citations"] || [])
        end)

    refs = citations |> Enum.map(&document_use_ref/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    caps = Profiles.capabilities("corpus", get_in(state, [:resolved, "preset"]))
    budget = Map.get(state, :document_budget, %{effects: 0, reads: 0, guarded: false})

    cond do
      state[:collection_query] == true and value["status"] in ~w(ok partial abstain) and
          (state.ctx[:query_time_scope] != :collection or not query_time_valid?(state)) ->
        publish_result(state, refused(:query_time_changed))

      refs == [] ->
        document_use_complete(action, state, value, [])

      :invalid in refs ->
        publish_result(state, refused(:invalid_document_current_source))

      not is_list(caps) or "host.tools" not in caps ->
        publish_result(state, refused(:document_current_check_unavailable))

      budget.effects + length(refs) > 16 or budget.reads > 512 ->
        publish_result(state, refused(:document_current_check_limit))

      true ->
        guard = %{remaining: refs, checked: [], action: action, value: value}

        next_document_use(
          state
          |> Map.put(:document_budget, %{budget | guarded: true})
          |> Map.put(:ctx, Map.put(state.ctx || %{}, :document_use, guard))
        )
    end
  end

  defp document_use_ref(citation) do
    stored = get_in(citation, ["origin", "receipt"])

    receipt =
      if is_map(stored) and stored["version"] == 4,
        do: stored,
        else: Evidence.document_receipt(%{"origin" => %{"receipt" => stored}})

    case receipt do
      %{"acquisition" => %{"kind" => "workspace.read", "path" => path}} ->
        if workspace_path?(path) and Evidence.sha256?(receipt["original_sha256"]) and
             is_integer(receipt["original_bytes"]) and receipt["original_bytes"] in 1..1_048_576 do
          Map.take(receipt, ~w(original_sha256 original_bytes)) |> Map.put("path", path)
        else
          :invalid
        end

      %{"acquisition" => acquisition} when not is_nil(acquisition) ->
        :invalid

      _ ->
        nil
    end
  end

  defp next_document_use(%{ctx: %{document_use: %{remaining: [ref | tail]} = guard}} = state) do
    {request, phase} =
      if ref["original_bytes"] > 32_768 do
        {snapshot_request("verify", ref["path"], ref["original_sha256"]), :document_use_verify}
      else
        request = document_request(ref["path"], ref["original_sha256"])
        {put_in(request, ["arguments", "max_bytes"], 1), :document_use_check}
      end

    guard = Map.merge(guard, %{remaining: tail, current: ref})
    call(request, %{state | phase: phase, ctx: %{state.ctx | document_use: guard}})
  end

  defp next_document_use(%{ctx: %{document_use: %{remaining: []} = guard}} = state) do
    document_use_complete(
      guard.action,
      %{state | ctx: Map.delete(state.ctx, :document_use)},
      guard.value,
      Enum.reverse(guard.checked)
    )
  end

  defp document_use_verified(
         %{
           "operation_id" => operation,
           "outcome" => %{"status" => "ok", "value" => %{"text" => text}}
         },
         state
       ) do
    ref = state.ctx.document_use.current

    with true <- is_binary(operation) and Regex.match?(~r/\A[0-9a-f]{32}\z/, operation),
         true <- text?(text, 8192),
         value when is_map(value) <- JSON.decode!(text),
         true <- exact?(value, ~w(byte_count path sha256)),
         true <- value["path"] === ref["path"] and value["sha256"] === ref["original_sha256"],
         true <- value["byte_count"] === ref["original_bytes"] do
      checked = Map.put(ref, "operation_id", operation)
      guard = state.ctx.document_use
      guard = %{guard | checked: [checked | guard.checked]}
      next_document_use(%{state | ctx: %{state.ctx | document_use: guard}})
    else
      _ -> publish_result(state, refused(:document_source_changed_or_unavailable))
    end
  rescue
    _ -> publish_result(state, refused(:document_source_changed_or_unavailable))
  end

  defp document_use_verified(_, state),
    do: publish_result(state, refused(:document_source_changed_or_unavailable))

  defp document_use_checked(
         %{
           "operation_id" => operation,
           "outcome" => %{"status" => "ok", "value" => %{"text" => text}}
         },
         state
       ) do
    ref = state.ctx.document_use.current

    with true <- is_binary(operation) and Regex.match?(~r/\A[0-9a-f]{32}\z/, operation),
         true <- text?(text, 8192),
         value when is_map(value) <- JSON.decode!(text),
         true <-
           exact?(value, ~w(version encoding path byte_count sha256 data offset page_sha256 next)),
         true <- value["version"] === 2 and value["encoding"] == "base64",
         true <- value["path"] === ref["path"] and value["sha256"] === ref["original_sha256"],
         true <- value["byte_count"] === ref["original_bytes"] and value["offset"] === 0,
         {:ok, bytes} <- Base.decode64(value["data"]),
         true <- byte_size(bytes) == 1 and value["page_sha256"] == Evidence.sha256(bytes),
         true <- value["next"] === if(ref["original_bytes"] > 1, do: 1, else: nil) do
      checked = Map.put(ref, "operation_id", operation)
      guard = state.ctx.document_use
      guard = %{guard | checked: [checked | guard.checked]}
      next_document_use(%{state | ctx: %{state.ctx | document_use: guard}})
    else
      _ -> publish_result(state, refused(:document_source_changed_or_unavailable))
    end
  rescue
    _ -> publish_result(state, refused(:document_source_changed_or_unavailable))
  end

  defp document_use_checked(_, state),
    do: publish_result(state, refused(:document_source_changed_or_unavailable))

  defp document_use_complete(:publish, state, value, checks) do
    value =
      if checks == [],
        do: value,
        else:
          Map.update!(value, "coverage", fn coverage ->
            Map.merge(coverage, %{
              "workspace_file_check_scope" => "returned_evidence_and_claims",
              "workspace_file_checks" => checks,
              "workspace_file_check_effects" => length(checks)
            })
          end)

    cond do
      checks == [] ->
        publish_result(state, value)

      is_integer(state.ctx[:document_generation]) ->
        {:ok, profile} = Profiles.lookup(state.resolved, "stores", state.ctx.args["store"])

        advance(
          CollectionStore.start(profile, :value_read, %{
            "key" => "catalog." <> profile["partition"]
          }),
          %{
            state
            | phase: :document_use_collection,
              ctx: Map.put(state.ctx, :document_use_result, value)
          }
        )

      is_list(get_in(state.ctx, [:snapshot, "tokens"])) ->
        advance(
          Store.start_fenced_revalidation(
            state.ctx.args["store"],
            state.ctx.store_profile,
            %{
              "effects_used" => state.document_budget.effects,
              "reads_used" => state.document_budget.reads,
              "tokens" => state.ctx.snapshot["tokens"]
            }
          ),
          %{
            state
            | phase: :document_use_store,
              ctx: Map.put(state.ctx, :document_use_result, value)
          }
        )

      true ->
        publish_result(state, value)
    end
  end

  defp document_use_complete(:rerank, state, _, _) do
    if query_time_valid?(state) do
      advance(
        Adapters.start(state.resolved, :rerank, %{
          "profile" => state.ctx.args["rerank"],
          "query" => state.ctx.args["query"],
          "candidates" => Enum.take(state.ctx.rank["evidence"], 16)
        }),
        %{state | phase: :query_rerank}
      )
    else
      finish(state, refused(:query_time_changed))
    end
  end

  defp document_use_complete(:index_embed, state, _, _) do
    advance(
      Adapters.start(state.resolved, :embed, %{
        "profile" => state.ctx.args["embedding"],
        "inputs" => state.ctx.index_inputs
      }),
      %{state | phase: :index_embed}
    )
  end

  defp document_use_complete(:index_commit, state, _, _) do
    advance(
      Store.start(state.ctx.args["store"], state.ctx.store_profile, :projection_commit, %{
        "draft" => state.ctx.opened["draft"],
        "vectors" => state.ctx.index_vectors
      }),
      %{state | phase: :index_commit}
    )
  end

  defp publish_result(state, value) do
    value =
      if state[:collection_query] == true and
           value["status"] in ~w(ok partial abstain) and
           (get_in(state, [:ctx, :query_time_scope]) != :collection or
              not query_time_valid?(state)),
         do: refused(:query_time_changed),
         else: value

    value =
      if get_in(value, ["coverage", "workspace_file_checks"]) do
        budget = state.document_budget

        update_in(value, ["coverage"], fn coverage ->
          Map.merge(coverage, %{
            "workspace_invocation_effects" => budget.effects,
            "workspace_invocation_reads" => budget.reads
          })
        end)
      else
        value
      end

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
