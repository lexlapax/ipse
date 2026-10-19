defmodule Ipse.Extensions.ResultDocument do
  @moduledoc """
  Validates complete result documents independently of bounded SDK envelopes.

  The ordinary SDK validator limits objects to 16 KiB and collections to 128
  entries. A complete result may span many envelopes, so this adapter enforces
  its own finite resource limits before applying the same checked schema subset.
  Received bytes remain the caller's digest input; decoding never replaces them
  with a re-encoding.

  Integers remain exact within Jason's 1,024-byte integer-token limit, including
  the minus sign. Other lexical tokens have an independent 8,192-byte guard.
  """

  alias Ipse.MCP.Schema

  @bytes 4 * 1024 * 1024
  @depth 12
  @string_bytes 8192
  @collection_size 4096
  @nodes 262_144
  @encoded_string_bytes 49_154
  @primitive_bytes 8192
  @integer_bytes 1024
  @max_integer Integer.pow(10, @integer_bytes) - 1
  @min_integer -(Integer.pow(10, @integer_bytes - 1) - 1)
  @error {:error, :invalid_result_document}

  @doc "Decode a complete bounded JSON object, rejecting duplicate keys at every depth."
  def decode(bytes, schema) when is_binary(bytes) and byte_size(bytes) <= @bytes do
    with :ok <- preflight(bytes),
         {:ok, value} <- Ipse.JSON.decode_unique(bytes, @depth - 1),
         {:ok, _encoded} <- encode(value, schema) do
      {:ok, value}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def decode(_, _), do: @error

  @doc "Encode a complete result after checking its aggregate bounds and declared schema."
  def encode(value, schema) when is_map(value) do
    with {:ok, _counts} <- value_nodes(value, 1, {0, 0}),
         {:ok, encoded} <- Jason.encode(value),
         true <- byte_size(encoded) <= @bytes,
         :ok <- preflight(encoded),
         :ok <- Schema.validate_result(schema, value) do
      {:ok, encoded}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def encode(_, _), do: @error

  defp value_nodes(_value, depth, {count, _bytes}) when depth > @depth or count >= @nodes,
    do: @error

  defp value_nodes(value, _depth, count) when is_binary(value) do
    if byte_size(value) <= @string_bytes and String.valid?(value),
      do: scalar_node(value, count),
      else: @error
  end

  defp value_nodes(value, _depth, count) when is_nil(value) or is_boolean(value),
    do: scalar_node(value, count)

  defp value_nodes(value, _depth, count) when is_integer(value) do
    if value >= @min_integer and value <= @max_integer,
      do: scalar_node(value, count),
      else: @error
  end

  defp value_nodes(value, _depth, count) when is_float(value) do
    if value == value and abs(value) < 1.0e308, do: scalar_node(value, count), else: @error
  end

  defp value_nodes(value, depth, count)
       when is_map(value) and map_size(value) <= @collection_size do
    with {:ok, initial} <- container_node(count, map_size(value), map_size(value)) do
      Enum.reduce_while(value, {:ok, initial}, fn {key, item}, {:ok, current} ->
        with true <- is_binary(key),
             {:ok, after_key} <- value_nodes(key, depth + 1, current),
             {:ok, after_value} <- value_nodes(item, depth + 1, after_key) do
          {:cont, {:ok, after_value}}
        else
          _ -> {:halt, @error}
        end
      end)
    end
  end

  defp value_nodes(value, depth, count) when is_list(value) do
    with {:ok, size} <- collection_size(value, 0),
         {:ok, initial} <- container_node(count, size, 0) do
      Enum.reduce_while(value, {:ok, initial}, fn item, {:ok, current} ->
        case value_nodes(item, depth + 1, current) do
          {:ok, next} -> {:cont, {:ok, next}}
          error -> {:halt, error}
        end
      end)
    else
      _ -> @error
    end
  end

  defp value_nodes(_, _, _), do: @error

  defp collection_size([], size), do: {:ok, size}

  defp collection_size([_ | rest], size) when size < @collection_size,
    do: collection_size(rest, size + 1)

  defp collection_size(_, _), do: @error

  defp scalar_node(value, {nodes, bytes}) do
    with {:ok, encoded} <- Jason.encode(value),
         true <- bytes + byte_size(encoded) <= @bytes do
      {:ok, {nodes + 1, bytes + byte_size(encoded)}}
    else
      _ -> @error
    end
  end

  defp container_node({nodes, bytes}, size, colons) do
    bytes = bytes + 2 + max(size - 1, 0) + colons
    if bytes <= @bytes, do: {:ok, {nodes + 1, bytes}}, else: @error
  end

  # This scan only limits parser resources. Jason still checks JSON syntax,
  # escapes, UTF8, numbers and matching delimiters. Keys count as nodes too.
  defp preflight(bytes), do: scan(bytes, 0, 0)

  defp scan(_bytes, depth, tokens) when depth > @depth or tokens > @nodes,
    do: @error

  defp scan(<<>>, _depth, _tokens), do: :ok

  defp scan(<<byte, rest::binary>>, depth, tokens) when byte in [32, 9, 10, 13, ?:, ?,],
    do: scan(rest, depth, tokens)

  defp scan(<<byte, rest::binary>>, depth, tokens) when byte in [?{, ?[],
    do: scan(rest, depth + 1, tokens + 1)

  defp scan(<<byte, rest::binary>>, depth, tokens) when byte in [?}, ?]],
    do: scan(rest, max(depth - 1, 0), tokens)

  defp scan(<<?", rest::binary>>, depth, tokens) when tokens < @nodes,
    do: string(rest, depth, tokens + 1, 1)

  defp scan(bytes, depth, tokens) when tokens < @nodes,
    do: primitive(bytes, depth, tokens + 1, 0)

  defp scan(_, _, _), do: @error

  defp string(_bytes, _depth, _tokens, count) when count >= @encoded_string_bytes,
    do: @error

  defp string(<<?", rest::binary>>, depth, tokens, _count),
    do: scan(rest, depth, tokens)

  defp string(<<?\\, _escaped, rest::binary>>, depth, tokens, count),
    do: string(rest, depth, tokens, count + 2)

  defp string(<<_byte, rest::binary>>, depth, tokens, count),
    do: string(rest, depth, tokens, count + 1)

  defp string(_, _, _, _), do: @error

  defp primitive(<<byte, _rest::binary>> = bytes, depth, tokens, _count)
       when byte in [32, 9, 10, 13, ?:, ?,, ?{, ?[, ?}, ?], ?"],
       do: scan(bytes, depth, tokens)

  defp primitive(<<>>, _depth, _tokens, _count), do: :ok

  defp primitive(_bytes, _depth, _tokens, count) when count >= @primitive_bytes,
    do: @error

  defp primitive(<<_byte, rest::binary>>, depth, tokens, count),
    do: primitive(rest, depth, tokens, count + 1)
end
