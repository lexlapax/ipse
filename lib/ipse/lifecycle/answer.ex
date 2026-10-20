defmodule Ipse.Lifecycle.Answer do
  @moduledoc "A completed answer boundary, retaining bounded original and presented text views."
  alias Ipse.Lifecycle.Source

  @keys ~w(type version turn_id request_id effective_source assistant_sha256 original original_bytes original_sha256 presented presented_bytes presented_sha256)

  def build(turn, request, assistant, presented, effective_source) do
    original = assistant["content"]

    %{
      "type" => "lifecycle_answer_committed",
      "version" => 1,
      "turn_id" => turn,
      "request_id" => request,
      "effective_source" => effective_source,
      "assistant_sha256" => Ipse.JSON.digest([assistant]),
      "original" => bounded(original),
      "original_bytes" => byte_size(original),
      "original_sha256" => Ipse.JSON.sha256(original),
      "presented" => bounded(presented),
      "presented_bytes" => byte_size(presented),
      "presented_sha256" => Ipse.JSON.sha256(presented)
    }
  end

  def valid?(record) do
    is_map(record) and Enum.sort(Map.keys(record)) == Enum.sort(@keys) and
      record["type"] == "lifecycle_answer_committed" and record["version"] === 1 and
      id?(record["turn_id"]) and id?(record["request_id"]) and
      Source.valid?(record["effective_source"]) and hash?(record["assistant_sha256"]) and
      Enum.all?(
        ~w(original presented),
        &view?(record[&1], record[&1 <> "_bytes"], record[&1 <> "_sha256"])
      )
  rescue
    _ -> false
  end

  defp bounded(text), do: if(byte_size(text) <= 8192, do: text)

  defp view?(nil, bytes, hash),
    do: is_integer(bytes) and bytes in 8193..9_007_199_254_740_991 and hash?(hash)

  defp view?(text, bytes, hash) when is_binary(text),
    do:
      String.valid?(text) and byte_size(text) <= 8192 and bytes === byte_size(text) and
        Ipse.JSON.sha256(text) == hash

  defp view?(_, _, _), do: false
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
