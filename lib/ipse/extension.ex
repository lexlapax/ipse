defmodule Ipse.Extension do
  @moduledoc "Worker SDK. SDK-2 adds private paged results; wire objects remain bounded."
  @type value :: nil | boolean() | number() | String.t() | [value()] | %{String.t() => value()}
  @type object :: %{String.t() => value()}
  @callback describe() :: object()
  @callback init(object()) :: {:ok, term()}
  @callback handle(String.t(), object(), term()) ::
              {:ok, object() | Ipse.Extension.ResultPublication.Output.t(), term()}

  @doc "Reject private runtime terms and independently bound each SDK object."
  def validate(object) do
    case Ipse.JSON.validate_object(object) do
      :ok -> :ok
      _ -> {:error, :invalid_extension_value}
    end
  end

  @doc "Build untrusted evidence JSON from public read/quote receipts; the host resolves it again before publication."
  def source_proof(page, quote, text) do
    with true <- is_map(page) and is_map(quote) and is_binary(text),
         true <- String.valid?(text) and byte_size(text) in 1..8192,
         true <- source_page?(page),
         true <- source_quote?(quote),
         true <-
           page["kind"] in ~w(input.original input.operator_answer answer.original tool.outcome),
         true <-
           Enum.all?(
             ~w(occurrence_id version_id chunk_id origin coverage content_sha256),
             &(page[&1] === quote[&1])
           ),
         true <- Ipse.JSON.sha256(text) == quote["quote_sha256"],
         start = quote["start_byte"] - page["offset"],
         bytes = quote["end_byte"] - quote["start_byte"],
         true <-
           start >= 0 and bytes == byte_size(text) and start + bytes <= byte_size(page["text"]),
         true <- binary_part(page["text"], start, bytes) == text,
         receipt when is_binary(receipt) <- page["provenance"]["receipt_sha256"],
         true <- Ipse.JSON.sha256?(receipt) do
      {:ok,
       quote
       |> Map.take(
         ~w(occurrence_id version_id origin coverage start_byte end_byte quote_sha256 content_sha256)
       )
       |> Map.merge(%{
         "version" => 1,
         "session_id" => page["window"]["session_id"],
         "kind" => page["kind"],
         "path" => nil,
         "quote" => text,
         "receipt_sha256" => receipt
       })}
    else
      _ -> {:error, :source_index_refused}
    end
  rescue
    _ -> {:error, :source_index_refused}
  end

  defp source_page?(page) do
    validate(page) == :ok and page["version"] === 1 and
      Enum.sort(Map.keys(page)) ==
        ~w(chunk_id complete content_sha256 coverage handle kind next occurrence_id offset origin original_bytes provenance reason text version version_id window) and
      is_map(page["window"]) and page["window"]["version"] === 1 and
      is_binary(page["window"]["session_id"]) and
      Regex.match?(~r/\A[0-9a-f]{32}\z/, page["window"]["session_id"]) and
      Ipse.JSON.safe_uint?(page["offset"]) and is_binary(page["text"]) and
      String.valid?(page["text"]) and page["coverage"] in ~w(available partial) and
      Ipse.JSON.sha256?(page["content_sha256"])
  end

  defp source_quote?(quote) do
    validate(quote) == :ok and
      Enum.sort(Map.keys(quote)) ==
        ~w(chunk_id content_sha256 coverage end_byte occurrence_id origin quote_sha256 start_byte version_id) and
      Enum.all?(~w(chunk_id occurrence_id version_id), fn key ->
        is_binary(quote[key]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, quote[key])
      end) and Ipse.JSON.safe_uint?(quote["start_byte"]) and
      Ipse.JSON.safe_uint?(quote["end_byte"]) and quote["end_byte"] > quote["start_byte"] and
      Ipse.JSON.sha256?(quote["content_sha256"]) and Ipse.JSON.sha256?(quote["quote_sha256"])
  end
end

