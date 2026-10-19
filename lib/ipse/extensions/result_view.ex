defmodule Ipse.Extensions.ResultView do
  @moduledoc "Pure, bounded structured views of an already validated saved result."

  @limit 12_000
  @error {:error, :invalid_saved_result_read}
  @cursor_keys ~w(output_id source_sha256 path kind offset)
  @descriptor_keys ~w(version kind output_id byte_count sha256 historical_receipt)

  @doc "Read one view. Session must authorize the committed descriptor before calling."
  def read(value, descriptor, request) do
    with true <- is_map(value),
         true <- descriptor?(descriptor),
         :ok <- Ipse.Extension.validate(request),
         {:ok, path, kind, offset} <- target(value, descriptor, request),
         {:ok, item, name} <- resolve(value, path),
         {:ok, response} <- view(item, name, descriptor, path, kind, offset),
         true <- bounded?(response) do
      {:ok, response}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp descriptor?(descriptor) do
    is_map(descriptor) and closed?(descriptor, @descriptor_keys) and
      descriptor["version"] == 1 and descriptor["kind"] == "saved.result" and
      descriptor["historical_receipt"] == true and digest?(descriptor["output_id"]) and
      digest?(descriptor["sha256"]) and is_integer(descriptor["byte_count"]) and
      descriptor["byte_count"] in 1..4_194_304
  end

  defp target(value, descriptor, %{"cursor" => cursor} = request) do
    with true <- closed?(request, ["cursor"]),
         true <- is_map(cursor) and closed?(cursor, @cursor_keys),
         true <- cursor["output_id"] == descriptor["output_id"],
         true <- cursor["source_sha256"] == descriptor["sha256"],
         true <- canonical_path?(cursor["path"]),
         {:ok, item, name} <- resolve(value, cursor["path"]),
         true <- cursor["kind"] == kind(item) or (cursor["kind"] == "key" and is_binary(name)),
         true <- nonnegative?(cursor["offset"]) do
      {:ok, cursor["path"], cursor["kind"], cursor["offset"]}
    else
      _ -> @error
    end
  end

  defp target(value, descriptor, %{"output_id" => output_id, "path" => path} = request) do
    with true <- Map.keys(request) -- ~w(output_id path offset) == [],
         true <- output_id == descriptor["output_id"],
         true <- is_list(path) and length(path) <= 12,
         true <- nonnegative?(Map.get(request, "offset", 0)),
         {:ok, canonical, item} <- initial_path(value, path, []) do
      {:ok, canonical, kind(item), Map.get(request, "offset", 0)}
    else
      _ -> @error
    end
  end

  defp target(_, _, _), do: @error

  defp initial_path(item, [], path), do: {:ok, Enum.reverse(path), item}

  defp initial_path(item, [key | rest], path) when is_map(item) and is_binary(key) do
    keys = item |> Map.keys() |> Enum.sort()

    case Enum.find_index(keys, &(&1 == key)) do
      nil -> @error
      index -> initial_path(Map.fetch!(item, key), rest, [edge("object", index) | path])
    end
  end

  defp initial_path(item, [index | rest], path) when is_list(item) and is_integer(index) do
    with true <- index >= 0,
         {:ok, child} <- Enum.fetch(item, index) do
      initial_path(child, rest, [edge("array", index) | path])
    else
      _ -> @error
    end
  end

  defp initial_path(_, _, _), do: @error

  defp resolve(value, path), do: resolve(value, path, nil)
  defp resolve(value, [], name), do: {:ok, value, name}

  defp resolve(value, [%{"kind" => "object", "index" => index} | rest], _)
       when is_map(value) do
    with {:ok, key} <- value |> Map.keys() |> Enum.sort() |> Enum.fetch(index) do
      resolve(Map.fetch!(value, key), rest, key)
    end
  end

  defp resolve(value, [%{"kind" => "array", "index" => index} | rest], _)
       when is_list(value) do
    with {:ok, item} <- Enum.fetch(value, index), do: resolve(item, rest, nil)
  end

  defp resolve(_, _, _), do: @error

  defp view(item, _name, descriptor, path, "children", offset)
       when is_map(item) or is_list(item) do
    children =
      if is_map(item), do: Enum.sort(item), else: Enum.with_index(item, fn v, i -> {i, v} end)

    total = length(children)

    if offset <= total do
      available = children |> Enum.drop(offset) |> Enum.take(16)
      entries = Enum.with_index(available, offset) |> Enum.map(&child(&1, item, descriptor, path))
      children_view(entries, total, descriptor, path, type(item), offset)
    else
      @error
    end
  end

  defp view(item, _name, descriptor, path, "string", offset) when is_binary(item),
    do: text_view(item, descriptor, path, "string", "string", offset)

  defp view(_item, name, descriptor, path, "key", offset) when is_binary(name),
    do: text_view(name, descriptor, path, "key", "string", offset)

  defp view(item, _name, descriptor, path, "scalar", 0) do
    if kind(item) == "scalar" do
      {:ok,
       base(descriptor, path, "scalar", type(item), 0)
       |> Map.merge(%{
         "value" => item,
         "total_bytes" => byte_size(Jason.encode!(item)),
         "next" => nil,
         "complete" => true
       })}
    else
      @error
    end
  end

  defp view(_, _, _, _, _, _), do: @error

  defp child({{name, item}, ordinal}, parent, descriptor, path) do
    child_path = path ++ [edge(if(is_map(parent), do: "object", else: "array"), ordinal)]
    name = to_string(name)
    prefix = utf8_prefix(name, 128)

    summary = %{
      "ordinal" => ordinal,
      "type" => type(item),
      "name" => prefix,
      "name_complete" => byte_size(prefix) == byte_size(name)
    }

    summary =
      if byte_size(prefix) < byte_size(name) do
        Map.put(summary, "name_reference", cursor(descriptor, child_path, "key", 0))
      else
        summary
      end

    if kind(item) == "scalar" or (is_binary(item) and byte_size(item) <= 128) do
      Map.put(summary, "value", item)
    else
      Map.put(summary, "reference", cursor(descriptor, child_path, kind(item), 0))
    end
  end

  defp children_view(entries, total, descriptor, path, target_type, offset) do
    next_offset = offset + length(entries)

    response =
      base(descriptor, path, "children", target_type, offset)
      |> Map.merge(%{
        "children" => entries,
        "total_children" => total,
        "next" => if(next_offset < total, do: cursor(descriptor, path, "children", next_offset)),
        "complete" => next_offset == total
      })

    cond do
      bounded?(response) ->
        {:ok, response}

      length(entries) > 1 ->
        children_view(Enum.drop(entries, -1), total, descriptor, path, target_type, offset)

      true ->
        @error
    end
  end

  defp text_view(text, descriptor, path, kind, target_type, offset) do
    total = byte_size(text)

    if offset <= total and String.valid?(binary_part(text, 0, offset)) do
      part = text |> binary_part(offset, total - offset) |> utf8_prefix(1024)
      next_offset = offset + byte_size(part)

      {:ok,
       base(descriptor, path, kind, target_type, offset)
       |> Map.merge(%{
         "text" => part,
         "total_bytes" => total,
         "next" => if(next_offset < total, do: cursor(descriptor, path, kind, next_offset)),
         "complete" => next_offset == total
       })}
    else
      @error
    end
  end

  defp base(descriptor, path, kind, target_type, offset) do
    %{
      "version" => 1,
      "output_id" => descriptor["output_id"],
      "source_sha256" => descriptor["sha256"],
      "historical_receipt" => true,
      "path" => path,
      "kind" => kind,
      "target_type" => target_type,
      "offset" => offset
    }
  end

  defp cursor(descriptor, path, kind, offset) do
    %{
      "output_id" => descriptor["output_id"],
      "source_sha256" => descriptor["sha256"],
      "path" => path,
      "kind" => kind,
      "offset" => offset
    }
  end

  defp edge(kind, index), do: %{"kind" => kind, "index" => index}
  defp kind(item) when is_map(item) or is_list(item), do: "children"
  defp kind(item) when is_binary(item), do: "string"
  defp kind(_), do: "scalar"
  defp type(item) when is_map(item), do: "object"
  defp type(item) when is_list(item), do: "array"
  defp type(item) when is_binary(item), do: "string"
  defp type(item) when is_boolean(item), do: "boolean"
  defp type(nil), do: "null"
  defp type(item) when is_integer(item), do: "integer"
  defp type(item) when is_float(item), do: "number"

  defp canonical_path?(path) do
    is_list(path) and length(path) <= 12 and
      Enum.all?(path, fn segment ->
        is_map(segment) and closed?(segment, ~w(kind index)) and
          segment["kind"] in ~w(object array) and nonnegative?(segment["index"])
      end)
  end

  defp utf8_prefix(text, limit), do: trim_utf8(binary_part(text, 0, min(byte_size(text), limit)))

  defp trim_utf8(text) do
    if String.valid?(text), do: text, else: trim_utf8(binary_part(text, 0, byte_size(text) - 1))
  end

  defp bounded?(value),
    do: Ipse.Extension.validate(value) == :ok and byte_size(Jason.encode!(value)) <= @limit

  defp closed?(value, keys), do: Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp nonnegative?(value), do: is_integer(value) and value >= 0
  defp digest?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
