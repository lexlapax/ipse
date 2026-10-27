defmodule Ipse.Extension.Collection.Encoding do
  @moduledoc false
  alias Ipse.Extension.Collection.Migration
  @limit 32_768

  # Generations are never reset: the local row index is its original generation.
  # Imported identities retain their source generation explicitly. Wire packing
  # changes no receipt returned by inspect or bound by the typed export digest.
  def encode(%{"version" => 3} = state) do
    state
    |> Map.put("operations", encode_local(state["operations"]))
    |> Map.put("imported_operations", encode_imported(state["imported_operations"]))
    |> update_migration(&encode_imported/1)
    |> Jason.encode!()
  end

  def decode(%{"version" => version} = state) when version in [2, 3] do
    with {:ok, local} <- decode_local(state["operations"], state["generation"], version),
         {:ok, imported} <- decode_imported(state["imported_operations"], version),
         {:ok, migration} <- decode_migration(state["migration"], version),
         true <-
           Enum.all?(
             [local, imported, (migration || %{})["imported_operations"] || %{}],
             fn rows ->
               Enum.all?(rows, fn {_, receipt} ->
                 not Map.has_key?(receipt, "managed_binding_sha256")
               end)
             end
           ),
         true <- map_size(local) + map_size(imported) + staged_size(migration) <= @limit,
         true <-
           (Map.has_key?(state, "floor_anchor") and Map.has_key?(state, "floor_lineage")) or
             state["floor"] === 0 do
      decoded = %{
        state
        | "version" => 3,
          "operations" => local,
          "imported_operations" => imported,
          "migration" => migration
      }

      {:ok, decoded |> Map.put_new("floor_anchor", nil) |> Map.put_new("floor_lineage", [])}
    else
      _ -> {:error, :invalid_collection_encoding}
    end
  rescue
    _ -> {:error, :invalid_collection_encoding}
  end

  def decode(_), do: {:error, :invalid_collection_encoding}

  def pack_receipts(operations), do: encode_imported(operations)
  def unpack_receipts(rows), do: decode_imported(rows, 3)

  defp encode_local(operations) do
    operations
    |> Enum.sort_by(fn {_, receipt} -> receipt["generation"] end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{id, receipt}, generation} ->
      if receipt["generation"] !== generation,
        do: raise(ArgumentError, "noncontiguous collection receipts")

      [pack(id), pack(receipt["request_sha256"]), receipt["floor"]] ++ extras(receipt)
    end)
  end

  defp encode_imported(operations) do
    operations
    |> Enum.sort()
    |> Enum.map(fn {id, receipt} ->
      [pack(id), receipt["generation"], pack(receipt["request_sha256"]), receipt["floor"]] ++
        extras(receipt)
    end)
  end

  defp extras(receipt) do
    case receipt do
      %{"managed_binding_sha256" => hash} ->
        [%{"managed_binding_sha256" => pack(hash)}]

      _ ->
        case Map.take(receipt, ~w(migration_id checkpoint_id)) do
          extra when map_size(extra) == 0 -> []
          extra -> [extra]
        end
    end
  end

  defp pack(hex), do: hex |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)

  defp unpack(value, bytes) when is_binary(value) do
    with true <- byte_size(value) == div(bytes * 8 + 5, 6),
         {:ok, raw} <- Base.url_decode64(value, padding: false),
         true <- byte_size(raw) == bytes and Base.url_encode64(raw, padding: false) == value,
         do: {:ok, Base.encode16(raw, case: :lower)}
  end

  defp unpack(_, _), do: :error

  defp decode_local(rows, generation, 3) when is_list(rows) and is_integer(generation) do
    if generation in 0..@limit and length(rows) == generation do
      rows
      |> Enum.with_index(1)
      |> decode_rows(fn {row, index} ->
        case row do
          [id, hash, floor | extra] -> receipt(id, index, hash, floor, extra)
          _ -> :error
        end
      end)
    else
      :error
    end
  end

  defp decode_local(rows, generation, 2) when is_map(rows) and is_integer(generation) do
    if valid_legacy?(rows) and generation in 0..@limit and map_size(rows) == generation and
         Enum.sort(Enum.map(rows, fn {_, receipt} -> receipt["generation"] end)) ==
           sequence(generation) do
      {:ok, rows}
    else
      :error
    end
  end

  defp decode_local(_, _, _), do: :error

  defp decode_imported(rows, 3) when is_list(rows) and length(rows) <= @limit do
    decode_rows(rows, fn
      [id, generation, hash, floor | extra] -> receipt(id, generation, hash, floor, extra)
      _ -> :error
    end)
  end

  defp decode_imported(rows, 2) when is_map(rows),
    do: if(valid_legacy?(rows), do: {:ok, rows}, else: :error)

  defp decode_imported(_, _), do: :error

  defp valid_legacy?(rows) do
    map_size(rows) <= @limit and
      Enum.all?(rows, fn {id, receipt} ->
        is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id) and Migration.receipt?(receipt)
      end)
  end

  defp receipt(id, generation, hash, floor, extra) do
    with {:ok, id} <- unpack(id, 16),
         {:ok, hash} <- unpack(hash, 32),
         {:ok, extra} <- extra(extra),
         receipt =
           Map.merge(extra, %{
             "generation" => generation,
             "floor" => floor,
             "request_sha256" => hash
           }),
         true <- Migration.receipt?(receipt),
         do: {:ok, id, receipt}
  end

  defp extra([]), do: {:ok, %{}}

  defp extra([%{"managed_binding_sha256" => value} = m]) when map_size(m) == 1 do
    with {:ok, hash} <- unpack(value, 32), do: {:ok, %{"managed_binding_sha256" => hash}}
  end

  defp extra([m]) when is_map(m) and map_size(m) in 1..2 do
    if Map.keys(m) -- ~w(migration_id checkpoint_id) == [], do: {:ok, m}, else: :error
  end

  defp extra(_), do: :error

  defp decode_rows(rows, fun) do
    Enum.reduce_while(rows, {:ok, %{}}, fn row, {:ok, collected} ->
      case fun.(row) do
        {:ok, id, receipt} ->
          if Map.has_key?(collected, id),
            do: {:halt, :error},
            else: {:cont, {:ok, Map.put(collected, id, receipt)}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp update_migration(%{"migration" => nil} = state, _), do: state

  defp update_migration(state, fun),
    do: update_in(state, ["migration", "imported_operations"], fun)

  defp decode_migration(nil, _), do: {:ok, nil}

  defp decode_migration(m, version) when is_map(m) do
    with {:ok, imported} <- decode_imported(m["imported_operations"], version),
         do: {:ok, %{m | "imported_operations" => imported}}
  end

  defp decode_migration(_, _), do: :error
  defp staged_size(nil), do: 0
  defp staged_size(m), do: map_size(m["imported_operations"])
  defp sequence(0), do: []
  defp sequence(n), do: Enum.to_list(1..n)
end
