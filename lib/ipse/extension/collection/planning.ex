defmodule Ipse.Extension.Collection.Planning do
  @moduledoc false
  alias Ipse.Extension.Collection.{Encoding, Migration}
  alias Ipse.JSON

  def export(state) do
    %{
      "version" => 1,
      "records" => rows(state["records"]),
      "operations" => Encoding.pack_receipts(Migration.operations(state))
    }
  end

  def shape?(plan), do: match?({:ok, _, _}, decode(plan))

  def validate(state, descriptor, plan) do
    with {:ok, records, operations} <- decode(plan),
         true <-
           map_size(records) == descriptor["records"] and
             Migration.bytes(records) == descriptor["data_bytes"] and
             Migration.digest(records) == descriptor["records_sha256"] and
             map_size(operations) == descriptor["operations"] and
             Migration.operation_digest(operations) == descriptor["operations_sha256"] do
      known = Migration.known_operations(state)

      cond do
        Enum.any?(operations, fn {id, receipt} -> known[id] != nil and known[id] != receipt end) ->
          {:failed, "collection_operation_identity"}

        not anchor?(operations, descriptor["floor_anchor"], descriptor["floor"]) or
          not Migration.valid_lineage?(
            descriptor["floor_lineage"],
            descriptor["floor_anchor"],
            descriptor["floor"],
            operations
          ) or
          not Migration.lineage_extends?(state["floor_lineage"], descriptor["floor_lineage"]) or
            (state["floor_anchor"] != nil and
               operations[state["floor_anchor"]] != known[state["floor_anchor"]]) ->
          {:failed, "collection_import_lineage"}

        true ->
          {:ok,
           %{
             records: records,
             operations: operations,
             aliases: Map.drop(operations, Map.keys(known)),
             page_hashes: rows(records) |> Enum.chunk_every(32) |> Enum.map(&JSON.digest([&1]))
           }}
      end
    else
      _ -> {:failed, "collection_import_plan"}
    end
  end

  def page_hash(records) do
    records
    |> Enum.map(fn row ->
      encoded = Migration.encode(row["value"])
      [row["key"], JSON.sha256(encoded), byte_size(encoded)]
    end)
    |> then(&JSON.digest([&1]))
  end

  defp anchor?(_, nil, 0), do: true
  defp anchor?(operations, id, floor), do: get_in(operations, [id, "floor"]) === floor

  defp decode(plan) do
    with true <- is_map(plan) and Enum.sort(Map.keys(plan)) == ~w(operations records version),
         true <- plan["version"] === 1,
         list when is_list(list) and length(list) <= 8192 <- plan["records"],
         true <- Enum.all?(list, &record?/1),
         keys = Enum.map(list, &hd/1),
         true <- keys == Enum.sort(Enum.uniq(keys)),
         {:ok, operations} <- Encoding.unpack_receipts(plan["operations"]),
         true <- Encoding.pack_receipts(operations) == plan["operations"],
         true <- byte_size(Jason.encode!(plan)) <= 8 * 1024 * 1024 do
      records =
        Map.new(list, fn [key, hash, bytes] ->
          {key, %{"key" => key, "sha256" => hash, "bytes" => bytes}}
        end)

      {:ok, records, operations}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp record?([key, hash, bytes]),
    do:
      is_binary(key) and byte_size(key) in 1..96 and
        Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/, key) and JSON.sha256?(hash) and
        is_integer(bytes) and bytes in 2..6144

  defp record?(_), do: false

  defp rows(records),
    do:
      records
      |> Enum.sort()
      |> Enum.map(fn {key, record} ->
        [key, record["sha256"], record["bytes"]]
      end)
end
