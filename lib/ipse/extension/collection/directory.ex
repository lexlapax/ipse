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

  def read_request?(%{"op" => "get_many", "keys" => keys} = request),
    do:
      exact?(request, ~w(op keys)) and is_list(keys) and length(keys) in 1..8 and
        Enum.all?(keys, &key?/1) and length(Enum.uniq(keys)) == length(keys)

  def read_request?(%{"op" => "scan", "after" => cursor, "limit" => limit} = request),
    do:
      exact?(request, ~w(op after limit)) and (is_nil(cursor) or key?(cursor)) and
        is_integer(limit) and limit in 1..8

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

  def cost(%{"op" => "get_many", "keys" => keys} = request),
    do: if(read_request?(request), do: {:ok, length(keys)}, else: :error)

  def cost(%{"op" => "scan", "limit" => limit} = request),
    do: if(read_request?(request), do: {:ok, limit}, else: :error)

  def cost(%{"op" => "neighbors", "request" => selected} = request),
    do:
      if(exact?(request, ~w(op request)) and neighbor_request?(selected),
        do: {:ok, 4},
        else: :error
      )

  def cost(_), do: :error

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
