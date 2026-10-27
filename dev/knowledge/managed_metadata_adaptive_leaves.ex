defmodule Ipse.Development.ManagedMetadata.AdaptiveLeaves do
  @moduledoc "Pure local leaf plans over supplied refs; no IO, authenticity, storage or domain policy."
  alias Ipse.Development.ManagedMetadata.{Adaptive, Codec}

  def profile(:anchor_native_candidate) do
    geometry(%{
      kind: :anchor_native_candidate,
      catalog: nil,
      header: 7,
      minimum: 37,
      maximum: 337
    })
  end

  def profile(:live, :per_row) do
    geometry(%{kind: :live, catalog: :per_row, header: 9, minimum: 170, maximum: 183})
  end

  def profile(:live, catalog) when is_list(catalog) do
    true = length(catalog) in 1..256 and catalog == Enum.sort(Enum.uniq(catalog))
    Enum.each(catalog, &Codec.unpacked_hash/1)
    index_bytes = if length(catalog) <= 128, do: 2, else: 4

    header =
      7 + byte_size(Ipse.Development.ManagedMetadata.Binary.uint(length(catalog))) +
        32 * length(catalog)

    geometry(%{
      kind: :live,
      catalog: catalog,
      header: header,
      minimum: 102 + index_bytes,
      maximum: 115 + index_bytes
    })
  end

  def geometry(p) do
    capacity = Enum.find(4608..0//-1, fn n -> 75 + div((n + p.header) * 8 + 5, 6) <= 6144 end)
    floor = div(capacity + 1 - p.maximum, 2)
    true = capacity >= 5 * p.maximum and floor >= 2 * p.maximum
    true = 128 * p.minimum > capacity
    Map.merge(p, %{capacity: capacity, floor: floor, row_cap: 128})
  end

  def prefix(:live), do: "proof.l."
  def prefix(:anchor_native_candidate), do: "proof.a."
  def key(kind, fence), do: prefix(kind) <> fence

  def weight(profile, id, row) do
    n = Adaptive.width(profile.kind) + 1 + Adaptive.row_bytes(profile.kind, id, row)

    n =
      if profile.kind == :live do
        if profile.catalog == :per_row do
          n + 4
        else
          true = Enum.all?([Enum.at(row, 2), Enum.at(row, 3)], &(&1 in profile.catalog))
          n - 64 + if(length(profile.catalog) <= 128, do: 2, else: 4)
        end
      else
        n
      end

    true = n in profile.minimum..profile.maximum
    n
  end

  def initialize(profile, rows) do
    checked(fn ->
      true = is_map(rows) and map_size(rows) <= 32768
      pieces = partition(profile, Enum.sort(rows))
      pages = emit(profile, Adaptive.zero(profile.kind), pieces)
      validate_tree!(profile, pages)
      pages
    end)
  end

  def directory(profile, refs) do
    true = is_list(refs) and length(refs) in 1..8192

    pairs =
      Enum.map(refs, fn ref ->
        true =
          Codec.keys?(ref, ~w(key revision)) and Codec.uint?(ref["revision"]) and
            ref["revision"] > 0

        true = is_binary(ref["key"]) and String.starts_with?(ref["key"], prefix(profile.kind))
        fence = String.replace_prefix(ref["key"], prefix(profile.kind), "")
        true = valid_id?(profile.kind, fence)
        {fence, ref}
      end)

    true =
      pairs == Enum.sort(pairs) and length(Enum.uniq_by(pairs, &elem(&1, 0))) == length(pairs)

    true = elem(hd(pairs), 0) == Adaptive.zero(profile.kind)
    pairs
  end

  def refs(profile, pages) do
    pages |> Enum.map(fn {fence, _} -> %{"key" => key(profile.kind, fence), "revision" => 1} end)
  end

  def required(profile, refs, selected, edits) do
    checked(fn ->
      pairs = directory(profile, refs)
      edits = edits!(profile, edits)
      groups = groups(profile, pairs, selected, edits)

      groups
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&elem(Enum.at(pairs, &1), 1)["key"])
    end)
  end

  def plan(profile, refs, selected, edits) do
    checked(fn ->
      pairs = directory(profile, refs)
      edits = edits!(profile, edits)
      groups = groups(profile, pairs, selected, edits)
      indices = groups |> List.flatten() |> Enum.uniq() |> Enum.sort()
      required = Enum.map(indices, &elem(Enum.at(pairs, &1), 1)["key"])
      true = Enum.sort(Map.keys(selected)) == Enum.sort(required)
      decoded = Map.new(indices, fn i -> {i, decode!(profile, pairs, i, selected)} end)

      changes =
        Enum.flat_map(groups, fn indices ->
          lower = elem(Enum.at(pairs, hd(indices)), 0)

          upper =
            case Enum.at(pairs, List.last(indices) + 1) do
              nil -> nil
              {f, _} -> f
            end

          original =
            Enum.reduce(indices, %{}, fn i, acc ->
              row = decoded[i]
              true = MapSet.disjoint?(MapSet.new(Map.keys(acc)), MapSet.new(Map.keys(row)))
              Map.merge(acc, row)
            end)

          rows =
            Enum.reduce(edits, original, fn {id, row}, acc ->
              if id >= lower and (is_nil(upper) or id < upper) do
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

          pieces = partition(profile, Enum.sort(rows))
          proposed = emit(profile, lower, pieces)

          true =
            length(pairs) == length(indices) or
              Enum.all?(pieces, &(sum(profile, &1) >= profile.floor))

          old =
            Map.new(indices, fn i -> {elem(Enum.at(pairs, i), 0), elem(Enum.at(pairs, i), 1)} end)

          new = Map.new(proposed)

          Enum.sort(Enum.uniq(Map.keys(old) ++ Map.keys(new)))
          |> Enum.flat_map(fn fence ->
            old_ref = old[fence]
            value = new[fence]
            old_value = if old_ref, do: selected[old_ref["key"]], else: nil

            if value == old_value do
              []
            else
              [
                %{
                  "key" => key(profile.kind, fence),
                  "expected_revision" => if(old_ref, do: old_ref["revision"], else: 0),
                  "value" => value
                }
              ]
            end
          end)
        end)

      true = length(changes) <= 3 * length(edits)

      %{
        changes: changes,
        read_keys: required,
        old_pages: length(indices),
        directory_refs: min(4 * length(edits), length(refs)),
        edit_count: length(edits)
      }
    end)
  end

  def apply_plan(profile, pages, plan) do
    current = Map.new(pages)

    next =
      Enum.reduce(plan.changes, current, fn c, acc ->
        fence = String.replace_prefix(c["key"], prefix(profile.kind), "")
        if is_nil(c["value"]), do: Map.delete(acc, fence), else: Map.put(acc, fence, c["value"])
      end)
      |> Enum.sort()

    validate_tree!(profile, next)
    next
  end

  def validate_tree!(profile, pages) do
    refs = refs(profile, pages)
    pairs = directory(profile, refs)
    values = Map.new(pages, fn {f, v} -> {key(profile.kind, f), v} end)

    Enum.with_index(pairs)
    |> Enum.reduce(%{}, fn {_, i}, acc ->
      rows = decode!(profile, pairs, i, values)
      true = length(pairs) == 1 or sum(profile, Enum.sort(rows)) >= profile.floor
      true = MapSet.disjoint?(MapSet.new(Map.keys(acc)), MapSet.new(Map.keys(rows)))
      Map.merge(acc, rows)
    end)
  end

  defp groups(profile, pairs, selected, edits) do
    located = Enum.map(edits, fn {id, _} -> locate(pairs, id) end) |> Enum.uniq()

    groups =
      Enum.map(located, fn i ->
        rows = decode!(profile, pairs, i, selected)
        lower = elem(Enum.at(pairs, i), 0)

        upper =
          case Enum.at(pairs, i + 1) do
            nil -> nil
            {f, _} -> f
          end

        edited =
          Enum.reduce(edits, rows, fn {id, row}, acc ->
            if id >= lower and (is_nil(upper) or id < upper) do
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

        if sum(profile, Enum.sort(edited)) < profile.floor and length(pairs) > 1 do
          buddy = if i == 0, do: 1, else: i - 1
          Enum.sort([i, buddy])
        else
          [i]
        end
      end)

    # Adjacent disjoint repairs retain their original boundary; only overlap joins.
    Enum.reduce(Enum.sort(groups), [], fn group, acc ->
      {overlap, separate} =
        Enum.split_with(acc, fn other ->
          not MapSet.disjoint?(MapSet.new(other), MapSet.new(group))
        end)

      [Enum.sort(Enum.uniq(group ++ List.flatten(overlap))) | separate]
    end)
    |> Enum.sort()
  end

  defp decode!(profile, pairs, i, values) do
    {lower, ref} = Enum.fetch!(pairs, i)

    upper =
      case Enum.at(pairs, i + 1) do
        nil -> nil
        {f, _} -> f
      end

    {:ok, %{entries: rows}} =
      Adaptive.decode_page(profile.kind, lower, Map.fetch!(values, ref["key"]), upper)

    true = map_size(rows) <= 128
    true = sum(profile, Enum.sort(rows)) <= profile.capacity
    rows
  end

  defp edits!(profile, edits) do
    true = is_list(edits) and length(edits) in 1..2
    true = length(Enum.uniq_by(edits, &elem(&1, 0))) == length(edits)

    Enum.each(edits, fn {id, row} ->
      true = valid_id?(profile.kind, id)
      if not is_nil(row), do: weight(profile, id, row)
    end)

    edits
  end

  defp locate(pairs, id),
    do:
      Enum.find_index(Enum.reverse(pairs), fn {f, _} -> f <= id end)
      |> then(&(length(pairs) - 1 - &1))

  defp partition(_profile, []), do: [[]]

  defp partition(profile, rows) do
    total = sum(profile, rows)

    if total <= profile.capacity do
      [rows]
    else
      weights = Enum.map(rows, fn {id, row} -> weight(profile, id, row) end)

      {_sum, bounds} =
        Enum.map_reduce(weights, 0, fn n, acc -> {acc + n, acc + n} end)
        |> then(fn {sums, last} -> {last, sums} end)

      split =
        bounds
        |> Enum.drop(-1)
        |> Enum.with_index(1)
        |> Enum.min_by(fn {n, i} -> {abs(total - 2 * n), i} end)
        |> elem(1)

      {left, right} = Enum.split(rows, split)
      true = sum(profile, left) >= profile.floor and sum(profile, right) >= profile.floor
      partition(profile, left) ++ partition(profile, right)
    end
  end

  defp emit(profile, lower, pieces) do
    Enum.with_index(pieces)
    |> Enum.map(fn {rows, index} ->
      fence = if index == 0, do: lower, else: elem(hd(rows), 0)
      {:ok, value} = Adaptive.encode_page(profile.kind, fence, Map.new(rows))
      {fence, value}
    end)
  end

  defp sum(profile, rows),
    do: Enum.sum(Enum.map(rows, fn {id, row} -> weight(profile, id, row) end))

  defp valid_id?(kind, id) do
    try do
      true = is_binary(id) and byte_size(id) == Adaptive.width(kind) * 2
      _ = Base.decode16!(id, case: :lower)
      if kind == :live, do: Codec.live_key(id)
      true
    rescue
      _ -> false
    end
  end

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_adaptive_plan}
  end
end
