defmodule Ipse.Extension.CollectionDirectoryTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.Directory, as: D

  defp key(n, width \\ 32),
    do: "p." <> String.pad_leading(String.downcase(Integer.to_string(n, 16)), width * 2, "0")

  defp request(n, width \\ 32),
    do: %{
      "version" => 1,
      "prefix" => "p.",
      "fence_bytes" => width,
      "needle" => String.slice(key(n, width), 2..-1//1)
    }

  defp select(index, n, width \\ 32),
    do: D.select(index, %{"op" => "neighbors", "request" => request(n, width)}, "present")

  test "exact and between fences include the preceding leaf and two following boundaries" do
    assert {:ok, tree} = D.index(["other", key(0), key(10), key(20), key(30), "z"])
    assert {:ok, [a, b, c, d], nil, slots} = select(tree, 15)
    assert [a, b, c, d] == Enum.map([0, 10, 20, 30], &key/1)

    assert slots == %{
             "state" => "initialized",
             "predecessor" => key(0),
             "selected" => key(10),
             "successor" => key(20),
             "second_successor" => key(30)
           }

    assert {:ok, _, nil, exact} = select(tree, 10)
    assert exact == slots
  end

  test "first and last boundaries have honest nil slots, including a one-leaf tree" do
    assert {:ok, tree} = D.index(Enum.map([0, 10, 20], &key/1))
    assert {:ok, _, nil, first} = select(tree, 0)
    assert first["predecessor"] == nil
    assert first["selected"] == key(0)
    assert first["successor"] == key(10)
    assert first["second_successor"] == key(20)
    assert {:ok, _, nil, last} = select(tree, 999)
    assert last["predecessor"] == key(10)
    assert last["selected"] == key(20)
    assert last["successor"] == nil and last["second_successor"] == nil
    assert {:ok, singleton} = D.index([key(0)])
    assert {:ok, [only], nil, one} = select(singleton, 10)
    assert only == key(0)
    assert Enum.count(Map.values(Map.delete(one, "state")), &is_nil/1) == 3
  end

  test "both bounded fence widths work at the maximum needle" do
    for width <- [32, 33] do
      assert {:ok, tree} = D.index([key(0, width), key(8, width)])
      r = %{request(0, width) | "needle" => String.duplicate("f", width * 2)}

      assert {:ok, _, nil, neighbors} =
               D.select(tree, %{"op" => "neighbors", "request" => r}, "present")

      assert neighbors["selected"] == key(8, width)
    end
  end

  test "all matching directory names validate, including poison outside the chosen four" do
    for poison <- [
          "p.bad",
          "p." <> String.duplicate("F", 64),
          key(100) <> "0",
          "p." <> String.duplicate("1", 63)
        ] do
      keys = Enum.sort(Enum.map([0, 1, 2, 3, 4, 5], &key/1) ++ [poison])
      assert {:ok, tree} = D.index(keys)
      assert {:error, :collection_directory_invalid} = select(tree, 0)
    end
  end

  test "missing sentinel or directory refuses on a materialized root" do
    for keys <- [[], ["other"], [key(1), key(2)]] do
      assert {:ok, tree} = D.index(keys)
      assert {:error, :collection_directory_invalid} = select(tree, 0)
    end
  end

  test "uninitialized is possible only for an actually absent empty index" do
    assert {:ok, empty} = D.index([])

    assert {:ok, [], nil, slots} =
             D.select(empty, %{"op" => "neighbors", "request" => request(0)}, "absent")

    assert slots["state"] == "uninitialized"

    assert Map.delete(slots, "state") ==
             Map.new(~w(predecessor selected successor second_successor), &{&1, nil})

    assert {:ok, present} = D.index([key(0)])

    assert {:error, :collection_directory_invalid} =
             D.select(present, %{"op" => "neighbors", "request" => request(0)}, "absent")
  end

  test "descriptor and observation requests have closed schemas and exact integers" do
    for r <- [
          Map.put(request(0), "version", 1.0),
          Map.put(request(0), "fence_bytes", 32.0),
          Map.put(request(0), "fence_bytes", 31),
          Map.put(request(0), "prefix", "../"),
          Map.put(request(0), "prefix", "a"),
          Map.put(request(0), "prefix", String.duplicate("x", 32) <> "."),
          Map.put(request(0), "needle", String.duplicate("A", 64)),
          Map.put(request(0), "needle", String.duplicate("0", 66)),
          Map.put(request(0), "owner", "invented"),
          %{}
        ] do
      refute D.neighbor_request?(r)
      assert :error = D.cost(%{"op" => "neighbors", "request" => r})
    end

    assert {:ok, 4} = D.cost(%{"op" => "neighbors", "request" => request(0)})
    assert :error = D.cost(%{"op" => "neighbors", "request" => request(0), "extra" => true})
    assert {:ok, 1} = D.cost("ordinary.key")
    assert {:ok, 2} = D.cost(%{"op" => "get_many", "keys" => ["a", "b"]})
    assert {:ok, 8} = D.cost(%{"op" => "scan", "after" => nil, "limit" => 8})
    assert :error = D.cost(%{"op" => "scan", "after" => nil, "limit" => 8.0})
    assert :error = D.cost(%{"op" => "get_many", "keys" => ["a", "a"]})
  end

  test "whole immutable index installation refuses duplicates, unsorted and oversized keys" do
    for keys <- [
          ["b", "a"],
          ["a", "a"],
          ["../x"],
          [String.duplicate("x", 97)],
          Enum.map(0..8192, &key/1)
        ] do
      assert {:error, :collection_directory_invalid} = D.index(keys)
    end
  end

  test "8192 refs use opaque OTP iteration and preserve exclusive scan cursors" do
    keys = Enum.map(0..8191, &key/1)
    assert {:ok, tree} = D.index(keys)
    assert D.keys(tree) == keys
    assert {:ok, neighbors, nil, _} = select(tree, 8190)
    assert neighbors == Enum.map(8189..8191, &key/1)

    assert {:ok, [a, b], cursor, nil} =
             D.select(tree, %{"op" => "scan", "after" => key(0), "limit" => 2}, "present")

    assert [a, b] == [key(1), key(2)] and cursor == key(2)

    assert {:ok, [], nil, nil} =
             D.select(tree, %{"op" => "scan", "after" => key(8191), "limit" => 8}, "present")
  end

  test "tree heap is separately measurable without retaining a duplicate key list" do
    keys = Enum.map(0..8191, &key/1)
    assert {:ok, tree} = D.index(keys)
    tree_words = :erts_debug.flat_size(tree)
    list_words = :erts_debug.flat_size(keys)
    word = :erlang.system_info(:wordsize)
    assert tree_words > list_words
    # Node overhead is bounded; binary/key storage appears in both flat sizes.
    assert (tree_words - list_words) * word <= 8192 * 64 + 128
    send(self(), {:heap_measurement, tree_words * word, list_words * word})
    assert_receive {:heap_measurement, _, _}
  end
end
