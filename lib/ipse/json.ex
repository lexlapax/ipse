defmodule Ipse.JSON do
  @moduledoc false

  # Callers bound the encoded input before invoking the maintained JSON parser.
  # Ordered objects preserve duplicate decoded keys until we can reject them.
  def decode_unique(bytes, max_depth \\ 16)

  def decode_unique(bytes, max_depth)
      when is_binary(bytes) and is_integer(max_depth) and max_depth in 0..16 do
    with {:ok, ordered} <- Jason.decode(bytes, objects: :ordered_objects),
         {:ok, value} <- unique_object(ordered, 0, max_depth) do
      {:ok, value}
    end
  rescue
    _ -> {:error, :invalid_json}
  end

  def decode_unique(_, _), do: {:error, :invalid_json}

  defp unique_object(_value, depth, max_depth) when depth > max_depth,
    do: {:error, :invalid_json}

  defp unique_object(%Jason.OrderedObject{values: pairs}, depth, max_depth) do
    if length(pairs) == map_size(Map.new(pairs)) do
      Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, map} ->
        case unique_object(value, depth + 1, max_depth) do
          {:ok, decoded} -> {:cont, {:ok, Map.put(map, key, decoded)}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :duplicate_key}
    end
  end

  defp unique_object(list, depth, max_depth) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case unique_object(value, depth + 1, max_depth) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp unique_object(value, _depth, _max_depth), do: {:ok, value}
end
