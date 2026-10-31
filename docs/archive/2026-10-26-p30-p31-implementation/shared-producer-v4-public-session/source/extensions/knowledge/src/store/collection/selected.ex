defmodule IpseKnowledge.Store.Collection.Selected do
  @moduledoc """
  Bounded read-only hydration of selected shared projection sources.

  The current raw catalog, directory, all selected group pages and complete raw
  sources must agree. This produces a coherent source snapshot, not a later-use
  authority seal. No projection value is returned before full group validation
  and the final catalog recheck. No mutation, inference or replay is performed.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.{Directory, Generation}

  def start(profile, args) do
    with true <- exact?(args, ~w(source_ids vector_selection fact_selection as_of_ms)),
         true <-
           is_list(args["source_ids"]) and length(args["source_ids"]) in 1..8 and
             length(Enum.uniq(args["source_ids"])) == length(args["source_ids"]) and
             Enum.all?(args["source_ids"], &(is_binary(&1) and byte_size(&1) in 1..512)),
         true <-
           E.safe_uint?(args["as_of_ms"]) and
             IpseKnowledge.Store.Collection.Projection.valid_selection?(args["vector_selection"]) and
             IpseKnowledge.Store.Collection.Projection.valid_extraction?(args["fact_selection"]) do
      s = %{
        profile: profile,
        args: args,
        reads: 0,
        values: %{},
        selected: [],
        pending: [],
        queue: [],
        keys: Enum.map(args["source_ids"], &E.sha256/1)
      }

      io(s, :value_read, %{"key" => "catalog." <> profile["partition"]}, :catalog)
    else
      _ -> error(:invalid_shared_selection)
    end
  rescue
    _ -> error(:invalid_shared_selection)
  end

  def resume(%{shared_selected: s, inner: inner}, outcome),
    do: advance(C.resume(inner, outcome), s)

  defp io(s, operation, args, phase),
    do: advance(C.start(s.profile, operation, args), Map.put(s, :phase, phase))

  defp advance({:call, request, inner}, s) do
    if C.read_request?(request) and s.reads < 512 do
      {:call, request, %{shared_selected: %{s | reads: s.reads + 1}, inner: inner}}
    else
      error(:shared_selection_read_budget)
    end
  end

  defp advance({:done, {:ok, value}}, s) do
    done(s, value)
  rescue
    _ -> error(:shared_selection_corrupt)
  end

  defp advance({:done, {:error, code, _}}, _), do: error(code)
  defp advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}

  defp done(%{phase: :catalog} = s, value) do
    row = value["record"]
    true = is_map(row) and C.valid_catalog?(row["value"], s.profile)

    io(
      Map.merge(s, %{catalog: row, native_generation: value["native_generation"]}),
      :value_read,
      %{"key" => "generation." <> s.profile["partition"]},
      :root
    )
  end

  defp done(%{phase: :root} = s, value) do
    true = value["native_generation"] === s.native_generation
    row = value["record"]
    true = is_map(row)
    root = row["value"]

    true =
      root["catalog_sha256"] === s.catalog["sha256"] and
        root["catalog_generation"] === s.catalog["value"]["generation"] and
        root["floor"] === s.catalog["value"]["floor"]

    true =
      root["vector_selection"] === s.args["vector_selection"] and
        root["fact_selection"] === s.args["fact_selection"]

    true = is_list(root["manifests"]) and length(root["manifests"]) in 1..8

    expected =
      Map.take(
        root,
        ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
      )
      |> Map.put("root_sha256", row["sha256"])

    true = Directory.valid_root?(root, expected)

    objects(
      Map.merge(s, %{
        root: root,
        expected: expected,
        queue: root["manifests"],
        after_objects: :manifest
      })
    )
  end

  defp done(%{phase: :object} = s, value) do
    true = value["native_generation"] === s.native_generation
    objects(%{s | values: Map.put(s.values, s.object_ref["key"], value["value"])})
  end

  defp done(%{phase: :sources} = s, value) do
    true =
      value["native_generation"] === s.native_generation and
        value["catalog_generation"] === s.root["catalog_generation"] and
        value["catalog_floor"] === s.root["floor"]

    header = s.group["header_value"]
    refs = header["source_pages"] ++ header["vector_pages"] ++ header["fact_pages"]
    true = length(refs) <= 384
    objects(Map.merge(s, %{bundles: value["bundles"], queue: refs, after_objects: :group}))
  end

  defp done(%{phase: :final} = s, value) do
    true =
      value["native_generation"] === s.native_generation and
        value["record"]["sha256"] === s.catalog["sha256"] and
        value["record"]["value"] === s.catalog["value"]

    true = length(s.selected) == length(s.keys)

    {:done,
     {:ok,
      %{
        "selected" => s.selected,
        "generation" => s.root["generation"],
        "catalog_sha256" => s.root["catalog_sha256"],
        "floor" => s.root["floor"],
        "coverage" => %{
          "cache_scope" => "selected_shared_snapshot",
          "selection_complete" => true,
          "namespace_complete" => false,
          "evidence_readable" => true,
          "later_use_authority" => false,
          "reads_used" => s.reads,
          "effects_used" => 0,
          "model_receipt_provenance" => false
        }
      }}}
  end

  defp objects(%{queue: [ref | tail]} = s) do
    args = Map.put(ref, "generation", s.native_generation)
    io(Map.merge(s, %{queue: tail, object_ref: ref}), :object_read, args, :object)
  end

  defp objects(%{queue: [], after_objects: :manifest} = s) do
    # Following at most eight candidate headers is only a bounded read. Directory
    # lookup authenticates the full chain before any payload hydration or output.
    rows = Enum.flat_map(s.root["manifests"], &Map.fetch!(s.values, &1["key"])["rows"])

    refs =
      Enum.filter(rows, fn row -> Enum.any?(row["sources"], fn [key, _] -> key in s.keys end) end)
      |> Enum.map(& &1["header"])

    true = length(refs) <= length(s.keys)
    objects(%{s | queue: refs, after_objects: :headers})
  end

  defp objects(%{queue: [], after_objects: :headers} = s) do
    {:ok, lookup} = Directory.lookup(s.root, s.values, s.keys, s.expected)
    true = lookup["missing_source_keys"] == []
    next_group(%{s | pending: lookup["groups"]})
  end

  defp objects(%{queue: [], after_objects: :group} = s) do
    header = s.group["header_value"]

    {:ok, data} =
      Generation.unpack_group(s.profile["partition"], header, s.values, s.bundles, %{
        "cursor" => header["cursor"],
        "vector_selection" => s.args["vector_selection"],
        "fact_selection" => s.args["fact_selection"]
      })

    selected =
      Enum.zip(s.bundles, data)
      |> Enum.filter(fn {b, _} -> b["source"]["source_key"] in s.keys end)
      |> Enum.map(fn {bundle, projections} ->
        true = E.current?(bundle["source"], s.args["as_of_ms"])

        %{
          "source" => bundle["source"],
          "vectors" => projections["vectors"],
          "facts" => projections["facts"]
        }
      end)

    # Group payloads can be dropped once fully validated; immutable directory
    # pages/header bindings alone remain for the next bounded group.
    keep =
      Enum.map(s.root["manifests"], & &1["key"]) ++ Enum.map(s.pending, & &1["header"]["key"])

    next_group(%{s | selected: s.selected ++ selected, values: Map.take(s.values, keep)})
  end

  defp next_group(%{pending: [group | tail]} = s) do
    io(
      Map.merge(s, %{pending: tail, group: group}),
      :source_bundles,
      %{
        "source_keys" => group["header_value"]["source_keys"],
        "as_of_ms" => s.args["as_of_ms"]
      },
      :sources
    )
  end

  defp next_group(%{pending: []} = s),
    do: io(s, :value_read, %{"key" => "catalog." <> s.profile["partition"]}, :final)

  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp error(code), do: {:done, {:error, code, %{}}}
end
