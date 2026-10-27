defmodule Ipse.Extension.CollectionEncodingTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.Encoding, as: E

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp receipt(n),
    do: %{
      "generation" => n,
      "floor" => max(n - 1, 0),
      "request_sha256" => Ipse.JSON.sha256("request#{n}")
    }

  defp state(n) do
    operations = for value <- 1..n, into: %{}, do: {id(value), receipt(value)}

    %{
      "version" => 3,
      "project" => Ipse.JSON.sha256("project"),
      "generation" => n,
      "floor" => max(n - 1, 0),
      "floor_anchor" => if(n > 1, do: id(n)),
      "floor_lineage" => if(n > 1, do: Enum.map(2..n, &id/1), else: []),
      "records" => %{},
      "operations" => operations,
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }
  end

  test "large annual receipt population is losslessly compact and retains its original export digest" do
    original = state(20_950)
    original = put_in(original, ["operations", id(1000), "checkpoint_id"], nil)
    original = put_in(original, ["operations", id(2000), "migration_id"], id(500_000))
    original = put_in(original, ["imported_operations", id(600_000)], receipt(900_000))
    bytes = E.encode(original)
    assert byte_size(bytes) < byte_size(Jason.encode!(original))

    assert byte_size(Jason.encode!(Jason.decode!(bytes)["operations"])) <
             byte_size(Jason.encode!(original["operations"])) * 0.60

    assert {:ok, decoded} = bytes |> Jason.decode!() |> E.decode()
    assert decoded == original

    assert Ipse.Extension.Collection.Migration.operation_digest(decoded["operations"]) ==
             Ipse.Extension.Collection.Migration.operation_digest(original["operations"])
  end

  test "duplicate IDs, floating counters and noncanonical Base64 cannot construct receipts" do
    wire = state(2) |> E.encode() |> Jason.decode!()
    [first, second] = wire["operations"]
    assert {:error, _} = E.decode(%{wire | "operations" => [first, first]})
    assert {:error, _} = E.decode(%{wire | "generation" => 2.0})

    assert {:error, _} =
             E.decode(%{wire | "operations" => [List.replace_at(first, 2, 1.0), second]})

    assert {:error, _} =
             E.decode(%{
               wire
               | "operations" => [List.replace_at(first, 0, hd(first) <> "="), second]
             })

    assert {:error, _} =
             E.decode(%{
               wire
               | "operations" => [List.replace_at(first, 1, String.duplicate("/", 43)), second]
             })

    # Different unused terminal bits must not alias an otherwise valid ID.
    assert {:error, _} =
             E.decode(%{
               wire
               | "operations" => [
                   List.replace_at(first, 0, String.duplicate("A", 21) <> "B"),
                   second
                 ]
             })

    assert {:error, _} = E.decode(%{wire | "generation" => 3})
  end

  test "unshipped v2 upgrade preserves all original receipts and rejects historical generation gaps" do
    assert {:error, _} = state(2) |> Map.delete("floor_anchor") |> E.decode()
    descriptor = Ipse.Extension.Collection.Migration.descriptor(state(2))
    refute Ipse.Extension.Collection.Migration.descriptor?(Map.delete(descriptor, "floor_anchor"))
    refute Ipse.Extension.Collection.Migration.descriptor?(%{descriptor | "version" => 1})

    original =
      state(2)
      |> Map.put("floor", 0)
      |> Map.put("floor_anchor", nil)
      |> Map.put("floor_lineage", [])

    original = put_in(original, ["operations", id(2), "floor"], 0)
    legacy = original |> Map.put("version", 2) |> Map.delete("floor_anchor")
    assert {:ok, ^original} = E.decode(legacy)
    broken = put_in(legacy, ["operations", id(2), "generation"], 3)
    assert {:error, _} = E.decode(broken)
    assert_raise ArgumentError, fn -> E.encode(%{broken | "version" => 3}) end
  end

  test "staged and committed imported aliases retain source generations and optional receipt fields" do
    imported = Map.put(receipt(400_000), "checkpoint_id", id(800_000))
    original = state(2)

    original = %{
      original
      | "imported_operations" => %{id(400_000) => imported},
        "migration" => %{
          "imported_operations" => %{
            id(500_000) => Map.put(receipt(700_000), "checkpoint_id", nil)
          }
        }
    }

    assert {:ok, ^original} = original |> E.encode() |> Jason.decode!() |> E.decode()
    wire = original |> E.encode() |> Jason.decode!()
    [row] = wire["imported_operations"]
    assert {:error, _} = E.decode(%{wire | "imported_operations" => [row, row]})

    assert {:error, _} =
             E.decode(%{wire | "imported_operations" => [List.replace_at(row, 1, 400_000.0)]})
  end
end
