defmodule Ipse.Lifecycle.Source do
  @moduledoc "Stable private references to committed journal records; no delivery or effect authority."
  alias Ipse.Extensions.Manifest
  @keys ~w(byte_offset event_id record_sha256 session_id version)
  @limit 1_048_576
  @error {:error, :invalid_lifecycle_source}

  def record_bytes, do: @limit

  def build(session, offset, record) when is_map(record) do
    with true <- id?(session) and offset?(offset),
         {:ok, encoded} <- Jason.encode(record),
         {:ok, decoded} <- Manifest.decode_json(encoded, @limit),
         true <- decoded == record do
      {:ok,
       %{
         "version" => 1,
         "session_id" => session,
         "byte_offset" => offset,
         "event_id" => event_id(session, offset),
         "record_sha256" => Ipse.Compaction.digest([record])
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def build(_, _, _), do: @error

  def valid?(source) when is_map(source) do
    Enum.sort(Map.keys(source)) == @keys and source["version"] === 1 and
      id?(source["session_id"]) and offset?(source["byte_offset"]) and
      hash?(source["record_sha256"]) and
      source["event_id"] == event_id(source["session_id"], source["byte_offset"])
  rescue
    _ -> false
  end

  def valid?(_), do: false

  @doc "Validate a content-free source reference. This is identity, not data-access authority."
  def valid_metadata?(source) when is_map(source) do
    Enum.sort(Map.keys(source)) == ~w(byte_offset event_id session_id version) and
      source["version"] === 1 and id?(source["session_id"]) and offset?(source["byte_offset"]) and
      source["event_id"] == event_id(source["session_id"], source["byte_offset"])
  rescue
    _ -> false
  end

  def valid_metadata?(_), do: false

  def matches?(source, record) do
    with true <- valid?(source),
         {:ok, expected} <- build(source["session_id"], source["byte_offset"], record) do
      expected == source
    else
      _ -> false
    end
  end

  @doc "Content hashes stay private, even when the event reference is safe to correlate."
  def metadata(source) do
    if valid?(source),
      do: {:ok, Map.delete(source, "record_sha256")},
      else: @error
  end

  defp event_id(session, offset) do
    Manifest.sha256("ipse:journal:v1:" <> session <> ":" <> Integer.to_string(offset))
    |> binary_part(0, 32)
  end

  defp offset?(value), do: is_integer(value) and value in 0..9_007_199_254_740_991
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
