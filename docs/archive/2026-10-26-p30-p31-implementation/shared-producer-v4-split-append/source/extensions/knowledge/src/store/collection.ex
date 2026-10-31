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
  @sources 1000
  @catalog_rows 16
  @block_bytes 48 * 1024
  @bundle_bytes 1024 * 1024
  @reads 512
  @effects 16

  def start(profile, :generation_selected, args),
    do: IpseKnowledge.Store.Collection.Selected.start(profile, args)

  def start(profile, :generation_job, args),
    do: IpseKnowledge.Store.Collection.Job.start(profile, args)

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
        checkpoint: checkpoint,
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
    do: op in ~w(snapshot value.stat value.read stage.list stage.inspect)

  def read_request?(_), do: false

  def resume(%{generation_job: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Job.resume(state, outcome)

  def resume(%{shared_selected: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Selected.resume(state, outcome)

  def resume(%{projection_state: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Projection.resume(state, outcome)

  def resume(%{index_state: _} = state, outcome),
    do: IpseKnowledge.Store.Collection.Index.resume(state, outcome)

  def resume(_, %{"status" => "unknown"}), do: {:stop, :unknown_effect}

  def resume(_, %{
        "status" => "failed",
        "value" => %{"code" => "document_store_deadline_unavailable"}
      }),
      do: error(:document_store_deadline_unavailable)

  def resume(_, %{"status" => status}) when status != "ok", do: error(:collection_refused)

  def resume(state, %{"status" => "ok", "value" => wrapped}) do
    with true <- exact?(wrapped, ~w(version operation_id request_sha256 result)),
         true <- wrapped["version"] === 1,
         {:ok, request_hash} <- Ipse.Extension.canonical_digest([state.request]),
         true <- request_hash == wrapped["request_sha256"],
         result when is_map(result) <- wrapped["result"] do
      if Map.get(state, :pinned_inline, false) do
        if is_binary(wrapped["operation_id"]) and
             Regex.match?(~r/\A[0-9a-fA-F]{32}\z/, wrapped["operation_id"]),
           do: next(Map.put(state, :operation_id, wrapped["operation_id"]), result),
           else: {:stop, :unknown_effect}
      else
        next(state, result)
      end
    else
      _ ->
        if Map.get(state, :pinned_inline, false),
          do: {:stop, :unknown_effect},
          else: error(:collection_response)
    end
  rescue
    _ ->
      if Map.get(state, :pinned_inline, false),
        do: {:stop, :unknown_effect},
        else: error(:collection_response)
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
    occupied = Enum.map(result["stages"], & &1["slot"])
    slot = Enum.find(0..15, &(&1 not in occupied))

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
      row == nil -> stage(s, data_key(s, E.sha256(bytes)), body, 0, true, 0)
      row["sha256"] == E.sha256(bytes) and row["value"] === body -> unit_done(s, nil)
      true -> error(:collection_block_conflict)
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
         true <- exact?(value, ~w(version kind pieces bundle_sha256 ordinal source_bundle_sha256)),
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
      "bundle_sha256" => s.checkpoint["plan_sha256"],
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

            call(s, %{"op" => "stage.list"}, :allocate_stage)
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
    r = if frame_fits?(r), do: r, else: request.([first])
    if frame_fits?(r), do: call(s, r, :writing_parts), else: error(:collection_budget)
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

  defp call(s, inner, phase) do
    read = inner["op"] in ~w(snapshot value.stat value.read stage.inspect stage.list)
    reads = s.reads + if(read, do: 1, else: 0)
    effects = s.effects + if(read, do: 0, else: 1)
    request = %{"op" => "collection.store", "scope" => "project", "request" => inner}

    cond do
      not read and effects > @effects and phase not in [:opened, :inline_prepared] and
        not (phase == :writing_parts and s.unit.offset == 0) and
          Map.has_key?(s, :unit) ->
        pause_unit(s)

      reads <= @reads and effects <= @effects and Ipse.Extension.validate(request) == :ok ->
        {:call, request,
         Map.merge(s, %{phase: phase, reads: reads, effects: effects, request: request})}

      true ->
        error(:collection_budget)
    end
  end

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
        %{"version" => 1, "inline_bytes" => 8192} -> 8192
        %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2} -> 8192
        _ -> 0
      end

    parts =
      if result["document_store"] === %{
           "version" => 2,
           "inline_bytes" => 8192,
           "write_parts" => 2
         }, do: 2, else: 0

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
      frame_fits?(request)
  end

  defp frame_fits?(request),
    do:
      Ipse.Extension.validate(%{
        "api_version" => 1,
        "kind" => "host_call",
        "request" => %{"op" => "collection.store", "scope" => "project", "request" => request}
      }) == :ok

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
      exact?(c, ~w(version plan_sha256 expected_revision unit stages base active)) and
        c["version"] === 3 and
        c["plan_sha256"] == hash and c["expected_revision"] == rev and E.safe_uint?(c["unit"]) and
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
end
