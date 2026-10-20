defmodule Ipse.Extension.ResultPublication do
  @moduledoc "SDK-2 result preparation and bounded terminal byte transport."
  alias Ipse.Extensions.{ResultDocument}
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
    if hash?(sha) and Ipse.JSON.sha256(bytes) == sha do
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
         true <- hash?(output["sha256"]) and id?(invocation_id),
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
         true <- hash?(payload["output_id"]),
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
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
