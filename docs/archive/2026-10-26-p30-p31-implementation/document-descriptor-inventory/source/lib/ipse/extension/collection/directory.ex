defmodule Ipse.Extension.Collection.Directory do
  @moduledoc false
  # This is an index of validated metadata keys, never a source of eligibility.
  # Use OTP's opaque ordered tree API; no persisted second index is introduced.
  @records 8192
  @slots ~w(predecessor selected successor second_successor)

  def index(keys) when is_list(keys) do
    if length(keys) <= @records and keys === Enum.sort(Enum.uniq(keys)) and
         Enum.all?(keys, &key?/1) do
      {:ok, :gb_trees.from_orddict(Enum.map(keys, &{&1, true}))}
    else
      {:error, :collection_directory_invalid}
    end
  end

  def index(_), do: {:error, :collection_directory_invalid}
  def keys(index), do: :gb_trees.keys(index)

  def key?(key),
    do: is_binary(key) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, key)

  def document_index_request?(r) do
    exact?(r, ~w(op generation after limit)) and r["op"] == "value.index" and
      Ipse.JSON.safe_uint?(r["generation"]) and is_integer(r["limit"]) and r["limit"] in 1..16 and
      (is_nil(r["after"]) or (key?(r["after"]) and not String.starts_with?(r["after"], "host.")))
  end

  @doc "Select complete public document descriptors from validated metadata, without value IO."
  def document_index(records, summary, request) do
    with true <- document_index_request?(request),
         true <- request["generation"] === summary["generation"],
         public =
           records |> Map.keys() |> Enum.reject(&String.starts_with?(&1, "host.")) |> Enum.sort(),
         {:ok, tree} <- index(public) do
      iterator =
        if is_nil(request["after"]),
          do: :gb_trees.iterator(tree),
          else: :gb_trees.iterator_from(request["after"], tree)

      found = take(iterator, request["limit"] + 1, request["after"])
      selected = Enum.take(found, request["limit"])
      following = length(found) > length(selected)

      page = fn keys ->
        more = length(keys) < length(selected) or following

        Map.merge(summary, %{
          "records" =>
            Enum.map(keys, fn key ->
              record = Map.fetch!(records, key)

              %{
                "key" => key,
                "revision" => record["revision"],
                "record_sha256" => record["sha256"],
                "record_bytes" => record["bytes"]
              }
            end),
          "next" => if(more and keys != [], do: List.last(keys)),
          "count" => length(public),
          "coverage" => "public_document_records"
        })
      end

      kept =
        Enum.reduce_while(selected, [], fn key, keys ->
          if byte_size(Jason.encode!(page.(keys ++ [key]))) <= 4096,
            do: {:cont, keys ++ [key]},
            else: {:halt, keys}
        end)

      if (kept != [] or selected == []) and byte_size(Jason.encode!(page.(kept))) <= 4096,
        do: {:ok, page.(kept)},
        else: {:error, :collection_directory_invalid}
    else
      _ -> {:error, :collection_directory_invalid}
    end
  end

  def read_request?(%{"op" => "snapshot"} = request), do: exact?(request, ~w(op))

  def read_request?(%{"op" => "get_many", "keys" => keys} = request),
    do:
      exact?(request, ~w(op keys)) and is_list(keys) and length(keys) in 1..8 and
        Enum.all?(keys, &key?/1) and length(Enum.uniq(keys)) == length(keys)

  def read_request?(%{"op" => "scan", "after" => cursor, "limit" => limit} = request),
    do:
      exact?(request, ~w(op after limit)) and (is_nil(cursor) or key?(cursor)) and
        is_integer(limit) and limit in 1..8

  def read_request?(
        %{"op" => "visible_scan", "after" => cursor, "limit" => limit, "generation" => generation} =
          request
      ),
      do:
        exact?(request, ~w(op after limit generation)) and Ipse.JSON.safe_uint?(generation) and
          (is_nil(cursor) or (key?(cursor) and not String.starts_with?(cursor, "host.validity."))) and
          is_integer(limit) and limit in 1..4

  def read_request?(
        %{
          "op" => "visible_index",
          "after" => cursor,
          "limit" => limit,
          "generation" => generation,
          "prefix" => prefix
        } = request
      ),
      do:
        exact?(request, ~w(op after limit generation prefix)) and
          (is_nil(generation) or Ipse.JSON.safe_uint?(generation)) and is_integer(limit) and
          limit in 1..32 and
          key?(prefix) and not String.starts_with?(prefix, "host.validity.") and
          (is_nil(cursor) or (key?(cursor) and String.starts_with?(cursor, prefix)))

  def read_request?(_), do: false

  def neighbor_request?(
        %{"version" => 1, "prefix" => prefix, "fence_bytes" => width, "needle" => needle} =
          request
      ) do
    exact?(request, ~w(version prefix fence_bytes needle)) and request["version"] === 1 and
      is_integer(width) and width in [32, 33] and is_binary(prefix) and
      byte_size(prefix) in 2..(96 - width * 2) and
      Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\.\z/, prefix) and
      hex?(needle, width)
  end

  def neighbor_request?(_), do: false

  # The eventual publication closure can use the same costs with its own
  # 32-unit owner-bound budget. This module never grants or renews that budget.
  def cost(key) when is_binary(key), do: if(key?(key), do: {:ok, 1}, else: :error)

  def cost(%{"op" => "snapshot"} = request),
    do: if(read_request?(request), do: {:ok, 1}, else: :error)

  def cost(%{"op" => "get_many", "keys" => keys} = request),
    do: if(read_request?(request), do: {:ok, length(keys)}, else: :error)

  def cost(%{"op" => "scan", "limit" => limit} = request),
    do: if(read_request?(request), do: {:ok, limit}, else: :error)

  def cost(%{"op" => "visible_scan", "limit" => limit} = request),
    do: if(read_request?(request), do: {:ok, limit}, else: :error)

  def cost(%{"op" => "visible_index", "limit" => limit} = request),
    do: if(read_request?(request), do: {:ok, limit}, else: :error)

  def cost(%{"op" => "neighbors", "request" => selected} = request),
    do:
      if(exact?(request, ~w(op request)) and neighbor_request?(selected),
        do: {:ok, 4},
        else: :error
      )

  # At most 64 already-loaded public record references; no value objects are
  # read. Eight units account for the bounded metadata walk separately from
  # individual object reads.
  def cost(%{"op" => "pending_summary"} = request),
    do: if(exact?(request, ["op"]), do: {:ok, 8}, else: :error)

  def cost(_), do: :error

  def pending_keys(index), do: take_prefix(:gb_trees.iterator_from("pending.", index), 64, [])

  defp take_prefix(_, 0, acc), do: Enum.reverse(acc)

  defp take_prefix(iterator, remaining, acc) do
    case :gb_trees.next(iterator) do
      {"pending." <> _ = key, _, next} -> take_prefix(next, remaining - 1, [key | acc])
      _ -> Enum.reverse(acc)
    end
  end

  def select(_index, %{"op" => "snapshot"} = request, _root),
    do:
      if(read_request?(request),
        do: {:ok, [], nil, nil},
        else: {:error, :collection_directory_invalid}
      )

  def select(_index, %{"op" => "get_many", "keys" => keys}, _root),
    do: {:ok, keys, nil, nil}

  def select(index, %{"op" => "scan", "after" => cursor, "limit" => limit}, _root) do
    iterator =
      if is_nil(cursor),
        do: :gb_trees.iterator(index),
        else: :gb_trees.iterator_from(cursor, index)

    keys = take(iterator, limit + 1, cursor)
    selected = Enum.take(keys, limit)
    {:ok, selected, if(length(keys) > limit, do: List.last(selected)), nil}
  end

  def select(index, %{"op" => "visible_scan", "after" => cursor, "limit" => limit}, _root) do
    iterator =
      if is_nil(cursor),
        do: :gb_trees.iterator(index),
        else: :gb_trees.iterator_from(cursor, index)

    keys = take_visible(iterator, limit + 1, cursor)
    selected = Enum.take(keys, limit)
    {:ok, selected, if(length(keys) > limit, do: List.last(selected)), nil}
  end

  def select(
        index,
        %{"op" => "visible_index", "after" => cursor, "limit" => limit, "prefix" => prefix},
        _
      ) do
    keys =
      matching(index, prefix)
      |> Enum.reject(&String.starts_with?(&1, "host.validity."))
      |> Enum.filter(&(is_nil(cursor) or &1 > cursor))

    selected = Enum.take(keys, limit)
    {:ok, selected, if(length(keys) > limit, do: List.last(selected)), nil}
  end

  def select(index, %{"op" => "neighbors", "request" => request}, root_state) do
    with true <- neighbor_request?(request),
         {:ok, neighbors} <- neighbors(index, request, root_state) do
      selected = @slots |> Enum.map(&neighbors[&1]) |> Enum.reject(&is_nil/1)
      {:ok, selected, nil, neighbors}
    else
      _ -> {:error, :collection_directory_invalid}
    end
  end

  def select(_, _, _), do: {:error, :collection_directory_invalid}

  def matching(index, prefix) do
    matching_from(:gb_trees.iterator_from(prefix, index), prefix, [])
  end

  defp neighbors(index, _request, "absent") do
    if :gb_trees.is_empty(index),
      do: {:ok, Map.new(@slots, &{&1, nil}) |> Map.put("state", "uninitialized")},
      else: {:error, :collection_directory_invalid}
  end

  defp neighbors(
         index,
         %{"prefix" => prefix, "fence_bytes" => width, "needle" => needle},
         "present"
       ) do
    keys = matching(index, prefix)
    zero = prefix <> String.duplicate("0", width * 2)

    with true <- List.first(keys) === zero,
         true <- Enum.all?(keys, &suffix?(&1, prefix, width)),
         {selected, _, reverse} <-
           :gb_trees.next(:gb_trees.iterator_from(prefix <> needle, index, :reversed)),
         true <- String.starts_with?(selected, prefix),
         {^selected, _, forward} <- :gb_trees.next(:gb_trees.iterator_from(selected, index)),
         {predecessor, _} <- step(reverse, prefix),
         {successor, tail} <- step(forward, prefix),
         {second, _} <- step(tail, prefix) do
      {:ok,
       %{
         "state" => "initialized",
         "predecessor" => predecessor,
         "selected" => selected,
         "successor" => successor,
         "second_successor" => second
       }}
    else
      _ -> {:error, :collection_directory_invalid}
    end
  end

  defp neighbors(_, _, _), do: {:error, :collection_directory_invalid}

  defp step(:none, _), do: {nil, :none}

  defp step(iterator, prefix) do
    case :gb_trees.next(iterator) do
      {key, _, next} -> if String.starts_with?(key, prefix), do: {key, next}, else: {nil, :none}
      :none -> {nil, :none}
    end
  end

  defp matching_from(iterator, prefix, acc) do
    case :gb_trees.next(iterator) do
      {key, _, next} ->
        if String.starts_with?(key, prefix),
          do: matching_from(next, prefix, [key | acc]),
          else: Enum.reverse(acc)

      :none ->
        Enum.reverse(acc)
    end
  end

  defp take_visible(_, 0, _), do: []

  defp take_visible(iterator, count, cursor) do
    case :gb_trees.next(iterator) do
      {key, _, next} ->
        if key === cursor or String.starts_with?(key, "host.validity."),
          do: take_visible(next, count, cursor),
          else: [key | take_visible(next, count - 1, cursor)]

      :none ->
        []
    end
  end

  defp take(_, 0, _), do: []

  defp take(iterator, count, cursor) do
    case :gb_trees.next(iterator) do
      {key, _, next} when key === cursor -> take(next, count, cursor)
      {key, _, next} -> [key | take(next, count - 1, cursor)]
      :none -> []
    end
  end

  defp suffix?(key, prefix, width) do
    size = byte_size(prefix)

    String.starts_with?(key, prefix) and
      hex?(binary_part(key, size, byte_size(key) - size), width)
  end

  defp hex?(value, bytes),
    do:
      is_binary(value) and byte_size(value) === bytes * 2 and
        Regex.match?(~r/\A[0-9a-f]+\z/, value)

  defp exact?(map, expected), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(expected)
end
