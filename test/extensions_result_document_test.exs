defmodule Ipse.Extensions.ResultDocumentTest do
  use ExUnit.Case, async: true

  alias Ipse.Extensions.{ResultDocument}
  alias Ipse.MCP.Schema

  @schema %{"type" => "object", "additionalProperties" => true}
  @limit 4 * 1024 * 1024

  test "round trips complete documents while retaining the ordinary SDK envelope limit" do
    value = %{"items" => Enum.to_list(1..256), "quote" => String.duplicate("é", 4096)}
    assert {:ok, bytes} = ResultDocument.encode(value, @schema)
    assert {:ok, ^value} = ResultDocument.decode(bytes, @schema)
    assert {:error, _} = Schema.validate_object(value)

    larger = %{"items" => List.duplicate(String.duplicate("x", 1024), 20)}
    assert {:ok, bytes} = ResultDocument.encode(larger, @schema)
    assert byte_size(bytes) > 16_384
    assert {:ok, ^larger} = ResultDocument.decode(bytes, @schema)
    assert {:error, _} = Schema.validate_object(larger)
  end

  test "validates the original declared schema, including draft-07 adaptation" do
    schema = %{
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "type" => "object",
      "properties" => %{
        "items" => %{
          "type" => "array",
          "items" => %{"type" => "integer", "minimum" => 1},
          "maxItems" => 256
        }
      },
      "required" => ["items"],
      "additionalProperties" => false
    }

    assert {:ok, bytes} = ResultDocument.encode(%{"items" => Enum.to_list(1..256)}, schema)
    assert {:ok, _} = ResultDocument.decode(bytes, schema)

    for value <- [%{}, %{"items" => [0]}, %{"items" => [1], "extra" => true}] do
      assert {:error, _} = ResultDocument.encode(value, schema)
      assert {:error, _} = ResultDocument.decode(Jason.encode!(value), schema)
    end

    unsupported = Map.put(schema, "$ref", "https://example.com/unavailable")
    assert {:error, _} = ResultDocument.decode(bytes, unsupported)
    assert {:error, _} = ResultDocument.encode(%{"items" => []}, unsupported)
  end

  test "rejects duplicate decoded keys in nested objects and array elements" do
    for bytes <- [
          ~s({"a":1,"a":2}),
          ~s({"items":[{"a":1,"a":2}]}),
          ~S({"items":{"a":1,"\u0061":2}})
        ] do
      assert {:error, _} = ResultDocument.decode(bytes, @schema)
      assert {:error, :duplicate_key} = Ipse.JSON.decode_bounded(bytes)
    end

    assert {:ok, %{"items" => [%{"a" => 1}, %{"a" => 2}]}} =
             ResultDocument.decode(~s({"items":[{"a":1},{"a":2}]}), @schema)
  end

  test "keeps the Manifest decode ceiling and depth behavior" do
    bytes = Jason.encode!(%{"items" => List.duplicate(String.duplicate("x", 8192), 129)})
    assert byte_size(bytes) > 1_048_576
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded(bytes, byte_size(bytes))
    assert {:ok, _} = ResultDocument.decode(bytes, @schema)

    at_depth = Enum.reduce(1..16, 0, fn _, value -> [value] end) |> Jason.encode!()
    assert {:ok, _} = Ipse.JSON.decode_bounded(at_depth)
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded("[" <> at_depth <> "]")
    assert {:error, %Jason.DecodeError{}} = Ipse.JSON.decode_bounded("not json")
    padded = String.duplicate(" ", 1_048_574) <> "{}"
    assert {:ok, %{}} = Ipse.JSON.decode_bounded(padded, 1_048_576)
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded(padded)
  end

  test "enforces the inclusive 4-MiB received and re-encoded byte ceilings" do
    value = sized_document(@limit)
    assert {:ok, bytes} = ResultDocument.encode(value, @schema)
    assert byte_size(bytes) == @limit
    assert {:ok, ^value} = ResultDocument.decode(bytes, @schema)
    assert {:error, _} = ResultDocument.decode(bytes <> " ", @schema)
    assert {:error, _} = ResultDocument.encode(Map.update!(value, "pad", &(&1 <> "x")), @schema)

    padding = Enum.map_join(1..491, ",", fn _ -> Jason.encode!(String.duplicate("x", 8192)) end)

    numbers =
      Enum.map_join(1..8, ",", fn _ ->
        "[" <> Enum.join(List.duplicate("1e99", 4096), ",") <> "]"
      end)

    expanded = ~s({"padding":[#{padding}],"numbers":[#{numbers}]})
    assert byte_size(expanded) < @limit
    assert byte_size(Jason.encode!(Jason.decode!(expanded))) > @limit
    assert {:error, _} = ResultDocument.decode(expanded, @schema)
  end

  test "bounds decoded strings and keys by bytes, including escaped strings" do
    escaped = ~s({"text":") <> String.duplicate("\\u0000", 8192) <> ~s("})
    assert {:ok, %{"text" => text}} = ResultDocument.decode(escaped, @schema)
    assert byte_size(text) == 8192

    for value <- [
          %{"text" => String.duplicate("x", 8193)},
          %{String.duplicate("k", 8193) => 1},
          %{"text" => String.duplicate("é", 4097)},
          %{"text" => <<255>>}
        ] do
      assert {:error, _} = ResultDocument.encode(value, @schema)
    end

    assert {:error, _} =
             ResultDocument.decode(
               ~s({"text":") <> String.duplicate("\\u0000", 8193) <> ~s("}),
               @schema
             )

    assert {:ok, _} = ResultDocument.decode(~S({"text":"escaped\"quote\\slash"}), @schema)
  end

  test "bounds collection entries independently of complete document size" do
    for value <- [%{"items" => List.duplicate(nil, 4096)}, Map.new(1..4096, &{"k#{&1}", nil})] do
      assert {:ok, bytes} = ResultDocument.encode(value, @schema)
      assert {:ok, ^value} = ResultDocument.decode(bytes, @schema)
    end

    for value <- [%{"items" => List.duplicate(nil, 4097)}, Map.new(1..4097, &{"k#{&1}", nil})] do
      assert {:error, _} = ResultDocument.encode(value, @schema)
      assert {:error, _} = ResultDocument.decode(Jason.encode!(value), @schema)
    end
  end

  test "counts root, keys, collections and values toward the total node cap" do
    arrays = List.duplicate(List.duplicate(nil, 4096), 63)
    at_limit = %{"items" => arrays ++ [List.duplicate(nil, 4029)]}
    over_limit = %{"items" => arrays ++ [List.duplicate(nil, 4030)]}
    assert {:ok, bytes} = ResultDocument.encode(at_limit, @schema)
    assert {:ok, ^at_limit} = ResultDocument.decode(bytes, @schema)
    assert {:error, _} = ResultDocument.encode(over_limit, @schema)
    assert {:error, _} = ResultDocument.decode(Jason.encode!(over_limit), @schema)
  end

  test "enforces depth before parsing and after decoding using root depth one" do
    nested = Enum.reduce(1..10, 0, fn _, inner -> [inner] end)
    assert {:ok, _} = ResultDocument.encode(%{"nested" => nested}, @schema)
    assert {:error, _} = ResultDocument.encode(%{"nested" => [nested]}, @schema)
    assert {:error, _} = ResultDocument.decode(Jason.encode!(%{"nested" => [nested]}), @schema)
    assert {:error, _} = ResultDocument.decode(String.duplicate("[", 100_000), @schema)
  end

  test "keeps finite float policy and exact integers with bounded encoded tokens" do
    exact = Integer.pow(10, 1023)
    assert {:ok, bytes} = ResultDocument.encode(%{"n" => exact, "f" => 1.0e100}, @schema)
    assert {:ok, %{"n" => ^exact, "f" => 1.0e100}} = ResultDocument.decode(bytes, @schema)
    assert {:error, _} = ResultDocument.encode(%{"n" => exact * 10}, @schema)
    assert {:error, _} = ResultDocument.encode(%{"n" => -exact}, @schema)
    negative = -Integer.pow(10, 1022)
    assert {:ok, negative_bytes} = ResultDocument.encode(%{"n" => negative}, @schema)
    assert {:ok, %{"n" => ^negative}} = ResultDocument.decode(negative_bytes, @schema)
    assert {:error, _} = ResultDocument.decode(Jason.encode!(%{"n" => -exact}), @schema)
    assert {:error, _} = ResultDocument.decode(Jason.encode!(%{"n" => exact * 10}), @schema)

    assert {:error, _} =
             ResultDocument.decode(~s({"n":) <> String.duplicate("1", 8193) <> "}", @schema)

    assert {:error, _} = ResultDocument.encode(%{"n" => 1.0e308}, @schema)
    assert {:error, _} = ResultDocument.decode(~s({"n":1e308}), @schema)
  end

  test "bounds primitive tokens before the maintained parser allocates numeric values" do
    at_limit = ~s({"n":0.) <> String.duplicate("0", 8190) <> "}"
    assert {:ok, %{"n" => number}} = ResultDocument.decode(at_limit, @schema)
    assert number == 0.0
    over_limit = ~s({"n":0.) <> String.duplicate("0", 8191) <> "}"
    assert {:error, _} = ResultDocument.decode(over_limit, @schema)
  end

  test "rejects malformed JSON, non-object roots and non-JSON Elixir values" do
    for bytes <- [
          "",
          "[]",
          "null",
          "1",
          "true",
          ~s({"x":01}),
          ~s({"x":NaN}),
          ~S({"x":"\uD800"}),
          <<255>>
        ] do
      assert {:error, _} = ResultDocument.decode(bytes, @schema)
    end

    for value <- [[], nil, %{x: 1}, %{"x" => :atom}, %{"x" => self()}, %{"x" => [1 | 2]}, %URI{}] do
      assert {:error, _} = ResultDocument.encode(value, @schema)
    end
  end

  defp sized_document(target) do
    base = %{"items" => List.duplicate(String.duplicate("x", 8192), 511), "pad" => ""}
    Map.put(base, "pad", String.duplicate("x", target - byte_size(Jason.encode!(base))))
  end
end
