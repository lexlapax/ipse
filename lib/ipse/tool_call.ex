defmodule Ipse.ToolCall do
  @moduledoc "Opaque provider call identifiers shared by admission and durable checkpoints."

  def valid_id?(id) when is_binary(id),
    do: byte_size(id) in 1..256 and String.valid?(id)

  def valid_id?(_), do: false
end