defmodule Ipse.Extension.ResultPublication do
  @moduledoc "SDK-2 result preparation and bounded terminal byte transport."
  alias Ipse.Extension.ResultDocument
  @schema %{"type" => "object"}
  @bytes 4 * 1024 * 1024
  @stride 4096
  @wrapper 12_000
  @error {:error, :invalid_result_document}

  defmodule Output do
    @moduledoc false
    @enforce_keys [:bytes, :byte_count, :sha256]
    defstruct [:bytes, :byte_count, :sha256]
    @opaque t :: %__MODULE__{bytes: binary(), byte_count: pos_integer(), sha256: String.t()}
  end

  @doc "Prepare an inline callback reply or a private immutable output value."
  def prepare(value) do
    with {:ok, bytes} <- ResultDocument.encode(value, @schema) do
      inline = %{"api_version" => 1, "kind" => "result", "value" => value}

      if bounded?(inline) do
        {:ok, inline}
      else
        {:ok,
         %Output{bytes: bytes, byte_count: byte_size(bytes), sha256: Ipse.JSON.sha256(bytes)}}
      end
    end
  end

  @doc false
  def eligible?(2, capabilities, stage),
    do: "invoke.result.pages" in capabilities and stage in ~w(invoke.tool invoke.command)

  def eligible?(_, _, _), do: false

  @doc false
  def domain_request?(sdk, capabilities, origin, awaiting_action, stage, payload) do
    if not is_nil(origin) and eligible?(sdk, capabilities, origin.stage) do
      awaiting_action and stage == "host.actions" and is_map(payload) and
        payload["invocation_id"] === origin.invocation_id
    else
      true
    end
  end

  @doc false
  def offer(%Output{bytes: bytes, byte_count: count, sha256: sha})
      when is_binary(bytes) and byte_size(bytes) == count and count in 2..@bytes do
    if Ipse.JSON.sha256?(sha) and Ipse.JSON.sha256(bytes) == sha do
      {:ok,
       %{
         "api_version" => 1,
         "kind" => "result_producer",
         "output" => %{"version" => 1, "byte_count" => count, "sha256" => sha}
       }}
    else
      @error
    end
  end

  def offer(_), do: @error

  @doc false
  def open(offer, invocation_id) do
    with true <- keys?(offer, ~w(api_version kind output)),
         true <- offer["api_version"] === 1 and offer["kind"] == "result_producer",
         output = offer["output"],
         true <- keys?(output, ~w(byte_count sha256 version)),
         true <- output["version"] === 1,
         true <- is_integer(output["byte_count"]) and output["byte_count"] in 2..@bytes,
         true <- Ipse.JSON.sha256?(output["sha256"]) and id?(invocation_id),
         true <- bounded?(offer) do
      {:ok,
       %{
         invocation_id: invocation_id,
         output_id: nil,
         offset: 0,
         byte_count: output["byte_count"],
         sha256: output["sha256"],
         complete: false,
         hash_context: :crypto.hash_init(:sha256)
       }}
    else
      _ -> @error
    end
  end

  @doc false
  def request(state, payload) do
    with false <- state.complete,
         true <- keys?(payload, ~w(api_version invocation_id limit offset output_id)),
         true <- payload["api_version"] === 1 and payload["limit"] === @stride,
         true <- payload["invocation_id"] === state.invocation_id,
         true <- Ipse.JSON.sha256?(payload["output_id"]),
         true <- is_nil(state.output_id) or state.output_id === payload["output_id"],
         true <- is_integer(payload["offset"]) and payload["offset"] === state.offset,
         true <- state.offset < state.byte_count,
         true <- bounded?(payload) do
      {:ok, %{state | output_id: payload["output_id"]}}
    else
      _ -> @error
    end
  end

  @doc false
  def chunk(%Output{} = output, state, payload) do
    with {:ok, bound} <- request(state, payload),
         true <- output.byte_count === bound.byte_count and output.sha256 === bound.sha256 do
      size = min(@stride, bound.byte_count - bound.offset)
      bytes = binary_part(output.bytes, bound.offset, size)

      response = %{
        "api_version" => 1,
        "kind" => "result_chunk",
        "output" => %{
          "version" => 1,
          "output_id" => bound.output_id,
          "offset" => bound.offset,
          "next" => bound.offset + size,
          "complete" => bound.offset + size == bound.byte_count,
          "data_base64" => Base.encode64(bytes),
          "sha256" => Ipse.JSON.sha256(bytes)
        }
      }

      with {:ok, next} <- accept(bound, payload, response), do: {:ok, response, next}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def accept(state, payload, response) do
    with {:ok, bound} <- request(state, payload),
         true <- keys?(response, ~w(api_version kind output)),
         true <- bounded?(response),
         true <- response["api_version"] === 1 and response["kind"] == "result_chunk",
         output = response["output"],
         true <- keys?(output, ~w(complete data_base64 next offset output_id sha256 version)),
         true <- output["version"] === 1 and output["output_id"] === bound.output_id,
         true <- output["offset"] === bound.offset,
         true <- is_binary(output["data_base64"]),
         {:ok, bytes} <- Base.decode64(output["data_base64"]),
         true <- Base.encode64(bytes) == output["data_base64"],
         size = min(@stride, bound.byte_count - bound.offset),
         true <- byte_size(bytes) == size,
         true <- output["next"] === bound.offset + size,
         complete = bound.offset + size == bound.byte_count,
         true <- output["complete"] === complete,
         true <- output["sha256"] === Ipse.JSON.sha256(bytes),
         context = :crypto.hash_update(bound.hash_context, bytes),
         true <-
           not complete or
             Base.encode16(:crypto.hash_final(context), case: :lower) == bound.sha256 do
      {:ok, %{bound | offset: output["next"], complete: complete, hash_context: context}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp bounded?(value),
    do: Ipse.Extension.validate(value) == :ok and byte_size(Jason.encode!(value)) <= @wrapper

  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == keys
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end

defmodule Ipse.Extension.ResultDocument do
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

  alias Ipse.JSON, as: Schema

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
