defmodule IpseKnowledge.Store do
  @moduledoc "Partitioned immutable evidence pages selected by registered source-root CAS."
  alias IpseKnowledge.Evidence
  alias IpseKnowledge.Store.{State, MCPCAS}

  @operations [
    :put,
    :open,
    :append,
    :publish,
    :abort,
    :forget,
    :inspect,
    :snapshot,
    :snapshot_selected,
    :revalidate,
    :export,
    :import,
    :collect,
    :projection_open,
    :projection_commit,
    :projection_abort
  ]
  @source_fields ~w(source_id partition generation title text uri observed_at_ms event_at_ms expires_at_ms origin)
  @root_fields ~w(format kind partition source_key source_id generation state title uri observed_at_ms event_at_ms expires_at_ms origin content_sha256 content_ref chunks_ref projections draft)
  @projection_limit 8

  def start(name, profile, operation, args) do
    with true <- name?(name) and profile?(profile) and operation in @operations and is_map(args),
         :ok <- arguments(operation, args) do
      state = %{
        name: name,
        profile: profile,
        operation: operation,
        args: args,
        effects: Map.get(args, "effects_used", 0),
        reads: Map.get(args, "reads_used", 0),
        cache: nil,
        stage: nil,
        io: nil
      }

      cond do
        legacy_addition?(state) ->
          error(:atomic_capacity_unavailable)

        operation == :snapshot_selected ->
          start_selected(state)

        operation == :revalidate ->
          perform(state)

        operation in [:projection_commit, :projection_abort] and Map.has_key?(args, "draft") ->
          token = args["draft"]

          if draft_token?(token, name, profile) and
               (operation == :projection_abort or
                  current_vector_contract?(token, "projection_kind")) do
            state = %{
              state
              | cache: token["cache"],
                effects:
                  token["effects_before_model"] +
                    if(operation == :projection_commit,
                      do: Map.get(token, "model_effects", 1),
                      else: 0
                    ),
                reads:
                  Map.get(token, "reads_before_model", 0) +
                    if(operation == :projection_commit,
                      do: Map.get(token, "model_reads", 2),
                      else: 0
                    )
            }

            io(state, :get_many, %{"keys" => [token["root_key"]]}, :projection_checked)
          else
            error(:invalid_draft)
          end

        true ->
          io(state, :snapshot, %{}, :loaded)
      end
    else
      _ -> error(:invalid_store_arguments)
    end
  rescue
    _ -> error(:invalid_store_arguments)
  end

  defp legacy_addition?(%{
         profile: %{"kind" => "mcp_cas", "contract" => contract},
         operation: operation,
         args: args
       })
       when contract != "ipse-cas-v3" do
    operation in [:put, :append, :publish, :projection_open, :projection_commit] or
      (operation in [:open, :forget] and args["expected_revision"] == 0) or
      (operation == :import and
         (get_in(args, ["export", "kind"]) == "source" or args["expected_revision"] == 0))
  end

  defp legacy_addition?(_), do: false

  def resume(state, outcome) do
    adapter = adapter(state.profile)
    bridge(adapter.resume(state.io, outcome), state)
  rescue
    _ -> error(:store_response)
  end

  def root_key(partition, source_key), do: Evidence.id("root", [partition, source_key])

  @doc "Read-only counts and hashes for a validated adapter snapshot; returns no source text."
  def inventory(cache, partition) do
    with true <-
           name?(partition) and is_map(cache["records"]) and
             Evidence.safe_uint?(cache["generation"]),
         true <- map_size(cache["records"]) <= 256,
         :ok <- valid_partition(cache, partition) do
      records = Map.values(cache["records"])
      roots = roots(%{cache: cache, profile: %{"partition" => partition}})

      {selected, drafts, root_rows} =
        Enum.reduce(roots, {MapSet.new(), MapSet.new(), []}, fn record,
                                                                {selected, drafts, rows} ->
          root = record["value"]
          selected_refs = references_in(Map.delete(root, "draft"))
          own_selected = inventory_closure(cache, selected_refs, root, MapSet.new())
          draft = root["draft"]

          draft_pages =
            if draft do
              Enum.filter(records, fn page ->
                not page["deleted"] and get_in(page, ["value", "kind"]) == "page" and
                  get_in(page, ["value", "partition"]) == partition and
                  get_in(page, ["value", "draft_id"]) == draft["id"]
              end)
            else
              []
            end

          own_draft =
            if draft do
              generation =
                if draft["kind"] == "source",
                  do: draft["target"]["generation"],
                  else: draft["source_generation"]

              target = %{root | "generation" => generation}
              refs = references_in(draft) ++ Enum.map(draft_pages, &reference/1)
              inventory_closure(cache, refs, target, MapSet.new())
            else
              MapSet.new()
            end

          row = %{
            "key" => record["key"],
            "revision" => record["revision"],
            "state" => root["state"],
            "value_sha256" => Evidence.id("inventory-root", [ordered(root)]),
            "selected_refs" => inventory_refs(cache, own_selected),
            "draft_refs" => inventory_refs(cache, own_draft)
          }

          {MapSet.union(selected, own_selected), MapSet.union(drafts, own_draft), rows ++ [row]}
        end)

      pages =
        Enum.filter(records, fn record ->
          not record["deleted"] and get_in(record, ["value", "partition"]) == partition and
            get_in(record, ["value", "kind"]) == "page"
        end)

      draft_only = MapSet.difference(drafts, selected)
      protected = MapSet.union(selected, drafts)

      {:ok,
       %{
         "version" => 1,
         "partition" => partition,
         "generation" => cache["generation"],
         "namespace_slots" => length(records),
         "namespace_unused_slots" => 256 - length(records),
         "namespace_tombstones" => inventory_count(Enum.filter(records, & &1["deleted"])),
         "other_live_records" =>
           inventory_count(
             Enum.filter(records, fn record ->
               not record["deleted"] and get_in(record, ["value", "partition"]) != partition
             end)
           ),
         "root_records" => inventory_count(roots),
         "roots" => root_rows,
         "selected_pages" =>
           inventory_count(Enum.filter(pages, &MapSet.member?(selected, &1["key"]))),
         "draft_pages" =>
           inventory_count(Enum.filter(pages, &MapSet.member?(draft_only, &1["key"]))),
         "orphan_pages" =>
           inventory_count(Enum.reject(pages, &MapSet.member?(protected, &1["key"]))),
         "byte_encoding" => "Elixir.JSON; actual file bytes measured separately"
       }}
    else
      _ -> {:error, :inventory_unavailable}
    end
  rescue
    _ -> {:error, :inventory_unavailable}
  end

  defp inventory_closure(cache, refs, root, seen) do
    Enum.reduce(refs, seen, fn ref, seen ->
      record = Map.fetch!(cache["records"], ref["key"])
      value = record["value"]

      true = ref?(ref) and not record["deleted"] and value["kind"] == "page"
      true = reference(record) === ref
      true = value["partition"] == root["partition"]
      true = value["source_key"] == root["source_key"]
      true = value["generation"] == root["generation"]

      if MapSet.member?(seen, ref["key"]),
        do: seen,
        else:
          inventory_closure(
            cache,
            references_in(value),
            root,
            MapSet.put(seen, ref["key"])
          )
    end)
  end

  defp inventory_refs(cache, keys),
    do: keys |> Enum.sort() |> Enum.map(&reference(Map.fetch!(cache["records"], &1)))

  defp inventory_count(records),
    do: %{
      "records" => length(records),
      "encoded_record_bytes" => Enum.sum(Enum.map(records, &byte_size(json(&1)))),
      "encoded_value_bytes" =>
        Enum.sum(
          Enum.map(records, fn record ->
            if record["deleted"], do: 0, else: byte_size(json(record["value"]))
          end)
        )
    }

  defp io(state, operation, args, stage) do
    bridge(adapter(state.profile).start(state.profile, operation, args), %{state | stage: stage})
  end

  defp bridge({:call, request, continuation}, state) do
    read = request["op"] in ~w(state.get state.scan effect.result.read)
    effects = state.effects + if(read, do: 0, else: 1)
    reads = state.reads + if(read, do: 1, else: 0)

    if effects <= 16 and reads <= 512 and effects + reads <= 528,
      do: {:call, request, %{state | io: continuation, effects: effects, reads: reads}},
      else: error(:effect_limit)
  end

  defp bridge({:done, {:ok, value}}, state), do: advance(state, value)
  defp bridge({:done, {:error, _, _}} = error, _), do: error
  defp bridge({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}

  defp advance(%{stage: :loaded} = state, cache) do
    with true <- is_map(cache["records"]) and map_size(cache["records"]) <= 256,
         true <-
           Evidence.safe_uint?(cache["generation"]) and Evidence.safe_uint?(cache["bytes"]) and
             cache["bytes"] <= 1_048_576,
         :ok <- valid_partition(cache, state.profile["partition"]) do
      perform(%{state | cache: cache})
    else
      _ -> error(:store_corrupt)
    end
  end

  defp advance(%{stage: :selected_roots} = state, value), do: selected_roots(state, value)
  defp advance(%{stage: :selected_pages} = state, value), do: selected_pages(state, value)

  defp advance(%{stage: :claimed, operation: :projection_open} = state, value) do
    record = value["record"]
    cache = put_record(state.cache, record, value["generation"])

    token = %{
      "version" => 1,
      "store" => state.name,
      "partition" => state.profile["partition"],
      "root_key" => record["key"],
      "revision" => record["revision"],
      "draft_id" => record["value"]["draft"]["id"],
      "generation" => record["value"]["generation"],
      "content_sha256" => record["value"]["content_sha256"],
      "projection_kind" => state.args["projection_kind"],
      "profile" => state.args["profile"],
      "chunks" => state.args["chunks"],
      "effects_before_model" => state.effects,
      "reads_before_model" => state.reads,
      "model_effects" => state.plan["model_effects"],
      "model_reads" => state.plan["model_reads"],
      "max_items" => Map.get(state.args, "max_items", 1),
      "prepared_sha256" => Map.get(state.plan, "prepared_sha256"),
      "reserved_pages" => state.plan["reserved_pages"],
      "cache" => cache
    }

    token = vector_contract(token, state.args["projection_kind"])

    {:done,
     {:ok,
      %{
        "source" => state.source,
        "chunks" => state.chunks,
        "draft" => token,
        "coverage" => state.plan
      }}}
  end

  defp advance(%{stage: :claimed, operation: :open}, value),
    do: draft_result(value["record"])

  defp advance(%{stage: :claimed} = state, value) do
    state =
      state
      |> Map.put(:expected, value["record"])
      |> Map.put(:cache, put_record(state.cache, value["record"], value["generation"]))

    stage_pages(state)
  end

  defp advance(%{stage: :staged} = state, _value),
    do: cas(state, state.expected, state.desired, :committed)

  defp advance(%{stage: :committed, operation: operation}, value)
       when operation in [:append],
       do: draft_result(value["record"])

  defp advance(%{stage: :committed, operation: :forget}, value) do
    root = value["record"]["value"]

    {:done,
     {:ok,
      %{
        "status" => "suppressed",
        "source_key" => root["source_key"],
        "generation" => root["generation"],
        "revision" => value["record"]["revision"]
      }}}
  end

  defp advance(%{stage: :committed, operation: operation}, value)
       when operation in [:abort, :projection_abort],
       do:
         {:done,
          {:ok,
           %{
             "status" => "aborted",
             "generation" => value["record"]["value"]["generation"],
             "revision" => value["record"]["revision"]
           }}}

  defp advance(%{stage: :committed} = state, value) do
    root = value["record"]["value"]

    {:done,
     {:ok,
      %{
        "status" => "stored",
        "source_id" => root["source_id"],
        "source_key" => root["source_key"],
        "generation" => root["generation"],
        "revision" => value["record"]["revision"],
        "continuation" => nil,
        "coverage" => Map.get(state, :plan, %{})
      }}}
  end

  defp advance(%{stage: :projection_checked} = state, value) do
    [record] = value["records"]
    token = state.args["draft"]

    with true <- record["revision"] == token["revision"] and record["deleted"] == false,
         root = record["value"],
         true <- valid_root?(root, state.profile["partition"]) and root["state"] == "active",
         true <-
           root["generation"] == token["generation"] and
             root["content_sha256"] == token["content_sha256"],
         true <- root["draft"] != nil and root["draft"]["id"] == token["draft_id"],
         true <-
           state.operation == :projection_abort or
             (current_vector_contract?(root["draft"], "kind") and
                Map.get(root["draft"], "vector_version") === Map.get(token, "vector_version")) do
      state = Map.put(state, :expected, record)

      if state.operation == :projection_abort,
        do: cas(state, record, Map.put(root, "draft", nil), :committed),
        else: commit_projection(state, root, token)
    else
      _ -> error(:stale_draft)
    end
  end

  defp advance(%{stage: :revalidated} = state, value) do
    tokens = state.args["tokens"]

    gaps =
      for {record, token} <- Enum.zip(value["records"], tokens),
          not matches_token?(record, token),
          do: %{"code" => "source_changed", "source_key" => token["source_key"]}

    {:done,
     {:ok,
      %{
        "tokens" => tokens,
        "gaps" => gaps,
        "valid" => gaps == [],
        "coverage" => counter_coverage(state)
      }}}
  end

  defp advance(%{stage: :collect_checked} = state, value) do
    roots = state.collect_roots

    if Enum.zip(value["records"], roots)
       |> Enum.all?(fn {actual, old} ->
         actual["revision"] == old["revision"] and actual["value"] === old["value"]
       end) do
      io(
        state,
        :collect,
        %{"records" => state.collect_pages, "snapshot_generation" => value["generation"]},
        :collected
      )
    else
      error(:snapshot_changed)
    end
  end

  defp advance(%{stage: :collected}, value),
    do:
      {:done,
       {:ok,
        %{
          "status" => "collected",
          "count" => length(value["records"]),
          "record_slots_recovered" => 0
        }}}

  defp start_selected(%{profile: %{"kind" => "mcp_cas"}} = state) do
    cache = %{"records" => %{}, "generation" => state.args["store_generation"], "bytes" => 0}
    state = Map.merge(state, %{cache: cache, selected_refs: %{}, selected_checked: MapSet.new()})

    keys =
      state.args["refs"]
      |> Enum.map(&root_key(state.profile["partition"], &1["source_key"]))
      |> Enum.uniq()
      |> Enum.sort()

    if keys == [], do: finish_selected(state), else: selected_fetch(state, keys, :selected_roots)
  end

  defp start_selected(_), do: error(:selected_store_required)

  defp selected_fetch(state, keys, stage) do
    roots = state.args["refs"] |> Enum.uniq_by(& &1["source_key"]) |> length()
    final_calls = div(roots + 7, 8)
    calls = div(length(keys) + 7, 8)

    if allowance?(state, calls + final_calls, 15 * (calls + final_calls)) do
      io(
        state,
        :get_many,
        %{"keys" => keys, "generation" => state.args["store_generation"]},
        stage
      )
    else
      error(:effect_limit)
    end
  end

  defp selected_roots(state, value) do
    with {:ok, state} <- selected_cache(state, value),
         true <- Enum.all?(value["records"], &selected_root?(state, &1)),
         {:ok, refs} <-
           Enum.reduce_while(value["records"], {:ok, %{}}, fn row, {:ok, refs} ->
             root = row["value"]

             with {:ok, refs} <- add_selected_refs(refs, [root["content_ref"]], root, "progress"),
                  {:ok, refs} <- add_selected_refs(refs, root["chunks_ref"], root, "chunks") do
               {:cont, {:ok, refs}}
             else
               error -> {:halt, error}
             end
           end) do
      selected_continue(%{state | selected_refs: refs})
    else
      false -> error(:selected_source_unavailable)
      other -> error_result(other)
    end
  end

  defp selected_root?(state, row) do
    root = row["value"]
    refs = Enum.filter(state.args["refs"], &(&1["source_key"] == root["source_key"]))

    row["deleted"] == false and Evidence.safe_positive?(row["revision"]) and
      valid_root?(root, state.profile["partition"]) and
      root["state"] == "active" and row["key"] == root_key(root["partition"], root["source_key"]) and
      refs != [] and
      Enum.all?(refs, fn ref ->
        Enum.all?(~w(source_id source_key generation content_sha256), &(root[&1] == ref[&1]))
      end) and
      case Evidence.source(root |> Map.take(@source_fields) |> Map.put("text", "")) do
        {:ok, source} -> Evidence.current?(source, state.args["as_of_ms"])
        _ -> false
      end
  rescue
    _ -> false
  end

  defp selected_pages(state, value) do
    case selected_cache(state, value) do
      {:ok, state} -> selected_continue(state)
      other -> error_result(other)
    end
  end

  defp selected_cache(state, value) do
    records = Enum.reduce(value["records"], state.cache["records"], &Map.put(&2, &1["key"], &1))
    bytes = byte_size(json(records))

    if value["generation"] == state.args["store_generation"] and map_size(records) <= 256 and
         bytes <= 1_048_576,
       do:
         {:ok,
          %{
            state
            | cache: %{
                "records" => records,
                "generation" => value["generation"],
                "bytes" => bytes
              }
          }},
       else: {:error, :selected_snapshot_bounds}
  end

  defp selected_continue(state) do
    missing =
      state.selected_refs
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(state.cache["records"], &1))
      |> Enum.sort()

    cond do
      missing != [] ->
        selected_fetch(state, missing, :selected_pages)

      map_size(state.selected_refs) == MapSet.size(state.selected_checked) ->
        finish_selected(state)

      true ->
        state.selected_refs
        |> Enum.reject(fn {key, _} -> MapSet.member?(state.selected_checked, key) end)
        |> Enum.reduce_while({:ok, state}, fn {key, wanted}, {:ok, state} ->
          with {:ok, page} <-
                 load_page(state, wanted.ref, wanted.source_key, wanted.generation, wanted.kind),
               {:ok, refs} <- selected_children(state.selected_refs, page) do
            {:cont,
             {:ok,
              %{
                state
                | selected_refs: refs,
                  selected_checked: MapSet.put(state.selected_checked, key)
              }}}
          else
            _ -> {:halt, {:error, :selected_page_corrupt}}
          end
        end)
        |> case do
          {:ok, state} -> selected_continue(state)
          other -> error_result(other)
        end
    end
  end

  defp selected_children(refs, %{"page_kind" => "progress", "body" => body} = page) do
    with true <-
           keys?(body, ~w(previous offset next_offset pieces)) and
             Evidence.safe_uint?(body["offset"]) and
             Evidence.safe_uint?(body["next_offset"]) and body["offset"] <= body["next_offset"] and
             body["next_offset"] <= 65_536 and
             is_list(body["pieces"]) and length(body["pieces"]) <= 16,
         {:ok, refs} <-
           add_selected_refs(
             refs,
             if(body["previous"] == nil, do: [], else: [body["previous"]]),
             page,
             "progress"
           ),
         {:ok, refs} <- add_selected_refs(refs, body["pieces"], page, "content") do
      {:ok, refs}
    else
      _ -> {:error, :selected_page_corrupt}
    end
  end

  defp selected_children(refs, %{"page_kind" => kind, "body" => body})
       when kind in ~w(content chunks) do
    valid =
      if kind == "content",
        do: keys?(body, ["text"]) and is_binary(body["text"]) and String.valid?(body["text"]),
        else: keys?(body, ["chunks"]) and is_list(body["chunks"]) and length(body["chunks"]) <= 32

    if valid, do: {:ok, refs}, else: {:error, :selected_page_corrupt}
  end

  defp selected_children(_, _), do: {:error, :selected_page_corrupt}

  defp add_selected_refs(refs, additions, owner, kind) do
    Enum.reduce_while(additions, {:ok, refs}, fn ref, {:ok, refs} ->
      wanted = %{
        ref: ref,
        source_key: owner["source_key"],
        generation: owner["generation"],
        kind: kind
      }

      cond do
        not ref?(ref) ->
          {:halt, {:error, :selected_page_corrupt}}

        Map.has_key?(refs, ref["key"]) and refs[ref["key"]] != wanted ->
          {:halt, {:error, :selected_page_corrupt}}

        map_size(refs) >= 256 and not Map.has_key?(refs, ref["key"]) ->
          {:halt, {:error, :selected_snapshot_bounds}}

        true ->
          {:cont, {:ok, Map.put(refs, ref["key"], wanted)}}
      end
    end)
  end

  defp finish_selected(state) do
    result =
      Enum.reduce_while(roots(state), {:ok, []}, fn row, {:ok, sources} ->
        with {:ok, source} <- load_source(state, row["value"]),
             true <- Evidence.current?(source, state.args["as_of_ms"]),
             {:ok, chunks} <- Evidence.chunks(source),
             true <-
               Enum.all?(state.args["refs"], fn ref ->
                 ref["source_key"] != source["source_key"] or
                   Enum.any?(chunks, &(&1["chunk_id"] == ref["chunk_id"]))
               end) do
          {:cont, {:ok, sources ++ [source]}}
        else
          _ -> {:halt, {:error, :selected_source_corrupt}}
        end
      end)

    case result do
      {:ok, sources} ->
        coverage =
          Map.merge(coverage(state), %{
            "cache_scope" => "selected",
            "namespace_complete" => false,
            "selection_complete" => true,
            "projections" => "omitted",
            "as_of_ms" => state.args["as_of_ms"],
            "selected_refs" => length(state.args["refs"])
          })

        {:done,
         {:ok,
          %{
            "sources" => sources,
            "projections" =>
              Map.new(sources, &{&1["source_key"], %{"vectors" => [], "facts" => []}}),
            "tokens" => Enum.map(roots(state), &token/1),
            "gaps" => [],
            "coverage" => coverage
          }}}

      other ->
        error_result(other)
    end
  end

  defp allowance?(state, effects, reads),
    do:
      state.effects + effects <= 16 and state.reads + reads <= 512 and
        state.effects + state.reads + effects + reads <= 528

  defp counter_coverage(state),
    do: %{"effects_used" => state.effects, "reads_used" => state.reads}

  defp perform(%{operation: :snapshot} = state) do
    with :ok <- snapshot_capacity(state),
         {:ok, sources, projections, tokens, gaps} <- selected(state) do
      {:done,
       {:ok,
        %{
          "sources" => sources,
          "projections" => projections,
          "tokens" => tokens,
          "gaps" => gaps,
          "coverage" => coverage(state)
        }}}
    else
      {:error, code} -> error(code)
    end
  end

  defp perform(%{operation: :inspect} = state) do
    case find_root(state, state.args["source_id"]) do
      nil ->
        error(:source_missing)

      record ->
        root = record["value"]

        if root["state"] == "suppressed" do
          {:done,
           {:ok,
            Map.take(root, ~w(partition source_key generation state))
            |> Map.put("revision", record["revision"])}}
        else
          with {:ok, source} <-
                 if(root["state"] == "active", do: load_source(state, root), else: {:ok, nil}),
               {:ok, chunks} <- if(source, do: Evidence.chunks(source), else: {:ok, []}) do
            {:done,
             {:ok,
              %{
                "source_id" => root["source_id"],
                "source_key" => root["source_key"],
                "generation" => root["generation"],
                "revision" => record["revision"],
                "state" => root["state"],
                "draft" => public_draft(root["draft"]),
                "chunks" => Enum.map(chunks, &Map.take(&1, ~w(chunk_id start_byte end_byte))),
                "projections" =>
                  Enum.map(root["projections"], fn {key, head} ->
                    Map.put(Map.drop(head, ["ref"]), "id", key)
                  end)
              }}}
          else
            _ -> error(:store_corrupt)
          end
        end
    end
  end

  defp perform(%{operation: :revalidate} = state) do
    tokens = state.args["tokens"]

    if Enum.all?(tokens, &(token?(&1) and &1["partition"] == state.profile["partition"])) do
      calls = if state.profile["kind"] == "state", do: 0, else: div(length(tokens) + 7, 8)
      reads = if state.profile["kind"] == "state", do: length(tokens), else: calls * 15

      cond do
        not allowance?(state, calls, reads) ->
          error(:effect_limit)

        tokens == [] ->
          {:done,
           {:ok,
            %{
              "tokens" => [],
              "gaps" => [],
              "valid" => true,
              "coverage" => counter_coverage(state)
            }}}

        true ->
          io(state, :get_many, %{"keys" => Enum.map(tokens, & &1["key"])}, :revalidated)
      end
    else
      error(:invalid_snapshot)
    end
  end

  defp perform(%{operation: :forget} = state) do
    record = find_root(state, state.args["source_id"])

    with true <- revision(record) == state.args["expected_revision"],
         true <- record == nil or record["value"]["state"] != "suppressed",
         source_key = Evidence.sha256(state.args["source_id"]),
         root = %{
           "format" => 1,
           "kind" => "root",
           "partition" => state.profile["partition"],
           "source_key" => source_key,
           "generation" =>
             if(record,
               do: min(record["value"]["generation"] + 1, Evidence.safe_integer_max()),
               else: 1
             ),
           "state" => "suppressed",
           "suppressed_at_ms" =>
             Map.get(state.args, "suppressed_at_ms", System.system_time(:millisecond))
         },
         :ok <- capacity(state, if(record, do: 0, else: 1), if(record, do: 0, else: 1)) do
      cas(state, record || missing(root_key(root["partition"], source_key)), root, :committed)
    else
      false -> error(:conflict)
      error -> error_result(error)
    end
  end

  defp perform(%{operation: operation} = state) when operation in [:put, :open] do
    args = state.args
    record = find_root(state, args["source_id"])

    with :ok <- writable(record, args["expected_revision"], args["generation"]),
         origin = origin(state, args),
         attrs =
           args
           |> Map.take(@source_fields)
           |> Map.merge(%{"partition" => state.profile["partition"], "origin" => origin}),
         {:ok, source} <-
           Evidence.source(
             Map.put(attrs, "text", if(operation == :put, do: args["text"], else: ""))
           ),
         true <-
           operation != :open or
             (Evidence.safe_uint?(args["byte_count"]) and args["byte_count"] <= 65_536 and
                Evidence.sha256?(args["content_sha256"])),
         target =
           source
           |> Map.drop(~w(text version source_key))
           |> Map.merge(%{
             "byte_count" =>
               if(operation == :put, do: byte_size(source["text"]), else: args["byte_count"]),
             "content_sha256" =>
               if(operation == :put, do: source["content_sha256"], else: args["content_sha256"])
           }),
         draft = source_draft(record, target),
         claimed =
           if(record, do: Map.put(record["value"], "draft", draft), else: staging(source, draft)),
         true <- fits?(claimed),
         :ok <- capacity(state, if(record, do: 0, else: 1), if(record, do: 0, else: 1)) do
      expected = record || missing(root_key(source["partition"], source["source_key"]))
      state = Map.merge(state, %{expected: expected, desired: nil, pages: [], source: source})

      if operation == :put do
        with {:ok, plan} <- source_plan(source, draft, nil, 0),
             :ok <-
               capacity(
                 state,
                 length(plan.pages) + if(record, do: 0, else: 1),
                 if(record, do: 0, else: 1)
               ),
             :ok <- effect_plan(state, page_effects(state.profile, plan.pages) + 2, 0) do
          desired = active_root(source, plan.progress, plan.chunks, %{}, nil)

          cas(
            Map.merge(state, %{pages: plan.pages, desired: desired}),
            expected,
            claimed,
            :claimed
          )
        else
          {:error, :effect_limit} -> error(:needs_paged_ingest)
          error -> error_result(error)
        end
      else
        cas(state, expected, claimed, :claimed)
      end
    else
      false -> error(:invalid_source)
      error -> error_result(error)
    end
  end

  defp perform(%{operation: :append} = state) do
    with {:ok, record, draft} <- source_draft_current(state),
         true <- draft["next_offset"] == state.args["offset"],
         next = state.args["offset"] + byte_size(state.args["text"]),
         true <- next <= draft["target"]["byte_count"],
         {:ok, pages} <-
           text_pages(
             state.profile["partition"],
             record["value"]["source_key"],
             draft["target"]["generation"],
             draft["id"],
             state.args["text"],
             "content",
             state.args["offset"]
           ),
         progress =
           page(
             state.profile["partition"],
             record["value"]["source_key"],
             draft["target"]["generation"],
             draft["id"],
             "progress",
             state.args["offset"],
             %{
               "previous" => draft["progress"],
               "offset" => state.args["offset"],
               "next_offset" => next,
               "pieces" => Enum.map(pages, &reference/1)
             }
           ),
         all = pages ++ [progress],
         {:ok, publication_records} <- append_publication_records(state, record, draft, next),
         :ok <- capacity(state, length(all) + publication_records, 0),
         :ok <- effect_plan(state, page_effects(state.profile, all) + 1, 0),
         desired =
           put_in(record["value"], ["draft"], %{
             draft
             | "progress" => reference(progress),
               "next_offset" => next
           }),
         true <- fits?(desired) do
      stage_pages(Map.merge(state, %{pages: all, expected: record, desired: desired}))
    else
      false -> error(:invalid_append)
      error -> error_result(error)
    end
  end

  defp perform(%{operation: :publish} = state) do
    with {:ok, record, draft} <- source_draft_current(state),
         true <- draft["next_offset"] == draft["target"]["byte_count"],
         {:ok, text, _} <-
           load_progress(
             state,
             record["value"]["source_key"],
             draft["target"]["generation"],
             draft["progress"],
             MapSet.new()
           ),
         true <-
           byte_size(text) == draft["target"]["byte_count"] and
             Evidence.sha256(text) == draft["target"]["content_sha256"],
         attrs = draft["target"] |> Map.take(@source_fields) |> Map.put("text", text),
         {:ok, source} <- Evidence.source(attrs),
         {:ok, chunk_pages} <- chunk_pages(source, draft["id"]),
         :ok <- capacity(state, length(chunk_pages), 0),
         :ok <- effect_plan(state, page_effects(state.profile, chunk_pages) + 1, 0) do
      desired =
        active_root(source, draft["progress"], Enum.map(chunk_pages, &reference/1), %{}, nil)

      stage_pages(Map.merge(state, %{pages: chunk_pages, expected: record, desired: desired}))
    else
      false -> error(:incomplete_source)
      error -> error_result(error)
    end
  end

  defp perform(%{operation: :abort} = state) do
    with {:ok, record, _} <- draft_current(state),
         do: cas(state, record, Map.put(record["value"], "draft", nil), :committed),
         else: (error -> error_result(error))
  end

  defp perform(%{operation: :projection_open} = state) do
    with record when is_map(record) <- find_root(state, state.args["source_id"]),
         root = record["value"],
         true <-
           root["state"] == "active" and root["generation"] == state.args["generation"] and
             root["draft"] == nil,
         {:ok, _} <- projection_slot(root, state.args["projection_kind"], state.args["profile"]),
         {:ok, source} <- load_source(state, root),
         {:ok, chunks} <- Evidence.chunks(source),
         selected = Enum.filter(chunks, &(&1["chunk_id"] in state.args["chunks"])),
         true <-
           length(selected) == length(state.args["chunks"]) and
             length(Enum.uniq(state.args["chunks"])) == length(selected),
         draft = projection_draft(root, state.args),
         claimed = Map.put(root, "draft", draft),
         true <- fits?(claimed),
         {:ok, plan} <- projection_allowance(state, source, root, draft, selected) do
      cas(
        Map.merge(state, %{source: source, chunks: selected, plan: plan}),
        record,
        claimed,
        :claimed
      )
    else
      nil -> error(:source_missing)
      false -> error(:stale_or_busy_source)
      error -> error_result(error)
    end
  end

  defp perform(%{operation: :collect} = state) do
    roots = roots(state)

    protected =
      Enum.reduce(roots, MapSet.new(), fn record, protected ->
        root = record["value"]
        selected_refs = references_in(root)
        protected = Enum.reduce(selected_refs, protected, &protect(state, &1, &2))

        if root["state"] != "suppressed" and root["draft"] != nil,
          do:
            Enum.reduce(state.cache["records"], protected, fn {key, record}, acc ->
              if is_map(record["value"]) and record["value"]["draft_id"] == root["draft"]["id"],
                do: MapSet.put(acc, key),
                else: acc
            end),
          else: protected
      end)

    pages =
      state.cache["records"]
      |> Map.values()
      |> Enum.filter(fn record ->
        value = record["value"]

        not record["deleted"] and is_map(value) and value["kind"] == "page" and
          value["partition"] == state.profile["partition"] and
          not MapSet.member?(protected, record["key"])
      end)
      |> Enum.sort_by(& &1["key"])
      |> Enum.take(state.args["limit"])

    cond do
      pages == [] ->
        {:done, {:ok, %{"status" => "collected", "count" => 0, "record_slots_recovered" => 0}}}

      roots == [] ->
        io(
          state,
          :collect,
          %{"records" => pages, "snapshot_generation" => state.cache["generation"]},
          :collected
        )

      true ->
        io(
          Map.merge(state, %{collect_roots: roots, collect_pages: pages}),
          :get_many,
          %{"keys" => Enum.map(roots, & &1["key"])},
          :collect_checked
        )
    end
  end

  defp perform(%{operation: :export} = state), do: export_source(state)
  defp perform(%{operation: :import} = state), do: import_source(state)
  defp perform(%{operation: :projection_abort} = state), do: perform_public_abort(state)

  defp append_publication_records(state, record, draft, next) do
    if next == draft["target"]["byte_count"] do
      with {:ok, previous, _} <-
             load_progress(
               state,
               record["value"]["source_key"],
               draft["target"]["generation"],
               draft["progress"],
               MapSet.new()
             ),
           {:ok, source} <-
             Evidence.source(
               draft["target"]
               |> Map.take(@source_fields)
               |> Map.put("text", previous <> state.args["text"])
             ),
           {:ok, pages} <- chunk_pages(source, draft["id"]) do
        {:ok, length(pages)}
      end
    else
      {:ok, 0}
    end
  end

  defp projection_allowance(state, source, root, draft, selected) do
    known = Map.has_key?(state.args, "facts")
    model = if known, do: 0, else: 1
    model_reads = if state.args["projection_kind"] == "vectors", do: length(selected) * 6, else: 0
    recheck = if state.profile["kind"] == "mcp_cas", do: 1, else: 0
    recheck_reads = if recheck == 1, do: 15, else: 1

    token = %{
      "profile" => state.args["profile"],
      "chunks" => state.args["chunks"],
      "projection_kind" => state.args["projection_kind"],
      "draft_id" => draft["id"],
      "max_items" => Map.get(state.args, "max_items", 1)
    }

    planned =
      cond do
        known ->
          with {:ok, pages, desired} <-
                 prepare_projection(state, source, root, token, state.args["facts"]) do
            with :ok <- publication_capacity(state, pages, desired) do
              {:ok, length(pages), page_effects(state.profile, pages),
               items_digest(state.args["facts"])}
            end
          end

        state.args["projection_kind"] == "vectors" ->
          pages = length(selected) * 6 + 1
          with :ok <- capacity(state, pages, 0), do: {:ok, pages, pages, nil}

        true ->
          write_budget = 16 - state.effects - 2 - recheck - model
          batch_size = if state.profile["kind"] == "mcp_cas", do: 2, else: 1

          pages =
            Enum.filter(1..15, fn count ->
              capacity(state, count, 0, state.cache["bytes"]) == :ok and
                count <= write_budget * batch_size
            end)

          case pages do
            [] ->
              case capacity(state, 1, 0, state.cache["bytes"]) do
                :ok -> {:error, :effect_limit}
                error -> error
              end

            _ ->
              {:ok, List.last(pages), min(List.last(pages), write_budget), nil}
          end
      end

    with {:ok, pages, writes, digest} <- planned,
         :ok <- capacity(state, pages, 0, state.cache["bytes"]),
         true <- allowance?(state, writes + 2 + recheck + model, recheck_reads + model_reads) do
      commit = writes + 1 + recheck

      {:ok,
       vector_contract(
         %{
           "effects_before_model" => state.effects + 1,
           "effects_remaining" => 15 - state.effects,
           "model_effects" => model,
           "model_reads" => model_reads,
           "commit_effects" => commit,
           "commit_effects_worst_case" => commit,
           "total_effects" => state.effects + 1 + model + commit,
           "reserved_pages" => pages,
           "prepared_sha256" => digest,
           "maximum_dimensions" => 4096
         },
         state.args["projection_kind"]
       )}
    else
      false -> {:error, :effect_limit}
      error -> error
    end
  end

  defp commit_projection(state, root, token) do
    kind = token["projection_kind"]
    items = state.args[kind]

    with {:ok, source} <- load_source(state, root),
         true <-
           token["prepared_sha256"] == nil or token["prepared_sha256"] == items_digest(items),
         {:ok, all, desired} <- prepare_projection(state, source, root, token, items),
         true <- length(all) <= token["reserved_pages"],
         :ok <- publication_capacity(state, all, desired),
         :ok <- effect_plan(state, page_effects(state.profile, all) + 1, 0) do
      stage_pages(Map.merge(state, %{pages: all, desired: desired}))
    else
      false -> error(:projection_bounds)
      error -> error_result(error)
    end
  end

  defp prepare_projection(state, source, root, token, items) do
    kind = token["projection_kind"]

    with :ok <- projection_items(kind, items, source, token),
         {:ok, projection_id} <- projection_slot(root, kind, token["profile"]),
         {:ok, previous} <- projection_previous(state, root, projection_id, kind, items),
         {:ok, pages, records} <- projection_pages(source, token["draft_id"], kind, items),
         manifest =
           page(
             root["partition"],
             root["source_key"],
             root["generation"],
             token["draft_id"],
             "projection",
             0,
             %{
               "projection_kind" => kind,
               "profile" => token["profile"],
               "previous" => previous,
               "records" => records
             }
           ),
         all = pages ++ [manifest],
         true <- Enum.all?(all, &fits?(&1["value"])),
         head = %{
           "kind" => kind,
           "profile_sha256" => Evidence.id("profile", [ordered(token["profile"])]),
           "ref" => reference(manifest)
         },
         projections = Map.put(root["projections"], projection_id, head),
         desired = root |> Map.put("projections", projections) |> Map.put("draft", nil),
         true <- fits?(desired),
         {:ok, _} <- load_projections(%{state | cache: staged_cache(state.cache, all)}, desired) do
      {:ok, all, desired}
    else
      false -> {:error, :projection_bounds}
      error -> error
    end
  end

  defp page_effects(%{"kind" => "mcp_cas"} = profile, pages),
    do: length(MCPCAS.write_batches(profile, pages))

  defp page_effects(_, pages), do: length(pages)
  defp items_digest(items), do: Evidence.id("projection-items", [ordered(items)])

  defp projection_slot(root, kind, profile) do
    id = Evidence.id("projection", [kind, ordered(profile)])

    if Map.has_key?(root["projections"], id) or
         map_size(root["projections"]) < @projection_limit,
       do: {:ok, id},
       else: {:error, :projection_bounds}
  end

  defp projection_items("vectors", vectors, source, token) do
    with true <- is_list(vectors) and length(vectors) == length(token["chunks"]),
         true <- Enum.map(vectors, & &1["chunk_id"]) |> Enum.sort() == Enum.sort(token["chunks"]),
         true <- Enum.all?(vectors, &Evidence.current_vector?/1),
         true <- compatible_projection?("vectors", vectors, token["profile"]),
         true <- Enum.all?(vectors, &(&1["profile"] == token["profile"]["profile"])),
         {:ok, chunks} <- Evidence.chunks(source),
         true <-
           Enum.all?(vectors, fn vector ->
             Enum.any?(chunks, &(&1["chunk_id"] == vector["chunk_id"]))
           end) do
      :ok
    else
      _ -> {:error, :invalid_vectors}
    end
  end

  defp projection_items("facts", facts, source, token) do
    if is_list(facts) and length(facts) <= Map.get(token, "max_items", 32) and length(facts) <= 32 and
         Enum.all?(facts, fn fact ->
           Evidence.valid_fact?(fact) and
             Enum.all?(
               fact["citations"],
               &(Evidence.valid_span?(source, &1) and &1["chunk_id"] in token["chunks"])
             )
         end) do
      :ok
    else
      {:error, :invalid_facts}
    end
  end

  defp projection_previous(state, root, id, kind, items) do
    previous = get_in(root, ["projections", id, "ref"])

    if kind == "vectors" and previous != nil do
      with {:ok, existing, _} <- load_projection(state, root, previous, kind, MapSet.new()) do
        compatible = Enum.all?(existing, &Evidence.compatible_vectors?(&1, hd(items)))

        {:ok, if(compatible, do: previous)}
      end
    else
      {:ok, previous}
    end
  end

  defp projection_pages(source, draft, "vectors", vectors) do
    {pages, records} =
      Enum.reduce(vectors, {[], []}, fn vector, {pages, records} ->
        bytes = for value <- vector["values"], into: <<>>, do: <<value::little-float-size(32)>>
        slices = for offset <- 0..div(vector["dimensions"] - 1, 768), do: offset * 768

        row_pages =
          Enum.map(slices, fn offset ->
            count = min(768, vector["dimensions"] - offset)

            body =
              vector
              |> Map.drop(["version", "values"])
              |> Map.merge(%{
                "encoding" => "float32le.base64",
                "offset" => offset,
                "values" => Base.encode64(binary_part(bytes, offset * 4, count * 4))
              })

            page(
              source["partition"],
              source["source_key"],
              source["generation"],
              draft,
              "vector",
              length(pages) + offset,
              body
            )
          end)

        record =
          vector |> Map.drop(["values"]) |> Map.put("pages", Enum.map(row_pages, &reference/1))

        {pages ++ row_pages, records ++ [record]}
      end)

    if Enum.all?(pages, &fits?(&1["value"])),
      do: {:ok, pages, records},
      else: {:error, :projection_bounds}
  end

  defp projection_pages(source, draft, "facts", facts) do
    bytes = json(facts)

    with {:ok, pages} <-
           text_pages(
             source["partition"],
             source["source_key"],
             source["generation"],
             draft,
             bytes,
             "facts",
             0
           ) do
      {:ok, pages,
       [
         %{
           "sha256" => Evidence.sha256(bytes),
           "byte_count" => byte_size(bytes),
           "pages" => Enum.map(pages, &reference/1)
         }
       ]}
    end
  end

  defp source_plan(source, draft, previous, offset) do
    with {:ok, pages} <-
           text_pages(
             source["partition"],
             source["source_key"],
             source["generation"],
             draft["id"],
             source["text"],
             "content",
             offset
           ),
         progress =
           page(
             source["partition"],
             source["source_key"],
             source["generation"],
             draft["id"],
             "progress",
             offset,
             %{
               "previous" => previous,
               "offset" => offset,
               "next_offset" => offset + byte_size(source["text"]),
               "pieces" => Enum.map(pages, &reference/1)
             }
           ),
         true <- fits?(progress["value"]),
         {:ok, chunks} <- chunk_pages(source, draft["id"]) do
      {:ok,
       %{
         pages: pages ++ [progress] ++ chunks,
         progress: reference(progress),
         chunks: Enum.map(chunks, &reference/1)
       }}
    else
      _ -> {:error, :source_bounds}
    end
  end

  defp chunk_pages(source, draft) do
    with {:ok, chunks} <- Evidence.chunks(source) do
      chunks = Enum.map(chunks, &Map.delete(&1, "text"))
      pack_items(source, draft, "chunks", "chunks", chunks)
    end
  end

  defp pack_items(source, draft, kind, field, items),
    do: pack_items(source, draft, kind, field, items, [], [])

  defp pack_items(source, draft, kind, field, [], current, pages) do
    pages =
      if current == [] and pages != [],
        do: pages,
        else:
          pages ++
            [
              page(
                source["partition"],
                source["source_key"],
                source["generation"],
                draft,
                kind,
                length(pages),
                %{field => current}
              )
            ]

    if Enum.all?(pages, &fits?(&1["value"])), do: {:ok, pages}, else: {:error, :page_bounds}
  end

  defp pack_items(source, draft, kind, field, [item | rest] = items, current, pages) do
    candidate =
      page(
        source["partition"],
        source["source_key"],
        source["generation"],
        draft,
        kind,
        length(pages),
        %{field => current ++ [item]}
      )

    cond do
      fits?(candidate["value"]) ->
        pack_items(source, draft, kind, field, rest, current ++ [item], pages)

      current == [] ->
        {:error, :page_bounds}

      true ->
        complete =
          page(
            source["partition"],
            source["source_key"],
            source["generation"],
            draft,
            kind,
            length(pages),
            %{field => current}
          )

        pack_items(source, draft, kind, field, items, [], pages ++ [complete])
    end
  end

  defp text_pages(partition, source_key, generation, draft, text, kind, offset),
    do: text_pages(partition, source_key, generation, draft, text, kind, offset, [])

  defp text_pages(_, _, _, _, "", _, _, pages), do: {:ok, pages}

  defp text_pages(partition, source_key, generation, draft, text, kind, offset, pages) do
    {prefix, record} =
      fitting_prefix(
        partition,
        source_key,
        generation,
        draft,
        text,
        kind,
        offset,
        min(4096, byte_size(text))
      )

    if prefix == "",
      do: {:error, :page_bounds},
      else:
        text_pages(
          partition,
          source_key,
          generation,
          draft,
          binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix)),
          kind,
          offset + byte_size(prefix),
          pages ++ [record]
        )
  end

  defp fitting_prefix(partition, source_key, generation, draft, text, kind, offset, count) do
    prefix = utf8_prefix(text, count)
    record = page(partition, source_key, generation, draft, kind, offset, %{"text" => prefix})

    if fits?(record["value"]) or count == 0,
      do: {prefix, record},
      else:
        fitting_prefix(
          partition,
          source_key,
          generation,
          draft,
          text,
          kind,
          offset,
          div(count, 2)
        )
  end

  defp utf8_prefix(text, count) do
    prefix = binary_part(text, 0, count)
    if String.valid?(prefix), do: prefix, else: utf8_prefix(text, count - 1)
  end

  defp page(partition, source_key, generation, draft, kind, ordinal, body) do
    body_sha256 = Evidence.id("page-body", [kind, ordered(body)])

    key =
      Evidence.id("page", [partition, source_key, generation, draft, kind, ordinal, body_sha256])

    value = %{
      "format" => 1,
      "kind" => "page",
      "partition" => partition,
      "source_key" => source_key,
      "generation" => generation,
      "draft_id" => draft,
      "page_kind" => kind,
      "ordinal" => ordinal,
      "body" => body,
      "body_sha256" => body_sha256
    }

    %{"key" => key, "value" => value}
  end

  defp reference(page),
    do: %{"key" => page["key"], "sha256" => Evidence.id("page-record", [ordered(page["value"])])}

  defp selected(state) do
    Enum.reduce_while(roots(state), {:ok, [], %{}, [], []}, fn record,
                                                               {:ok, sources, projections, tokens,
                                                                gaps} ->
      root = record["value"]
      token = token(record)

      cond do
        root["state"] == "suppressed" ->
          {:cont,
           {:ok, sources, projections, tokens ++ [token],
            gaps ++ [%{"code" => "suppressed", "source_key" => root["source_key"]}]}}

        root["state"] == "staging" ->
          {:cont,
           {:ok, sources, projections, tokens ++ [token],
            gaps ++ [%{"code" => "incomplete_source", "source_key" => root["source_key"]}]}}

        true ->
          with {:ok, source} <- load_source(state, root),
               {:ok, projection} <- load_projections(state, root) do
            {:cont,
             {:ok, sources ++ [source], Map.put(projections, source["source_key"], projection),
              tokens ++ [token], gaps}}
          else
            {:error, code} -> {:halt, {:error, code}}
          end
      end
    end)
  end

  defp load_source(state, root) do
    with {:ok, text, _} <-
           load_progress(
             state,
             root["source_key"],
             root["generation"],
             root["content_ref"],
             MapSet.new()
           ),
         true <- Evidence.sha256(text) == root["content_sha256"],
         attrs = root |> Map.take(@source_fields) |> Map.put("text", text),
         {:ok, source} <- Evidence.source(attrs),
         {:ok, chunks} <- Evidence.chunks(source),
         {:ok, stored_chunks} <- load_chunk_pages(state, root),
         true <- stored_chunks === Enum.map(chunks, &Map.delete(&1, "text")) do
      {:ok, source}
    else
      _ -> {:error, :source_corrupt}
    end
  end

  defp load_progress(_state, _source, _generation, nil, _seen), do: {:ok, "", 0}

  defp load_progress(state, source, generation, ref, seen) do
    with false <- MapSet.member?(seen, ref["key"]),
         true <- MapSet.size(seen) < 128,
         {:ok, progress} <- load_page(state, ref, source, generation, "progress"),
         body = progress["body"],
         true <-
           keys?(body, ~w(previous offset next_offset pieces)) and
             Evidence.safe_uint?(body["offset"]) and
             Evidence.safe_uint?(body["next_offset"]) and
             is_list(body["pieces"]) and length(body["pieces"]) <= 16,
         {:ok, before, prior_offset} <-
           load_progress(
             state,
             source,
             generation,
             body["previous"],
             MapSet.put(seen, ref["key"])
           ),
         true <- body["offset"] == prior_offset,
         {:ok, pieces} <-
           load_text_parts(
             state,
             body["pieces"],
             source,
             generation,
             "content",
             progress["draft_id"]
           ),
         text = before <> pieces,
         true <- body["next_offset"] == byte_size(text) and byte_size(text) <= 65_536 do
      {:ok, text, byte_size(text)}
    else
      _ -> {:error, :source_corrupt}
    end
  end

  defp load_text_parts(state, refs, source, generation, kind, draft) do
    Enum.reduce_while(refs, {:ok, ""}, fn ref, {:ok, text} ->
      with {:ok, page} <- load_page(state, ref, source, generation, kind),
           true <- page["draft_id"] == draft,
           true <-
             keys?(page["body"], ["text"]) and is_binary(page["body"]["text"]) and
               String.valid?(page["body"]["text"]) do
        {:cont, {:ok, text <> page["body"]["text"]}}
      else
        _ -> {:halt, {:error, :page_corrupt}}
      end
    end)
  end

  defp load_chunk_pages(state, root) do
    Enum.reduce_while(root["chunks_ref"], {:ok, []}, fn ref, {:ok, chunks} ->
      with {:ok, page} <- load_page(state, ref, root["source_key"], root["generation"], "chunks"),
           true <- keys?(page["body"], ["chunks"]) and is_list(page["body"]["chunks"]) do
        {:cont, {:ok, chunks ++ page["body"]["chunks"]}}
      else
        _ -> {:halt, {:error, :page_corrupt}}
      end
    end)
  end

  defp load_projections(state, root) do
    Enum.reduce_while(root["projections"], {:ok, %{"vectors" => [], "facts" => []}}, fn {id, head},
                                                                                        {:ok, all} ->
      with true <- keys?(head, ~w(kind profile_sha256 ref)) and head["kind"] in ~w(vectors facts),
           {:ok, items, profile} <-
             load_projection(state, root, head["ref"], head["kind"], MapSet.new()),
           true <-
             id == Evidence.id("projection", [head["kind"], ordered(profile)]) and
               head["profile_sha256"] == Evidence.id("profile", [ordered(profile)]) do
        {:cont, {:ok, Map.update!(all, head["kind"], &(&1 ++ items))}}
      else
        _ -> {:halt, {:error, :projection_corrupt}}
      end
    end)
  end

  defp load_projection(state, root, ref, kind, seen) do
    with false <- MapSet.member?(seen, ref["key"]),
         true <- MapSet.size(seen) < 32,
         {:ok, page} <-
           load_page(state, ref, root["source_key"], root["generation"], "projection"),
         body = page["body"],
         true <-
           keys?(body, ~w(projection_kind profile previous records)) and
             body["projection_kind"] == kind and is_map(body["profile"]),
         {:ok, items} <-
           load_projection_items(state, root, page["draft_id"], kind, body["records"]),
         {:ok, previous, profile} <-
           if(body["previous"] == nil,
             do: {:ok, [], body["profile"]},
             else:
               load_projection(state, root, body["previous"], kind, MapSet.put(seen, ref["key"]))
           ),
         true <- profile === body["profile"],
         true <- compatible_projection?(kind, items ++ previous, profile),
         items = dedupe_projection(kind, items ++ previous),
         true <-
           (kind == "vectors" and length(items) <= 32) or
             (kind == "facts" and length(items) <= 256) do
      {:ok, items, profile}
    else
      _ -> {:error, :projection_corrupt}
    end
  end

  defp load_projection_items(state, root, draft, "vectors", records) do
    {:ok, source} = load_source(state, root)
    {:ok, chunks} = Evidence.chunks(source)
    chunk_ids = Enum.map(chunks, & &1["chunk_id"])

    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, vectors} ->
      with true <- vector_record?(record),
           true <- is_list(record["pages"]) and length(record["pages"]) in 1..6,
           {:ok, bytes} <- load_vector_parts(state, root, draft, record, record["pages"], <<>>),
           true <- byte_size(bytes) == record["dimensions"] * 4,
           vector =
             record
             |> Map.delete("pages")
             |> Map.put("values", for(<<value::little-float-size(32) <- bytes>>, do: value)),
           true <- Evidence.valid_vector?(vector),
           true <- vector["chunk_id"] in chunk_ids,
           true <- vector["vector_sha256"] == record["vector_sha256"] do
        {:cont, {:ok, vectors ++ [vector]}}
      else
        _ -> {:halt, {:error, :vector_corrupt}}
      end
    end)
  end

  defp load_projection_items(state, root, draft, "facts", [record]) do
    with true <- keys?(record, ~w(sha256 byte_count pages)) and is_list(record["pages"]),
         {:ok, text} <-
           load_text_parts(
             state,
             record["pages"],
             root["source_key"],
             root["generation"],
             "facts",
             draft
           ),
         true <-
           byte_size(text) == record["byte_count"] and Evidence.sha256(text) == record["sha256"],
         facts = JSON.decode!(text),
         true <-
           is_list(facts) and length(facts) <= 32 and Enum.all?(facts, &Evidence.valid_fact?/1),
         {:ok, source} <- load_source(state, root),
         true <-
           Enum.all?(facts, fn fact ->
             Enum.all?(fact["citations"], &Evidence.valid_span?(source, &1))
           end) do
      {:ok, facts}
    else
      _ -> {:error, :facts_corrupt}
    end
  rescue
    _ -> {:error, :facts_corrupt}
  end

  defp load_projection_items(_, _, _, _, _), do: {:error, :projection_corrupt}

  defp vector_record?(record) do
    fields =
      ~w(version chunk_id input_sha256 profile model dimensions encoding vector_sha256 pages)

    ((record["version"] === 1 and keys?(record, fields)) or
       (record["version"] === 2 and keys?(record, ["selection_sha256" | fields]) and
          Evidence.sha256?(record["selection_sha256"]))) and record["encoding"] == "float32le" and
      is_integer(record["dimensions"]) and record["dimensions"] in 1..4096
  end

  defp vector_part_fields(record) do
    fields =
      ~w(chunk_id input_sha256 profile model dimensions encoding vector_sha256 offset values)

    if record["version"] === 2, do: ["selection_sha256" | fields], else: fields
  end

  defp load_vector_parts(_state, _root, _draft, _record, [], bytes), do: {:ok, bytes}

  defp load_vector_parts(state, root, draft, record, [ref | rest], bytes) do
    with {:ok, page} <- load_page(state, ref, root["source_key"], root["generation"], "vector"),
         true <- page["draft_id"] == draft,
         body = page["body"],
         true <-
           keys?(
             body,
             vector_part_fields(record)
           ),
         true <-
           Map.drop(body, ~w(encoding offset values)) ==
             Map.drop(record, ~w(version encoding pages)),
         true <-
           body["encoding"] == "float32le.base64" and body["offset"] == div(byte_size(bytes), 4),
         {:ok, part} <- Base.decode64(body["values"]),
         true <-
           Base.encode64(part) == body["values"] and byte_size(part) in 4..3072 and
             rem(byte_size(part), 4) == 0 do
      load_vector_parts(state, root, draft, record, rest, bytes <> part)
    else
      _ -> {:error, :vector_corrupt}
    end
  end

  defp load_page(state, ref, source_key, generation, kind) do
    with true <- ref?(ref),
         record when is_map(record) <- state.cache["records"][ref["key"]],
         true <- record["deleted"] == false and record["revision"] == 1,
         value = record["value"],
         true <-
           valid_page?(value, state.profile["partition"]) and value["source_key"] == source_key and
             value["generation"] == generation and value["page_kind"] == kind,
         true <- reference(%{"key" => record["key"], "value" => value}) === ref,
         true <-
           page(
             value["partition"],
             value["source_key"],
             value["generation"],
             value["draft_id"],
             kind,
             value["ordinal"],
             value["body"]
           )["key"] == record["key"] do
      {:ok, value}
    else
      _ -> {:error, :page_corrupt}
    end
  end

  defp export_source(state) do
    case find_root(state, state.args["source_id"]) do
      nil ->
        error(:source_missing)

      %{"value" => %{"state" => "suppressed"} = root} ->
        {:done,
         {:ok,
          %{
            "version" => 1,
            "kind" => "suppression",
            "root" => root,
            "complete" => true,
            "cursor" => 0,
            "next" => nil,
            "projection_coverage" => "omitted_reindex_required"
          }}}

      record ->
        with true <- record["value"]["state"] == "active",
             {:ok, source} <- load_source(state, record["value"]),
             offset = state.args["cursor"] || 0,
             true <-
               offset <= byte_size(source["text"]) and
                 String.valid?(binary_part(source["text"], 0, offset)),
             remaining = binary_part(source["text"], offset, byte_size(source["text"]) - offset),
             part =
               export_prefix(
                 source,
                 record["value"]["projections"],
                 offset,
                 remaining,
                 min(state.args["limit"] * 4096, min(8192, byte_size(remaining)))
               ),
             next = offset + byte_size(part),
             single = offset == 0 and next == byte_size(source["text"]),
             true <- part != "" or remaining == "",
             value = export_envelope(source, record["value"]["projections"], offset, part),
             duplicate = Map.put(value, "source", source),
             value = if(single and export_fits?(duplicate), do: duplicate, else: value),
             true <- export_fits?(value) do
          {:done, {:ok, value}}
        else
          _ -> error(:export_bounds)
        end
    end
  end

  defp export_envelope(source, heads, offset, part) do
    next = offset + byte_size(part)
    complete = next == byte_size(source["text"])

    %{
      "version" => 1,
      "kind" => "source",
      "source" => Map.delete(source, "text"),
      "text" => part,
      "byte_count" => byte_size(source["text"]),
      "cursor" => offset,
      "next" => if(complete, do: nil, else: next),
      "complete" => complete,
      "projection_coverage" => "omitted_reindex_required",
      "projection_heads" => heads
    }
  end

  defp export_prefix(source, heads, offset, remaining, count) do
    part = utf8_prefix(remaining, count)

    if export_fits?(export_envelope(source, heads, offset, part)) or count == 0,
      do: part,
      else: export_prefix(source, heads, offset, remaining, div(count, 2))
  end

  defp export_fits?(value),
    do: Ipse.Extension.validate(value) == :ok and byte_size(json(value)) <= 12_000

  defp import_source(state) do
    envelope = state.args["export"]

    cond do
      envelope["version"] !== 1 or envelope["complete"] !== true ->
        error(:incomplete_import)

      envelope["kind"] == "suppression" ->
        root = envelope["root"]
        key = root_key(state.profile["partition"], root["source_key"])
        current = state.cache["records"][key]

        if current && current["deleted"] do
          error(:store_corrupt)
        else
          if valid_root?(root, root["partition"]) and root["state"] == "suppressed" and
               revision(current) == state.args["expected_revision"] do
            next = Map.put(root, "partition", state.profile["partition"])

            if current && current["value"]["generation"] > next["generation"] do
              error(:stale_import)
            else
              with :ok <-
                     capacity(state, if(current, do: 0, else: 1), if(current, do: 0, else: 1)) do
                cas(%{state | operation: :forget}, current || missing(key), next, :committed)
              else
                error -> error_result(error)
              end
            end
          else
            error(:invalid_import)
          end
        end

      envelope["kind"] == "source" ->
        metadata = envelope["source"]

        source =
          if is_map(metadata) and not Map.has_key?(metadata, "text"),
            do: Map.put(metadata, "text", envelope["text"]),
            else: metadata

        if Evidence.valid_source?(source) and envelope["cursor"] === 0 and envelope["next"] == nil and
             envelope["byte_count"] == byte_size(source["text"]) and
             envelope["text"] == source["text"] and byte_size(source["text"]) <= 8192 do
          args =
            source
            |> Map.take(@source_fields)
            |> Map.drop(~w(partition origin))
            |> Map.merge(%{
              "expected_revision" => state.args["expected_revision"],
              "historical_import" => source["origin"]
            })

          perform(%{state | operation: :put, args: args})
        else
          error(:incomplete_import)
        end

      true ->
        error(:invalid_import)
    end
  end

  defp perform_public_abort(state) do
    record = find_root(state, state.args["source_id"])

    if record && record["value"]["state"] == "active" do
      root = record["value"]
      draft = root["draft"]

      if draft != nil and draft["kind"] in ~w(vectors facts) and
           root["generation"] == state.args["generation"] and
           draft["profile"] === state.args["profile"] and
           Enum.sort(draft["chunk_ids"]) == Enum.sort(state.args["chunks"]),
         do: cas(state, record, Map.put(root, "draft", nil), :committed),
         else: error(:stale_draft)
    else
      error(:source_missing)
    end
  end

  defp source_draft_current(state) do
    case draft_current(state) do
      {:ok, record, %{"kind" => "source"} = draft} -> {:ok, record, draft}
      _ -> {:error, :stale_draft}
    end
  end

  defp draft_current(state) do
    record = find_root(state, state.args["source_id"])

    if record != nil and record["revision"] == state.args["expected_revision"] and
         record["value"]["state"] != "suppressed" and
         record["value"]["draft"] != nil and
         record["value"]["draft"]["id"] == state.args["draft_id"],
       do: {:ok, record, record["value"]["draft"]},
       else: {:error, :stale_draft}
  end

  defp source_draft(record, target) do
    %{
      "id" => random_id(),
      "kind" => "source",
      "source_generation" => if(record, do: record["value"]["generation"]),
      "content_sha256" => if(record, do: record["value"]["content_sha256"]),
      "plan_sha256" => Evidence.id("source-plan", [ordered(target)]),
      "progress" => nil,
      "next_offset" => 0,
      "target" => target,
      "profile" => nil,
      "chunk_ids" => [],
      "expires_at_ms" => System.system_time(:millisecond) + 3_600_000
    }
  end

  defp projection_draft(root, args) do
    draft = %{
      "id" => random_id(),
      "kind" => args["projection_kind"],
      "source_generation" => root["generation"],
      "content_sha256" => root["content_sha256"],
      "plan_sha256" =>
        projection_plan(
          root,
          args["projection_kind"],
          args["profile"],
          args["chunks"],
          if(args["projection_kind"] == "vectors", do: 2)
        ),
      "progress" => nil,
      "next_offset" => 0,
      "target" => nil,
      "profile" => args["profile"],
      "chunk_ids" => args["chunks"],
      "expires_at_ms" => System.system_time(:millisecond) + 3_600_000
    }

    vector_contract(draft, args["projection_kind"])
  end

  defp vector_contract(value, "vectors"), do: Map.put(value, "vector_version", 2)
  defp vector_contract(value, _), do: value

  defp current_vector_contract?(value, field),
    do: value[field] != "vectors" or value["vector_version"] === 2

  defp projection_plan(root, kind, profile, chunks, vector_version) do
    fields = [
      root["source_key"],
      root["generation"],
      root["content_sha256"],
      kind,
      ordered(profile),
      chunks
    ]

    Evidence.id(
      "projection-plan",
      if(vector_version == nil, do: fields, else: fields ++ [vector_version])
    )
  end

  defp staging(source, draft),
    do: active_root(source, nil, [], %{}, draft) |> Map.put("state", "staging")

  defp active_root(source, content_ref, chunks_ref, projections, draft) do
    source
    |> Map.take(@source_fields -- ["text"])
    |> Map.merge(%{
      "format" => 1,
      "kind" => "root",
      "source_key" => source["source_key"],
      "state" => "active",
      "content_sha256" => source["content_sha256"],
      "content_ref" => content_ref,
      "chunks_ref" => chunks_ref,
      "projections" => projections,
      "draft" => draft
    })
  end

  defp origin(state, args) do
    imported = args["historical_import"]

    %{
      "kind" => if(imported, do: "import", else: "provided"),
      "store_profile" => state.name,
      "partition_or_scope" => state.profile["partition"],
      "receipt" => if(imported, do: %{"original_origin" => imported}),
      "historical" => imported != nil
    }
  end

  defp writable(record, expected, generation) do
    cond do
      revision(record) != expected -> {:error, :conflict}
      record && record["value"]["state"] == "suppressed" -> {:error, :source_suppressed}
      record && record["value"]["draft"] != nil -> {:error, :source_busy}
      record && generation <= record["value"]["generation"] -> {:error, :stale_generation}
      true -> :ok
    end
  end

  defp capacity(state, added, added_roots, bytes \\ nil) do
    cond do
      added > 0 and state.profile["kind"] == "mcp_cas" and
          state.profile["contract"] != "ipse-cas-v3" ->
        {:error, :atomic_capacity_unavailable}

      added_roots > 0 and length(roots(state)) + added_roots > 32 ->
        {:error, :source_limit}

      map_size(state.cache["records"]) + added > record_limit(state.profile) ->
        {:error, :record_limit}

      (bytes || state.cache["bytes"] + added * 6300 + if(added > 0, do: 6000, else: 0)) >
          1_048_576 ->
        {:error, :store_byte_limit}

      true ->
        :ok
    end
  end

  defp publication_capacity(state, pages, root) do
    root_key = root_key(root["partition"], root["source_key"])
    old = state.cache["records"][root_key]
    state? = state.profile["kind"] == "state"

    record = fn key, value, revision ->
      row = %{"key" => key, "value" => value, "revision" => revision, "deleted" => false}
      if state?, do: Map.put(row, "operation_id", String.duplicate("0", 32)), else: row
    end

    records =
      Enum.reduce(pages, state.cache["records"], fn page, records ->
        Map.put(records, page["key"], record.(page["key"], page["value"], 1))
      end)

    records = Map.put(records, root_key, record.(root_key, root, revision(old) + 2))

    bytes =
      byte_size(
        json(%{
          "version" => 1,
          "namespace" => String.duplicate("0", 64),
          "generation" => min(Evidence.safe_integer_max(), state.cache["generation"] + 16),
          "records" => records
        })
      )

    capacity(state, length(pages), 0, bytes)
  end

  defp record_limit(%{"kind" => "mcp_cas"}), do: 88
  defp record_limit(_), do: 256

  defp snapshot_capacity(state) do
    if length(roots(state)) <= 32, do: :ok, else: {:error, :root_capacity_exceeded}
  end

  defp effect_plan(state, writes, model) do
    if state.effects + writes + model <= 16, do: :ok, else: {:error, :effect_limit}
  end

  defp cas(state, record, next_root, stage) do
    with true <- fits?(next_root) and valid_root?(next_root, state.profile["partition"]),
         {:ok, expected_generation} <- root_admission(state, record) do
      old = record["value"]

      io(
        state,
        :cas_root,
        %{
          "key" => record["key"],
          "expected_revision" => record["revision"],
          "expected_generation" => expected_generation,
          "expected_source_generation" => if(old, do: old["generation"]),
          "expected_content_sha256" => if(old, do: old["content_sha256"]),
          "draft_id" =>
            if(old && old["state"] != "suppressed" && old["draft"], do: old["draft"]["id"]),
          "next_root" => next_root
        },
        stage
      )
    else
      false -> error(:root_bounds)
      other -> error_result(other)
    end
  end

  defp root_admission(state, record) do
    actual = state.cache["records"][record["key"]]

    cond do
      actual && actual["deleted"] ->
        {:error, :store_corrupt}

      record["revision"] == 0 ->
        with true <- actual == nil,
             :ok <- capacity(state, 1, 1) do
          {:ok, state.cache["generation"]}
        else
          false -> {:error, :conflict}
          other -> other
        end

      true ->
        {:ok, nil}
    end
  end

  defp stage_pages(%{pages: []} = state),
    do: cas(state, state.expected, state.desired, :committed)

  defp stage_pages(state), do: io(state, :put_immutable_many, %{"pages" => state.pages}, :staged)

  defp find_root(state, source_id) when is_binary(source_id) do
    key = root_key(state.profile["partition"], Evidence.sha256(source_id))

    case state.cache["records"][key] do
      %{"deleted" => false} = record -> record
      _ -> nil
    end
  end

  defp find_root(_, _), do: nil

  defp roots(state),
    do:
      state.cache["records"]
      |> Map.values()
      |> Enum.filter(fn record ->
        is_map(record["value"]) and not record["deleted"] and record["value"]["kind"] == "root" and
          record["value"]["partition"] == state.profile["partition"]
      end)
      |> Enum.sort_by(& &1["key"])

  defp valid_partition(cache, partition) do
    if Enum.all?(cache["records"], fn {key, record} ->
         value = record["value"]

         if record["deleted"] or not is_map(value) or value["partition"] != partition do
           true
         else
           case value["kind"] do
             "root" ->
               valid_root?(value, partition) and key == root_key(partition, value["source_key"])

             "page" ->
               valid_page?(value, partition) and
                 key ==
                   page(
                     partition,
                     value["source_key"],
                     value["generation"],
                     value["draft_id"],
                     value["page_kind"],
                     value["ordinal"],
                     value["body"]
                   )["key"]

             _ ->
               false
           end
         end
       end) do
      :ok
    else
      {:error, :store_corrupt}
    end
  end

  defp valid_root?(%{"state" => "suppressed"} = root, partition) do
    keys?(root, ~w(format kind partition source_key generation state suppressed_at_ms)) and
      root["format"] === 1 and root["kind"] == "root" and root["partition"] == partition and
      Evidence.sha256?(root["source_key"]) and Evidence.safe_positive?(root["generation"]) and
      Evidence.safe_uint?(root["suppressed_at_ms"]) and fits?(root)
  end

  defp valid_root?(root, partition) do
    attrs = root |> Map.take(@source_fields) |> Map.put("text", "")

    keys?(root, @root_fields) and root["format"] === 1 and root["kind"] == "root" and
      root["partition"] == partition and root["state"] in ~w(active staging) and
      match?({:ok, _}, Evidence.source(attrs)) and
      root["source_key"] == Evidence.sha256(root["source_id"]) and
      Evidence.sha256?(root["content_sha256"]) and is_list(root["chunks_ref"]) and
      length(root["chunks_ref"]) <= 32 and
      Enum.all?(root["chunks_ref"], &ref?/1) and is_map(root["projections"]) and
      map_size(root["projections"]) <= @projection_limit and
      Enum.all?(root["projections"], fn {key, head} ->
        Evidence.sha256?(key) and keys?(head, ~w(kind profile_sha256 ref)) and
          head["kind"] in ~w(vectors facts) and Evidence.sha256?(head["profile_sha256"]) and
          ref?(head["ref"])
      end) and
      (root["draft"] == nil or valid_draft?(root["draft"], root)) and
      if(root["state"] == "active",
        do: ref?(root["content_ref"]),
        else: root["content_ref"] == nil
      ) and fits?(root)
  rescue
    _ -> false
  end

  defp valid_draft?(draft, root) do
    fields =
      ~w(id kind source_generation content_sha256 plan_sha256 progress next_offset target profile chunk_ids expires_at_ms)

    fields =
      if draft["kind"] == "vectors" and Map.has_key?(draft, "vector_version"),
        do: ["vector_version" | fields],
        else: fields

    keys?(draft, fields) and
      (not Map.has_key?(draft, "vector_version") or draft["vector_version"] === 2) and
      id?(draft["id"]) and draft["kind"] in ~w(source vectors facts) and
      (draft["source_generation"] == nil or Evidence.safe_positive?(draft["source_generation"])) and
      (draft["content_sha256"] == nil or Evidence.sha256?(draft["content_sha256"])) and
      Evidence.sha256?(draft["plan_sha256"]) and
      (draft["progress"] == nil or ref?(draft["progress"])) and
      Evidence.safe_uint?(draft["next_offset"]) and
      draft["next_offset"] <= 65_536 and
      is_list(draft["chunk_ids"]) and Enum.all?(draft["chunk_ids"], &Evidence.sha256?/1) and
      Evidence.safe_uint?(draft["expires_at_ms"]) and
      if(draft["kind"] == "source",
        do: valid_source_target?(draft, root),
        else:
          draft["target"] == nil and is_map(draft["profile"]) and
            length(draft["chunk_ids"]) in 1..2 and root["state"] == "active" and
            draft["source_generation"] == root["generation"] and
            draft["content_sha256"] == root["content_sha256"] and
            draft["progress"] == nil and draft["next_offset"] == 0 and
            draft["plan_sha256"] ==
              projection_plan(
                root,
                draft["kind"],
                draft["profile"],
                draft["chunk_ids"],
                draft["vector_version"]
              )
      )
  rescue
    _ -> false
  end

  defp valid_source_target?(draft, root) do
    target = draft["target"]

    keys?(target, (@source_fields -- ["text"]) ++ ~w(content_sha256 byte_count)) and
      match?({:ok, _}, Evidence.source(target |> Map.take(@source_fields) |> Map.put("text", ""))) and
      target["source_id"] == root["source_id"] and target["partition"] == root["partition"] and
      Evidence.sha256?(target["content_sha256"]) and Evidence.safe_uint?(target["byte_count"]) and
      target["byte_count"] <= 65_536 and
      draft["next_offset"] <= target["byte_count"] and draft["profile"] == nil and
      draft["chunk_ids"] == [] and
      draft["plan_sha256"] == Evidence.id("source-plan", [ordered(target)]) and
      if(draft["source_generation"] == nil,
        do:
          root["state"] == "staging" and target["generation"] == root["generation"] and
            draft["content_sha256"] == nil,
        else:
          draft["source_generation"] == root["generation"] and
            target["generation"] > root["generation"] and
            draft["content_sha256"] == root["content_sha256"]
      )
  end

  defp valid_page?(value, partition) do
    keys?(
      value,
      ~w(format kind partition source_key generation draft_id page_kind ordinal body body_sha256)
    ) and
      value["format"] === 1 and value["kind"] == "page" and value["partition"] == partition and
      Evidence.sha256?(value["source_key"]) and Evidence.safe_positive?(value["generation"]) and
      id?(value["draft_id"]) and
      value["page_kind"] in ~w(content progress chunks vector facts projection) and
      Evidence.safe_uint?(value["ordinal"]) and
      is_map(value["body"]) and
      value["body_sha256"] ==
        Evidence.id("page-body", [value["page_kind"], ordered(value["body"])]) and fits?(value)
  rescue
    _ -> false
  end

  defp protect(state, ref, protected) do
    if not ref?(ref) or MapSet.member?(protected, ref["key"]) do
      protected
    else
      case state.cache["records"][ref["key"]] do
        %{"deleted" => false, "value" => value} ->
          Enum.reduce(
            references_in(value),
            MapSet.put(protected, ref["key"]),
            &protect(state, &1, &2)
          )

        _ ->
          protected
      end
    end
  end

  defp references_in(map) when is_map(map) do
    if ref?(map), do: [map], else: Enum.flat_map(Map.values(map), &references_in/1)
  end

  defp references_in(list) when is_list(list), do: Enum.flat_map(list, &references_in/1)
  defp references_in(_), do: []

  defp token(record),
    do: %{
      "partition" => record["value"]["partition"],
      "key" => record["key"],
      "revision" => record["revision"],
      "source_key" => record["value"]["source_key"],
      "generation" => record["value"]["generation"],
      "content_sha256" => record["value"]["content_sha256"],
      "state" => record["value"]["state"]
    }

  defp token?(token),
    do:
      keys?(token, ~w(partition key revision source_key generation content_sha256 state)) and
        name?(token["partition"]) and Evidence.sha256?(token["key"]) and
        Evidence.safe_positive?(token["revision"]) and
        Evidence.sha256?(token["source_key"]) and Evidence.safe_positive?(token["generation"]) and
        token["state"] in ~w(active staging suppressed) and
        (token["content_sha256"] == nil or Evidence.sha256?(token["content_sha256"]))

  defp matches_token?(record, token),
    do:
      record["deleted"] == false and record["revision"] == token["revision"] and
        is_map(record["value"]) and
        token(record) == token

  defp draft_token?(token, name, profile),
    do:
      is_map(token) and token["version"] === 1 and token["store"] == name and
        token["partition"] == profile["partition"] and Evidence.sha256?(token["root_key"]) and
        Evidence.safe_positive?(token["revision"]) and
        id?(token["draft_id"]) and Evidence.safe_positive?(token["generation"]) and
        Evidence.sha256?(token["content_sha256"]) and
        token["projection_kind"] in ~w(vectors facts) and is_map(token["profile"]) and
        (not Map.has_key?(token, "vector_version") or
           (token["projection_kind"] == "vectors" and token["vector_version"] === 2)) and
        is_list(token["chunks"]) and
        is_map(token["cache"]) and is_integer(token["effects_before_model"]) and
        token["effects_before_model"] in 1..16 and
        is_integer(token["reserved_pages"]) and token["reserved_pages"] in 1..15

  defp draft_result(record) do
    root = record["value"]
    draft = root["draft"]

    {:done,
     {:ok,
      %{
        "status" => "draft",
        "source_id" => root["source_id"],
        "source_key" => root["source_key"],
        "generation" => draft["target"]["generation"],
        "revision" => record["revision"],
        "draft_id" => draft["id"],
        "next_offset" => draft["next_offset"],
        "continuation" => %{
          "draft_id" => draft["id"],
          "expected_revision" => record["revision"],
          "offset" => draft["next_offset"]
        }
      }}}
  end

  defp public_draft(nil), do: nil

  defp public_draft(draft),
    do:
      Map.take(
        draft,
        ~w(id kind source_generation content_sha256 next_offset chunk_ids expires_at_ms vector_version)
      )

  defp put_record(cache, record, generation),
    do: %{
      cache
      | "records" => Map.put(cache["records"], record["key"], record),
        "generation" => generation
    }

  defp staged_cache(cache, pages),
    do:
      Enum.reduce(pages, cache, fn page, cache ->
        put_record(
          cache,
          %{"key" => page["key"], "revision" => 1, "deleted" => false, "value" => page["value"]},
          cache["generation"]
        )
      end)

  defp missing(key), do: %{"key" => key, "revision" => 0, "deleted" => true, "value" => nil}
  defp revision(nil), do: 0
  defp revision(record), do: record["revision"]
  defp dedupe_projection("vectors", items), do: Enum.uniq_by(items, & &1["chunk_id"])
  defp dedupe_projection("facts", items), do: Enum.uniq_by(items, & &1["fact_id"])

  defp compatible_projection?("facts", _items, _profile), do: true

  defp compatible_projection?("vectors", items, profile) do
    Enum.all?(items, &(&1["profile"] == profile["profile"])) and
      length(
        Enum.uniq_by(
          items,
          &Map.take(&1, ~w(version selection_sha256 profile model dimensions encoding))
        )
      ) <= 1
  end

  defp coverage(state),
    do: %{
      "store" => state.name,
      "kind" => state.profile["kind"],
      "partition" => state.profile["partition"],
      "generation" => state.cache["generation"],
      "records" => map_size(state.cache["records"]),
      "bytes" => state.cache["bytes"],
      "effects_used" => state.effects,
      "reads_used" => state.reads,
      "revalidate_effects_worst_case" =>
        if(state.profile["kind"] == "state", do: 0, else: div(length(roots(state)) + 7, 8)),
      "revalidate_reads_worst_case" =>
        if(state.profile["kind"] == "state",
          do: length(roots(state)),
          else: 15 * div(length(roots(state)) + 7, 8)
        ),
      "complete" => true
    }

  defp adapter(%{"kind" => "state"}), do: State
  defp adapter(%{"kind" => "mcp_cas"}), do: MCPCAS

  defp profile?(%{"kind" => "state"} = p),
    do:
      keys?(p, ~w(kind scope partition)) and p["scope"] in ~w(project operator session) and
        name?(p["partition"])

  defp profile?(%{"kind" => "mcp_cas"} = p),
    do:
      keys?(p, ~w(kind binding partition contract)) and name?(p["binding"]) and
        name?(p["partition"]) and p["contract"] in ~w(ipse-cas-v1 ipse-cas-v2 ipse-cas-v3)

  defp profile?(_), do: false

  defp ref?(ref),
    do:
      keys?(ref, ~w(key sha256)) and Evidence.sha256?(ref["key"]) and
        Evidence.sha256?(ref["sha256"])

  defp fits?(value),
    do: is_map(value) and byte_size(json(value)) <= 6000 and Ipse.Extension.validate(value) == :ok

  defp keys?(value, fields), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(fields)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp name?(value), do: is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,64}\z/, value)
  defp random_id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  defp json(value), do: JSON.encode!(value) |> IO.iodata_to_binary()

  defp ordered(map) when is_map(map),
    do: ["map", map |> Enum.sort() |> Enum.map(fn {key, value} -> [key, ordered(value)] end)]

  defp ordered(list) when is_list(list), do: ["list", Enum.map(list, &ordered/1)]
  defp ordered(value), do: value
  defp error(code), do: {:done, {:error, code, %{}}}
  defp error_result({:error, code}), do: error(code)
  defp error_result({:done, {:error, _, _}} = result), do: result
  defp error_result(_), do: error(:store_refused)

  defp arguments(operation, args) do
    fields =
      case operation do
        :put ->
          ~w(source_id generation expected_revision title text uri observed_at_ms event_at_ms expires_at_ms)

        :open ->
          ~w(source_id generation expected_revision title uri observed_at_ms event_at_ms expires_at_ms byte_count content_sha256)

        :append ->
          ~w(source_id draft_id expected_revision offset text)

        action when action in [:publish, :abort] ->
          ~w(source_id draft_id expected_revision)

        :forget ->
          ~w(source_id expected_revision)

        :inspect ->
          ~w(source_id)

        :snapshot ->
          []

        :snapshot_selected ->
          ~w(refs store_generation effects_used reads_used as_of_ms)

        :revalidate ->
          ~w(tokens)

        :projection_open ->
          ~w(source_id generation projection_kind profile chunks)

        :projection_commit ->
          ["draft"]

        :projection_abort ->
          if(Map.has_key?(args, "draft"),
            do: ["draft"],
            else: ~w(source_id generation profile chunks)
          )

        :export ->
          ~w(source_id cursor limit)

        :import ->
          ~w(expected_revision export)

        :collect ->
          ~w(limit)
      end

    optional =
      case operation do
        action when action in [:put, :open] -> ~w(historical_import)
        :forget -> ~w(suppressed_at_ms)
        :projection_open -> ~w(max_items facts)
        :projection_commit -> ~w(vectors facts)
        :revalidate -> ~w(effects_used reads_used)
        _ -> []
      end

    valid =
      keys?(Map.drop(args, optional), fields) and
        (not Map.has_key?(args, "source_id") or
           (is_binary(args["source_id"]) and byte_size(args["source_id"]) in 1..256 and
              not Regex.match?(~r/[\x00-\x1f\x7f]/, args["source_id"]))) and
        (not Map.has_key?(args, "expected_revision") or
           Evidence.safe_uint?(args["expected_revision"])) and
        (not Map.has_key?(args, "generation") or Evidence.safe_positive?(args["generation"])) and
        (operation not in [:put, :open] or
           (Evidence.safe_uint?(args["observed_at_ms"]) and
              Enum.all?(~w(event_at_ms expires_at_ms), fn field ->
                args[field] == nil or Evidence.safe_uint?(args[field])
              end))) and
        (not Map.has_key?(args, "suppressed_at_ms") or
           Evidence.safe_uint?(args["suppressed_at_ms"])) and
        (not Map.has_key?(args, "draft_id") or id?(args["draft_id"])) and
        (not Map.has_key?(args, "text") or
           (is_binary(args["text"]) and String.valid?(args["text"]) and
              byte_size(args["text"]) <= if(operation == :put, do: 8192, else: 4096))) and
        (not Map.has_key?(args, "offset") or Evidence.safe_uint?(args["offset"])) and
        (not Map.has_key?(args, "historical_import") or
           (is_map(args["historical_import"]) and
              byte_size(json(args["historical_import"])) <= 2048)) and
        (operation != :projection_open or
           (args["projection_kind"] in ~w(vectors facts) and is_map(args["profile"]) and
              is_list(args["chunks"]) and length(args["chunks"]) in 1..2 and
              Enum.all?(args["chunks"], &Evidence.sha256?/1) and
              Map.get(args, "max_items", 1) in 1..32)) and
        (operation != :projection_open or not Map.has_key?(args, "facts") or
           (args["projection_kind"] == "facts" and is_list(args["facts"]))) and
        (operation != :projection_commit or
           Map.has_key?(args, "vectors") != Map.has_key?(args, "facts")) and
        (operation != :revalidate or (is_list(args["tokens"]) and length(args["tokens"]) <= 32)) and
        (operation not in [:snapshot_selected, :revalidate] or
           (Evidence.safe_uint?(Map.get(args, "effects_used", 0)) and
              Map.get(args, "effects_used", 0) <= 16 and
              Evidence.safe_uint?(Map.get(args, "reads_used", 0)) and
              Map.get(args, "reads_used", 0) <= 512 and
              Map.get(args, "effects_used", 0) + Map.get(args, "reads_used", 0) <= 528)) and
        (operation != :snapshot_selected or
           (Evidence.safe_uint?(args["store_generation"]) and
              Evidence.safe_uint?(args["as_of_ms"]) and is_list(args["refs"]) and
              length(args["refs"]) <= 10 and
              Enum.all?(args["refs"], &selected_ref?/1) and
              length(Enum.uniq_by(args["refs"], &{&1["source_key"], &1["chunk_id"]})) ==
                length(args["refs"]) and
              Enum.all?(Enum.group_by(args["refs"], & &1["source_key"]), fn {_key, refs} ->
                length(
                  Enum.uniq_by(
                    refs,
                    &Map.take(&1, ~w(source_id source_key generation content_sha256))
                  )
                ) == 1
              end))) and
        (operation not in [:collect, :export] or
           (is_integer(args["limit"]) and
              args["limit"] in 1..if(operation == :collect, do: 12, else: 4))) and
        (operation != :export or args["cursor"] == nil or Evidence.safe_uint?(args["cursor"]))

    if valid, do: :ok, else: {:error, :invalid_store_arguments}
  end

  defp selected_ref?(ref) do
    keys?(ref, ~w(source_id source_key generation content_sha256 chunk_id score)) and
      is_binary(ref["source_id"]) and String.valid?(ref["source_id"]) and
      byte_size(ref["source_id"]) in 1..256 and
      not Regex.match?(~r/[\x00-\x1f\x7f]/, ref["source_id"]) and
      Evidence.sha256?(ref["source_key"]) and
      ref["source_key"] == Evidence.sha256(ref["source_id"]) and
      Evidence.safe_positive?(ref["generation"]) and Evidence.sha256?(ref["content_sha256"]) and
      Evidence.sha256?(ref["chunk_id"]) and
      is_number(ref["score"]) and abs(ref["score"]) <= 1.7976931348623157e308
  rescue
    _ -> false
  end
end
