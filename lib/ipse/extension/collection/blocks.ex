defmodule Ipse.Extension.Collection.Blocks do
  @moduledoc false
  alias Ipse.Extension.Collection.{Encoding, Migration}
  alias Ipse.JSON
  import Bitwise
  @block_bytes 64 * 1024
  @block_count 1024
  @decoded_bytes 8 * 1024 * 1024
  @block_total_bytes 9 * 1024 * 1024
  @operations 32_768

  # Flat references have no child graph. Each referenced file binds its kind,
  # position/prefix and rows in the hashed bytes. Canonical reconstruction also
  # verifies the complete partition, including split thresholds and ordering.
  def encode(state) do
    true = state["generation"] === map_size(state["operations"])

    true =
      Enum.all?(Migration.known_operations(state), fn {_, receipt} ->
        Migration.receipt?(receipt)
      end)

    ids =
      Map.keys(state["operations"]) ++
        Map.keys(state["imported_operations"]) ++
        Map.keys(get_in(state, ["migration", "imported_operations"]) || %{})

    true = length(ids) <= @operations and length(ids) == length(Enum.uniq(ids))
    {wire, blocks} = pack(state)
    true = length(references(wire)) <= @block_count
    bytes = Migration.encode(wire)
    true = map_size(blocks) <= @block_count
    true = Enum.sum(Enum.map(blocks, fn {_, bytes} -> byte_size(bytes) end)) <= @block_total_bytes
    true = byte_size(Encoding.encode(state)) <= @decoded_bytes
    {:ok, bytes, blocks}
  rescue
    _ -> {:error, :invalid_collection_blocks}
  end

  def decode(%{"version" => version} = wire, reader)
      when version in [4, 5] and is_function(reader, 2) do
    refs = references(wire)
    true = length(refs) <= @block_count
    true = Enum.all?(refs, &reference?/1)
    true = receipt_count(wire) <= @operations

    true =
      Enum.all?(record_sets(wire), fn set -> Enum.sum(Enum.map(set, & &1["count"])) <= 8192 end)

    unique = Enum.uniq_by(refs, & &1["sha256"])
    true = Enum.sum(Enum.map(unique, & &1["bytes"])) <= @block_total_bytes
    hashes = Enum.map(refs, & &1["sha256"])
    true = length(Enum.uniq(hashes)) <= @block_count

    blocks =
      Enum.reduce(refs, %{}, fn ref, blocks ->
        true = reference?(ref)
        hash = ref["sha256"]

        case Map.fetch(blocks, hash) do
          {:ok, bytes} ->
            true = byte_size(bytes) == ref["bytes"]
            blocks

          :error ->
            {:ok, bytes} = reader.(hash, ref["bytes"])
            true = byte_size(bytes) == ref["bytes"] and JSON.sha256(bytes) == hash
            Map.put(blocks, hash, bytes)
        end
      end)

    state = unpack(wire, blocks)

    true =
      map_size(state["operations"]) + map_size(state["imported_operations"]) +
        map_size(get_in(state, ["migration", "imported_operations"]) || %{}) <= @operations

    {:ok, canonical, expected} = encode(state)
    true = canonical == Migration.encode(wire) and expected == blocks
    {:ok, state, MapSet.new(hashes)}
  rescue
    _ -> {:error, :invalid_collection_blocks}
  end

  def decode(_, _), do: {:error, :invalid_collection_blocks}

  def version(state) do
    if Enum.any?(Migration.known_operations(state), fn {_, receipt} ->
         Map.has_key?(receipt, "managed_binding_sha256")
       end),
       do: 5,
       else: 4
  end

  def hashes(state) do
    {:ok, _, blocks} = encode(state)
    Map.keys(blocks) |> MapSet.new()
  end

  def import_stable_hashes(%{"migration" => migration} = state) when is_map(migration) do
    {wire, _} = pack(state)
    # Import pages cannot change active records, known aliases, admitted source
    # aliases or applied proofs. Full local chunks never change on append. The
    # partial local tail and staged record index deliberately remain outside
    # this set. Terminal publications receive their own additional reservation.
    refs =
      Enum.filter(wire["operations"], &(&1["count"] == 256)) ++
        wire["records"] ++
        wire["imported_operations"] ++
        wire["floor_lineage"] ++
        wire["migration"]["imported_operations"] ++
        wire["migration"]["descriptor"]["floor_lineage"]

    refs |> Enum.map(& &1["sha256"]) |> MapSet.new()
  end

  defp pack(state) do
    {local, a} = local(state["operations"])
    {imported, b} = partition(state["imported_operations"], "aliases", 256)
    {records, c} = partition(state["records"], "records", 128)
    {lineage, d} = lineage(state["floor_lineage"])
    {migration, e} = pack_migration(state["migration"])
    {checkpoint, f} = pack_checkpoint(state["checkpoint"])

    wire = %{
      state
      | "version" => version(state),
        "operations" => local,
        "imported_operations" => imported,
        "records" => records,
        "floor_lineage" => lineage,
        "migration" => migration,
        "checkpoint" => checkpoint
    }

    {wire, merge([a, b, c, d, e, f])}
  end

  defp local(operations) do
    operations
    |> Enum.sort_by(fn {_, receipt} -> receipt["generation"] end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{id, receipt}, index} ->
      true = receipt["generation"] === index
      {id, receipt}
    end)
    |> Enum.chunk_every(256)
    |> Enum.with_index()
    |> Enum.map(fn {rows, index} ->
      block("local", %{"start" => index * 256 + 1}, Encoding.pack_receipts(Map.new(rows)))
    end)
    |> gather()
  end

  defp lineage(ids) do
    true = is_list(ids) and length(ids) <= @operations

    ids
    |> Enum.chunk_every(512)
    |> Enum.with_index()
    |> Enum.map(fn {rows, index} -> block("lineage", %{"start" => index * 512}, rows) end)
    |> gather()
  end

  defp partition(records, kind, maximum) do
    true = is_map(records) and map_size(records) <= @operations
    rows = Enum.map(records, fn {id, value} -> {id, value, :crypto.hash(:sha256, id)} end)
    split(rows, kind, maximum, "") |> gather()
  end

  defp split([], _, _, _), do: []

  defp split(rows, kind, maximum, prefix) when length(rows) <= maximum do
    values = Map.new(rows, fn {id, value, _} -> {id, value} end)
    encoded = if kind == "aliases", do: Encoding.pack_receipts(values), else: record_rows(values)
    [block(kind, %{"prefix" => prefix}, encoded)]
  end

  defp split(rows, kind, maximum, prefix) when byte_size(prefix) < 256 do
    depth = byte_size(prefix)

    {left, right} =
      Enum.split_with(rows, fn {_, _, hash} ->
        band(bsr(:binary.at(hash, div(depth, 8)), 7 - rem(depth, 8)), 1) == 0
      end)

    split(left, kind, maximum, prefix <> "0") ++ split(right, kind, maximum, prefix <> "1")
  end

  defp block(kind, position, rows) do
    bytes =
      Migration.encode(Map.merge(position, %{"version" => 1, "kind" => kind, "rows" => rows}))

    true = byte_size(bytes) <= @block_bytes
    hash = JSON.sha256(bytes)

    ref =
      Map.merge(position, %{
        "kind" => kind,
        "count" => length(rows),
        "sha256" => hash,
        "bytes" => byte_size(bytes)
      })

    {ref, %{hash => bytes}}
  end

  defp gather(list), do: {Enum.map(list, &elem(&1, 0)), merge(Enum.map(list, &elem(&1, 1)))}

  defp merge(maps),
    do:
      Enum.reduce(maps, %{}, fn map, acc ->
        Map.merge(acc, map, fn _, a, b ->
          true = a == b
          a
        end)
      end)

  defp pack_migration(nil), do: {nil, %{}}

  defp pack_migration(m) do
    {records, a} = partition(m["records"], "records", 128)
    {imported, b} = partition(m["imported_operations"], "aliases", 256)
    {lineage, c} = lineage(m["descriptor"]["floor_lineage"])

    {%{
       m
       | "records" => records,
         "imported_operations" => imported,
         "descriptor" => %{m["descriptor"] | "floor_lineage" => lineage}
     }, merge([a, b, c])}
  end

  defp pack_checkpoint(nil), do: {nil, %{}}

  defp pack_checkpoint(c) do
    {records, blocks} = partition(c["records"], "records", 128)
    {%{c | "records" => records}, blocks}
  end

  defp record_rows(records),
    do:
      records
      |> Enum.sort()
      |> Enum.map(fn {key, r} ->
        [key, r["revision"], r["sha256"], r["bytes"], r["operation_id"]]
      end)

  defp references(wire) do
    base =
      wire["operations"] ++
        wire["imported_operations"] ++ wire["records"] ++ wire["floor_lineage"]

    staged =
      case wire["migration"] do
        nil -> []
        m -> m["records"] ++ m["imported_operations"] ++ m["descriptor"]["floor_lineage"]
      end

    checkpoint =
      case wire["checkpoint"] do
        nil -> []
        c -> c["records"]
      end

    base ++ staged ++ checkpoint
  end

  defp receipt_count(wire) do
    staged = if wire["migration"], do: wire["migration"]["imported_operations"], else: []
    Enum.sum(Enum.map(wire["operations"] ++ wire["imported_operations"] ++ staged, & &1["count"]))
  end

  defp record_sets(wire),
    do: [
      wire["records"],
      if(wire["migration"], do: wire["migration"]["records"], else: []),
      if(wire["checkpoint"], do: wire["checkpoint"]["records"], else: [])
    ]

  defp reference?(r) do
    is_map(r) and r["kind"] in ~w(local aliases records lineage) and
      is_integer(r["count"]) and r["count"] in 1..512 and
      JSON.sha256?(r["sha256"]) and is_integer(r["bytes"]) and r["bytes"] in 2..@block_bytes and
      if(r["kind"] in ~w(local lineage),
        do:
          Enum.sort(Map.keys(r)) == ~w(bytes count kind sha256 start) and is_integer(r["start"]) and
            r["start"] >= 0,
        else:
          Enum.sort(Map.keys(r)) == ~w(bytes count kind prefix sha256) and is_binary(r["prefix"]) and
            byte_size(r["prefix"]) <= 256 and Regex.match?(~r/\A[01]*\z/, r["prefix"])
      )
  end

  defp unpack(wire, blocks) do
    local = receipt_map(wire["operations"], "local", blocks)
    imported = receipt_map(wire["imported_operations"], "aliases", blocks)
    records = record_map(wire["records"], blocks)
    lineage = lineage_rows(wire["floor_lineage"], blocks)

    migration =
      case wire["migration"] do
        nil ->
          nil

        m ->
          %{
            m
            | "records" => record_map(m["records"], blocks),
              "imported_operations" => receipt_map(m["imported_operations"], "aliases", blocks),
              "descriptor" => %{
                m["descriptor"]
                | "floor_lineage" => lineage_rows(m["descriptor"]["floor_lineage"], blocks)
              }
          }
      end

    checkpoint =
      case wire["checkpoint"] do
        nil -> nil
        c -> %{c | "records" => record_map(c["records"], blocks)}
      end

    ids =
      Map.keys(local) ++
        Map.keys(imported) ++ Map.keys(get_in(migration || %{}, ["imported_operations"]) || %{})

    true = length(ids) == length(Enum.uniq(ids))

    %{
      wire
      | "version" => 3,
        "operations" => local,
        "imported_operations" => imported,
        "records" => records,
        "floor_lineage" => lineage,
        "migration" => migration,
        "checkpoint" => checkpoint
    }
  end

  defp rows(ref, kind, blocks) do
    true = ref["kind"] == kind
    {:ok, body} = JSON.decode_unique(Map.fetch!(blocks, ref["sha256"]))
    position = if kind in ~w(local lineage), do: ~w(start), else: ~w(prefix)
    true = Enum.sort(Map.keys(body)) == Enum.sort(~w(version kind rows) ++ position)
    true = body["version"] === 1 and body["kind"] == kind
    true = Map.take(body, position) == Map.take(ref, position)
    true = is_list(body["rows"]) and length(body["rows"]) == ref["count"]
    body["rows"]
  end

  defp receipt_map(refs, kind, blocks) do
    Enum.reduce(refs, %{}, fn ref, acc ->
      {:ok, receipts} = Encoding.unpack_receipts(rows(ref, kind, blocks))
      true = Enum.all?(Map.keys(receipts), &(not Map.has_key?(acc, &1)))
      Map.merge(acc, receipts)
    end)
  end

  defp record_map(refs, blocks) do
    Enum.reduce(refs, %{}, fn ref, acc ->
      Enum.reduce(rows(ref, "records", blocks), acc, fn [key, revision, hash, bytes, operation],
                                                        acc ->
        true = is_binary(key) and not Map.has_key?(acc, key)

        Map.put(acc, key, %{
          "key" => key,
          "revision" => revision,
          "sha256" => hash,
          "bytes" => bytes,
          "operation_id" => operation
        })
      end)
    end)
  end

  defp lineage_rows(refs, blocks), do: Enum.flat_map(refs, &rows(&1, "lineage", blocks))
end
