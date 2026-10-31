defmodule Ipse.Extension.Collection.PendingCapacity do
  @moduledoc false

  alias Ipse.JSON
  alias Ipse.Extension.Collection.Migration

  # The held Collection reader supplies a bounded summary of already loaded
  # references; this function does not authenticate the reader or its owner.
  def check(%{"kind" => "proposal", "key" => "pending." <> _}, value, read)
      when is_function(read, 1) do
    with {:ok, summary} <- read.(%{"op" => "pending_summary"}),
         true <- is_map(summary) and Enum.sort(Map.keys(summary)) == ~w(bytes count),
         true <- summary["count"] in 0..63 and JSON.safe_uint?(summary["bytes"]),
         true <- summary["bytes"] + byte_size(Migration.encode(value)) <= 262_144 do
      :ok
    else
      _ -> {:error, :pending_capacity_refused}
    end
  rescue
    _ -> {:error, :pending_capacity_refused}
  end

  def check(_, _, _), do: :ok
end
