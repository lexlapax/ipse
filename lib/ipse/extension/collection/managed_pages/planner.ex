defmodule Ipse.Extension.Collection.ManagedPages.Planner do
  @moduledoc """
  Bounded local repair using the actual held Collection read closure.

  No directory array, path, worker callback or imported metadata is accepted.
  The caller supplies current semantic edits and the checked Core read closure;
  shaped observations do not independently attest that provenance. Every old
  selected/buddy page is authenticated, range checked and checked against its
  immutable profile minimum before a repair is prepared. Signing is a separate
  step after the caller's semantic and operator-authority checks.
  """
  alias Ipse.Extension.Collection.ManagedPages, as: Pages
  @error {:error, :managed_pages_plan_refused}

  @doc "Prepare at most two edits; closure reads retain their existing 32-unit owner budget."
  def plan(cap, kind, edits, read) when is_function(read, 1) do
    checked(fn ->
      edits = edits!(kind, edits)

      observations =
        Enum.map(edits, fn {id, _} ->
          request = %{
            "version" => 1,
            "prefix" => Pages.prefix(kind),
            "fence_bytes" => Pages.width(kind),
            "needle" => id
          }

          {:ok, observation} = read.(%{"op" => "neighbors", "request" => request})
          {:ok, facts} = Pages.observation(observation)
          true = facts.kind == kind
          observation
        end)

      first = hd(observations)
      true = Enum.all?(observations, &same_root?(&1, first))

      case first["state"] do
        "uninitialized" -> initialize!(kind, edits, first)
        "initialized" -> repair!(cap, kind, edits, observations, read)
      end
    end)
  end

  def plan(_, _, _, _), do: @error

  @doc "Seal against the same actual callback witness; revision comes from old global generation+1."
  def seal_changes(cap, witness, plan) do
    checked(fn ->
      true = is_map(plan) and plan.kind in [:anchor, :live]
      true = witness["root"] == plan.summary
      true = witness["root_state"] == plan.witness["root_state"]
      true = witness["root_sha256"] == plan.witness["root_sha256"]
      true = witness["manifest_sha256"] == plan.witness["manifest_sha256"]
      true = length(plan.changes) <= 3 * plan.edit_count

      Enum.map(plan.changes, fn change ->
        value =
          if is_nil(change.body) do
            true = change.expected_revision > 0
            nil
          else
            {:ok, value} = Pages.seal(cap, witness, change.key, change.body)
            value
          end

        %{"key" => change.key, "expected_revision" => change.expected_revision, "value" => value}
      end)
    end)
  end

  defp initialize!(kind, edits, o) do
    true = o["witness"]["root_state"] == "absent" and o["state"] == "uninitialized"
    true = Enum.all?(edits, fn {_, row} -> not is_nil(row) end)
    rows = Map.new(edits)
    {:ok, body} = Pages.pack(kind, Pages.zero(kind), rows)

    %{
      kind: kind,
      summary: o["summary"],
      witness: o["witness"],
      edit_count: length(edits),
      old_pages: 0,
      changes: [%{key: Pages.page_key(kind, Pages.zero(kind)), expected_revision: 0, body: body}]
    }
  end

  defp repair!(cap, kind, edits, observations, read) do
    selected = observations |> Enum.map(& &1["neighbors"]["selected"]["key"]) |> Enum.uniq()

    context =
      Enum.reduce(observations, %{}, fn o, acc ->
        Enum.reduce(~w(predecessor selected successor), acc, fn slot, acc ->
          if o["neighbors"][slot] do
            {:ok, range} = Pages.range(o, slot)
            node = %{observation: o, slot: slot, range: range}

            case acc[range.ref["key"]] do
              nil ->
                Map.put(acc, range.ref["key"], node)

              old ->
                true = old.range == range
                acc
            end
          else
            acc
          end
        end)
      end)

    pages = Enum.reduce(selected, %{}, &fetch!(&2, &1, context, cap, read))
    p = Pages.profile(kind)

    groups =
      Enum.map(selected, fn key ->
        node = context[key]
        next = apply_edits!(pages[key].entries, edits, node.range)

        if Pages.weight(kind, next) < p.floor and not node.range.single do
          slots = node.observation["neighbors"]
          buddy = slots["predecessor"] || slots["successor"]
          true = is_map(buddy)
          Enum.sort([key, buddy["key"]])
        else
          [key]
        end
      end)
      |> components()

    needed = groups |> List.flatten() |> Enum.uniq()
    true = length(needed) <= 4
    pages = Enum.reduce(needed, pages, &fetch!(&2, &1, context, cap, read))

    changes =
      Enum.flat_map(groups, fn keys ->
        keys = Enum.sort(keys)
        nodes = Enum.map(keys, &context[&1])

        Enum.chunk_every(nodes, 2, 1, :discard)
        |> Enum.each(fn [a, b] ->
          true = a.range.upper == b.range.fence
        end)

        lower = hd(nodes).range.fence
        upper = List.last(nodes).range.upper
        whole = lower == Pages.zero(kind) and is_nil(upper)

        rows =
          Enum.reduce(keys, %{}, fn key, rows ->
            next = pages[key].entries
            true = MapSet.disjoint?(MapSet.new(Map.keys(rows)), MapSet.new(Map.keys(next)))
            Map.merge(rows, next)
          end)

        range = %{fence: lower, upper: upper}
        rows = apply_edits!(rows, edits, range)
        true = map_size(rows) <= 514
        pieces = partition(kind, Enum.sort(rows))
        true = whole or Enum.all?(pieces, &(weight(kind, &1) >= p.floor))

        proposed =
          Enum.with_index(pieces)
          |> Map.new(fn {rows, i} ->
            fence = if i == 0, do: lower, else: elem(hd(rows), 0)
            {:ok, body} = Pages.pack(kind, fence, Map.new(rows))
            {Pages.page_key(kind, fence), body}
          end)

        old = Map.take(pages, keys)

        (Map.keys(old) ++ Map.keys(proposed))
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.flat_map(fn key ->
          previous = old[key]
          body = proposed[key]

          if previous && previous.body == body do
            []
          else
            # New fences are strictly interior to the checked old component range.
            # Its actual consecutive directory refs plus global CAS prove absence.
            if is_nil(previous) do
              {:ok, decoded} =
                Pages.unpack(
                  kind,
                  String.replace_prefix(key, Pages.prefix(kind), ""),
                  body,
                  upper
                )

              true = map_size(decoded.entries) > 0
              true = key > hd(keys) and (is_nil(upper) or key < Pages.page_key(kind, upper))
            end

            [
              %{
                key: key,
                expected_revision: if(previous, do: previous.ref["revision"], else: 0),
                body: body
              }
            ]
          end
        end)
      end)

    true = length(changes) <= 3 * length(edits)
    true = length(Enum.uniq_by(changes, & &1.key)) == length(changes)

    %{
      kind: kind,
      summary: hd(observations)["summary"],
      witness: hd(observations)["witness"],
      edit_count: length(edits),
      old_pages: length(needed),
      changes: changes
    }
  end

  defp fetch!(cache, key, context, cap, read) do
    if Map.has_key?(cache, key) do
      cache
    else
      node = Map.fetch!(context, key)
      {:ok, record} = read.(key)
      {:ok, page} = Pages.open(cap, record, node.observation, node.slot)
      Map.put(cache, key, Map.put(page, :ref, node.range.ref))
    end
  end

  defp edits!(kind, edits) do
    true = kind in [:anchor, :live] and is_list(edits) and length(edits) in 1..2
    true = length(Enum.uniq_by(edits, &elem(&1, 0))) == length(edits)

    Enum.each(edits, fn {id, row} ->
      true = is_binary(id) and byte_size(id) == Pages.width(kind) * 2

      if is_nil(row) do
        raw = Base.decode16!(id, case: :lower)
        true = Base.encode16(raw, case: :lower) == id
        if kind == :live, do: Pages.live_key(id)
      else
        Pages.row_weight(kind, id, row)
      end
    end)

    edits
  end

  defp apply_edits!(rows, edits, range) do
    Enum.reduce(edits, rows, fn {id, row}, acc ->
      if id >= range.fence and (is_nil(range.upper) or id < range.upper) do
        if is_nil(row) do
          true = Map.has_key?(acc, id)
          Map.delete(acc, id)
        else
          Map.put(acc, id, row)
        end
      else
        acc
      end
    end)
  end

  defp components(groups) do
    Enum.reduce(Enum.sort(groups), [], fn group, acc ->
      {overlap, disjoint} =
        Enum.split_with(acc, fn other ->
          not MapSet.disjoint?(MapSet.new(other), MapSet.new(group))
        end)

      [Enum.sort(Enum.uniq(group ++ List.flatten(overlap))) | disjoint]
    end)
    |> Enum.sort()
  end

  defp partition(_kind, []), do: [[]]

  defp partition(kind, rows) do
    p = Pages.profile(kind)
    total = weight(kind, rows)

    if total <= p.capacity do
      [rows]
    else
      sums =
        Enum.map_reduce(rows, 0, fn {id, row}, n ->
          n = n + Pages.row_weight(kind, id, row)
          {n, n}
        end)
        |> elem(0)

      split =
        sums
        |> Enum.drop(-1)
        |> Enum.with_index(1)
        |> Enum.min_by(fn {n, i} -> {abs(total - 2 * n), i} end)
        |> elem(1)

      {a, b} = Enum.split(rows, split)
      true = weight(kind, a) >= p.floor and weight(kind, b) >= p.floor
      partition(kind, a) ++ partition(kind, b)
    end
  end

  defp weight(kind, rows), do: Pages.weight(kind, Map.new(rows))

  defp same_root?(a, b),
    do: a["summary"] == b["summary"] and a["witness"] == b["witness"] and a["state"] == b["state"]

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> @error
  end
end
