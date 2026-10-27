Code.require_file("../../dev/knowledge/managed_metadata.ex", __DIR__)
Code.require_file("../../dev/knowledge/managed_metadata_shapes.exs", __DIR__)

defmodule Ipse.Development.ManagedMetadataTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.ManagedMetadata.{Codec, Leaves}
  alias Ipse.Development.ManagedMetadata.Shapes, as: F

  # These declared identities exercise a pure codec, not source admission or any publication.
  def refs(pages),
    do: Enum.map(pages, fn {key, r} -> %{"key" => key, "revision" => r.revision} end)

  def apply_plan(pages, plan, n) do
    Enum.reduce(plan, pages, fn c, p ->
      assert c["expected_revision"] == if(p[c["key"]], do: p[c["key"]].revision, else: 0)

      if is_nil(c["value"]),
        do: Map.delete(p, c["key"]),
        else: Map.put(p, c["key"], %{revision: n, value: c["value"]})
    end)
  end

  def insert(pages, kind, id, row, n) do
    rs = refs(pages)
    {:ok, loc} = Leaves.neighbors(kind, rs, id)
    value = if loc["previous"], do: pages[loc["previous"]["key"]].value
    {:ok, plan} = Leaves.put(kind, rs, value, id, row)
    assert length(plan) <= 2
    apply_plan(pages, plan, n)
  end

  def remove(pages, kind, id, n) do
    rs = refs(pages)
    {:ok, loc} = Leaves.neighbors(kind, rs, id)
    {:ok, sibling} = Leaves.deletion_neighbor(kind, rs, id)
    selected = pages[loc["previous"]["key"]].value
    other = if sibling, do: pages[sibling["key"]].value
    {:ok, plan} = Leaves.delete(kind, rs, selected, other, id)
    assert length(plan) <= 3
    apply_plan(pages, plan, n)
  end

  def validate(pages, kind) do
    rs = refs(pages)
    {:ok, ordered} = Leaves.directory(kind, rs)

    Enum.each(Enum.with_index(ordered), fn {{_, r}, i} ->
      next =
        case Enum.at(ordered, i + 1) do
          nil -> nil
          {_, v} -> v
        end

      assert Leaves.valid_page?(kind, r, next, pages[r["key"]].value)

      if map_size(pages) > 1 do
        weights =
          pages[r["key"]].value["entries"]
          |> Enum.map(fn {packed, row} -> {Leaves.identity(kind, packed), row} end)
          |> then(&Leaves.weights(kind, &1))

        assert Enum.sum(weights) >= %{anchor_full: 1193, anchor_candidate: 1847, live: 2882}[kind]
      end
    end)

    Enum.flat_map(pages, fn {_, p} ->
      Enum.map(p.value["entries"], fn {packed, row} -> {Leaves.identity(kind, packed), row} end)
    end)
    |> Map.new()
  end

  test "live roundtrip derives exact duplicated facts only from the hash-matched canonical record" do
    {row, record} = F.live()
    assert {:ok, {id, wire}} = Codec.encode_live(row, record)
    assert {:ok, ^row} = Codec.decode_live(id, wire, record)
    assert {:error, _} = Codec.decode_live(id, wire, put_in(record, ["value", "text"], "changed"))
    assert {:error, _} = Codec.encode_live(Map.put(row, "extra", true), record)

    assert {:error, _} =
             Codec.encode_live(
               put_in(row, ["sources", Access.at(0), "version_id"], String.duplicate("0", 32)),
               record
             )

    assert {:error, _} = Codec.encode_live(row, Map.put(record, "key", "note." <> F.hash(2)))
  end

  test "both full-evidence and separate unratified candidate choices roundtrip losslessly" do
    id = F.hash(1)

    for {kind, choice} <- [
          anchor_full: F.full_choice(id),
          anchor_candidate: F.candidate_choice(id)
        ] do
      semantic = F.anchor(choice)
      assert {:ok, wire} = Codec.encode_anchor(id, semantic, kind)
      assert {:ok, ^semantic} = Codec.decode_anchor(id, wire, kind)

      refute Codec.valid_wire?(
               if(kind == :anchor_full, do: :anchor_candidate, else: :anchor_full),
               id,
               wire
             )
    end

    assert {:error, _} =
             Codec.encode_anchor(
               id,
               F.anchor(put_in(F.full_choice(id), ["override", "lineage"], F.hash(2)))
             )
  end

  test "maximum shapes retain full evidence and keep class-specific choices distinct" do
    id = F.hash(1)
    {:ok, full} = Codec.encode_anchor(id, F.anchor(F.full_choice(id)))

    {:ok, candidate} =
      Codec.encode_anchor(id, F.anchor(F.candidate_choice(id)), :anchor_candidate)

    {live, record} = F.live()
    {:ok, {_, wire}} = Codec.encode_live(live, record)
    assert byte_size(Codec.bytes(full)) == 2052
    assert byte_size(Codec.bytes(candidate)) == 744
    assert byte_size(Codec.bytes(wire)) == 217

    for policy <- [%{"kind" => "pin"}, %{"kind" => "session"}] do
      semantic = F.anchor(put_in(F.full_choice(id), ["override", "policy"], policy))
      assert {:ok, encoded} = Codec.encode_anchor(id, semantic)
      assert {:ok, ^semantic} = Codec.decode_anchor(id, encoded)
      assert byte_size(Codec.bytes(encoded)) == 2038
    end

    # The original proof envelope's byte ceiling still applies before packing.
    quote = String.duplicate("\"", 1024)
    changed = F.full_choice(id)
    changed = put_in(changed, ["evidence", "sources", Access.at(0), "quote"], quote)

    changed =
      put_in(
        changed,
        ["evidence", "sources", Access.at(0), "quote_sha256"],
        Ipse.JSON.sha256(quote)
      )

    assert {:error, _} = Codec.encode_anchor(id, F.anchor(changed))
  end

  test "canonical encodings refuse floats, overflow, padding, alias alphabet and noncanonical clocks" do
    {row, record} = F.live()
    {:ok, {id, wire}} = Codec.encode_live(row, record)

    for bad <- [
          List.replace_at(wire, 0, hd(wire) <> "="),
          List.replace_at(wire, 4, "00"),
          List.replace_at(wire, 4, "+1"),
          List.replace_at(wire, 4, 1.0),
          List.replace_at(wire, 4, String.duplicate("z", 12)),
          List.replace_at(wire, 6, 0.0),
          wire ++ [nil]
        ] do
      refute Codec.valid_wire?(:live, id, bad)
    end

    assert {:error, _} =
             Codec.encode_live(Map.put(row, "first_admitted_ms", F.safe() + 1), record)

    for category <- ~w(pin preference current history) do
      {classified, classified_record} = F.live(1, category)

      assert {:ok, _} =
               Codec.encode_live(
                 Map.put(classified, "valid_until_ms", nil),
                 classified_record
               )
    end

    assert {:error, _} = Codec.encode_live(Map.put(row, "valid_until_ms", nil), record)
  end

  test "directory and complete selected page reject poisoned ranges and malformed neighbors" do
    id = F.hash(1)
    {:ok, row} = Codec.encode_anchor(id, F.anchor())
    pages = insert(%{}, :anchor_full, id, row, 1)
    [ref] = refs(pages)
    value = pages[ref["key"]].value
    assert {:error, _} = Leaves.directory(:anchor_full, [ref, ref])

    assert {:error, _} =
             Leaves.directory(:anchor_full, [Map.put(ref, "key", Leaves.key(:anchor_full, id))])

    assert {:error, _} =
             Leaves.directory(:anchor_full, [Map.put(ref, "key", ref["key"] <> "poison")])

    refute Leaves.valid_page?(:anchor_full, ref, %{"key" => "bad", "revision" => 1}, value)
    refute Leaves.valid_page?(:anchor_full, ref, nil, Map.put(value, "extra", true))
    refute Leaves.valid_page?(:anchor_full, ref, nil, Map.put(value, "version", 2))

    refute Leaves.valid_page?(
             :anchor_full,
             ref,
             %{"key" => Leaves.key(:anchor_full, id), "revision" => 1},
             value
           )
  end

  test "33 same-prefix identities cross old fixed capacity without shard limits" do
    ids =
      for n <- 1..33,
          do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

    pages =
      Enum.reduce(Enum.with_index(ids, 1), %{}, fn {id, n}, p ->
        {:ok, row} = Codec.encode_anchor(id, F.anchor(F.full_choice(id)))
        insert(p, :anchor_full, id, row, n)
      end)

    assert map_size(validate(pages, :anchor_full)) == 33
    assert map_size(pages) > 1
  end

  test "ascending descending and hashed insertion select valid deterministic byte splits" do
    ids = for n <- 1..160, do: F.hash(n)

    for ordering <- [ids, Enum.sort(ids), Enum.sort(ids, :desc)] do
      pages =
        Enum.reduce(Enum.with_index(ordering, 1), %{}, fn {id, n}, p ->
          {:ok, row} = Codec.encode_anchor(id, F.anchor(if rem(n, 3) == 0, do: F.full_choice(id)))
          insert(p, :anchor_full, id, row, n)
        end)

      assert map_size(validate(pages, :anchor_full)) == length(ids)
      for {_, p} <- pages, do: assert(byte_size(Codec.bytes(p.value)) <= 6144)
    end
  end

  test "bounded churn merges and redistributes without accumulating unreachable leaf keys" do
    ids = for n <- 1..96, do: F.hash(n)

    pages =
      Enum.reduce(Enum.with_index(ids, 1), %{}, fn {id, n}, p ->
        {:ok, row} = Codec.encode_anchor(id, F.anchor(F.full_choice(id)))
        insert(p, :anchor_full, id, row, n)
      end)

    pages =
      Enum.reduce(Enum.with_index(Enum.reverse(ids), 97), pages, fn {id, n}, p ->
        remove(p, :anchor_full, id, n)
      end)

    assert validate(pages, :anchor_full) == %{}
    assert map_size(pages) == 1
    assert Enum.all?(pages, fn {_, p} -> p.value["fence"] == Leaves.zero(:anchor_full) end)
  end

  test "33 declared live records collide in the old 9-bit shard and fit the fence layout" do
    selected =
      Enum.reduce_while(1..65_536, [], fn n, selected ->
        lineage = F.lineage(n)

        shard =
          Ipse.JSON.sha256("note." <> lineage)
          |> binary_part(0, 3)
          |> String.to_integer(16)
          |> rem(512)

        selected = if shard == 0, do: [n | selected], else: selected
        if length(selected) == 33, do: {:halt, selected}, else: {:cont, selected}
      end)

    assert length(selected) == 33

    pages =
      Enum.reduce(Enum.with_index(selected, 1), %{}, fn {n, index}, pages ->
        {semantic, record} = F.live(n)
        {:ok, {id, row}} = Codec.encode_live(semantic, record)
        insert(pages, :live, id, row, index)
      end)

    assert map_size(validate(pages, :live)) == 33

    assert {:error, _} =
             Leaves.directory(:live, [
               %{"key" => Leaves.prefix(:live) <> "ff" <> F.hash(1), "revision" => 1}
             ])
  end

  test "ten thousand structural edits preserve rows and reclaim logical leaf keys" do
    ids = for n <- 1..64, do: F.hash(n)

    {pages, expected} =
      Enum.reduce(1..10_000, {%{}, %{}}, fn n, {pages, expected} ->
        id = Enum.at(ids, rem(n, 64))

        if rem(n, 5) == 0 and Map.has_key?(expected, id) do
          {remove(pages, :anchor_full, id, n), Map.delete(expected, id)}
        else
          {:ok, row} = Codec.encode_anchor(id, F.anchor(if rem(n, 2) == 0, do: F.full_choice(id)))

          pages =
            if Map.has_key?(expected, id) do
              rs = refs(pages)
              {:ok, location} = Leaves.neighbors(:anchor_full, rs, id)
              {:ok, sibling} = Leaves.deletion_neighbor(:anchor_full, rs, id)
              value = pages[location["previous"]["key"]].value
              other = if sibling, do: pages[sibling["key"]].value
              {:ok, plan} = Leaves.replace(:anchor_full, rs, value, other, id, row)
              assert length(plan) <= 3
              apply_plan(pages, plan, n)
            else
              insert(pages, :anchor_full, id, row, n)
            end

          expected = Map.put(expected, id, row)
          if rem(n, 100) == 0, do: assert(validate(pages, :anchor_full) == expected)
          {pages, expected}
        end
      end)

    assert validate(pages, :anchor_full) == expected
    assert map_size(pages) <= map_size(expected)
  end

  test "shrinking updates require a neighbor rather than weakening occupancy" do
    id = F.hash(1)
    {:ok, large} = Codec.encode_anchor(id, F.anchor(F.full_choice(id)))
    {:ok, small} = Codec.encode_anchor(id, F.anchor())
    pages = insert(%{}, :anchor_full, id, large, 1)
    [ref] = refs(pages)
    assert {:error, _} = Leaves.put(:anchor_full, [ref], pages[ref["key"]].value, id, small)

    assert {:ok, [_]} =
             Leaves.replace(:anchor_full, [ref], pages[ref["key"]].value, nil, id, small)
  end

  test "two full 64-row pages can rebalance a deletion without increasing leaf count" do
    ids =
      for n <- 1..128,
          do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

    [left, right] = Enum.chunk_every(ids, 64)
    row = ["0", "1", "0", "1", nil]

    make = fn fence, rows, revision ->
      {Leaves.key(:anchor_full, fence),
       %{
         revision: revision,
         value: Leaves.page(:anchor_full, fence, Map.new(rows, &{Leaves.entry_id(&1), row}))
       }}
    end

    pages = Map.new([make.(Leaves.zero(:anchor_full), left, 1), make.(hd(right), right, 2)])
    assert map_size(validate(pages, :anchor_full)) == 128
    pages = remove(pages, :anchor_full, Enum.at(ids, 20), 3)
    assert map_size(validate(pages, :anchor_full)) == 127
    assert map_size(pages) == 2
  end
end
