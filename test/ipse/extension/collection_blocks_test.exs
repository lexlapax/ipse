defmodule Ipse.Extension.CollectionBlocksTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.{Blocks, Encoding, Migration}
  alias Ipse.JSON

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp receipt(n),
    do: %{"generation" => n, "floor" => n, "request_sha256" => JSON.sha256("request#{n}")}

  defp state(n, aliases \\ 0, records \\ 0) do
    local = for i <- sequence(n), into: %{}, do: {id(i), receipt(i)}
    imported = for i <- sequence(aliases), into: %{}, do: {id(100_000 + i), receipt(100_000 + i)}

    rows =
      for i <- sequence(records), into: %{} do
        generation = rem(i, n) + 1
        key = "note#{i}"

        {key,
         %{
           "key" => key,
           "revision" => generation,
           "operation_id" => id(generation),
           "sha256" => JSON.sha256("value#{i}"),
           "bytes" => 6144
         }}
      end

    %{
      "version" => 3,
      "project" => JSON.sha256("block fixture"),
      "generation" => n,
      "floor" => n,
      "floor_anchor" => if(n == 0, do: nil, else: id(n)),
      "floor_lineage" => Enum.map(sequence(n), &id/1),
      "records" => rows,
      "operations" => local,
      "imported_operations" => imported,
      "migration" => nil,
      "checkpoint" => nil
    }
  end

  defp sequence(0), do: []
  defp sequence(n), do: 1..n

  defp encode(state) do
    {:ok, bytes, blocks} = Blocks.encode(state)
    {Jason.decode!(bytes), blocks}
  end

  defp decode(wire, blocks), do: Blocks.decode(wire, fn hash, _ -> Map.fetch(blocks, hash) end)

  test "managed receipt hash requires explicit v5 root and remains canonical through blocks" do
    original =
      put_in(
        state(1),
        ["operations", id(1), "managed_binding_sha256"],
        JSON.sha256("managed binding")
      )

    {wire, blocks} = encode(original)
    assert wire["version"] == 5
    assert {:ok, ^original, _} = decode(wire, blocks)
    assert {:error, _} = decode(%{wire | "version" => 4}, blocks)
    assert {:error, _} = original |> Encoding.encode() |> Jason.decode!() |> Encoding.decode()
    assert Migration.receipt?(original["operations"][id(1)])
    refute Migration.receipt?(Map.put(original["operations"][id(1)], "checkpoint_id", nil))

    refute Migration.receipt?(
             put_in(original, ["operations", id(1), "managed_binding_sha256"], "invalid")[
               "operations"
             ][id(1)]
           )
  end

  test "annual managed receipt population retains every binding within existing block bounds" do
    original = state(20_950, 1000, 4096)

    original =
      Enum.reduce(~w(operations imported_operations), original, fn field, state ->
        Map.update!(state, field, fn rows ->
          Map.new(rows, fn {id, receipt} ->
            {id, Map.put(receipt, "managed_binding_sha256", JSON.sha256("managed " <> id))}
          end)
        end)
      end)

    {wire, blocks} = encode(original)
    assert wire["version"] == 5
    assert Enum.all?(blocks, fn {_, bytes} -> byte_size(bytes) <= 64 * 1024 end)
    assert map_size(blocks) <= 1024
    assert Enum.sum(Enum.map(blocks, fn {_, bytes} -> byte_size(bytes) end)) <= 9 * 1024 * 1024
    assert {:ok, ^original, _} = decode(wire, blocks)

    assert Migration.operation_digest(original["operations"]) ==
             Migration.operation_digest(elem(decode(wire, blocks), 1)["operations"])
  end

  test "annual receipts, record indexes and applied proofs reconstruct exactly and bind original export digests" do
    original = state(20_950, 1000, 4096)
    original = put_in(original, ["operations", id(2000), "checkpoint_id"], nil)
    {wire, blocks} = encode(original)
    assert byte_size(Migration.encode(wire)) < 64 * 1024
    assert Enum.all?(blocks, fn {_, bytes} -> byte_size(bytes) <= 64 * 1024 end)
    assert {:ok, ^original, hashes} = decode(wire, blocks)
    assert MapSet.size(hashes) == map_size(blocks)

    assert Migration.operation_digest(original["operations"]) ==
             Migration.operation_digest(elem(decode(wire, blocks), 1)["operations"])
  end

  test "one append copies only the local partial tail and one record-index leaf; old immutable blocks stay identical" do
    original = state(600, 600, 1000)
    {before, old_blocks} = encode(original)

    next = %{
      original
      | "generation" => 601,
        "operations" => Map.put(original["operations"], id(601), %{receipt(601) | "floor" => 600})
    }

    next =
      next
      |> put_in(["records", "note1", "revision"], 601)
      |> put_in(["records", "note1", "operation_id"], id(601))

    {after_wire, after_blocks} = encode(next)
    assert Enum.take(before["operations"], 2) == Enum.take(after_wire["operations"], 2)
    assert length(before["records"] -- after_wire["records"]) == 1
    assert length(after_wire["records"] -- before["records"]) == 1
    assert before["imported_operations"] == after_wire["imported_operations"]
    assert length(Map.keys(after_blocks) -- Map.keys(old_blocks)) == 2
    assert {:ok, ^next, _} = decode(after_wire, after_blocks)
  end

  test "an arbitrary alias insertion rewrites its bounded leaf and preserves unrelated partitions" do
    original = state(1, 600)
    {before, old_blocks} = encode(original)
    next = put_in(original, ["imported_operations", id(100_601)], receipt(100_601))
    {after_wire, after_blocks} = encode(next)
    assert length(before["imported_operations"] -- after_wire["imported_operations"]) == 1
    assert length(Map.keys(after_blocks) -- Map.keys(old_blocks)) == 1
    assert {:ok, ^next, _} = decode(after_wire, after_blocks)
  end

  test "declared aggregate counts refuse before any block read" do
    {wire, _} = encode(state(1))
    first = hd(wire["operations"])
    wire = %{wire | "operations" => List.duplicate(%{first | "count" => 512}, 65)}
    owner = self()

    assert {:error, _} =
             Blocks.decode(wire, fn _, _ ->
               send(owner, :read)
               {:error, :unavailable}
             end)

    refute_received :read
  end

  test "the largest closed receipt shape is already smaller than its serialized bound" do
    maximum = %{
      "generation" => 9_007_199_254_740_991,
      "floor" => 9_007_199_254_740_991,
      "request_sha256" => String.duplicate("f", 64),
      "migration_id" => String.duplicate("f", 32),
      "checkpoint_id" => String.duplicate("f", 32)
    }

    assert Migration.receipt?(maximum)
    assert byte_size(Jason.encode!(maximum)) == 241
    assert byte_size(Jason.encode!(maximum)) < 512
    refute Migration.receipt?(Map.put(maximum, "unbounded", String.duplicate("x", 1000)))
    refute Migration.receipt?(Map.put(maximum, "generation", 1.0))
    refute Migration.receipt?(Map.put(maximum, "checkpoint_id", String.duplicate("f", 33)))
  end

  test "staged aliases and descriptor proof plus checkpoint indexes retain all referenced blocks" do
    original = state(600, 600, 1000)

    original = %{
      original
      | "migration" => %{
          "records" => original["records"],
          "imported_operations" => %{id(800_000) => receipt(900_000)},
          "descriptor" => %{"floor_lineage" => original["floor_lineage"]}
        },
        "checkpoint" => %{"records" => original["records"]}
    }

    {wire, blocks} = encode(original)
    assert {:ok, ^original, _} = decode(wire, blocks)
    assert wire["records"] == wire["checkpoint"]["records"]
    assert wire["floor_lineage"] == wire["migration"]["descriptor"]["floor_lineage"]
    ref = hd(wire["migration"]["imported_operations"])
    assert {:error, _} = decode(wire, Map.delete(blocks, ref["sha256"]))
  end

  test "cross-class IDs, missing blocks, forged counts and unknown reference fields refuse" do
    {wire, blocks} = encode(state(600, 600, 1000))
    first = hd(wire["operations"])
    assert {:error, _} = decode(wire, Map.delete(blocks, first["sha256"]))

    assert {:error, _} =
             decode(
               put_in(wire, ["operations"], [%{first | "count" => 0} | tl(wire["operations"])]),
               blocks
             )

    assert {:error, _} =
             decode(
               put_in(wire, ["operations"], [
                 Map.put(first, "ignored", true) | tl(wire["operations"])
               ]),
               blocks
             )

    alias_state = %{state(0) | "imported_operations" => %{id(1) => receipt(1)}}
    {alias_wire, alias_blocks} = encode(alias_state)

    assert {:error, _} =
             decode(
               %{wire | "imported_operations" => alias_wire["imported_operations"]},
               Map.merge(blocks, alias_blocks)
             )
  end

  test "changed prefix with internally consistent content hash still refuses noncanonical partition" do
    {wire, blocks} = encode(state(1, 600))
    [first | rest] = wire["imported_operations"]
    body = Jason.decode!(blocks[first["sha256"]]) |> Map.put("prefix", "")
    bytes = Migration.encode(body)
    ref = %{first | "prefix" => "", "sha256" => JSON.sha256(bytes), "bytes" => byte_size(bytes)}
    wire = %{wire | "imported_operations" => [ref | rest]}
    assert {:error, _} = decode(wire, Map.put(blocks, ref["sha256"], bytes))
  end

  test "local generation gaps and duplicate classes cannot be encoded, and legacy inline receipts remain exact" do
    original = state(2)
    assert {:error, _} = Blocks.encode(put_in(original, ["operations", id(2), "generation"], 3))

    assert {:error, _} =
             Blocks.encode(%{original | "imported_operations" => %{id(1) => receipt(1)}})

    assert {:ok, ^original} =
             original |> Encoding.encode() |> Jason.decode!() |> Encoding.decode()
  end
end
