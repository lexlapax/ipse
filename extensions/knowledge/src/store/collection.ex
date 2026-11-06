defmodule IpseKnowledge.Store.Collection do
  @moduledoc """
  Packed project source storage through the explicit host Collection grant.

  A put performs one bounded unit per explicit invocation. Immutable data blocks
  can be prepared before selection; three sealed metadata values switch the
  source head, catalog page and catalog head in one final CAS. Continuations
  contain bindings and refs, never source text. Unknown effects stop immediately.
  Selected reads authenticate the complete source bundle and catalog membership.
  Namespace lexical search uses the catalog-bound Index adapter. Graph/vector
  population, lifecycle collection and populated capacity remain separate work.
  """
  alias IpseKnowledge.Evidence, as: E
  alias Ipse.Extension.ResultDocument
  @sources 1000
  @catalog_rows 16
  @block_bytes 48 * 1024
  @bundle_bytes 1024 * 1024
  @reads 512
  @effects 16

  @doc "Read-only epoch observation; this supplies no publication authority."
  def snapshot_epoch(result) when is_map(result) do
    descriptor = result["document_store"]

    cond do
      not Map.has_key?(result, "document_store") or
          descriptor in [
            %{"version" => 1, "inline_bytes" => 8192},
            %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2}
          ] ->
        {:ok, 0, "idle"}

      is_map(descriptor) and
        exact?(
          descriptor,
          if(descriptor["version"] === 4,
            do:
              ~w(version inline_bytes write_parts maintenance_epoch maintenance_status progress),
            else: ~w(version inline_bytes write_parts maintenance_epoch maintenance_status)
          )
        ) and
        descriptor["version"] in [3, 4] and
        (descriptor["version"] === 3 or descriptor["progress"] === 1) and
        descriptor["inline_bytes"] === 8192 and
        descriptor["write_parts"] === 2 and E.safe_positive?(descriptor["maintenance_epoch"]) and
          descriptor["maintenance_status"] in ~w(idle active) ->
        {:ok, descriptor["maintenance_epoch"], descriptor["maintenance_status"]}

      true ->
        {:error, :document_epoch_changed}
    end
  end

  def snapshot_epoch(_), do: {:error, :document_epoch_changed}

  def progress_supported?(result) when is_map(result),
    do:
      match?({:ok, _, _}, snapshot_epoch(result)) and
        get_in(result, ["document_store", "version"]) === 4

  def progress_supported?(_), do: false

  @doc false
  def start_with_progress(profile, operation, args, epoch, tag) do
    if operation in [
         :value_put_inline_at,
         :fact_input_put_at,
         :value_write,
         :value_prepare,
         :value_commit_at,
         :fact_commit_at,
         :group_commit_at,
         :selection_commit_at,
         :value_commit,
         :progress_retire
       ] and E.safe_positive?(epoch) and progress_tag?(tag) do
      pending =
        if operation === :progress_retire do
          if tag["action"] === "retire" and profile?(profile) and
               exact?(args, ~w(generation)) and E.safe_uint?(args["generation"]) do
            call(
              %{
                operation: :progress_retire,
                generation: args["generation"],
                reads: 0,
                effects: 0,
                request: nil,
                maintenance_epoch: epoch,
                progress_tag: tag
              },
              Map.put(args, "op", "progress.retire"),
              :values_committed_at
            )
          else
            error(:invalid_collection_progress)
          end
        else
          start_with_epoch(profile, operation, args, epoch)
        end

      case pending do
        {:call, _, _} = pending ->
          if tag["action"] === "start" do
            dispatch_progress(pending, tag, nil)
          else
            call(
              %{
                operation: :progress_gate,
                reads: 0,
                effects: 0,
                request: nil,
                pending: pending,
                progress_tag: tag,
                maintenance_epoch: epoch
              },
              %{"op" => "progress.inspect", "head_id" => tag["head_id"]},
              :progress_gate
            )
          end

        other ->
          other
      end
    else
      error(:invalid_collection_progress)
    end
  end

  @doc "Primitive I/O with an explicitly frozen epoch condition, never a refreshed observation."
  def start_with_epoch(profile, operation, args, epoch)
      when operation in [
             :snapshot,
             :value_read,
             :value_read_at,
             :value_read_ref_at,
             :value_put_inline_at,
             :fact_input_put_at,
             :value_write,
             :value_prepare,
             :object_read,
             :value_commit_at,
             :fact_commit_at,
             :group_commit_at,
             :selection_commit_at,
             :value_commit,
             :stage_inspect,
             :value_stat,
             :value_layout,
             :value_read_chunk,
             :backup_metadata,
             :page_read,
             :selected_keys,
             :lexical_keys,
             :source_keys,
             :progress_inspect,
             :progress_retire
           ] do
    if E.safe_uint?(epoch) do
      case start(profile, operation, args) do
        {:call, request, %{request: _} = state} ->
          request = epoch_request(request, epoch)

          if host_frame_fits?(request),
            do:
              {:call, request,
               state |> Map.put(:maintenance_epoch, epoch) |> Map.put(:request, request)},
            else: error(:collection_budget)

        {:call, _, _} ->
          error(:invalid_collection_epoch_operation)

        other ->
          other
      end
    else
      error(:invalid_collection_epoch)
    end
  end

  def start_with_epoch(_, _, _, _), do: error(:invalid_collection_epoch_operation)

  def start(profile, :progress_inspect, %{"head_id" => id} = args) do
    if profile?(profile) and exact?(args, ~w(head_id)) and native_id?(id),
      do:
        call(
          %{operation: :progress_inspect, reads: 0, effects: 0, request: nil},
          Map.put(args, "op", "progress.inspect"),
          :progress_inspected
        ),
      else: error(:invalid_collection_progress)
  end

  def start(profile, :progress_retire, %{"generation" => generation} = args) do
    if profile?(profile) and exact?(args, ~w(generation)) and E.safe_uint?(generation),
      do:
        call(
          %{
            operation: :progress_retire,
            generation: generation,
            reads: 0,
            effects: 0,
            request: nil
          },
          Map.put(args, "op", "progress.retire"),
          :values_committed_at
        ),
      else: error(:invalid_collection_progress)
  end

  def start(profile, :snapshot, args) do
    if profile?(profile) and args === %{} do
      call(
        %{operation: :snapshot, reads: 0, effects: 0, request: nil},
        %{"op" => "snapshot"},
        :snapshot
      )
    else
      error(:invalid_collection_snapshot)
    end
  end

  def start(profile, :progress_abort, args) do
    if profile?(profile) and exact?(args, ~w(head_id kind)) and
         native_id?(args["head_id"]) and args["kind"] in ~w(source projection) do
      call(
        %{
          operation: :progress_abort,
          reads: 0,
          effects: 0,
          request: nil,
          head_id: args["head_id"],
          kind: args["kind"],
          cleanup_operations: 0
        },
        %{"op" => "snapshot"},
        :draft_abort_boot
      )
    else
      error(:invalid_collection_draft_abort)
    end
  end

  def start(profile, :generation_selected, args),
    do: IpseKnowledge.Store.Collection.Selected.start(profile, args)

  @doc false
  def start(profile, :backup_page, args), do: backup_start(profile, :page, args)

  @doc false
  def start(profile, :backup_plan, args) do
    if profile?(profile) and exact?(args, ~w(generation data_inputs)) and
         E.safe_uint?(args["generation"]) and is_list(args["data_inputs"]) and
         length(args["data_inputs"]) in 1..4 and
         Enum.all?(args["data_inputs"], &backup_result_ref?/1) and
         length(Enum.uniq(args["data_inputs"])) === length(args["data_inputs"]) do
      state = %{
        profile: profile,
        generation: args["generation"],
        inputs: args["data_inputs"],
        pages: [],
        descriptor: nil,
        rows: [],
        operations: [],
        lineage: [],
        section: "records",
        reads: 0
      }

      backup_plan_metadata(state, 0)
    else
      error(:invalid_collection_backup_plan)
    end
  end

  @doc false
  def start(profile, :selected_backup_result, args) do
    if profile?(profile) and exact?(args, ~w(result_input plan_input)) and
         backup_result_ref?(args["result_input"]) and
         (is_nil(args["plan_input"]) or backup_result_ref?(args["plan_input"])) do
      state = %{
        profile: profile,
        result_input: args["result_input"],
        plan_input: args["plan_input"],
        bytes: "",
        origin: :unset,
        reads: 0
      }

      backup_read_input(state)
    else
      error(:invalid_collection_result_input)
    end
  end

  @doc false
  def start(profile, :selected_fact_result, args) do
    if profile?(profile) and exact?(args, ~w(result_input)) and
         backup_result_ref?(args["result_input"]) do
      backup_read_input(%{
        profile: profile,
        result_input: args["result_input"],
        plan_input: nil,
        bytes: "",
        origin: :unset,
        owner: :unset,
        kind: :fact,
        reads: 0
      })
    else
      error(:invalid_collection_result_input)
    end
  end

  @doc false
  def start(profile, :validate_backup_page, args) do
    if profile?(profile) and exact?(args, ~w(result_input plan_input)) and
         backup_result_ref?(args["result_input"]) and backup_result_ref?(args["plan_input"]) do
      state = %{
        profile: profile,
        selected: args["result_input"],
        plan_ref: args["plan_input"],
        plan: nil,
        inputs: [],
        pages: [],
        phase: :plan,
        reads: 0
      }

      backup_validation_read(state, state.plan_ref, nil)
    else
      error(:invalid_collection_result_input)
    end
  end

  def start(profile, :generation_job, args),
    do: IpseKnowledge.Store.Collection.Job.start(profile, args)

  @doc false
  def start(profile, :guarded_generation_append, args),
    do: IpseKnowledge.Store.Collection.Job.start(profile, args, true)

  @doc false
  def start(profile, :guarded_generation_finalize, args),
    do: IpseKnowledge.Store.Collection.Job.start(profile, args, :selection)

  @doc false
  def start(profile, :value_read, %{"key" => key} = args) do
    if profile?(profile) and value_key?(key) and exact?(args, ~w(key)),
      do:
        call(
          %{
            operation: :value_read,
            profile: profile,
            key: key,
            reads: 0,
            effects: 0,
            generation: nil,
            request: nil
          },
          %{"op" => "snapshot"},
          :value_boot
        ),
      else: error(:invalid_collection_value)
  end

  @doc false
  def start(profile, :value_read_at, %{"key" => key, "generation" => generation} = args) do
    if profile?(profile) and value_key?(key) and exact?(args, ~w(key generation)) and
         E.safe_uint?(generation) do
      fetch(
        %{
          operation: :value_read,
          profile: profile,
          key: key,
          reads: 0,
          effects: 0,
          generation: generation,
          request: nil
        },
        key,
        :value
      )
    else
      error(:invalid_collection_value)
    end
  end

  @doc false
  def start(
        profile,
        :value_read_ref_at,
        %{"key" => key, "sha256" => sha, "generation" => generation} = args
      ) do
    if profile?(profile) and value_key?(key) and E.sha256?(sha) and
         exact?(args, ~w(key sha256 generation)) and E.safe_uint?(generation) do
      fetch_ref(
        %{
          operation: :value_read,
          profile: profile,
          key: key,
          reads: 0,
          effects: 0,
          generation: generation,
          request: nil
        },
        %{"key" => key, "sha256" => sha},
        :value
      )
    else
      error(:invalid_collection_value)
    end
  end

  @doc false
  def start(profile, :value_put_inline_at, args) do
    with true <- profile?(profile),
         true <- exact?(args, ~w(key value expected_revision generation)),
         true <- value_key?(args["key"]) and is_map(args["value"]),
         true <- E.safe_uint?(args["expected_revision"]) and E.safe_uint?(args["generation"]),
         bytes = json(args["value"]),
         true <- byte_size(bytes) in 2..8192,
         s = %{
           operation: :value_write,
           pinned_inline: true,
           generation: args["generation"],
           reads: 0,
           effects: 0,
           request: nil
         },
         request = inline_request(s, args["key"], bytes, args["expected_revision"], nil),
         true <- frame_fits?(request) do
      call(s, request, :inline_published)
    else
      _ -> error(:invalid_collection_value)
    end
  rescue
    _ -> error(:invalid_collection_value)
  end

  @doc false
  def start(profile, :fact_input_put_at, args) do
    with true <- profile?(profile),
         true <- exact?(args, ~w(key value expected_revision generation)),
         true <- value_key?(args["key"]) and is_map(args["value"]),
         true <- E.safe_uint?(args["expected_revision"]) and E.safe_uint?(args["generation"]),
         bytes = json(args["value"]),
         true <- byte_size(bytes) in 2..8192,
         s = %{
           operation: :value_write,
           pinned_inline: true,
           generation: args["generation"],
           reads: 0,
           effects: 0,
           request: nil,
           source_guard: "explicit_fact_input_v1"
         },
         request = inline_request(s, args["key"], bytes, args["expected_revision"], nil),
         true <- frame_fits?(request) do
      call(s, request, :inline_published)
    else
      _ -> error(:invalid_collection_value)
    end
  rescue
    _ -> error(:invalid_collection_value)
  end

  @doc false
  def start(profile, operation, args) when operation in [:value_write, :value_prepare] do
    with true <- profile?(profile),
         true <-
           exact?(
             Map.drop(args, ~w(reads_used effects_used)),
             ~w(key value expected_revision reuse continuation)
           ),
         true <- value_key?(args["key"]) and is_map(args["value"]),
         true <- E.safe_uint?(args["expected_revision"]) and is_boolean(args["reuse"]),
         true <-
           Map.get(args, "reads_used", 0) in 0..512 and Map.get(args, "effects_used", 0) in 0..16,
         bytes = json(args["value"]),
         true <- byte_size(bytes) <= @block_bytes,
         hash = E.sha256(bytes),
         checkpoint =
           args["continuation"] ||
             %{
               "version" => 1,
               "key" => args["key"],
               "sha256" => hash,
               "expected_revision" => args["expected_revision"],
               "active" => nil
             },
         true <- exact?(checkpoint, ~w(version key sha256 expected_revision active)),
         true <-
           checkpoint["version"] === 1 and checkpoint["key"] == args["key"] and
             checkpoint["sha256"] == hash and
             checkpoint["expected_revision"] == args["expected_revision"] do
      call(
        %{
          operation: operation,
          profile: profile,
          args: args,
          key: args["key"],
          value: args["value"],
          bytes: bytes,
          checkpoint: checkpoint,
          reads: Map.get(args, "reads_used", 0),
          effects: Map.get(args, "effects_used", 0),
          generation: nil,
          request: nil
        },
        %{"op" => "snapshot"},
        :value_boot
      )
    else
      _ -> error(:invalid_collection_value)
    end
  rescue
    _ -> error(:invalid_collection_value)
  end

  @doc false
  def start(profile, :object_read, args) do
    with true <- profile?(profile),
         true <- exact?(Map.delete(args, "revision"), ~w(key sha256 byte_count generation)),
         true <- value_key?(args["key"]) and E.sha256?(args["sha256"]),
         true <- is_integer(args["byte_count"]) and args["byte_count"] in 2..61_440,
         true <- E.safe_uint?(args["generation"]),
         true <-
           not Map.has_key?(args, "revision") or
             (E.safe_uint?(args["revision"]) and args["revision"] > 0 and
                args["revision"] <= args["generation"]) do
      call(
        %{
          operation: :object_read,
          profile: profile,
          ref: args,
          generation: args["generation"],
          bundle: "",
          reads: 0,
          effects: 0,
          request: nil
        },
        %{
          "op" => "value.read",
          "key" => args["key"],
          "offset" => 0,
          "generation" => args["generation"]
        },
        :object
      )
    else
      _ -> error(:invalid_collection_object)
    end
  end

  @doc false
  def start(profile, :value_commit_at, %{"stages" => stages, "generation" => generation} = args) do
    if profile?(profile) and exact?(args, ~w(stages generation)) and is_list(stages) and
         length(stages) in 1..8 and E.safe_uint?(generation) do
      call(
        %{operation: :value_commit, generation: generation, reads: 0, effects: 0, request: nil},
        %{"op" => "commit", "stages" => stages, "generation" => generation},
        :values_committed_at
      )
    else
      error(:invalid_collection_commit)
    end
  end

  @doc false
  def start(profile, :fact_commit_at, %{"stages" => stages, "generation" => generation} = args) do
    if profile?(profile) and exact?(args, ~w(stages generation)) and is_list(stages) and
         length(stages) === 2 and E.safe_uint?(generation) do
      call(
        %{
          operation: :value_commit,
          generation: generation,
          reads: 0,
          effects: 0,
          request: nil,
          source_guard: "explicit_fact_projection_v1"
        },
        %{"op" => "commit", "stages" => stages, "generation" => generation},
        :values_committed_at
      )
    else
      error(:invalid_collection_commit)
    end
  end

  @doc false
  def start(profile, :group_commit_at, %{"stages" => stages, "generation" => generation} = args) do
    if profile?(profile) and exact?(args, ~w(stages generation)) and is_list(stages) and
         length(stages) === 2 and E.safe_uint?(generation) do
      call(
        %{
          operation: :value_commit,
          generation: generation,
          reads: 0,
          effects: 0,
          request: nil,
          source_guard: "explicit_fact_group_v1"
        },
        %{"op" => "commit", "stages" => stages, "generation" => generation},
        :values_committed_at
      )
    else
      error(:invalid_collection_commit)
    end
  end

  @doc false
  def start(
        profile,
        :selection_commit_at,
        %{"stages" => stages, "generation" => generation} = args
      ) do
    if profile?(profile) and exact?(args, ~w(stages generation)) and is_list(stages) and
         length(stages) === 3 and E.safe_uint?(generation) do
      call(
        %{
          operation: :value_commit,
          generation: generation,
          reads: 0,
          effects: 0,
          request: nil,
          source_guard: "explicit_generation_selection_v1"
        },
        %{"op" => "commit", "stages" => stages, "generation" => generation},
        :values_committed_at
      )
    else
      error(:invalid_collection_commit)
    end
  end

  @doc false
  def start(profile, :value_commit, %{"stages" => stages}) do
    if profile?(profile) and is_list(stages) and length(stages) in 1..8,
      do:
        call(
          %{
            operation: :value_commit,
            profile: profile,
            stages: stages,
            generation: nil,
            reads: 0,
            effects: 0,
            request: nil
          },
          %{"op" => "snapshot"},
          :commit_boot
        ),
      else: error(:invalid_collection_commit)
  end

  def start(profile, :stage_inspect, %{"ref" => ref}) do
    if profile?(profile) and exact?(ref, ~w(slot epoch)),
      do:
        call(
          %{
            operation: :stage_inspect,
            profile: profile,
            ref: ref,
            generation: nil,
            reads: 0,
            effects: 0,
            request: nil
          },
          %{"op" => "snapshot"},
          :inspect_boot
        ),
      else: error(:invalid_collection_stage)
  end

  def start(profile, :value_stat, %{"key" => key, "generation" => generation}) do
    if profile?(profile) and value_key?(key) and E.safe_uint?(generation),
      do:
        call(
          %{
            operation: :value_stat,
            profile: profile,
            key: key,
            generation: generation,
            reads: 0,
            effects: 0,
            request: nil
          },
          %{"op" => "value.stat", "key" => key, "generation" => generation},
          :value_statted
        ),
      else: error(:invalid_collection_value)
  end

  @doc false
  def start(profile, :value_layout, %{"key" => key, "generation" => generation} = args) do
    if profile?(profile) and exact?(args, ~w(key generation)) and value_key?(key) and
         E.safe_uint?(generation) do
      call(
        %{
          operation: :value_layout,
          profile: profile,
          key: key,
          generation: generation,
          reads: 0,
          effects: 0,
          request: nil
        },
        %{"op" => "value.layout", "key" => key, "generation" => generation},
        :value_layout
      )
    else
      error(:invalid_collection_value)
    end
  end

  @doc false
  def start(
        profile,
        :value_read_chunk,
        %{"key" => key, "generation" => generation, "offset" => offset} = args
      ) do
    if profile?(profile) and exact?(args, ~w(key generation offset)) and value_key?(key) and
         E.safe_uint?(generation) and E.safe_uint?(offset) do
      call(
        %{
          operation: :value_read_chunk,
          profile: profile,
          key: key,
          generation: generation,
          offset: offset,
          reads: 0,
          effects: 0,
          request: nil
        },
        %{"op" => "value.read", "key" => key, "generation" => generation, "offset" => offset},
        :value_read_chunk
      )
    else
      error(:invalid_collection_value)
    end
  end

  @doc false
  def start(profile, :backup_metadata, args) do
    if profile?(profile) and exact?(args, ~w(generation section offset limit)) and
         E.safe_uint?(args["generation"]) and args["section"] in ~w(records operations lineage) and
         E.safe_uint?(args["offset"]) and args["offset"] <= 32_768 and
         is_integer(args["limit"]) and args["limit"] in 1..8 do
      call(
        %{
          operation: :backup_metadata,
          profile: profile,
          generation: args["generation"],
          section: args["section"],
          offset: args["offset"],
          reads: 0,
          effects: 0,
          request: nil
        },
        Map.put(args, "op", "backup.metadata"),
        :backup_metadata
      )
    else
      error(:invalid_collection_backup_metadata)
    end
  end

  @doc false
  def start(profile, :result_input_read, args) do
    with true <- profile?(profile) and exact?(args, ~w(result_input plan_input offset)),
         ref = args["result_input"],
         true <- backup_result_ref?(ref),
         true <- is_nil(args["plan_input"]) or backup_result_ref?(args["plan_input"]),
         true <- E.safe_uint?(args["offset"]) and args["offset"] < ref["delivery"]["byte_count"],
         request = %{
           "op" => "collection.store",
           "scope" => "project",
           "request" => %{"op" => "restore.input.read", "offset" => args["offset"]},
           "result_input" => ref
         },
         request =
           if(is_nil(args["plan_input"]),
             do: request,
             else: Map.put(request, "plan_input", args["plan_input"])
           ),
         true <- host_frame_fits?(request) do
      {:call, request,
       %{
         operation: :result_input_read,
         request: request,
         ref: ref,
         offset: args["offset"],
         reads: 1,
         effects: 0
       }}
    else
      _ -> error(:invalid_collection_result_input)
    end
  end

  @doc false
  def start(profile, :fact_result_input_read, args) do
    case start(profile, :result_input_read, args) do
      {:call, request, state} -> {:call, request, Map.put(state, :owner_result, true)}
      other -> other
    end
  end

  @doc false
  def start(profile, :restore_mutation, args) do
    with true <- profile?(profile) and exact?(args, ~w(request result_input plan_input)),
         inner when is_map(inner) <- args["request"],
         true <- backup_restore_request?(inner, args["result_input"], args["plan_input"]),
         request = %{"op" => "collection.store", "scope" => "project", "request" => inner},
         request =
           if(is_nil(args["result_input"]),
             do: request,
             else: Map.put(request, "result_input", args["result_input"])
           ),
         request =
           if(is_nil(args["plan_input"]),
             do: request,
             else: Map.put(request, "plan_input", args["plan_input"])
           ),
         true <- host_frame_fits?(request) do
      {:call, request,
       %{
         operation: :restore_mutation,
         request: request,
         inner_request: inner,
         reads: 0,
         effects: 1
       }}
    else
      _ -> error(:invalid_collection_restore)
    end
  end

  @doc false
  def start(profile, :restore_action, args) do
    with true <- profile?(profile) and exact?(args, ~w(action args result_input plan_input)),
         action when action in ~w(open page commit abort rollback checkpoint_drop) <-
           args["action"],
         params when is_map(params) <- args["args"],
         true <-
           backup_restore_action_args?(action, params, args["result_input"], args["plan_input"]),
         {:ok, empty_union} <- Ipse.Extension.canonical_digest([[]]),
         plan_ref = if(action === "open", do: args["result_input"], else: args["plan_input"]),
         {:ok, binding} <- backup_restore_binding(plan_ref, params),
         state = %{
           profile: profile,
           action: action,
           args: params,
           result_input: args["result_input"],
           plan_input: args["plan_input"],
           plan_binding: binding,
           empty_union: empty_union,
           reads: 0,
           effects: 0,
           phase: :input
         } do
      if action in ~w(open page) do
        backup_restore_action_advance(
          start(profile, :selected_backup_result, %{
            "result_input" => args["result_input"],
            "plan_input" => if(action === "page", do: args["plan_input"], else: nil)
          }),
          state
        )
      else
        backup_restore_issue(state, nil)
      end
    else
      _ -> error(:invalid_collection_restore)
    end
  end

  @doc false
  def start(profile, :page_read, args) do
    ref = args["ref"]

    with true <- profile?(profile),
         true <- exact?(Map.drop(args, ["generation"]), ["ref"]),
         true <- not Map.has_key?(args, "generation") or E.safe_uint?(args["generation"]),
         true <- exact?(ref, ~w(key object_sha256 offset byte_count sha256)),
         true <-
           value_key?(ref["key"]) and E.sha256?(ref["object_sha256"]) and E.sha256?(ref["sha256"]),
         true <-
           E.safe_uint?(ref["offset"]) and is_integer(ref["byte_count"]) and
             ref["byte_count"] in 2..6144 do
      state = %{
        operation: :page_read,
        profile: profile,
        ref: ref,
        reads: 0,
        effects: 0,
        generation: nil,
        request: nil
      }

      if Map.has_key?(args, "generation") and E.safe_uint?(args["generation"]),
        do:
          next(Map.merge(state, %{generation: args["generation"], phase: :page_boot}), %{
            "generation" => args["generation"]
          }),
        else: call(state, %{"op" => "snapshot"}, :page_boot)
    else
      _ -> error(:invalid_collection_page)
    end
  end

  def start(profile, operation, args) when operation in [:lexical_build, :lexical_query],
    do: IpseKnowledge.Store.Collection.Index.start(profile, operation, args)

  def start(profile, operation, args)
      when operation in [:vector_store, :vector_selected, :fact_store, :fact_selected],
      do: IpseKnowledge.Store.Collection.Projection.start(profile, operation, args)

  def start(profile, :put, args) do
    with true <- profile?(profile),
         true <-
           exact?(
             Map.drop(args, ~w(effects_used reads_used)),
             ~w(source expected_revision continuation)
           ),
         true <-
           Map.get(args, "effects_used", 0) in 0..16 and Map.get(args, "reads_used", 0) in 0..512,
         true <- E.safe_uint?(args["expected_revision"]),
         {:ok, source} <- E.collection_source(args["source"]),
         true <- source["partition"] == profile["partition"],
         {:ok, chunks} <- E.chunks(source),
         bytes = json(source),
         true <- byte_size(bytes) <= @bundle_bytes,
         plan = E.sha256(bytes),
         blocks = blocks(bytes, plan),
         true <- length(blocks) in 1..32,
         {:ok, lexical} <- E.lexical_run(source),
         lexical_bytes = json(lexical),
         true <- byte_size(lexical_bytes) <= 4 * @bundle_bytes,
         lexical_hash = E.sha256(lexical_bytes),
         lexical_blocks = lexical_blocks(lexical_bytes, lexical_hash, plan),
         true <- length(lexical_blocks) in 1..128,
         true <- checkpoint?(args["continuation"], plan, args["expected_revision"]) do
      checkpoint =
        args["continuation"] ||
          %{
            "version" => 3,
            "plan_sha256" => plan,
            "expected_revision" => args["expected_revision"],
            "unit" => 0,
            "stages" => [],
            "base" => nil,
            "active" => nil
          }

      state = %{
        operation: :put,
        profile: profile,
        source: source,
        chunks: length(chunks),
        blocks: blocks,
        prepared: blocks ++ lexical_blocks,
        lexical_bytes: byte_size(lexical_bytes),
        lexical_hash: lexical_hash,
        lexical_blocks: lexical_blocks,
        bytes: byte_size(bytes),
        source_sha256: plan,
        checkpoint: checkpoint,
        continuing: is_map(args["continuation"]),
        reads: Map.get(args, "reads_used", 0),
        effects: Map.get(args, "effects_used", 0),
        phase: :boot,
        generation: nil,
        request: nil
      }

      call(state, %{"op" => "snapshot"}, :boot)
    else
      _ -> error(:invalid_collection_source)
    end
  rescue
    _ -> error(:invalid_collection_source)
  end

  def start(profile, operation, args)
      when operation in [
             :selected,
             :lexical,
             :selected_keys,
             :lexical_keys,
             :source_keys,
             :source_bundles,
             :source_bundles_bound
           ] do
    keys =
      operation in [
        :selected_keys,
        :lexical_keys,
        :source_keys,
        :source_bundles,
        :source_bundles_bound
      ]

    field = if keys, do: "source_keys", else: "source_ids"

    with true <- profile?(profile),
         true <-
           exact?(Map.drop(args, ~w(head_hashes generation catalog_record)), [field, "as_of_ms"]),
         true <- is_list(args[field]) and length(args[field]) in 1..8,
         true <- length(Enum.uniq(args[field])) == length(args[field]),
         true <- Enum.all?(args[field], &(is_binary(&1) and byte_size(&1) in 1..512)),
         true <- not keys or Enum.all?(args[field], &E.sha256?/1),
         true <-
           if(operation == :source_bundles_bound,
             do:
               is_map(args["head_hashes"]) and E.safe_uint?(args["generation"]) and
                 Enum.sort(Map.keys(args["head_hashes"])) == Enum.sort(args[field]) and
                 Enum.all?(Map.values(args["head_hashes"]), &E.sha256?/1) and
                 bound_catalog?(args["catalog_record"], profile, args["generation"]),
             else:
               Enum.all?(~w(head_hashes generation catalog_record), &(not Map.has_key?(args, &1)))
           ),
         true <- E.safe_uint?(args["as_of_ms"]) do
      state = %{
        operation: :selected,
        read_mode:
          cond do
            operation in [:lexical, :lexical_keys] -> :lexical
            operation == :source_keys -> :source
            operation in [:source_bundles, :source_bundles_bound] -> :bundles
            true -> :selected
          end,
        key_mode: keys,
        profile: profile,
        args: args,
        reads: 0,
        effects: 0,
        phase: :boot,
        generation: if(operation == :source_bundles_bound, do: args["generation"], else: nil),
        request: nil,
        selected: [],
        selected_pages: %{},
        bound_heads: if(operation == :source_bundles_bound, do: [], else: nil),
        bound_hashes: if(operation == :source_bundles_bound, do: args["head_hashes"], else: nil),
        remaining: args[field]
      }

      if operation == :source_bundles_bound,
        do:
          select_next(
            Map.merge(state, %{
              catalog: args["catalog_record"]["value"],
              catalog_stamp: stamp(args["catalog_record"])
            })
          ),
        else: call(state, %{"op" => "snapshot"}, :boot)
    else
      _ -> error(:invalid_collection_selection)
    end
  end

  def start(_, _, _), do: error(:unsupported_collection_operation)

  defp bound_catalog?(row, profile, generation) do
    exact?(row, ~w(revision sha256 byte_count value)) and catalog?(row["value"], profile) and
      E.safe_uint?(row["revision"]) and row["revision"] in 1..generation and
      row["sha256"] === E.sha256(json(row["value"])) and
      row["byte_count"] === byte_size(json(row["value"]))
  rescue
    _ -> false
  end

  @doc false
  def valid_catalog?(catalog, profile), do: catalog?(catalog, profile)
  @doc false
  def valid_catalog_page?(row, ref, ordinal, profile), do: valid_page?(row, ref, ordinal, profile)
  @doc false
  def valid_source_head?(head, key), do: source_head?(head, key)
  @doc false
  def planned_source_head(%{operation: :put} = plan, ordinal) do
    with true <- is_integer(ordinal) and ordinal in 0..999,
         head = new_head(Map.put(plan, :ordinal, ordinal)),
         true <- source_head?(head, plan.source["source_key"]) do
      {:ok, head}
    else
      _ -> {:error, :invalid_source_storage_plan}
    end
  rescue
    _ -> {:error, :invalid_source_storage_plan}
  end

  @doc false
  def read_request?(%{"op" => "collection.store", "request" => %{"op" => op}}),
    do:
      op in ~w(snapshot value.stat value.layout value.read backup.metadata restore.input.read stage.list stage.inspect stage.available progress.inspect)

  def read_request?(_), do: false

  def resume(%{backup_state: _} = state, outcome), do: backup_resume(state, outcome)

  def resume(%{backup_plan_state: state, inner: inner}, outcome),
    do: backup_plan_advance(resume(inner, outcome), state)

  def resume(%{backup_validation_state: state, inner: inner}, outcome),
    do: backup_validation_advance(resume(inner, outcome), state)

  def resume(%{backup_restore_state: state, inner: inner}, outcome),
    do: backup_restore_action_advance(resume(inner, outcome), state)

  def resume(%{backup_input_state: state, inner: inner}, outcome),
    do: backup_input_advance(resume(inner, outcome), state)

  def resume(%{generation_job: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Job.resume(state, outcome)

  def resume(%{shared_selected: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Selected.resume(state, outcome)

  def resume(%{projection_state: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Projection.resume(state, outcome)

  def resume(%{index_state: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Index.resume(state, outcome)

  def resume(_, %{"status" => "unknown"}), do: {:stop, :unknown_effect}

  def resume(%{operation: :progress_abort} = state, %{"status" => status})
      when status != "ok",
      do:
        error(
          if(state.cleanup_operations > 0,
            do: :document_draft_abort_incomplete,
            else: :collection_refused
          )
        )

  def resume(_, %{
        "status" => "failed",
        "value" => %{"code" => "document_store_deadline_unavailable"}
      }),
      do: error(:document_store_deadline_unavailable)

  def resume(_, %{"status" => status}) when status != "ok", do: error(:collection_refused)

  def resume(%{operation: :backup_metadata} = state, %{"status" => "ok", "value" => wrapped}) do
    with true <- exact?(wrapped, ~w(version owner operation_id request_sha256 result)),
         true <- wrapped["version"] === 3 and backup_input_owner?(wrapped["owner"]),
         true <- native_id?(wrapped["operation_id"]),
         {:ok, request_hash} <- Ipse.Extension.canonical_digest([state.request]),
         true <- wrapped["request_sha256"] === request_hash,
         result when is_map(result) <- wrapped["result"] do
      next(state, result)
    else
      _ -> error(:collection_response)
    end
  rescue
    _ -> error(:collection_response)
  end

  def resume(%{operation: :restore_mutation} = state, %{"status" => "ok", "value" => wrapped}) do
    with true <- exact?(wrapped, ~w(version owner operation_id request_sha256 result)),
         true <- wrapped["version"] === 3 and backup_input_owner?(wrapped["owner"]),
         true <- native_id?(wrapped["operation_id"]),
         {:ok, request_hash} <- Ipse.Extension.canonical_digest([state.request]),
         true <- wrapped["request_sha256"] === request_hash,
         owner = Map.take(wrapped["owner"], ~w(project_id session_id identity_sha256)),
         {:ok, native_hash} <- Ipse.Extension.canonical_digest([state.inner_request, owner]),
         result when is_map(result) <- wrapped["result"],
         true <-
           backup_restore_receipt?(
             state.inner_request,
             result,
             native_hash,
             wrapped["operation_id"]
           ) do
      {:done,
       {:ok,
        %{
          "operation_id" => wrapped["operation_id"],
          "receipt" => result,
          "coverage" => coverage(state, false)
        }}}
    else
      _ -> {:stop, :unknown_effect}
    end
  rescue
    _ -> {:stop, :unknown_effect}
  end

  def resume(%{operation: :result_input_read} = state, %{"status" => "ok", "value" => wrapped}) do
    with true <- exact?(wrapped, ~w(version owner operation_id request_sha256 result)),
         true <- wrapped["version"] === 3 and backup_input_owner?(wrapped["owner"]),
         true <- native_id?(wrapped["operation_id"]),
         {:ok, request_hash} <- Ipse.Extension.canonical_digest([state.request]),
         true <- wrapped["request_sha256"] === request_hash,
         result when is_map(result) <- wrapped["result"],
         true <- exact?(result, ~w(delivery offset next data_base64 sha256 origin)),
         true <-
           result["delivery"] === state.ref["delivery"] and result["offset"] === state.offset,
         true <- is_nil(result["origin"]) or backup_origin?(result["origin"], state.ref),
         encoded when is_binary(encoded) <- result["data_base64"],
         {:ok, bytes} <- Base.decode64(encoded),
         true <- byte_size(bytes) in 1..6144 and Base.encode64(bytes) === encoded,
         true <- E.sha256(bytes) === result["sha256"],
         next = state.offset + byte_size(bytes),
         total = state.ref["delivery"]["byte_count"],
         true <- next <= total and result["next"] === if(next < total, do: next, else: nil) do
      value = %{
        "delivery" => result["delivery"],
        "offset" => state.offset,
        "next" => result["next"],
        "origin" => result["origin"],
        "data" => bytes,
        "coverage" => coverage(state, false)
      }

      value = if state[:owner_result], do: Map.put(value, "owner", wrapped["owner"]), else: value
      {:done, {:ok, value}}
    else
      _ -> error(:collection_result_input_corrupt)
    end
  rescue
    _ -> error(:collection_result_input_corrupt)
  end

  def resume(state, %{"status" => "ok", "value" => wrapped}) do
    tagged = is_map(state.request["request"]["progress"])

    with true <-
           exact?(
             wrapped,
             if(tagged,
               do: ~w(version operation_id request_sha256 result progress),
               else: ~w(version operation_id request_sha256 result)
             )
           ),
         true <- wrapped["version"] === if(tagged, do: 2, else: 1),
         true <- not tagged or native_id?(wrapped["operation_id"]),
         {:ok, request_hash} <- Ipse.Extension.canonical_digest([state.request]),
         true <- request_hash == wrapped["request_sha256"],
         true <-
           not tagged or
             (progress_transition?(state, wrapped["progress"]) and
                (state.request["request"]["progress"]["action"] !== "start" or
                   wrapped["progress"]["head_id"] === wrapped["operation_id"])),
         result when is_map(result) <- wrapped["result"] do
      state = if tagged, do: remember_progress(state, wrapped["progress"]), else: state

      if Map.get(state, :pinned_inline, false) do
        if is_binary(wrapped["operation_id"]) and
             Regex.match?(~r/\A[0-9a-fA-F]{32}\z/, wrapped["operation_id"]),
           do:
             progress_return(
               next(Map.put(state, :operation_id, wrapped["operation_id"]), result),
               state
             ),
           else: {:stop, :unknown_effect}
      else
        progress_return(next(state, result), state)
      end
    else
      _ ->
        if tagged or Map.get(state, :pinned_inline, false),
          do: {:stop, :unknown_effect},
          else: error(:collection_response)
    end
  rescue
    _ ->
      if is_map(state.request["request"]["progress"]) or Map.get(state, :pinned_inline, false),
        do: {:stop, :unknown_effect},
        else: error(:collection_response)
  end

  defp next(%{phase: :draft_abort_boot} = s, result) do
    with {:ok, epoch, "idle"} <- snapshot_epoch(result),
         true <- epoch > 0 and progress_supported?(result),
         true <- E.safe_uint?(result["generation"]) do
      call(
        Map.merge(s, %{maintenance_epoch: epoch, generation: result["generation"]}),
        %{"op" => "progress.inspect", "head_id" => s.head_id},
        :draft_abort_head
      )
    else
      _ -> error(:document_draft_abort_refused)
    end
  end

  defp next(%{phase: :draft_abort_head} = s, result) do
    p = result["progress"]

    with true <- progress_receipt?(p),
         true <- p["head_id"] === s.head_id and p["kind"] === s.kind,
         true <- p["status"] in ~w(active retiring),
         true <- p["maintenance_epoch"] <= s.maintenance_epoch,
         true <- is_nil(p["retirement_epoch"]) or p["retirement_epoch"] === s.maintenance_epoch,
         true <- result["generation"] === s.generation do
      abort_draft_stage(Map.put(s, :progress, p))
    else
      _ -> error(:document_draft_abort_refused)
    end
  end

  defp next(%{phase: :draft_abort_step} = s, result) do
    previous = s.abort_previous

    active =
      if is_map(previous["active"]) and
           Map.take(previous["active"], ~w(slot epoch)) === s.abort_ref,
         do: nil,
         else: previous["active"]

    prepared = List.delete(previous["prepared"], s.abort_ref)
    terminal = is_nil(active) and prepared === []

    expected = %{
      previous
      | "revision" => result["generation"],
        "retirement_epoch" => s.maintenance_epoch,
        "status" => if(terminal, do: "retired", else: "retiring"),
        "active" => active,
        "prepared" => prepared,
        "slots" => if(terminal, do: [], else: previous["slots"])
    }

    if E.safe_uint?(result["generation"]) and result["generation"] === s.generation + 1 and
         s.progress === expected do
      s = %{s | generation: result["generation"], cleanup_operations: s.cleanup_operations + 1}

      if terminal do
        {:done,
         {:ok,
          %{
            "status" => "aborted",
            "head_id" => s.head_id,
            "kind" => s.kind,
            "maintenance_epoch" => previous["maintenance_epoch"],
            "retirement_epoch" => s.maintenance_epoch,
            "native_generation" => s.generation,
            "cleanup_operations" => s.cleanup_operations,
            "coverage" => coverage(s, false)
          }}}
      else
        abort_draft_stage(s)
      end
    else
      {:stop, :unknown_effect}
    end
  end

  defp next(%{phase: :progress_inspected}, result) do
    if progress_receipt?(result["progress"]),
      do: {:done, {:ok, result}},
      else: error(:collection_progress_changed)
  end

  defp next(%{phase: :progress_gate} = s, result) do
    p = result["progress"]
    t = s.progress_tag

    if progress_receipt?(p) and p["head_id"] === t["head_id"] and
         p["revision"] === t["revision"] and
         (t["action"] === "retire" or
            (p["unit"] === t["unit"] and p["maintenance_epoch"] === s.maintenance_epoch and
               p["status"] === "active")),
       do: dispatch_progress(add_progress_reads(s.pending, s.reads), t, p),
       else: error(:collection_progress_changed)
  end

  defp next(%{phase: :snapshot}, result) do
    with {:ok, _, _} <- snapshot_epoch(result),
         do: {:done, {:ok, result}},
         else: (_ -> error(:document_epoch_changed))
  end

  defp next(%{phase: :boot, operation: :put} = s, result) do
    with {:ok, epoch, "idle"} <- snapshot_epoch(result),
         true <- not s.continuing or Map.get(s.checkpoint, "maintenance_epoch", 0) === epoch,
         true <- epoch === 0 or progress_supported?(result),
         true <- epoch === 0 or not s.continuing or s.checkpoint["version"] === 5 do
      checkpoint =
        if not s.continuing and epoch > 0,
          do:
            Map.merge(s.checkpoint, %{
              "version" => 5,
              "maintenance_epoch" => epoch,
              "epoch_binding_sha256" => source_plan(s.source_sha256, epoch),
              "progress" => nil
            }),
          else: s.checkpoint

      s =
        admitted_inline(
          s
          |> Map.put(:maintenance_epoch, epoch)
          |> Map.put(:checkpoint, checkpoint)
          |> Map.put(:generation, result["generation"]),
          result
        )

      cond do
        epoch === 0 ->
          fetch(s, catalog_key(s), :catalog)

        s.continuing ->
          call(
            s,
            %{"op" => "progress.inspect", "head_id" => checkpoint["progress"]["head_id"]},
            :source_progress_boot
          )

        true ->
          s =
            Map.put(s, :progress_tag, %{
              "version" => 1,
              "action" => "start",
              "kind" => "source",
              "plan_sha256" => source_progress_plan(s),
              "body_sha256" => s.source_sha256,
              "unit_limit" => length(s.prepared) + 3
            })

          fetch(s, catalog_key(s), :catalog)
      end
    else
      _ -> error(:document_epoch_changed)
    end
  end

  defp next(%{phase: :source_progress_boot} = s, result) do
    p = result["progress"]
    cp = s.checkpoint

    if progress_receipt?(p) and p === cp["progress"] and p["status"] === "active" and
         p["kind"] === "source" and p["maintenance_epoch"] === s.maintenance_epoch and
         p["plan_sha256"] === source_progress_plan(s) and p["body_sha256"] === s.source_sha256 and
         p["unit_limit"] === length(s.prepared) + 3 and p["unit"] === cp["unit"] and
         p["prepared"] === Enum.sort_by(cp["stages"], & &1["slot"]) and
         source_progress_active?(s, p["active"]) do
      fetch(remember_progress(s, p), catalog_key(s), :catalog)
    else
      error(:collection_progress_changed)
    end
  end

  defp next(%{phase: :boot} = s, result) do
    fetch(
      admitted_inline(%{s | generation: result["generation"]}, result),
      catalog_key(s),
      :catalog
    )
  end

  defp next(%{phase: :value_boot} = s, result),
    do: fetch(admitted_inline(%{s | generation: result["generation"]}, result), s.key, :value)

  defp next(%{phase: :inline_published} = s, result) do
    request = s.request["request"]
    row = result["record"]

    with true <- result["generation"] == s.generation + 1,
         true <- result["key"] == request["key"] and is_map(row),
         true <-
           row["sha256"] == request["sha256"] and row["byte_count"] == request["byte_count"] and
             row["revision"] == result["generation"] do
      s = %{s | generation: result["generation"]}

      if s.operation == :value_write,
        do:
          {:done,
           {:ok,
            %{
              "record" =>
                row
                |> Map.put("key", request["key"])
                |> then(fn value ->
                  if Map.get(s, :pinned_inline, false),
                    do: Map.put(value, "operation_id", s.operation_id),
                    else: value
                end),
              "native_generation" => s.generation,
              "coverage" => coverage(s, false)
            }}},
        else: unit_done(s, nil)
    else
      _ -> {:stop, :unknown_effect}
    end
  end

  defp next(%{phase: :inline_prepared} = s, result) do
    stage = result["stage"]

    with true <- result["generation"] == s.generation + 1,
         true <- is_map(stage) and Map.take(stage, ~w(slot epoch)) === s.unit.ref,
         true <-
           stage["key"] == s.unit.key and stage["expected_revision"] == s.unit.revision and
             stage["state"] == "sealed",
         true <-
           stage["sha256"] == E.sha256(s.unit.bytes) and
             stage["byte_count"] == byte_size(s.unit.bytes) and
             stage["offset"] == byte_size(s.unit.bytes) do
      s = %{s | generation: result["generation"]}

      if s.operation == :value_prepare,
        do:
          {:done,
           {:ok,
            %{
              "stage" => s.unit.ref,
              "native_generation" => s.generation,
              "coverage" => coverage(s, false)
            }}},
        else: unit_done(s, s.unit.ref)
    else
      _ -> {:stop, :unknown_effect}
    end
  end

  defp next(%{phase: :writing_parts} = s, result) do
    r = s.request["request"]
    write = result["write"]
    offset = s.unit.offset + Enum.sum(Enum.map(r["data"], &byte_size/1))

    state =
      if offset == byte_size(s.unit.bytes),
        do: if(s.unit.publish, do: "published", else: "sealed"),
        else: "open"

    with true <- result["generation"] == s.generation + 1,
         true <-
           exact?(
             write,
             ~w(slot epoch key expected_revision byte_count sha256 offset state expires_at_ms publish revision)
           ),
         true <-
           Map.take(write, ~w(slot epoch key expected_revision byte_count sha256 publish)) ===
             Map.take(r, ~w(slot epoch key expected_revision byte_count sha256 publish)),
         true <-
           write["offset"] === offset and write["state"] == state and
             E.safe_uint?(write["expires_at_ms"]),
         true <- write["revision"] === if(state == "published", do: result["generation"], else: 0) do
      case state do
        "open" ->
          append(%{s | generation: result["generation"], unit: Map.put(s.unit, :offset, offset)})

        "published" ->
          next(
            %{s | phase: :inline_published},
            result
            |> Map.put("key", write["key"])
            |> Map.put("record", Map.take(write, ~w(sha256 byte_count revision)))
          )

        "sealed" ->
          next(
            %{s | phase: :inline_prepared},
            Map.put(result, "stage", Map.put(write, "version", 1))
          )
      end
    else
      _ -> {:stop, :unknown_effect}
    end
  end

  defp next(%{phase: :commit_boot} = s, result),
    do:
      call(
        %{s | generation: result["generation"]},
        %{"op" => "commit", "stages" => s.stages, "generation" => result["generation"]},
        :values_committed
      )

  defp next(%{phase: :inspect_boot} = s, result),
    do:
      call(
        %{s | generation: result["generation"]},
        Map.merge(s.ref, %{"op" => "stage.inspect", "generation" => result["generation"]}),
        :inspected
      )

  defp next(%{phase: :inspected} = s, result),
    do: {:done, {:ok, Map.put(result, "coverage", coverage(s, false))}}

  defp next(%{phase: :value_statted} = s, result),
    do:
      if(result["generation"] == s.generation and result["key"] == s.key,
        do: {:done, {:ok, Map.put(result, "coverage", coverage(s, false))}},
        else: error(:collection_response)
      )

  defp next(%{phase: :value_layout} = s, result),
    do:
      if(result["generation"] === s.generation and result["key"] === s.key,
        do: {:done, {:ok, Map.put(result, "coverage", coverage(s, false))}},
        else: error(:collection_response)
      )

  defp next(%{phase: :value_read_chunk} = s, result),
    do:
      if(
        result["generation"] === s.generation and result["key"] === s.key and
          result["offset"] === s.offset,
        do: {:done, {:ok, Map.put(result, "coverage", coverage(s, false))}},
        else: error(:collection_response)
      )

  defp next(%{phase: :backup_metadata} = s, result),
    do:
      if(
        result["generation"] === s.generation and result["section"] === s.section and
          result["offset"] === s.offset,
        do: {:done, {:ok, Map.put(result, "coverage", coverage(s, false))}},
        else: error(:collection_response)
      )

  defp next(%{phase: :values_committed_at} = s, result) do
    if result["generation"] === s.generation + 1,
      do:
        {:done,
         {:ok, %{"native_generation" => result["generation"], "coverage" => coverage(s, false)}}},
      else: {:stop, :unknown_effect}
  end

  defp next(%{phase: :values_committed} = s, result),
    do:
      {:done,
       {:ok, %{"native_generation" => result["generation"], "coverage" => coverage(s, false)}}}

  defp next(%{phase: :object} = s, result) do
    with true <- result["generation"] == s.generation and result["key"] == s.ref["key"],
         true <- not Map.has_key?(s.ref, "revision") or result["revision"] === s.ref["revision"],
         true <-
           result["sha256"] == s.ref["sha256"] and result["byte_count"] == s.ref["byte_count"],
         true <- result["offset"] == byte_size(s.bundle),
         data when is_binary(data) <- result["data"],
         bytes = s.bundle <> data,
         true <- byte_size(bytes) <= s.ref["byte_count"] do
      if result["next"] do
        if result["next"] == byte_size(bytes),
          do:
            call(
              %{s | bundle: bytes},
              %{
                "op" => "value.read",
                "key" => s.ref["key"],
                "offset" => byte_size(bytes),
                "generation" => s.generation
              },
              :object
            ),
          else: error(:collection_object_corrupt)
      else
        with true <-
               byte_size(bytes) == s.ref["byte_count"] and E.sha256(bytes) == s.ref["sha256"],
             {:ok, value} <- Ipse.JSON.decode_unique(bytes) do
          {:done,
           {:ok,
            %{
              "value" => value,
              "native_generation" => s.generation,
              "coverage" => coverage(s, false)
            }}}
        else
          _ -> error(:collection_object_corrupt)
        end
      end
    else
      _ -> error(:collection_object_corrupt)
    end
  end

  defp next(%{operation: :value_prepare, phase: :sealed} = s, result),
    do:
      {:done,
       {:ok,
        %{
          "stage" => s.unit.ref,
          "native_generation" => result["generation"],
          "coverage" => coverage(s, false)
        }}}

  defp next(%{phase: :page_boot} = s, result),
    do:
      call(
        %{s | generation: result["generation"]},
        %{
          "op" => "value.read",
          "key" => s.ref["key"],
          "offset" => s.ref["offset"],
          "generation" => result["generation"]
        },
        :page
      )

  defp next(%{phase: :page} = s, result) do
    ref = s.ref

    with true <- result["generation"] == s.generation and result["key"] == ref["key"],
         true <- result["sha256"] == ref["object_sha256"] and result["offset"] == ref["offset"],
         data when is_binary(data) <- result["data"],
         true <- byte_size(data) >= ref["byte_count"],
         bytes = binary_part(data, 0, ref["byte_count"]),
         true <- E.sha256(bytes) == ref["sha256"],
         {:ok, page} <- Ipse.JSON.decode_unique(bytes) do
      {:done, {:ok, %{"value" => page, "coverage" => coverage(s, false)}}}
    else
      _ -> error(:collection_page_corrupt)
    end
  end

  defp next(%{operation: :value_write, phase: :unit_done} = s, result),
    do:
      call(
        %{s | generation: result["generation"]},
        %{"op" => "value.stat", "key" => s.key, "generation" => result["generation"]},
        :value_written
      )

  defp next(%{phase: :value_written} = s, result) do
    row = result["record"]

    if result["generation"] == s.generation and is_map(row) and
         row["sha256"] == E.sha256(s.bytes) and row["byte_count"] == byte_size(s.bytes),
       do:
         {:done,
          {:ok,
           %{
             "record" => Map.put(row, "key", s.key),
             "native_generation" => s.generation,
             "coverage" => coverage(s, false)
           }}},
       else: error(:collection_value_unconfirmed)
  end

  defp next(%{phase: :source_reused} = s, result) do
    if result["generation"] === s.generation + 1,
      do: unit_done(%{s | generation: result["generation"]}, nil),
      else: {:stop, :unknown_effect}
  end

  defp next(%{phase: :value_reused} = s, result) do
    if result["generation"] === s.generation + 1,
      do:
        {:done,
         {:ok,
          %{
            "record" => s.reused_row,
            "native_generation" => result["generation"],
            "coverage" => coverage(s, false)
          }}},
      else: {:stop, :unknown_effect}
  end

  defp next(%{phase: :verify_data, verify: [body | rest]} = s, result) do
    bytes = json(body)

    with true <- result["generation"] == s.generation,
         record when is_map(record) <- result["record"],
         true <- record["sha256"] == E.sha256(bytes) and record["byte_count"] == byte_size(bytes) do
      verify_data(%{s | verify: rest})
    else
      _ -> error(:collection_unprepared_data)
    end
  end

  defp next(%{phase: :verify_stage, verify_stages: [{n, ref} | rest]} = s, result) do
    {key, body, revision} = metadata_unit(s, n)
    stage = result["stage"]

    with true <- result["generation"] == s.generation,
         true <- stage["slot"] == ref["slot"] and stage["epoch"] == ref["epoch"],
         true <- stage["state"] == "sealed" and stage["key"] == key,
         bytes = json(body),
         true <- stage["sha256"] == E.sha256(bytes),
         true <- stage["byte_count"] == byte_size(bytes) and stage["offset"] == byte_size(bytes),
         true <- stage["expected_revision"] == revision do
      verify_stages(%{s | verify_stages: rest})
    else
      _ -> error(:collection_continuation_mismatch)
    end
  end

  defp next(%{phase: {:stat, key, after_read}} = s, result) do
    with true <- result["key"] == key and result["generation"] == s.generation do
      if result["record"] == nil,
        do: loaded(s, after_read, nil),
        else:
          call(
            Map.put(s, :fetch, %{
              key: key,
              descriptor: result["record"],
              text: "",
              after_read: after_read
            }),
            %{"op" => "value.read", "key" => key, "offset" => 0, "generation" => s.generation},
            :read
          )
    else
      _ -> error(:collection_response)
    end
  end

  defp next(%{phase: {:known_ref, ref, after_read}} = s, result) do
    with true <- result["key"] === ref["key"] and result["generation"] === s.generation,
         true <- result["offset"] === 0 and result["sha256"] === ref["sha256"],
         descriptor = Map.take(result, ~w(revision sha256 byte_count)),
         fetch = %{key: ref["key"], descriptor: descriptor, text: "", after_read: after_read} do
      next(Map.merge(s, %{phase: :read, fetch: fetch}), result)
    else
      _ -> error(:collection_response)
    end
  end

  defp next(%{phase: :read, fetch: f} = s, r) do
    with true <- r["key"] == f.key and r["generation"] == s.generation,
         true <- r["offset"] == byte_size(f.text),
         true <-
           r["sha256"] == f.descriptor["sha256"] and r["revision"] == f.descriptor["revision"],
         true <- r["byte_count"] == f.descriptor["byte_count"],
         text = f.text <> r["data"],
         true <- byte_size(text) <= 61_440 do
      if r["next"] do
        if r["next"] == byte_size(text),
          do:
            call(
              %{s | fetch: %{f | text: text}},
              %{
                "op" => "value.read",
                "key" => f.key,
                "offset" => byte_size(text),
                "generation" => s.generation
              },
              :read
            ),
          else: error(:collection_response)
      else
        with true <-
               byte_size(text) == f.descriptor["byte_count"] and
                 E.sha256(text) == f.descriptor["sha256"],
             {:ok, value} <- Ipse.Extension.ResultDocument.decode(text, %{"type" => "object"}) do
          loaded(Map.delete(s, :fetch), f.after_read, Map.put(f.descriptor, "value", value))
        else
          _ -> error(:collection_corrupt)
        end
      end
    else
      _ -> error(:collection_response)
    end
  end

  defp next(%{phase: :opened} = s, result), do: append(%{s | generation: result["generation"]})

  defp next(%{phase: :allocate_stage} = s, result) do
    slot =
      if Map.get(s, :maintenance_epoch, 0) > 0,
        do: List.first(result["available_slots"] || []),
        else: Enum.find(0..15, &(&1 not in Enum.map(result["stages"], fn r -> r["slot"] end)))

    if slot != nil and result["generation"] == s.generation,
      do: open_stage(s, slot),
      else: error(:collection_stages_occupied)
  end

  defp next(%{phase: :appended} = s, result) do
    request = s.request["request"]
    unit = %{s.unit | offset: request["offset"] + byte_size(request["data"])}
    append(%{s | generation: result["generation"], unit: unit})
  end

  defp next(%{phase: :sealed, unit: %{publish: true}} = s, result),
    do:
      call(
        %{s | generation: result["generation"], unit: %{s.unit | state: "sealed"}},
        %{"op" => "commit", "stages" => [s.unit.ref], "generation" => result["generation"]},
        :unit_done
      )

  defp next(%{phase: :sealed} = s, result),
    do: unit_done(%{s | generation: result["generation"]}, s.unit.ref)

  defp next(%{phase: :unit_done} = s, result),
    do: unit_done(%{s | generation: result["generation"]}, nil)

  defp next(%{phase: :resume_stage} = s, result) do
    actual = result["stage"]
    expected = s.checkpoint["active"]

    with true <- result["generation"] == s.generation,
         true <- Map.take(actual, Map.keys(expected)) === expected,
         true <-
           not Map.has_key?(actual, "write_publish") or
             (actual["write_publish"] === s.unit.publish and Map.get(s, :write_parts, 0) == 2) do
      s = %{s | unit: Map.put(s.unit, :fused, Map.has_key?(actual, "write_publish"))}

      if actual["state"] == "sealed" do
        if s.unit.publish,
          do:
            call(
              s,
              %{"op" => "commit", "stages" => [s.unit.ref], "generation" => s.generation},
              :unit_done
            ),
          else:
            if(s.operation == :value_prepare,
              do: next(%{s | phase: :sealed}, %{"generation" => s.generation}),
              else: unit_done(s, s.unit.ref)
            )
      else
        append(s)
      end
    else
      _ -> error(:collection_active_stage_changed)
    end
  end

  defp next(%{phase: :published} = s, _) do
    {:done,
     {:ok,
      %{
        "status" => "stored",
        "source_id" => s.source["source_id"],
        "generation" => s.source["generation"],
        "revision" => s.checkpoint["expected_revision"] + 1,
        "catalog_generation" => s.catalog["generation"] + 1,
        "continuation" => nil,
        "coverage" => coverage(s, false)
      }}}
  end

  defp next(%{phase: :selection_final} = s, result) do
    if result["generation"] == s.generation and stamp(result["record"]) == s.catalog_stamp,
      do:
        {:done,
         {:ok,
          %{
            case s.read_mode do
              :lexical -> "runs"
              :bundles -> "bundles"
              _ -> "sources"
            end => s.selected,
            "catalog_generation" => s.catalog["generation"],
            "catalog_floor" => s.catalog["floor"],
            "native_generation" => s.generation,
            "coverage" => coverage(s, true)
          }
          |> then(fn value ->
            if is_list(s.bound_heads),
              do: Map.put(value, "head_stamps", s.bound_heads),
              else: value
          end)}},
      else: error(:collection_selection_changed)
  end

  defp loaded(%{operation: :value_read} = s, :value, row),
    do:
      {:done,
       {:ok,
        %{"record" => row, "native_generation" => s.generation, "coverage" => coverage(s, false)}}}

  defp loaded(%{operation: op} = s, :value, row) when op in [:value_write, :value_prepare] do
    cond do
      s.args["reuse"] and row != nil and row["value"] === s.value and is_map(s[:progress_tag]) ->
        verify_reuse(s, s.key, s.bytes, row, :value_reused)

      s.args["reuse"] and row != nil and row["value"] === s.value ->
        {:done,
         {:ok,
          %{
            "record" => row,
            "native_generation" => s.generation,
            "coverage" => coverage(s, false)
          }}}

      revision(row) != s.args["expected_revision"] ->
        error(:collection_value_conflict)

      s.checkpoint["active"] == nil ->
        stage(s, s.key, s.value, s.args["expected_revision"], op == :value_write, 0)

      true ->
        active = s.checkpoint["active"]

        if exact?(active, ~w(slot epoch offset state key expected_revision byte_count sha256)) and
             active["key"] == s.key and active["expected_revision"] == s.args["expected_revision"] and
             active["byte_count"] == byte_size(s.bytes) and active["sha256"] == E.sha256(s.bytes) and
             E.safe_uint?(active["offset"]) and active["offset"] <= byte_size(s.bytes) and
             active["state"] in ~w(open sealed) and active["slot"] in 0..15 do
          ref = Map.take(active, ~w(slot epoch))

          unit = %{
            bytes: s.bytes,
            offset: active["offset"],
            ref: ref,
            key: s.key,
            revision: s.args["expected_revision"],
            publish: op == :value_write,
            state: active["state"]
          }

          call(
            Map.put(s, :unit, unit),
            Map.merge(ref, %{"op" => "stage.inspect", "generation" => s.generation}),
            :resume_stage
          )
        else
          error(:collection_active_stage_changed)
        end
    end
  end

  defp loaded(%{operation: :put} = s, :catalog, row) do
    catalog = if row, do: row["value"], else: empty_catalog(s.profile)

    with true <- catalog?(catalog, s.profile),
         true <- s.checkpoint["base"] == nil or s.checkpoint["base"] == stamp(row) do
      s =
        s
        |> Map.put(:catalog, catalog)
        |> Map.put(:catalog_row, row)
        |> Map.update!(:checkpoint, &Map.put(&1, "base", stamp(row)))

      fetch(s, source_key(s, s.source["source_key"]), :head)
    else
      _ -> error(:collection_catalog_changed)
    end
  end

  defp loaded(%{operation: :put} = s, :head, row) do
    with true <- row == nil or source_head?(row["value"], s.source["source_key"]),
         true <-
           if(row, do: row["value"]["revision"], else: 0) == s.checkpoint["expected_revision"],
         true <- row == nil or s.source["generation"] > row["value"]["generation"],
         ordinal = if(row, do: row["value"]["ordinal"], else: s.catalog["sources"]),
         true <- ordinal < @sources,
         true <-
           s.catalog["extracted_bytes"] - if(row, do: row["value"]["text_bytes"], else: 0) +
             byte_size(s.source["text"]) <= 20 * 1024 * 1024,
         true <-
           s.catalog["chunks"] - if(row, do: row["value"]["chunks"], else: 0) + s.chunks <= 10_000 do
      s = s |> Map.put(:head, row) |> Map.put(:ordinal, ordinal)
      fetch(s, page_key(s, div(ordinal, @catalog_rows)), :page)
    else
      _ -> error(:collection_source_conflict)
    end
  end

  defp loaded(%{operation: :put} = s, :page, row) do
    page_no = div(s.ordinal, @catalog_rows)
    ref = Enum.at(s.catalog["pages"], page_no)

    with true <- (row == nil and ref == nil) or valid_page?(row, ref, page_no, s.profile),
         true <-
           s.head == nil or
             Enum.any?(
               row["value"]["rows"],
               &(&1["source_key"] == s.source["source_key"] and
                   &1["head_sha256"] == s.head["sha256"])
             ) do
      s = Map.put(s, :page, row)
      plan_unit(s)
    else
      _ -> error(:collection_catalog_corrupt)
    end
  end

  defp loaded(%{operation: :put} = s, :data_existing, row) do
    body = Enum.at(s.prepared, s.checkpoint["unit"])
    bytes = json(body)

    cond do
      row == nil ->
        stage(s, data_key(s, E.sha256(bytes)), body, 0, true, 0)

      row["sha256"] == E.sha256(bytes) and row["value"] === body ->
        if is_map(s[:progress_tag]),
          do: verify_reuse(s, data_key(s, E.sha256(bytes)), bytes, row, :source_reused),
          else: unit_done(s, nil)

      true ->
        error(:collection_block_conflict)
    end
  end

  defp loaded(%{operation: :selected} = s, :catalog, row) do
    with true <- row != nil and catalog?(row["value"], s.profile) do
      select_next(s |> Map.put(:catalog, row["value"]) |> Map.put(:catalog_stamp, stamp(row)))
    else
      _ -> error(:collection_catalog_missing)
    end
  end

  defp loaded(%{operation: :selected} = s, :head, row) do
    key = selection_key(s)

    with true <- row != nil and source_head?(row["value"], key),
         true <- s.read_mode != :lexical or is_map(row["value"]["lexical"]) do
      s = Map.put(s, :head, row)
      page = div(row["value"]["ordinal"], @catalog_rows)

      case Map.fetch(s.selected_pages, page) do
        {:ok, cached} -> loaded(s, :selected_page, cached)
        :error -> fetch_ref(s, Enum.at(s.catalog["pages"], page), :selected_page)
      end
    else
      _ -> error(:selected_source_missing)
    end
  end

  defp loaded(%{operation: :selected} = s, :selected_page, row) do
    page = div(s.head["value"]["ordinal"], @catalog_rows)

    with true <- valid_page?(row, Enum.at(s.catalog["pages"], page), page, s.profile),
         true <-
           Enum.any?(
             row["value"]["rows"],
             &(&1["source_key"] == s.head["value"]["source_key"] and
                 &1["head_sha256"] == s.head["sha256"])
           ) do
      {manifest, phase} =
        if s.read_mode == :lexical,
          do: {s.head["value"]["lexical"], :lexical_block},
          else: {s.head["value"], :block}

      s =
        s
        |> Map.put(:selected_pages, Map.put(s.selected_pages, page, row))
        |> Map.merge(%{bundle: "", pending_blocks: manifest["blocks"]})

      fetch_ref(s, hd(s.pending_blocks), phase)
    else
      _ -> error(:selected_catalog_mismatch)
    end
  end

  defp loaded(%{operation: :selected} = s, :block, row) do
    [ref | rest] = s.pending_blocks

    with true <- row != nil and row["sha256"] == ref["sha256"],
         value = row["value"],
         true <-
           ((exact?(value, ~w(version kind pieces)) and value["version"] === 1) or
              (exact?(value, ~w(version kind pieces bundle_sha256 ordinal)) and
                 value["version"] === 2 and
                 value["bundle_sha256"] == s.head["value"]["bundle_sha256"] and
                 value["ordinal"] == length(s.head["value"]["blocks"]) - length(s.pending_blocks))) and
             value["kind"] == "source_data",
         true <- is_list(value["pieces"]) and length(value["pieces"]) in 1..12,
         true <- Enum.all?(value["pieces"], &(is_binary(&1) and byte_size(&1) <= 4096)),
         bytes = s.bundle <> Enum.join(value["pieces"]),
         true <- byte_size(bytes) <= @bundle_bytes do
      s = %{s | bundle: bytes, pending_blocks: rest}

      if rest != [] do
        fetch_ref(s, hd(rest), :block)
      else
        with true <-
               byte_size(bytes) == s.head["value"]["byte_count"] and
                 E.sha256(bytes) == s.head["value"]["bundle_sha256"],
             {:ok, attrs} <- Ipse.JSON.decode_unique(bytes),
             {:ok, source} <- source(attrs),
             true <- source["partition"] == s.profile["partition"],
             true <-
               source["source_key"] == s.head["value"]["source_key"] and
                 source["generation"] == s.head["value"]["generation"],
             true <- byte_size(source["text"]) == s.head["value"]["text_bytes"],
             {:ok, chunks} <- E.chunks(source),
             true <- length(chunks) == s.head["value"]["chunks"],
             true <- s.read_mode in [:source, :bundles] or E.current?(source, s.args["as_of_ms"]) do
          item =
            if s.read_mode == :bundles,
              do: %{"source" => source, "head" => s.head["value"]},
              else: source

          s = %{s | selected: s.selected ++ [item], remaining: tl(s.remaining)}

          s =
            if is_list(s.bound_heads),
              do: %{
                s
                | bound_heads: s.bound_heads ++ [Map.take(s.head, ~w(revision sha256 byte_count))]
              },
              else: s

          select_next(s)
        else
          _ -> error(:selected_bundle_corrupt)
        end
      end
    else
      _ -> error(:selected_block_corrupt)
    end
  end

  defp loaded(%{operation: :selected} = s, :lexical_block, row) do
    [ref | rest] = s.pending_blocks
    manifest = s.head["value"]["lexical"]

    with true <- row != nil and row["sha256"] == ref["sha256"],
         value = row["value"],
         true <-
           exact?(value, ~w(version kind pieces bundle_sha256 ordinal source_bundle_sha256)),
         true <- value["version"] === 1 and value["kind"] == "source_lexical",
         true <- value["source_bundle_sha256"] == s.head["value"]["bundle_sha256"],
         true <- value["bundle_sha256"] == manifest["bundle_sha256"],
         true <- value["ordinal"] == length(manifest["blocks"]) - length(s.pending_blocks),
         true <- is_list(value["pieces"]) and length(value["pieces"]) in 1..12,
         true <- Enum.all?(value["pieces"], &(is_binary(&1) and byte_size(&1) <= 4096)),
         bytes = s.bundle <> Enum.join(value["pieces"]),
         true <- byte_size(bytes) <= 4 * @bundle_bytes do
      s = %{s | bundle: bytes, pending_blocks: rest}

      if rest != [] do
        fetch_ref(s, hd(rest), :lexical_block)
      else
        with true <- byte_size(bytes) == manifest["byte_count"],
             true <- E.sha256(bytes) == manifest["bundle_sha256"],
             {:ok, run} <- Ipse.JSON.decode_unique(bytes),
             true <- E.valid_lexical_run?(run),
             true <- run["source_key"] == s.head["value"]["source_key"],
             true <- run["generation"] == s.head["value"]["generation"],
             true <- run["content_sha256"] == manifest["content_sha256"],
             true <- length(run["chunks"]) == s.head["value"]["chunks"],
             true <- run["recipe"] == manifest["recipe"] do
          selected = %{
            "run" => run,
            "source_bundle_sha256" => s.head["value"]["bundle_sha256"],
            "source_revision" => s.head["value"]["revision"],
            "run_sha256" => manifest["bundle_sha256"]
          }

          select_next(%{s | selected: s.selected ++ [selected], remaining: tl(s.remaining)})
        else
          _ -> error(:lexical_bundle_corrupt)
        end
      end
    else
      _ -> error(:lexical_block_corrupt)
    end
  end

  defp plan_unit(s) do
    unit = s.checkpoint["unit"]
    expected_stages = min(max(unit - length(s.prepared), 0), 3)

    if length(s.checkpoint["stages"]) == expected_stages and unit <= length(s.prepared) + 3 and
         (unit < length(s.prepared) + 3 or s.checkpoint["active"] == nil) do
      if unit < length(s.prepared),
        do: perform_unit(s),
        else: verify_data(Map.put(s, :verify, s.prepared))
    else
      error(:invalid_collection_continuation)
    end
  end

  defp verify_data(%{verify: []} = s),
    do:
      verify_stages(
        Map.put(
          s,
          :verify_stages,
          Enum.with_index(s.checkpoint["stages"]) |> Enum.map(fn {ref, n} -> {n, ref} end)
        )
      )

  defp verify_data(%{verify: [body | _]} = s),
    do:
      call(
        s,
        %{
          "op" => "value.stat",
          "key" => data_key(s, E.sha256(json(body))),
          "generation" => s.generation
        },
        :verify_data
      )

  defp verify_stages(%{verify_stages: []} = s), do: perform_unit(s)

  defp verify_stages(%{verify_stages: [{_, ref} | _]} = s),
    do:
      call(
        s,
        Map.merge(ref, %{"op" => "stage.inspect", "generation" => s.generation}),
        :verify_stage
      )

  defp perform_unit(s) do
    unit = s.checkpoint["unit"]
    count = length(s.prepared)

    cond do
      s.checkpoint["active"] != nil ->
        resume_unit(s)

      unit < count ->
        body = Enum.at(s.prepared, unit)
        fetch(s, data_key(s, E.sha256(json(body))), :data_existing)

      unit < count + 3 ->
        {key, body, revision} = metadata_unit(s, unit - count)
        stage(s, key, body, revision, false, unit - count + 1)

      unit == count + 3 and length(s.checkpoint["stages"]) == 3 ->
        call(
          s,
          %{"op" => "commit", "stages" => s.checkpoint["stages"], "generation" => s.generation},
          :published
        )

      true ->
        error(:invalid_collection_continuation)
    end
  end

  defp resume_unit(s) do
    active = s.checkpoint["active"]

    {key, body, revision, publish, _slot_hint} =
      if s.checkpoint["unit"] < length(s.prepared) do
        body = Enum.at(s.prepared, s.checkpoint["unit"])
        {data_key(s, E.sha256(json(body))), body, 0, true, 0}
      else
        n = s.checkpoint["unit"] - length(s.prepared)
        {key, body, revision} = metadata_unit(s, n)
        {key, body, revision, false, n + 1}
      end

    bytes = json(body)

    if active["key"] == key and active["slot"] in 0..15 and
         active["expected_revision"] == revision and
         active["sha256"] == E.sha256(bytes) and active["byte_count"] == byte_size(bytes) do
      ref = Map.take(active, ~w(slot epoch))

      s =
        Map.put(s, :unit, %{
          bytes: bytes,
          offset: active["offset"],
          ref: ref,
          key: key,
          revision: revision,
          publish: publish,
          state: active["state"]
        })

      call(
        s,
        Map.merge(ref, %{"op" => "stage.inspect", "generation" => s.generation}),
        :resume_stage
      )
    else
      error(:collection_active_stage_changed)
    end
  end

  defp metadata_unit(s, 0),
    do: {source_key(s, s.source["source_key"]), new_head(s), revision(s.head)}

  defp metadata_unit(s, 1),
    do: {page_key(s, div(s.ordinal, @catalog_rows)), new_page(s), revision(s.page)}

  defp metadata_unit(s, 2), do: {catalog_key(s), new_catalog(s), revision(s.catalog_row)}

  defp new_head(s),
    do: %{
      "version" => 2,
      "kind" => "source_head",
      "source_key" => s.source["source_key"],
      "generation" => s.source["generation"],
      "revision" => s.checkpoint["expected_revision"] + 1,
      "ordinal" => s.ordinal,
      "text_bytes" => byte_size(s.source["text"]),
      "chunks" => s.chunks,
      "byte_count" => s.bytes,
      "bundle_sha256" => s.source_sha256,
      "blocks" =>
        Enum.map(s.blocks, fn body ->
          sha = E.sha256(json(body))
          %{"key" => data_key(s, sha), "sha256" => sha}
        end),
      "lexical" => %{
        "version" => 1,
        "recipe" => E.lexical_recipe(),
        "content_sha256" => s.source["content_sha256"],
        "byte_count" => s.lexical_bytes,
        "bundle_sha256" => s.lexical_hash,
        "blocks" =>
          Enum.map(s.lexical_blocks, fn body ->
            sha = E.sha256(json(body))
            %{"key" => data_key(s, sha), "sha256" => sha}
          end)
      }
    }

  defp new_page(s) do
    rows = if s.page, do: s.page["value"]["rows"], else: []

    entry = %{
      "source_key" => s.source["source_key"],
      "head_sha256" => E.sha256(json(new_head(s)))
    }

    rows = Enum.reject(rows, &(&1["source_key"] == entry["source_key"])) ++ [entry]

    %{
      "version" => 1,
      "kind" => "catalog_page",
      "partition" => s.profile["partition"],
      "ordinal" => div(s.ordinal, @catalog_rows),
      "rows" => Enum.sort_by(rows, & &1["source_key"])
    }
  end

  defp new_catalog(s) do
    page = div(s.ordinal, @catalog_rows)
    ref = %{"key" => page_key(s, page), "sha256" => E.sha256(json(new_page(s)))}

    refs =
      if length(s.catalog["pages"]) == page,
        do: s.catalog["pages"] ++ [ref],
        else: List.replace_at(s.catalog["pages"], page, ref)

    s.catalog
    |> Map.put("pages", refs)
    |> Map.put("generation", s.catalog["generation"] + 1)
    |> Map.put("floor", s.catalog["floor"] + if(s.head, do: 1, else: 0))
    |> Map.put("sources", s.catalog["sources"] + if(s.head, do: 0, else: 1))
    |> Map.put(
      "extracted_bytes",
      s.catalog["extracted_bytes"] - if(s.head, do: s.head["value"]["text_bytes"], else: 0) +
        byte_size(s.source["text"])
    )
    |> Map.put(
      "chunks",
      s.catalog["chunks"] - if(s.head, do: s.head["value"]["chunks"], else: 0) + s.chunks
    )
  end

  defp stage(s, key, body, expected, publish, _slot_hint) do
    bytes = json(body)

    if byte_size(bytes) <= @block_bytes do
      inline = inline_request(s, key, bytes, expected, nil)

      if publish and inline_fits?(s, inline),
        do: call(s, inline, :inline_published),
        else:
          (
            s =
              Map.put(s, :allocation, %{
                key: key,
                bytes: bytes,
                expected: expected,
                publish: publish
              })

            if is_map(s[:progress]) do
              occupied =
                Enum.map(s.progress["prepared"], & &1["slot"]) ++
                  if(is_map(s.progress["active"]), do: [s.progress["active"]["slot"]], else: [])

              case Enum.find(s.progress["slots"], &(&1 not in occupied)) do
                nil -> error(:collection_stages_occupied)
                slot -> open_stage(s, slot)
              end
            else
              call(
                s,
                %{
                  "op" =>
                    if(Map.get(s, :maintenance_epoch, 0) > 0,
                      do: "stage.available",
                      else: "stage.list"
                    )
                },
                :allocate_stage
              )
            end
          )
    else
      error(:collection_unit_bound)
    end
  end

  defp open_stage(s, slot) do
    %{key: key, bytes: bytes, expected: expected, publish: publish} = s.allocation

    ref = %{
      "slot" => slot,
      "epoch" => Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    }

    s =
      Map.put(s, :unit, %{
        bytes: bytes,
        offset: 0,
        ref: ref,
        publish: publish,
        key: key,
        revision: expected,
        state: "open"
      })

    inline = inline_request(s, key, bytes, expected, ref)

    cond do
      inline_fits?(s, inline) ->
        call(s, inline, :inline_prepared)

      Map.get(s, :write_parts, 0) == 2 ->
        append(%{s | unit: Map.put(s.unit, :fused, true)})

      true ->
        call(
          s,
          %{
            "op" => "value.open",
            "slot" => slot,
            "epoch" => ref["epoch"],
            "key" => key,
            "expected_revision" => expected,
            "byte_count" => byte_size(bytes),
            "sha256" => E.sha256(bytes),
            "generation" => s.generation
          },
          :opened
        )
    end
  end

  defp append(s) do
    u = s.unit

    cond do
      Map.get(u, :fused, false) ->
        fused_append(s)

      u.offset == byte_size(u.bytes) ->
        call(s, Map.merge(u.ref, %{"op" => "value.seal", "generation" => s.generation}), :sealed)

      true ->
        data = utf8(binary_part(u.bytes, u.offset, byte_size(u.bytes) - u.offset), 6144)

        call(
          s,
          Map.merge(
            u.ref,
            %{
              "op" => "value.append",
              "offset" => u.offset,
              "data" => data,
              "generation" => s.generation
            }
          ),
          :appended
        )
    end
  end

  defp fused_append(s) do
    u = s.unit
    tail = binary_part(u.bytes, u.offset, byte_size(u.bytes) - u.offset)
    first = utf8(tail, 6144)
    rest = binary_part(tail, byte_size(first), byte_size(tail) - byte_size(first))
    data = if rest == "", do: [first], else: [first, utf8(rest, 6144)]

    request = fn data ->
      Map.merge(u.ref, %{
        "op" => "value.write_parts",
        "key" => u.key,
        "expected_revision" => u.revision,
        "byte_count" => byte_size(u.bytes),
        "sha256" => E.sha256(u.bytes),
        "offset" => u.offset,
        "publish" => u.publish,
        "data" => data,
        "generation" => s.generation
      })
    end

    r = request.(data)
    r = if state_frame_fits?(s, r), do: r, else: request.([first])

    if state_frame_fits?(s, r),
      do: call(s, r, :writing_parts),
      else: error(:collection_budget)
  end

  defp unit_done(s, ref) do
    checkpoint =
      s.checkpoint
      |> Map.put("unit", s.checkpoint["unit"] + 1)
      |> Map.put("active", nil)
      |> Map.update!("stages", &if(ref, do: &1 ++ [ref], else: &1))

    {:done,
     {:continue,
      %{"status" => "staged", "continuation" => checkpoint, "coverage" => coverage(s, false)}}}
  end

  defp select_next(%{remaining: []} = s),
    do:
      call(
        s,
        %{"op" => "value.stat", "key" => catalog_key(s), "generation" => s.generation},
        :selection_final
      )

  defp select_next(s) do
    key = selection_key(s)
    physical_key = source_key(s, key)

    if is_map(s.bound_hashes) do
      fetch_ref(s, %{"key" => physical_key, "sha256" => s.bound_hashes[key]}, :head)
    else
      fetch(s, physical_key, :head)
    end
  end

  defp selection_key(s), do: if(s.key_mode, do: hd(s.remaining), else: E.sha256(hd(s.remaining)))

  defp native_id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  defp source_progress_plan(s),
    do:
      E.sha256(
        json(%{
          "version" => 1,
          "body_sha256" => s.source_sha256,
          "expected_revision" => s.checkpoint["expected_revision"],
          "profile" => s.profile,
          "unit_limit" => length(s.prepared) + 3
        })
      )

  defp source_progress_active?(s, nil), do: is_nil(s.checkpoint["active"])

  defp source_progress_active?(s, actual) do
    expected = s.checkpoint["active"]

    is_map(expected) and expected["state"] === "open" and
      Map.drop(actual, ["publish"]) === Map.drop(expected, ["state"]) and
      actual["publish"] === s.checkpoint["unit"] < length(s.prepared)
  end

  defp verify_reuse(s, key, bytes, row, phase),
    do:
      call(
        Map.put(s, :reused_row, row),
        %{
          "op" => "value.verify",
          "key" => key,
          "expected_revision" => row["revision"],
          "byte_count" => byte_size(bytes),
          "sha256" => E.sha256(bytes),
          "generation" => s.generation
        },
        phase
      )

  defp progress_tag?(t) do
    is_map(t) and t["version"] === 1 and
      case t["action"] do
        "start" ->
          exact?(t, ~w(version action kind plan_sha256 body_sha256 unit_limit)) and
            t["kind"] in ~w(source projection) and E.sha256?(t["plan_sha256"]) and
            E.sha256?(t["body_sha256"]) and E.safe_positive?(t["unit_limit"])

        a when a in ~w(continue finish) ->
          exact?(t, ~w(version action head_id revision unit)) and
            native_id?(t["head_id"]) and E.safe_positive?(t["revision"]) and
            E.safe_uint?(t["unit"])

        "retire" ->
          exact?(t, ~w(version action head_id revision)) and
            native_id?(t["head_id"]) and E.safe_positive?(t["revision"])

        _ ->
          false
      end
  end

  @doc false
  def progress_receipt?(p) do
    exact?(
      p,
      ~w(version status head_id revision unit maintenance_epoch retirement_epoch slots active prepared plan_sha256 body_sha256 unit_limit kind)
    ) and
      p["version"] === 1 and p["status"] in ~w(active retiring finished retired) and
      native_id?(p["head_id"]) and E.safe_positive?(p["revision"]) and
      E.safe_uint?(p["unit"]) and E.safe_positive?(p["unit_limit"]) and
      p["unit"] <= p["unit_limit"] and E.safe_positive?(p["maintenance_epoch"]) and
      (is_nil(p["retirement_epoch"]) or E.safe_positive?(p["retirement_epoch"])) and
      p["kind"] in ~w(source projection) and E.sha256?(p["plan_sha256"]) and
      E.sha256?(p["body_sha256"]) and
      is_list(p["slots"]) and length(p["slots"]) <= 3 and
      Enum.all?(p["slots"], &(is_integer(&1) and &1 in 0..15)) and
      p["slots"] === Enum.sort(Enum.uniq(p["slots"])) and
      is_list(p["prepared"]) and length(p["prepared"]) <= 3 and
      Enum.all?(p["prepared"], fn ref ->
        exact?(ref, ~w(slot epoch)) and
          ref["slot"] in p["slots"] and native_id?(ref["epoch"])
      end) and
      p["prepared"] === Enum.sort_by(Enum.uniq_by(p["prepared"], & &1["slot"]), & &1["slot"]) and
      progress_active?(p["active"], p["slots"]) and
      (is_nil(p["active"]) or Enum.all?(p["prepared"], &(&1["slot"] !== p["active"]["slot"]))) and
      case p["status"] do
        "active" ->
          length(p["slots"]) === if(p["kind"] === "source", do: 3, else: 2) and
            is_nil(p["retirement_epoch"])

        "retiring" ->
          length(p["slots"]) === if(p["kind"] === "source", do: 3, else: 2) and
            E.safe_positive?(p["retirement_epoch"]) and
            p["retirement_epoch"] >= p["maintenance_epoch"]

        "finished" ->
          p["slots"] === [] and p["prepared"] === [] and is_nil(p["active"]) and
            is_nil(p["retirement_epoch"]) and p["unit"] === p["unit_limit"]

        "retired" ->
          p["slots"] === [] and p["prepared"] === [] and is_nil(p["active"]) and
            E.safe_positive?(p["retirement_epoch"]) and
            p["retirement_epoch"] >= p["maintenance_epoch"]
      end
  end

  defp progress_active?(nil, _), do: true

  defp progress_active?(a, slots),
    do:
      exact?(a, ~w(slot epoch key expected_revision byte_count sha256 offset publish)) and
        a["slot"] in slots and native_id?(a["epoch"]) and value_key?(a["key"]) and
        E.safe_uint?(a["expected_revision"]) and E.safe_uint?(a["offset"]) and
        is_integer(a["byte_count"]) and a["byte_count"] in 2..61_440 and
        a["offset"] < a["byte_count"] and E.sha256?(a["sha256"]) and is_boolean(a["publish"])

  defp progress_transition?(s, p) do
    t = s.request["request"]["progress"]

    progress_receipt?(p) and
      if(t["action"] === "retire",
        do: p["retirement_epoch"] === s.maintenance_epoch,
        else: p["maintenance_epoch"] === s.maintenance_epoch
      ) and
      if t["action"] === "start" do
        p["status"] === "active" and p["unit"] in [0, 1] and
          p["kind"] === t["kind"] and p["plan_sha256"] === t["plan_sha256"] and
          p["body_sha256"] === t["body_sha256"] and p["unit_limit"] === t["unit_limit"]
      else
        p["head_id"] === t["head_id"] and p["revision"] > t["revision"] and
          case t["action"] do
            "finish" -> p["status"] === "finished" and p["unit"] === t["unit"]
            "retire" -> p["status"] in ~w(retiring retired)
            "continue" -> p["status"] === "active"
          end and
          (t["action"] === "retire" or p["unit"] in [t["unit"], t["unit"] + 1])
      end
  end

  defp remember_progress(s, p) do
    s = s |> Map.put(:progress, p) |> Map.put(:progress_tag, progress_next_tag(p))

    if s[:operation] === :put,
      do: Map.update!(s, :checkpoint, &Map.put(&1, "progress", p)),
      else: s
  end

  defp progress_next_tag(p),
    do: %{
      "version" => 1,
      "action" => "continue",
      "head_id" => p["head_id"],
      "revision" => p["revision"],
      "unit" => p["unit"]
    }

  defp progress_return({:done, {status, value}}, %{progress: p})
       when status in [:ok, :continue] and is_map(value) and is_map(p),
       do: {:done, {status, Map.put(value, "progress", p)}}

  defp progress_return(result, _), do: result

  defp add_progress_reads({:call, request, state}, reads),
    do: {:call, request, Map.update!(state, :reads, &(&1 + reads))}

  defp dispatch_progress({:call, request, s}, tag, receipt) do
    s = s |> Map.put(:progress_tag, tag) |> Map.put(:progress, receipt)

    request =
      if read_request?(request),
        do: request,
        else: put_in(request, ["request", "progress"], tag)

    if s.reads <= @reads and host_frame_fits?(request),
      do: {:call, request, Map.put(s, :request, request)},
      else: error(:collection_budget)
  end

  defp abort_draft_stage(s) do
    p = s.progress
    limit = if s.kind === "source", do: 3, else: 2

    ref =
      if is_map(p["active"]),
        do: Map.take(p["active"], ~w(slot epoch)),
        else: List.first(p["prepared"])

    if s.cleanup_operations < limit do
      tag = %{
        "version" => 1,
        "action" => "retire",
        "head_id" => p["head_id"],
        "revision" => p["revision"]
      }

      inner =
        if is_nil(ref),
          do: %{"op" => "progress.retire", "generation" => s.generation},
          else: Map.merge(ref, %{"op" => "value.abort", "generation" => s.generation})

      call(
        Map.merge(s, %{progress_tag: tag, abort_previous: p, abort_ref: ref}),
        inner,
        :draft_abort_step
      )
    else
      error(:document_draft_abort_incomplete)
    end
  end

  defp call(s, inner, phase) do
    read =
      inner["op"] in ~w(snapshot value.stat value.layout value.read backup.metadata stage.inspect stage.list stage.available progress.inspect)

    reads = s.reads + if(read, do: 1, else: 0)
    effects = s.effects + if(read, do: 0, else: 1)

    inner =
      if not read and is_map(s[:progress_tag]),
        do:
          Map.put(
            inner,
            "progress",
            if(phase === :published,
              do: Map.put(s.progress_tag, "action", "finish"),
              else: s.progress_tag
            )
          ),
        else: inner

    request = %{"op" => "collection.store", "scope" => "project", "request" => inner}

    request =
      if s[:source_guard], do: Map.put(request, "source_guard", s.source_guard), else: request

    request = epoch_request(request, Map.get(s, :maintenance_epoch))

    cond do
      not read and effects > @effects and phase not in [:opened, :inline_prepared] and
        not (phase == :writing_parts and s.unit.offset == 0) and
          Map.has_key?(s, :unit) ->
        pause_unit(s)

      reads <= @reads and effects <= @effects and host_frame_fits?(request) ->
        {:call, request,
         Map.merge(s, %{phase: phase, reads: reads, effects: effects, request: request})}

      true ->
        error(:collection_budget)
    end
  end

  defp epoch_request(request, epoch) when is_integer(epoch) and epoch > 0 do
    if read_request?(request),
      do: request,
      else: put_in(request, ["request", "maintenance_epoch"], epoch)
  end

  defp epoch_request(request, _), do: request

  defp pause_unit(s) do
    u = s.unit

    active =
      Map.merge(u.ref, %{
        "offset" => u.offset,
        "state" => u.state,
        "key" => u.key,
        "expected_revision" => u.revision,
        "byte_count" => byte_size(u.bytes),
        "sha256" => E.sha256(u.bytes)
      })

    checkpoint = Map.put(s.checkpoint, "active", active)

    {:done,
     {:continue,
      %{"status" => "staged", "continuation" => checkpoint, "coverage" => coverage(s, false)}}}
  end

  defp admitted_inline(s, result) do
    bytes =
      case result["document_store"] do
        %{"version" => 1, "inline_bytes" => 8192} ->
          8192

        %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2} ->
          8192

        %{"version" => version, "inline_bytes" => 8192, "write_parts" => 2}
        when version in [3, 4] ->
          8192

        _ ->
          0
      end

    parts =
      case result["document_store"] do
        %{"version" => version, "inline_bytes" => 8192, "write_parts" => 2}
        when version in [2, 3, 4] ->
          2

        _ ->
          0
      end

    s |> Map.put(:inline_bytes, bytes) |> Map.put(:write_parts, parts)
  end

  defp inline_request(s, key, bytes, revision, ref) do
    request = %{
      "op" => if(ref, do: "value.prepare_inline", else: "value.put_inline"),
      "key" => key,
      "expected_revision" => revision,
      "byte_count" => byte_size(bytes),
      "sha256" => E.sha256(bytes),
      "data" => bytes,
      "generation" => s.generation
    }

    if ref, do: Map.merge(request, ref), else: request
  end

  defp inline_fits?(s, request) do
    byte_size(request["data"]) <= Map.get(s, :inline_bytes, 0) and
      state_frame_fits?(s, request)
  end

  defp state_frame_fits?(s, request) do
    request =
      if is_map(s[:progress_tag]), do: Map.put(request, "progress", s.progress_tag), else: request

    request = %{"op" => "collection.store", "scope" => "project", "request" => request}

    request =
      if s[:source_guard], do: Map.put(request, "source_guard", s.source_guard), else: request

    host_frame_fits?(epoch_request(request, s[:maintenance_epoch]))
  end

  defp frame_fits?(request, epoch \\ nil),
    do:
      host_frame_fits?(
        epoch_request(
          %{"op" => "collection.store", "scope" => "project", "request" => request},
          epoch
        )
      )

  defp host_frame_fits?(request),
    do:
      Ipse.Extension.validate(%{"api_version" => 1, "kind" => "host_call", "request" => request}) ==
        :ok

  defp fetch(s, key, after_read),
    do:
      call(
        s,
        %{"op" => "value.stat", "key" => key, "generation" => s.generation},
        {:stat, key, after_read}
      )

  defp fetch_ref(s, ref, after_read) do
    call(
      s,
      %{"op" => "value.read", "key" => ref["key"], "offset" => 0, "generation" => s.generation},
      {:known_ref, ref, after_read}
    )
  end

  defp blocks(bytes, plan),
    do: packed_blocks(bytes, %{"version" => 2, "kind" => "source_data", "bundle_sha256" => plan})

  defp lexical_blocks(bytes, hash, source_hash),
    do:
      packed_blocks(bytes, %{
        "version" => 1,
        "kind" => "source_lexical",
        "bundle_sha256" => hash,
        "source_bundle_sha256" => source_hash
      })

  defp packed_blocks(bytes, header) do
    pieces =
      Stream.unfold(bytes, fn
        "" ->
          nil

        rest ->
          part = utf8(rest, 4096)
          {part, binary_part(rest, byte_size(part), byte_size(rest) - byte_size(part))}
      end)
      |> Enum.to_list()

    Enum.reduce(pieces, [], fn piece, blocks ->
      fresh = Map.merge(header, %{"ordinal" => length(blocks), "pieces" => [piece]})

      case blocks do
        [] ->
          [fresh]

        _ ->
          last = List.last(blocks)
          next = Map.update!(last, "pieces", &(&1 ++ [piece]))

          if byte_size(json(next)) <= @block_bytes and length(next["pieces"]) <= 12,
            do: List.replace_at(blocks, -1, next),
            else: blocks ++ [fresh]
      end
    end)
  end

  defp coverage(s, selected),
    do: %{
      "reads_used" => s.reads,
      "effects_used" => s.effects,
      "cache_scope" =>
        case Map.get(s, :read_mode) do
          :lexical -> "source_lexical_preparation"
          :bundles -> "source_bundle_preparation"
          _ -> if(selected, do: "explicit_selected_sources", else: "staged_source")
        end,
      "evidence_readable" => selected and Map.get(s, :read_mode) == :selected,
      "namespace_complete" => false,
      "selection_complete" => selected,
      "population_qualified" => false
    }

  defp source(attrs), do: if(E.valid_source?(attrs), do: {:ok, attrs}, else: E.source(attrs))

  defp empty_catalog(p),
    do: %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => p["partition"],
      "generation" => 0,
      "floor" => 0,
      "sources" => 0,
      "extracted_bytes" => 0,
      "chunks" => 0,
      "entities" => 0,
      "assertions" => 0,
      "pages" => []
    }

  defp catalog?(c, p),
    do:
      exact?(
        c,
        ~w(version kind partition generation floor sources extracted_bytes chunks entities assertions pages)
      ) and
        c["version"] === 1 and c["kind"] == "catalog" and c["partition"] == p["partition"] and
        Enum.all?(
          ~w(generation floor sources extracted_bytes chunks entities assertions),
          &E.safe_uint?(c[&1])
        ) and
        c["sources"] <= @sources and c["extracted_bytes"] <= 20 * 1024 * 1024 and
        c["chunks"] <= 10_000 and
        c["entities"] <= 5000 and c["assertions"] <= 20_000 and is_list(c["pages"]) and
        length(c["pages"]) <= 63 and
        length(c["pages"]) == div(c["sources"] + @catalog_rows - 1, @catalog_rows) and
        Enum.all?(c["pages"], &ref?/1)

  defp source_head?(h, key),
    do:
      ((exact?(
          h,
          ~w(version kind source_key generation revision ordinal text_bytes chunks byte_count bundle_sha256 blocks)
        ) and
          h["version"] === 1) or
         (exact?(
            h,
            ~w(version kind source_key generation revision ordinal text_bytes chunks byte_count bundle_sha256 blocks lexical)
          ) and
            h["version"] === 2 and lexical_manifest?(h["lexical"]))) and
        h["kind"] == "source_head" and h["source_key"] == key and
        Enum.all?(
          ~w(generation revision ordinal text_bytes chunks byte_count),
          &E.safe_uint?(h[&1])
        ) and
        h["ordinal"] < @sources and h["text_bytes"] <= 65_536 and h["chunks"] <= 32 and
        h["generation"] > 0 and h["revision"] > 0 and h["byte_count"] in 1..@bundle_bytes and
        E.sha256?(h["bundle_sha256"]) and
        is_list(h["blocks"]) and length(h["blocks"]) in 1..32 and Enum.all?(h["blocks"], &ref?/1)

  defp lexical_manifest?(m),
    do:
      exact?(m, ~w(version recipe content_sha256 byte_count bundle_sha256 blocks)) and
        m["version"] === 1 and m["recipe"] == E.lexical_recipe() and
        E.sha256?(m["content_sha256"]) and E.sha256?(m["bundle_sha256"]) and
        is_integer(m["byte_count"]) and m["byte_count"] in 1..(4 * @bundle_bytes) and
        is_list(m["blocks"]) and length(m["blocks"]) in 1..128 and Enum.all?(m["blocks"], &ref?/1)

  defp valid_page?(row, ref, ordinal, p),
    do:
      is_map(row) and ref?(ref) and row["sha256"] == ref["sha256"] and
        ref["key"] == "catalog.#{p["partition"]}.#{ordinal}" and
        exact?(row["value"], ~w(version kind partition ordinal rows)) and
        row["value"]["version"] === 1 and
        row["value"]["kind"] == "catalog_page" and row["value"]["partition"] == p["partition"] and
        row["value"]["ordinal"] == ordinal and is_list(row["value"]["rows"]) and
        length(row["value"]["rows"]) in 1..@catalog_rows and
        Enum.all?(
          row["value"]["rows"],
          &(exact?(&1, ~w(source_key head_sha256)) and E.sha256?(&1["source_key"]) and
              E.sha256?(&1["head_sha256"]))
        ) and
        row["value"]["rows"] ==
          Enum.sort_by(Enum.uniq_by(row["value"]["rows"], & &1["source_key"]), & &1["source_key"])

  defp checkpoint?(nil, _, _), do: true

  defp checkpoint?(c, hash, rev),
    do:
      ((exact?(c, ~w(version plan_sha256 expected_revision unit stages base active)) and
          c["version"] === 3) or
         (exact?(
            c,
            ~w(version plan_sha256 expected_revision unit stages base active maintenance_epoch epoch_binding_sha256)
          ) and
            c["version"] === 4 and E.safe_positive?(c["maintenance_epoch"]) and
            c["epoch_binding_sha256"] === source_plan(hash, c["maintenance_epoch"])) or
         (exact?(
            c,
            ~w(version plan_sha256 expected_revision unit stages base active maintenance_epoch epoch_binding_sha256 progress)
          ) and
            c["version"] === 5 and E.safe_positive?(c["maintenance_epoch"]) and
            c["epoch_binding_sha256"] === source_plan(hash, c["maintenance_epoch"]) and
            progress_receipt?(c["progress"]) and c["progress"]["status"] === "active")) and
        c["plan_sha256"] == hash and
        c["expected_revision"] == rev and E.safe_uint?(c["unit"]) and
        is_list(c["stages"]) and length(c["stages"]) <= 3 and
        (c["unit"] > 0 or is_map(c["active"])) and
        (is_nil(c["active"]) or
           (exact?(
              c["active"],
              ~w(slot epoch offset state key expected_revision byte_count sha256)
            ) and
              E.safe_uint?(c["active"]["offset"]) and c["active"]["state"] in ~w(open sealed) and
              c["active"]["offset"] <= c["active"]["byte_count"] and
              E.sha256?(c["active"]["sha256"]))) and
        Enum.all?(
          c["stages"],
          &(exact?(&1, ~w(slot epoch)) and &1["slot"] in 0..15 and is_binary(&1["epoch"]) and
              Regex.match?(~r/\A[0-9a-f]{32}\z/, &1["epoch"]))
        )

  defp source_plan(hash, 0), do: hash

  defp source_plan(hash, epoch),
    do: E.sha256(json(%{"version" => 4, "source_sha256" => hash, "maintenance_epoch" => epoch}))

  defp stamp(nil), do: %{"revision" => 0, "sha256" => nil}
  defp stamp(row), do: Map.take(row, ~w(revision sha256))
  defp revision(nil), do: 0
  defp revision(row), do: row["revision"]
  defp catalog_key(s), do: "catalog." <> s.profile["partition"]
  defp page_key(s, n), do: "catalog." <> s.profile["partition"] <> ".#{n}"
  defp source_key(s, key), do: "source." <> s.profile["partition"] <> "." <> key
  defp data_key(s, sha), do: "data." <> s.profile["partition"] <> "." <> sha

  defp ref?(r),
    do:
      exact?(r, ~w(key sha256)) and is_binary(r["key"]) and byte_size(r["key"]) <= 96 and
        E.sha256?(r["sha256"])

  defp value_key?(key),
    do:
      is_binary(key) and byte_size(key) in 1..96 and
        not String.starts_with?(key, "host.") and
        Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/, key)

  defp profile?(p),
    do:
      exact?(p, ~w(kind scope partition)) and p["kind"] == "collection" and
        p["scope"] == "project" and
        is_binary(p["partition"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, p["partition"])

  defp utf8(bytes, count) do
    piece = binary_part(bytes, 0, min(byte_size(bytes), count))
    if String.valid?(piece), do: piece, else: utf8(bytes, count - 1)
  end

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp error(code), do: {:done, {:error, code, %{}}}

  @doc false
  def backup_start(
        profile,
        :page,
        %{"generation" => generation, "offset" => offset, "limit" => limit} = args
      ) do
    if backup_exact?(args, ~w(generation offset limit)) and E.safe_uint?(generation) and
         E.safe_uint?(offset) and offset <= 8192 and is_integer(limit) and limit in 1..8 do
      state = %{
        profile: profile,
        generation: generation,
        offset: offset,
        limit: limit,
        reads: 0,
        phase: :records,
        descriptor: nil,
        lineage: [],
        rows: [],
        assembled: [],
        body: "",
        layout: nil
      }

      backup_metadata(state, "records", offset, limit)
    else
      backup_error(:invalid_collection_backup_page)
    end
  end

  def backup_start(_, _, _), do: backup_error(:invalid_collection_backup_page)

  @doc false
  def backup_resume(%{backup_state: state, inner: inner}, outcome),
    do: backup_advance(__MODULE__.resume(inner, outcome), state)

  defp backup_metadata(state, section, offset, limit),
    do:
      backup_io(state, :backup_metadata, %{
        "generation" => state.generation,
        "section" => section,
        "offset" => offset,
        "limit" => limit
      })

  defp backup_io(state, operation, args),
    do: backup_advance(__MODULE__.start(state.profile, operation, args), state)

  defp backup_advance({:call, request, inner}, state) do
    if __MODULE__.read_request?(request) and state.reads < @reads,
      do: {:call, request, %{backup_state: %{state | reads: state.reads + 1}, inner: inner}},
      else: backup_error(:collection_backup_read_budget)
  end

  defp backup_advance({:done, {:ok, value}}, state), do: backup_next(state, value)
  defp backup_advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}
  defp backup_advance({:done, {:error, code, _}}, _), do: backup_error(code)
  defp backup_advance(_, _), do: backup_error(:collection_backup_corrupt)

  defp backup_next(%{phase: :records} = state, result) do
    descriptor = result["descriptor"]
    rows = result["rows"]

    with true <- backup_metadata?(result, state, "records", state.offset),
         true <-
           backup_compact_descriptor?(descriptor) and
             descriptor["generation"] === state.generation,
         true <- is_integer(descriptor["records"]) and descriptor["records"] in 1..8192,
         true <-
           state.offset < descriptor["records"] and is_list(rows) and
             length(rows) === min(state.limit, descriptor["records"] - state.offset),
         true <-
           result["next"] ===
             if(state.offset + length(rows) < descriptor["records"],
               do: state.offset + length(rows),
               else: nil
             ),
         true <- Enum.all?(rows, &backup_record_row?/1),
         keys = Enum.map(rows, &hd/1),
         true <- keys === Enum.sort(Enum.uniq(keys)),
         true <-
           E.safe_uint?(descriptor["floor_lineage_count"]) and
             descriptor["floor_lineage_count"] <= 128 do
      state = %{state | phase: :lineage, descriptor: descriptor, rows: rows}
      backup_metadata(state, "lineage", 0, 8)
    else
      _ -> backup_error(:collection_backup_corrupt)
    end
  end

  defp backup_next(%{phase: :lineage} = state, result) do
    offset = length(state.lineage)

    with true <- backup_metadata?(result, state, "lineage", offset),
         true <- result["descriptor"] === state.descriptor,
         true <-
           length(result["rows"]) === min(8, state.descriptor["floor_lineage_count"] - offset),
         true <-
           result["next"] ===
             if(offset + length(result["rows"]) < state.descriptor["floor_lineage_count"],
               do: offset + length(result["rows"]),
               else: nil
             ),
         lineage = state.lineage ++ result["rows"],
         true <-
           length(lineage) <= state.descriptor["floor_lineage_count"] and
             Enum.all?(lineage, &backup_id?/1) and length(Enum.uniq(lineage)) === length(lineage) do
      if is_integer(result["next"]) do
        backup_metadata(%{state | lineage: lineage}, "lineage", result["next"], 8)
      else
        with true <- length(lineage) === state.descriptor["floor_lineage_count"],
             {:ok, digest} <- Ipse.Extension.canonical_digest([lineage]),
             true <- digest === state.descriptor["floor_lineage_sha256"] do
          descriptor =
            state.descriptor
            |> Map.delete("floor_lineage_count")
            |> Map.put("floor_lineage", lineage)

          backup_read_layout(%{state | descriptor: descriptor, lineage: lineage, phase: :layout})
        else
          _ -> backup_error(:collection_backup_corrupt)
        end
      end
    else
      _ -> backup_error(:collection_backup_corrupt)
    end
  end

  defp backup_next(%{phase: :layout, rows: [[key, revision, _, hash, bytes] | _]} = state, result) do
    layout = result["layout"]

    if is_map(layout) and layout["revision"] === revision and
         layout["record_sha256"] === hash and layout["record_bytes"] === bytes do
      backup_read_chunk(%{state | phase: :chunk, layout: layout, body: ""}, key, 0)
    else
      backup_error(:collection_backup_corrupt)
    end
  end

  defp backup_next(
         %{phase: :chunk, rows: [[key, revision, _, _, _] = row | rest]} = state,
         result
       ) do
    layout = state.layout
    data = result["data"]

    with true <- result["key"] === key and result["revision"] === revision,
         true <-
           result["sha256"] === layout["sha256"] and
             result["byte_count"] === layout["byte_count"],
         true <-
           result["offset"] === byte_size(state.body) and is_binary(data) and
             byte_size(data) in 1..6144,
         body = state.body <> data,
         true <- byte_size(body) <= layout["byte_count"] do
      if is_nil(result["next"]) do
        with true <- byte_size(body) === layout["byte_count"],
             {:ok, record} <- backup_reconstruct(row, layout, body) do
          state = %{
            state
            | rows: rest,
              assembled: [record | state.assembled],
              body: "",
              layout: nil
          }

          if rest === [] do
            records = Enum.reverse(state.assembled)

            next =
              if state.offset + length(records) < state.descriptor["records"],
                do: List.last(records)["key"]

            {:done,
             {:ok, %{"descriptor" => state.descriptor, "records" => records, "next" => next}}}
          else
            backup_read_layout(%{state | phase: :layout})
          end
        else
          _ -> backup_error(:collection_backup_corrupt)
        end
      else
        if result["next"] === byte_size(body),
          do: backup_read_chunk(%{state | body: body}, key, result["next"]),
          else: backup_error(:collection_backup_corrupt)
      end
    else
      _ -> backup_error(:collection_backup_corrupt)
    end
  end

  defp backup_next(_, _), do: backup_error(:collection_backup_corrupt)

  defp backup_read_layout(%{rows: [[key | _] | _]} = state),
    do: backup_io(state, :value_layout, %{"key" => key, "generation" => state.generation})

  defp backup_read_layout(_), do: backup_error(:collection_backup_corrupt)

  defp backup_read_chunk(state, key, offset),
    do:
      backup_io(state, :value_read_chunk, %{
        "key" => key,
        "generation" => state.generation,
        "offset" => offset
      })

  defp backup_metadata?(result, state, section, offset) do
    result["generation"] === state.generation and result["section"] === section and
      result["offset"] === offset and is_list(result["rows"]) and
      (is_nil(result["next"]) or
         (is_integer(result["next"]) and result["next"] === offset + length(result["rows"]) and
            result["next"] > offset))
  end

  defp backup_record_row?([key, revision, operation_id, sha256, bytes]),
    do:
      is_binary(key) and byte_size(key) in 1..96 and
        Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/, key) and
        not String.starts_with?(key, "host.") and E.safe_positive?(revision) and
        backup_id?(operation_id) and E.sha256?(sha256) and is_integer(bytes) and
        bytes in 2..65_536

  defp backup_record_row?(_), do: false
  defp backup_id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)

  defp backup_result_ref?(ref) when is_map(ref) do
    delivery = ref["delivery"]

    backup_exact?(ref, ~w(version session_id delivery)) and ref["version"] === 1 and
      backup_id?(ref["session_id"]) and
      backup_exact?(delivery, ~w(version kind output_id byte_count sha256 historical_receipt)) and
      delivery["version"] === 1 and delivery["kind"] === "saved.result" and
      E.sha256?(delivery["output_id"]) and E.sha256?(delivery["sha256"]) and
      is_integer(delivery["byte_count"]) and delivery["byte_count"] in 1..(4 * 1024 * 1024) and
      delivery["historical_receipt"] === true
  end

  defp backup_result_ref?(_), do: false

  defp backup_restore_request?(request, result_input, plan_input) do
    operation = request["op"]

    fields =
      case operation do
        "restore.open" ->
          ~w(op expected_generation expected_epoch input_sha256 plan_binding_sha256 dependency_union_sha256)

        "restore.page" ->
          ~w(op expected_generation expected_epoch migration_id ordinal input_sha256 data_binding_sha256 plan_binding_sha256 dependency_union_sha256)

        op when op in ~w(restore.commit restore.abort) ->
          ~w(op expected_generation expected_epoch migration_id plan_binding_sha256 dependency_union_sha256)

        op when op in ~w(restore.rollback restore.checkpoint_drop) ->
          ~w(op expected_generation expected_epoch checkpoint_id plan_binding_sha256 dependency_union_sha256)

        _ ->
          []
      end

    expected_refs =
      case operation do
        "restore.open" -> {true, false}
        "restore.page" -> {true, true}
        op when op in ~w(restore.commit restore.rollback) -> {false, true}
        op when op in ~w(restore.abort restore.checkpoint_drop) -> {false, false}
        _ -> :invalid
      end

    with true <- fields != [] and backup_exact?(request, fields),
         true <- {not is_nil(result_input), not is_nil(plan_input)} === expected_refs,
         true <- is_nil(result_input) or backup_result_ref?(result_input),
         true <- is_nil(plan_input) or backup_result_ref?(plan_input),
         true <-
           E.safe_uint?(request["expected_generation"]) and
             request["expected_generation"] < E.safe_integer_max() and
             E.safe_uint?(request["expected_epoch"]),
         true <-
           E.sha256?(request["plan_binding_sha256"]) and
             E.sha256?(request["dependency_union_sha256"]),
         {:ok, empty_union} <- Ipse.Extension.canonical_digest([[]]),
         true <- request["dependency_union_sha256"] === empty_union,
         true <- not Map.has_key?(request, "input_sha256") or E.sha256?(request["input_sha256"]),
         true <- not Map.has_key?(request, "migration_id") or backup_id?(request["migration_id"]),
         true <-
           not Map.has_key?(request, "checkpoint_id") or backup_id?(request["checkpoint_id"]),
         true <- operation !== "restore.page" or E.safe_uint?(request["ordinal"]),
         plan_ref = if(operation === "restore.open", do: result_input, else: plan_input),
         true <- is_nil(plan_ref) or backup_ref_digest?(plan_ref, request["plan_binding_sha256"]),
         true <-
           operation !== "restore.page" or
             backup_ref_digest?(result_input, request["data_binding_sha256"]) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp backup_ref_digest?(ref, expected),
    do: match?({:ok, ^expected}, Ipse.Extension.canonical_digest([ref]))

  defp backup_restore_receipt?(request, receipt, native_hash, operation_id) do
    expected = ~w(generation floor request_sha256)

    fields =
      case request["op"] do
        op when op in ~w(restore.open restore.page) -> expected ++ ["migration_id"]
        "restore.commit" -> expected ++ ["checkpoint_id"]
        _ -> expected
      end

    backup_exact?(receipt, fields) and
      receipt["generation"] === request["expected_generation"] + 1 and
      E.safe_uint?(receipt["floor"]) and receipt["request_sha256"] === native_hash and
      case request["op"] do
        "restore.open" ->
          receipt["migration_id"] === operation_id

        "restore.page" ->
          receipt["migration_id"] === request["migration_id"]

        "restore.commit" ->
          is_nil(receipt["checkpoint_id"]) or receipt["checkpoint_id"] === operation_id

        _ ->
          true
      end
  end

  defp backup_read_input(state) do
    request = %{
      "result_input" => state.result_input,
      "plan_input" => state.plan_input,
      "offset" => byte_size(state.bytes)
    }

    operation = if state[:kind] === :fact, do: :fact_result_input_read, else: :result_input_read
    backup_input_advance(start(state.profile, operation, request), state)
  end

  defp backup_input_advance({:call, request, inner}, state) do
    if read_request?(request) and state.reads < @reads,
      do:
        {:call, request, %{backup_input_state: %{state | reads: state.reads + 1}, inner: inner}},
      else: backup_error(:collection_backup_read_budget)
  end

  defp backup_input_advance({:done, {:ok, result}}, state) do
    bytes = state.bytes <> result["data"]
    delivery = state.result_input["delivery"]
    origin = result["origin"]
    owner = if state[:kind] === :fact, do: result["owner"], else: nil

    cond do
      state[:kind] === :fact and state.owner !== :unset and state.owner !== owner ->
        backup_error(:collection_result_input_corrupt)

      state.origin !== :unset and state.origin !== origin ->
        backup_error(:collection_result_input_corrupt)

      byte_size(bytes) > delivery["byte_count"] ->
        backup_error(:collection_result_input_corrupt)

      is_integer(result["next"]) and result["next"] === byte_size(bytes) ->
        state = %{state | bytes: bytes, origin: origin}
        state = if state[:kind] === :fact, do: %{state | owner: owner}, else: state
        backup_read_input(state)

      is_nil(result["next"]) and byte_size(bytes) === delivery["byte_count"] and
          E.sha256(bytes) === delivery["sha256"] ->
        case ResultDocument.decode(bytes, %{"type" => "object"}) do
          {:ok, value} ->
            value = %{
              "result_input" => state.result_input,
              "value" => value,
              "raw_sha256" => delivery["sha256"],
              "byte_count" => byte_size(bytes),
              "origin" => origin
            }

            value =
              if state[:kind] === :fact do
                value
                |> Map.delete("origin")
                |> Map.put("owner", Map.delete(owner, "invocation_id"))
                |> Map.put("reads_used", state.reads)
              else
                value
              end

            {:done, {:ok, value}}

          _ ->
            backup_error(:collection_result_input_corrupt)
        end

      true ->
        backup_error(:collection_result_input_corrupt)
    end
  rescue
    _ -> backup_error(:collection_result_input_corrupt)
  end

  defp backup_input_advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}
  defp backup_input_advance({:done, {:error, code, _}}, _), do: backup_error(code)
  defp backup_input_advance(_, _), do: backup_error(:collection_result_input_corrupt)

  defp backup_input_owner?(owner),
    do:
      backup_exact?(owner, ~w(project_id session_id identity_sha256 invocation_id)) and
        E.sha256?(owner["project_id"]) and E.sha256?(owner["identity_sha256"]) and
        backup_id?(owner["session_id"]) and backup_id?(owner["invocation_id"])

  defp backup_origin?(origin, ref) do
    backup_exact?(
      origin,
      ~w(version artifact_sha256 invocation_id command_id action owner descriptor metadata_sha256)
    ) and
      origin["version"] === 1 and E.sha256?(origin["artifact_sha256"]) and
      E.sha256?(origin["metadata_sha256"]) and backup_id?(origin["invocation_id"]) and
      origin["command_id"] === "source" and origin["action"] in ~w(backup_page backup_plan) and
      backup_input_owner?(origin["owner"]) and
      origin["owner"]["session_id"] === ref["session_id"] and
      origin["owner"]["invocation_id"] === origin["invocation_id"] and
      backup_compact_descriptor?(origin["descriptor"])
  rescue
    _ -> false
  end

  defp backup_origin_matches?(selected, action, descriptor) do
    origin = selected["origin"]
    ref = selected["result_input"]

    compact =
      descriptor
      |> Map.delete("floor_lineage")
      |> Map.put("floor_lineage_count", length(descriptor["floor_lineage"]))

    backup_origin?(origin, ref) and origin["action"] === action and
      origin["descriptor"] === compact
  rescue
    _ -> false
  end

  defp backup_error(code), do: {:done, {:error, code, %{}}}

  defp backup_restore_action_args?(action, args, result_input, plan_input) do
    common = ~w(expected_generation expected_epoch)

    extra =
      case action do
        "open" -> []
        "page" -> ~w(migration_id ordinal)
        "commit" -> ~w(migration_id)
        "abort" -> ~w(migration_id plan_binding_sha256)
        "rollback" -> ~w(checkpoint_id)
        "checkpoint_drop" -> ~w(checkpoint_id plan_binding_sha256)
      end

    expected_refs =
      case action do
        "open" -> {true, false}
        "page" -> {true, true}
        op when op in ~w(commit rollback) -> {false, true}
        _ -> {false, false}
      end

    backup_exact?(args, common ++ extra) and
      {not is_nil(result_input), not is_nil(plan_input)} === expected_refs and
      (is_nil(result_input) or backup_result_ref?(result_input)) and
      (is_nil(plan_input) or backup_result_ref?(plan_input)) and
      E.safe_uint?(args["expected_generation"]) and
      args["expected_generation"] < E.safe_integer_max() and
      E.safe_uint?(args["expected_epoch"]) and
      (action not in ~w(open rollback) or args["expected_epoch"] < E.safe_integer_max()) and
      (not Map.has_key?(args, "migration_id") or backup_id?(args["migration_id"])) and
      (not Map.has_key?(args, "checkpoint_id") or backup_id?(args["checkpoint_id"])) and
      (not Map.has_key?(args, "ordinal") or E.safe_uint?(args["ordinal"])) and
      (not Map.has_key?(args, "plan_binding_sha256") or E.sha256?(args["plan_binding_sha256"]))
  end

  defp backup_restore_binding(nil, args), do: {:ok, args["plan_binding_sha256"]}
  defp backup_restore_binding(ref, _), do: Ipse.Extension.canonical_digest([ref])

  defp backup_restore_action_advance({:call, request, inner}, state) do
    read = read_request?(request)
    reads = state.reads + if(read, do: 1, else: 0)
    effects = state.effects + if(read, do: 0, else: 1)

    if reads <= @reads and effects <= @effects,
      do:
        {:call, request,
         %{backup_restore_state: %{state | reads: reads, effects: effects}, inner: inner}},
      else: backup_error(:collection_budget)
  end

  defp backup_restore_action_advance({:done, {:ok, result}}, %{phase: :input} = state) do
    with true <- result["result_input"] === state.result_input,
         true <-
           state.action !== "open" or
             (backup_descriptor?(result["value"]["descriptor"]) and
                backup_origin_matches?(result, "backup_plan", result["value"]["descriptor"]) and
                result["value"]["descriptor"]["maintenance_epoch"] < E.safe_integer_max()),
         {:ok, input_sha} <- Ipse.Extension.canonical_object_digest(result["value"]) do
      source_epoch =
        if state.action === "open",
          do: result["value"]["descriptor"]["maintenance_epoch"],
          else: 0

      backup_restore_issue(Map.put(state, :source_epoch, source_epoch), input_sha)
    else
      _ -> backup_error(:collection_result_input_corrupt)
    end
  end

  defp backup_restore_action_advance({:done, {:ok, result}}, %{phase: :mutation} = state) do
    epoch =
      case state.action do
        "open" -> max(state.args["expected_epoch"], state.source_epoch) + 1
        "rollback" -> state.args["expected_epoch"] + 1
        _ -> state.args["expected_epoch"]
      end

    {:done,
     {:ok,
      Map.merge(result, %{
        "action" => state.action,
        "maintenance_epoch" => epoch,
        "plan_binding_sha256" => state.plan_binding,
        "coverage" => %{"reads_used" => state.reads, "effects_used" => state.effects}
      })}}
  end

  defp backup_restore_action_advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}
  defp backup_restore_action_advance({:done, {:error, code, _}}, _), do: backup_error(code)
  defp backup_restore_action_advance(_, _), do: backup_error(:collection_backup_corrupt)

  defp backup_restore_issue(state, input_sha) do
    inner = %{
      "op" => "restore." <> state.action,
      "expected_generation" => state.args["expected_generation"],
      "expected_epoch" => state.args["expected_epoch"],
      "plan_binding_sha256" => state.plan_binding,
      "dependency_union_sha256" => state.empty_union
    }

    inner = Map.merge(inner, Map.take(state.args, ~w(migration_id checkpoint_id ordinal)))

    inner =
      if state.action in ~w(open page), do: Map.put(inner, "input_sha256", input_sha), else: inner

    with {:ok, inner} <- backup_restore_data_binding(inner, state) do
      backup_restore_action_advance(
        start(state.profile, :restore_mutation, %{
          "request" => inner,
          "result_input" => state.result_input,
          "plan_input" => state.plan_input
        }),
        %{state | phase: :mutation}
      )
    else
      _ -> backup_error(:invalid_collection_restore)
    end
  end

  defp backup_restore_data_binding(inner, %{action: "page", result_input: ref}) do
    with {:ok, hash} <- Ipse.Extension.canonical_digest([ref]),
         do: {:ok, Map.put(inner, "data_binding_sha256", hash)}
  end

  defp backup_restore_data_binding(inner, _), do: {:ok, inner}

  defp backup_validation_read(state, result_input, plan_input),
    do:
      backup_validation_advance(
        start(state.profile, :selected_backup_result, %{
          "result_input" => result_input,
          "plan_input" => plan_input
        }),
        state
      )

  defp backup_validation_advance({:call, request, inner}, state) do
    if read_request?(request) and state.reads < @reads,
      do:
        {:call, request,
         %{backup_validation_state: %{state | reads: state.reads + 1}, inner: inner}},
      else: backup_error(:collection_backup_read_budget)
  end

  defp backup_validation_advance({:done, {:ok, selected}}, %{phase: :plan} = state) do
    plan = selected["value"]
    inputs = get_in(plan, ["plan", "data_inputs"])

    with true <- selected["result_input"] === state.plan_ref,
         true <- backup_origin_matches?(selected, "backup_plan", plan["descriptor"]),
         true <- is_list(inputs) and length(inputs) in 1..4,
         true <-
           Enum.all?(inputs, &backup_result_ref?/1) and
             length(Enum.uniq(inputs)) === length(inputs),
         true <- state.selected in inputs do
      [next | _] = inputs

      backup_validation_read(
        %{state | phase: :inputs, plan: plan, inputs: inputs},
        next,
        state.plan_ref
      )
    else
      _ -> backup_error(:collection_backup_plan_invalid)
    end
  end

  defp backup_validation_advance({:done, {:ok, selected}}, %{phase: :inputs} = state) do
    [expected | rest] = state.inputs

    if selected["result_input"] === expected do
      state = %{state | inputs: rest, pages: [selected | state.pages]}

      if rest === [] do
        pages = Enum.reverse(state.pages)
        records = Enum.flat_map(pages, &get_in(&1, ["value", "records"]))
        page = Enum.find(pages, &(&1["result_input"] === state.selected))

        with :ok <- backup_verify_plan(state.plan, pages),
             true <-
               Enum.all?(
                 pages,
                 &backup_origin_matches?(&1, "backup_page", state.plan["descriptor"])
               ),
             true <-
               IpseKnowledge.Store.Collection.Projection.completed_backup?(
                 state.profile,
                 records,
                 state.plan["descriptor"]["maintenance_epoch"]
               ),
             true <- is_map(page) do
          {:done, {:ok, page["value"]}}
        else
          _ -> backup_error(:collection_backup_incomplete_domain)
        end
      else
        backup_validation_read(state, hd(rest), state.plan_ref)
      end
    else
      backup_error(:collection_backup_plan_invalid)
    end
  rescue
    _ -> backup_error(:collection_backup_plan_invalid)
  end

  defp backup_validation_advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}
  defp backup_validation_advance({:done, {:error, code, _}}, _), do: backup_error(code)
  defp backup_validation_advance(_, _), do: backup_error(:collection_backup_plan_invalid)

  defp backup_plan_metadata(state, offset),
    do:
      backup_plan_advance(
        start(state.profile, :backup_metadata, %{
          "generation" => state.generation,
          "section" => state.section,
          "offset" => offset,
          "limit" => 8
        }),
        state
      )

  defp backup_plan_advance({:call, request, inner}, state) do
    if read_request?(request) and state.reads < @reads,
      do: {:call, request, %{backup_plan_state: %{state | reads: state.reads + 1}, inner: inner}},
      else: backup_error(:collection_backup_read_budget)
  end

  defp backup_plan_advance({:done, {:ok, value}}, %{section: "inputs"} = state) do
    [expected | rest] = state.inputs

    if value["result_input"] === expected do
      state = %{state | inputs: rest, pages: [value | state.pages]}

      if rest === [] do
        case backup_plan(
               state.descriptor,
               state.rows,
               state.operations,
               Enum.reverse(state.pages)
             ) do
          {:ok, plan} -> {:done, {:ok, plan}}
          {:error, code} -> backup_error(code)
        end
      else
        backup_plan_input(state)
      end
    else
      backup_error(:collection_backup_plan_invalid)
    end
  end

  defp backup_plan_advance({:done, {:ok, result}}, state) do
    current =
      case state.section do
        "records" -> state.rows
        "operations" -> state.operations
        "lineage" -> state.lineage
      end

    descriptor = result["descriptor"]
    count_key = if state.section === "lineage", do: "floor_lineage_count", else: state.section
    maximum = if state.section === "records", do: 32, else: 128

    with true <-
           backup_compact_descriptor?(descriptor) and
             descriptor["generation"] === state.generation,
         true <- is_nil(state.descriptor) or descriptor === state.descriptor,
         total when is_integer(total) and total in 0..maximum//1 <- descriptor[count_key],
         true <- state.section !== "records" or total > 0,
         offset = length(current),
         true <- backup_metadata?(result, state, state.section, offset),
         true <- length(result["rows"]) === min(8, total - offset),
         true <-
           result["next"] ===
             if(offset + length(result["rows"]) < total,
               do: offset + length(result["rows"]),
               else: nil
             ) do
      state = Map.put(state, :descriptor, descriptor)
      current = current ++ result["rows"]

      state =
        case state.section do
          "records" -> %{state | rows: current}
          "operations" -> %{state | operations: current}
          "lineage" -> %{state | lineage: current}
        end

      if is_integer(result["next"]) do
        backup_plan_metadata(state, result["next"])
      else
        case state.section do
          "records" ->
            backup_plan_metadata(%{state | section: "operations"}, 0)

          "operations" ->
            backup_plan_metadata(%{state | section: "lineage"}, 0)

          "lineage" ->
            descriptor =
              descriptor
              |> Map.delete("floor_lineage_count")
              |> Map.put("floor_lineage", state.lineage)

            backup_plan_input(%{state | section: "inputs", descriptor: descriptor})
        end
      end
    else
      _ -> backup_error(:collection_backup_plan_invalid)
    end
  rescue
    _ -> backup_error(:collection_backup_plan_invalid)
  end

  defp backup_plan_advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}
  defp backup_plan_advance({:done, {:error, code, _}}, _), do: backup_error(code)
  defp backup_plan_advance(_, _), do: backup_error(:collection_backup_plan_invalid)

  defp backup_plan_input(%{inputs: [ref | _]} = state),
    do:
      backup_plan_advance(
        start(state.profile, :selected_backup_result, %{
          "result_input" => ref,
          "plan_input" => nil
        }),
        state
      )

  @doc false
  def backup_plan(descriptor, rows, operations, pages)
      when is_map(descriptor) and is_list(rows) and is_list(operations) and is_list(pages) do
    with true <- backup_descriptor?(descriptor),
         true <- length(rows) in 1..32 and length(rows) === descriptor["records"],
         true <- Enum.all?(rows, &backup_record_row?/1),
         true <- Enum.map(rows, &hd/1) === Enum.sort(Enum.uniq(Enum.map(rows, &hd/1))),
         true <- Enum.sum(Enum.map(rows, &Enum.at(&1, 4))) === descriptor["data_bytes"],
         {:ok, envelope_sha} <- Ipse.Extension.canonical_digest([rows]),
         true <- envelope_sha === descriptor["envelopes_sha256"],
         entries = Enum.map(rows, fn [key, _, _, hash, bytes] -> [key, hash, bytes] end),
         {:ok, records_sha} <- Ipse.Extension.canonical_digest([entries]),
         true <- records_sha === descriptor["records_sha256"],
         true <- length(operations) <= 128 and length(operations) === descriptor["operations"],
         {:ok, packed, operation_sha, operation_map} <- backup_pack_operations(operations),
         true <- operation_sha === descriptor["operations_sha256"],
         true <-
           Enum.all?(rows, fn [_, revision, id, _, _] ->
             revision <= descriptor["generation"] and
               get_in(operation_map, [id, "generation"]) === revision
           end),
         {:ok, inputs, bindings, counts} <- backup_plan_pages(pages, descriptor, rows),
         {:ok, empty_union} <- Ipse.Extension.canonical_digest([[]]) do
      {:ok,
       %{
         "descriptor" => descriptor,
         "plan" => %{
           "version" => 2,
           "records" => rows,
           "operations" => packed,
           "page_counts" => counts,
           "data_inputs" => inputs,
           "data_bindings" => bindings,
           "dependency_union_sha256" => empty_union
         }
       }}
    else
      _ -> {:error, :collection_backup_plan_invalid}
    end
  rescue
    _ -> {:error, :collection_backup_plan_invalid}
  end

  def backup_plan(_, _, _, _), do: {:error, :collection_backup_plan_invalid}

  @doc false
  def backup_verify_plan(plan, pages) when is_map(plan) and is_list(pages) do
    with true <- backup_exact?(plan, ~w(descriptor plan)),
         data when is_map(data) <- plan["plan"],
         true <-
           backup_exact?(
             data,
             ~w(version records operations page_counts data_inputs data_bindings dependency_union_sha256)
           ) and data["version"] === 2,
         {:ok, operations} <- backup_unpack_operations(data["operations"]),
         {:ok, rebuilt} <- backup_plan(plan["descriptor"], data["records"], operations, pages),
         true <- rebuilt === plan do
      :ok
    else
      _ -> {:error, :collection_backup_plan_invalid}
    end
  rescue
    _ -> {:error, :collection_backup_plan_invalid}
  end

  def backup_verify_plan(_, _), do: {:error, :collection_backup_plan_invalid}

  defp backup_descriptor?(d) do
    fields =
      ~w(version profile project generation maintenance_epoch floor floor_anchor floor_lineage floor_lineage_sha256 records data_bytes records_sha256 operations operations_sha256 envelopes_sha256)

    with true <- backup_exact?(d, fields) and d["version"] === 4,
         true <- d["profile"] === "document_graph_v1" and E.sha256?(d["project"]),
         true <-
           E.safe_uint?(d["generation"]) and E.safe_uint?(d["maintenance_epoch"]) and
             E.safe_uint?(d["floor"]),
         lineage when is_list(lineage) and length(lineage) <= 128 <- d["floor_lineage"],
         true <-
           Enum.all?(lineage, &backup_id?/1) and length(Enum.uniq(lineage)) === length(lineage),
         true <-
           if(d["floor"] === 0,
             do: lineage === [] and is_nil(d["floor_anchor"]),
             else: lineage != [] and List.last(lineage) === d["floor_anchor"]
           ),
         {:ok, lineage_sha} <- Ipse.Extension.canonical_digest([lineage]),
         true <- lineage_sha === d["floor_lineage_sha256"],
         true <-
           E.safe_uint?(d["records"]) and E.safe_uint?(d["operations"]) and
             E.safe_uint?(d["data_bytes"]),
         true <-
           Enum.all?(~w(records_sha256 operations_sha256 envelopes_sha256), &E.sha256?(d[&1])) do
      true
    else
      _ -> false
    end
  end

  defp backup_compact_descriptor?(d) do
    fields =
      ~w(version profile project generation maintenance_epoch floor floor_anchor floor_lineage_count floor_lineage_sha256 records data_bytes records_sha256 operations operations_sha256 envelopes_sha256)

    backup_exact?(d, fields) and d["version"] === 4 and d["profile"] === "document_graph_v1" and
      E.sha256?(d["project"]) and
      Enum.all?(
        ~w(generation maintenance_epoch floor floor_lineage_count records data_bytes operations),
        &E.safe_uint?(d[&1])
      ) and d["floor_lineage_count"] <= 128 and
      if(d["floor"] === 0,
        do: d["floor_anchor"] === nil and d["floor_lineage_count"] === 0,
        else: backup_id?(d["floor_anchor"]) and d["floor_lineage_count"] > 0
      ) and
      Enum.all?(
        ~w(floor_lineage_sha256 records_sha256 operations_sha256 envelopes_sha256),
        &E.sha256?(d[&1])
      )
  rescue
    _ -> false
  end

  defp backup_pack_operations(rows) do
    ids = Enum.map(rows, fn [id, _] -> id end)

    with true <- ids === Enum.sort(Enum.uniq(ids)),
         {:ok, empty} <- Ipse.Extension.canonical_digest(["collection-operations", 1]) do
      Enum.reduce_while(rows, {:ok, [], empty, %{}}, fn [id, receipt],
                                                        {:ok, packed, digest, map} ->
        with true <- backup_id?(id) and backup_receipt?(receipt),
             {:ok, next} <- Ipse.Extension.canonical_digest([digest, id, receipt]) do
          extra = Map.take(receipt, ~w(migration_id checkpoint_id))

          row = [
            backup_pack_hex(id),
            receipt["generation"],
            backup_pack_hex(receipt["request_sha256"]),
            receipt["floor"]
          ]

          row = if map_size(extra) === 0, do: row, else: row ++ [extra]
          {:cont, {:ok, [row | packed], next, Map.put(map, id, receipt)}}
        else
          _ -> {:halt, {:error, :invalid_operations}}
        end
      end)
      |> case do
        {:ok, packed, digest, map} -> {:ok, Enum.reverse(packed), digest, map}
        error -> error
      end
    else
      _ -> {:error, :invalid_operations}
    end
  rescue
    _ -> {:error, :invalid_operations}
  end

  defp backup_receipt?(r) when is_map(r) do
    optional = Map.take(r, ~w(migration_id checkpoint_id))

    backup_exact?(
      Map.drop(r, ~w(migration_id checkpoint_id)),
      ~w(generation floor request_sha256)
    ) and
      E.safe_positive?(r["generation"]) and E.safe_uint?(r["floor"]) and
      E.sha256?(r["request_sha256"]) and
      (not Map.has_key?(optional, "migration_id") or backup_id?(optional["migration_id"])) and
      (not Map.has_key?(optional, "checkpoint_id") or is_nil(optional["checkpoint_id"]) or
         backup_id?(optional["checkpoint_id"]))
  end

  defp backup_receipt?(_), do: false

  defp backup_unpack_operations(rows) when is_list(rows) and length(rows) <= 128 do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, unpacked} ->
      case row do
        [packed_id, generation, packed_hash, floor | extras] ->
          with {:ok, id} <- backup_unpack_hex(packed_id, 16),
               {:ok, hash} <- backup_unpack_hex(packed_hash, 32),
               {:ok, extra} <- backup_receipt_extra(extras),
               receipt =
                 Map.merge(extra, %{
                   "generation" => generation,
                   "floor" => floor,
                   "request_sha256" => hash
                 }),
               true <- backup_receipt?(receipt) do
            {:cont, {:ok, [[id, receipt] | unpacked]}}
          else
            _ -> {:halt, {:error, :invalid_operations}}
          end

        _ ->
          {:halt, {:error, :invalid_operations}}
      end
    end)
    |> case do
      {:ok, unpacked} -> {:ok, Enum.reverse(unpacked)}
      error -> error
    end
  end

  defp backup_unpack_operations(_), do: {:error, :invalid_operations}
  defp backup_receipt_extra([]), do: {:ok, %{}}

  defp backup_receipt_extra([extra]) when is_map(extra) and map_size(extra) in 1..2,
    do:
      if(Map.keys(extra) -- ~w(migration_id checkpoint_id) === [],
        do: {:ok, extra},
        else: {:error, :invalid_operations}
      )

  defp backup_receipt_extra(_), do: {:error, :invalid_operations}

  defp backup_unpack_hex(value, size) when is_binary(value) do
    with {:ok, bytes} <- Base.url_decode64(value, padding: false),
         true <- byte_size(bytes) === size and Base.url_encode64(bytes, padding: false) === value do
      {:ok, Base.encode16(bytes, case: :lower)}
    else
      _ -> {:error, :invalid_operations}
    end
  end

  defp backup_unpack_hex(_, _), do: {:error, :invalid_operations}

  defp backup_pack_hex(hex),
    do: hex |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)

  defp backup_plan_pages(pages, descriptor, rows) when length(pages) in 1..4 do
    with true <- Enum.all?(pages, &backup_plan_page?(&1, descriptor)),
         inputs = Enum.map(pages, & &1["result_input"]),
         true <- length(Enum.uniq(inputs)) === length(inputs),
         flattened = Enum.flat_map(pages, & &1["value"]["records"]),
         true <- Enum.map(flattened, &backup_page_row/1) === rows,
         true <-
           pages
           |> Enum.with_index()
           |> Enum.all?(fn {page, i} ->
             last = List.last(page["value"]["records"])["key"]
             page["value"]["next"] === if(i + 1 < length(pages), do: last, else: nil)
           end),
         {:ok, bindings} <- backup_bind_inputs(inputs) do
      {:ok, inputs, bindings, Enum.map(pages, &length(&1["value"]["records"]))}
    else
      _ -> {:error, :invalid_pages}
    end
  end

  defp backup_plan_pages(_, _, _), do: {:error, :invalid_pages}

  defp backup_plan_page?(page, descriptor) do
    value = page["value"]
    ref = page["result_input"]

    backup_exact?(page, ~w(result_input value raw_sha256 byte_count origin)) and
      backup_result_ref?(ref) and
      page["raw_sha256"] === ref["delivery"]["sha256"] and
      page["byte_count"] === ref["delivery"]["byte_count"] and
      backup_exact?(value, ~w(descriptor records next)) and value["descriptor"] === descriptor and
      (is_nil(page["origin"]) or backup_origin_matches?(page, "backup_page", descriptor)) and
      is_list(value["records"]) and length(value["records"]) in 1..8 and
      Enum.all?(value["records"], &backup_page_record?/1)
  end

  defp backup_page_record?(record) when is_map(record) do
    packed = record["value"]
    row = backup_page_row(record)

    with true <- backup_exact?(record, ~w(key revision operation_id sha256 bytes value)),
         true <-
           backup_record_row?(row) and
             backup_exact?(packed, ~w(version kind sha256 byte_count parts)),
         true <- packed["version"] === 1 and packed["kind"] === "document_value",
         parts when is_list(parts) and length(parts) in 1..10 <- packed["parts"],
         true <-
           Enum.all?(parts, &(is_binary(&1) and String.valid?(&1) and byte_size(&1) in 1..6144)),
         body = IO.iodata_to_binary(parts),
         true <- byte_size(body) === packed["byte_count"] and E.sha256(body) === packed["sha256"],
         {:ok, _} <- ResultDocument.decode(body, %{"type" => "object"}),
         {:ok, physical} <- ResultDocument.encode(packed, %{"type" => "object"}),
         true <-
           byte_size(physical) === record["bytes"] and E.sha256(physical) === record["sha256"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp backup_page_record?(_), do: false

  defp backup_page_row(record),
    do: Enum.map(~w(key revision operation_id sha256 bytes), &record[&1])

  defp backup_bind_inputs(inputs) do
    Enum.reduce_while(inputs, {:ok, []}, fn input, {:ok, hashes} ->
      case Ipse.Extension.canonical_digest([input]) do
        {:ok, hash} -> {:cont, {:ok, [hash | hashes]}}
        _ -> {:halt, {:error, :invalid_input}}
      end
    end)
    |> case do
      {:ok, hashes} -> {:ok, Enum.reverse(hashes)}
      error -> error
    end
  end

  # Rebuild the physical wrapper from the native layout and the exact logical
  # bytes returned by bounded reads. The source's boundaries are data: do not
  # rechunk them or hash a re-encoded logical document.
  def backup_reconstruct([key, revision, operation_id, record_sha256, record_bytes], layout, body)
      when is_binary(key) and is_integer(revision) and is_binary(operation_id) and
             is_binary(record_sha256) and is_integer(record_bytes) and is_map(layout) and
             is_binary(body) do
    with true <-
           backup_exact?(
             layout,
             ~w(version recipe revision record_sha256 record_bytes sha256 byte_count parts)
           ),
         true <-
           byte_size(key) in 1..96 and
             Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/, key) and
             not String.starts_with?(key, "host.") and E.safe_positive?(revision) and
             Regex.match?(~r/\A[a-f0-9]{32}\z/, operation_id) and
             record_bytes in 2..65_536,
         true <- layout["version"] === 1 and layout["recipe"] === "document_packed_layout_v1",
         true <- layout["revision"] === revision and layout["record_sha256"] === record_sha256,
         true <- layout["record_bytes"] === record_bytes and E.sha256?(record_sha256),
         true <- is_integer(layout["byte_count"]) and layout["byte_count"] in 2..61_440,
         true <- byte_size(body) === layout["byte_count"] and E.sha256(body) === layout["sha256"],
         {:ok, parts} <- backup_parts(body, layout["parts"]),
         {:ok, _} <- ResultDocument.decode(body, %{"type" => "object"}),
         packed = %{
           "version" => 1,
           "kind" => "document_value",
           "sha256" => layout["sha256"],
           "byte_count" => layout["byte_count"],
           "parts" => parts
         },
         {:ok, physical} <- ResultDocument.encode(packed, %{"type" => "object"}),
         true <- byte_size(physical) === record_bytes and E.sha256(physical) === record_sha256 do
      {:ok,
       %{
         "key" => key,
         "revision" => revision,
         "operation_id" => operation_id,
         "sha256" => record_sha256,
         "bytes" => record_bytes,
         "value" => packed
       }}
    else
      _ -> {:error, :collection_backup_corrupt}
    end
  rescue
    _ -> {:error, :collection_backup_corrupt}
  end

  def backup_reconstruct(_, _, _), do: {:error, :collection_backup_corrupt}

  defp backup_parts(body, parts) when is_list(parts) and length(parts) in 1..10 do
    result =
      Enum.reduce_while(parts, {:ok, 0, []}, fn part, {:ok, offset, values} ->
        with true <- backup_exact?(part, ~w(offset byte_count sha256)),
             true <- part["offset"] === offset,
             count when is_integer(count) and count in 1..6144 <- part["byte_count"],
             true <- offset + count <= byte_size(body),
             value = binary_part(body, offset, count),
             true <- String.valid?(value) and E.sha256(value) === part["sha256"] do
          {:cont, {:ok, offset + count, [value | values]}}
        else
          _ -> {:halt, {:error, :collection_backup_corrupt}}
        end
      end)

    case result do
      {:ok, size, values} when size === byte_size(body) -> {:ok, Enum.reverse(values)}
      _ -> {:error, :collection_backup_corrupt}
    end
  end

  defp backup_parts(_, _), do: {:error, :collection_backup_corrupt}
  defp backup_exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) === Enum.sort(keys)
end
