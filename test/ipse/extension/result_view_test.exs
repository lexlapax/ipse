defmodule Ipse.Extension.ResultViewTest do
  use ExUnit.Case, async: true

  alias Ipse.Extension.ResultView

  @id String.duplicate("a", 64)
  @sha String.duplicate("b", 64)
  @descriptor %{
    "version" => 1,
    "kind" => "saved.result",
    "output_id" => @id,
    "byte_count" => 100,
    "sha256" => @sha,
    "historical_receipt" => true
  }

  test "enumerates all 4096 object names in decoded byte order without skipping children" do
    value = Map.new(0..4095, fn i -> {String.pad_leading(to_string(i), 4, "0"), i} end)
    pages = pages(value, initial([]))
    children = Enum.flat_map(pages, & &1["children"])

    assert Enum.map(children, & &1["ordinal"]) == Enum.to_list(0..4095)
    assert Enum.map(children, & &1["name"]) == Enum.sort(Map.keys(value))
    assert Enum.map(children, & &1["value"]) == Enum.to_list(0..4095)
    assert Enum.all?(children, & &1["name_complete"])
    assert Enum.all?(pages, &(length(&1["children"]) <= 16))
    assert Enum.all?(pages, &(&1["total_children"] == 4096))
    assert List.last(pages)["complete"]
    assert List.last(pages)["next"] == nil

    assert {:ok, terminal} = read(value, initial([], 4096))
    assert terminal["children"] == []
    assert terminal["complete"]
    assert terminal["offset"] == 4096
    assert {:error, :invalid_saved_result_read} = read(value, initial([], 4097))
  end

  test "reduces child count to fit escaped names and references at full wrapper size" do
    value =
      Map.new(0..31, fn i ->
        {String.duplicate(<<0>>, 128) <> String.pad_leading(to_string(i), 2, "0"), %{"x" => i}}
      end)

    pages = pages(value, initial([]))
    assert length(hd(pages)["children"]) < 16

    assert Enum.flat_map(pages, & &1["children"]) |> Enum.map(& &1["ordinal"]) ==
             Enum.to_list(0..31)

    for page <- pages, child <- page["children"] do
      assert child["type"] == "object"
      refute child["name_complete"]
      assert child["name_reference"]["kind"] == "key"
      assert child["reference"]["kind"] == "children"
      assert {:ok, nested} = read(value, %{"cursor" => child["reference"]})
      assert hd(nested["children"])["value"] == child["ordinal"]
    end
  end

  test "array children preserve all 4096 original positions and value types" do
    value = %{"array" => Enum.to_list(0..4095)}
    children = value |> pages(initial(["array"])) |> Enum.flat_map(& &1["children"])
    assert Enum.map(children, & &1["value"]) == Enum.to_list(0..4095)
    assert Enum.map(children, & &1["ordinal"]) == Enum.to_list(0..4095)
    assert Enum.all?(children, &(&1["type"] == "integer" and &1["name_complete"]))
  end

  test "deep positional references and maximally escaped windows retain wrapper bounds" do
    name = String.duplicate(<<0>>, 8192)
    text = String.duplicate(<<1>>, 8192)
    value = Enum.reduce(1..8, %{name => text}, fn _, child -> %{"nested" => child} end)
    path = List.duplicate("nested", 8)
    assert {:ok, parent} = read(value, initial(path))
    child = hd(parent["children"])
    key_views = pages(value, %{"cursor" => child["name_reference"]})
    string_views = pages(value, %{"cursor" => child["reference"]})
    assert Enum.map_join(key_views, & &1["text"]) == name
    assert Enum.map_join(string_views, & &1["text"]) == text
    assert length(key_views) == 8
    assert length(string_views) == 8
  end

  test "8192-byte escaped UTF8 names are reachable through positional key windows" do
    name = String.duplicate("🙂" <> <<0>>, 1638) <> "xy"
    assert byte_size(name) == 8192
    value = %{name => "value"}
    assert {:ok, root} = read(value, initial([]))
    child = hd(root["children"])
    refute child["name_complete"]
    assert String.valid?(child["name"])
    assert byte_size(child["name"]) <= 128
    assert child["value"] == "value"
    assert child["name_reference"]["path"] == [%{"kind" => "object", "index" => 0}]
    views = pages(value, %{"cursor" => child["name_reference"]})
    assert Enum.map_join(views, & &1["text"]) == name
    assert Enum.all?(views, &(&1["kind"] == "key" and &1["total_bytes"] == 8192))
    assert List.last(views)["complete"]
  end

  test "UTF8 string windows preserve every byte and reject offsets inside a codepoint" do
    text = String.duplicate("🙂" <> <<0>>, 1638) <> "xy"
    value = %{"data" => [text]}
    assert {:ok, parent} = read(value, initial(["data"]))
    child = hd(parent["children"])
    assert child["name"] == "0"
    assert child["type"] == "string"
    assert child["reference"]["kind"] == "string"
    views = pages(value, %{"cursor" => child["reference"]})
    assert Enum.map_join(views, & &1["text"]) == text

    for view <- views do
      assert String.valid?(view["text"])
      assert byte_size(view["text"]) in 1..1024
      assert view["offset"] < 8192
      assert view["target_type"] == "string"
      assert view["total_bytes"] == 8192
    end

    assert {:ok, terminal} = read(value, initial(["data", 0], 8192))
    assert terminal["text"] == ""
    assert terminal["complete"]
    assert terminal["next"] == nil
    assert {:error, :invalid_saved_result_read} = read(value, initial(["data", 0], 1))
    assert {:error, :invalid_saved_result_read} = read(value, initial(["data", 0], 8193))
  end

  test "object ordering uses decoded keys and initial paths resolve exact escaped keys" do
    value = %{"z" => nil, "\"" => false, "\\" => 1.25, "\n" => 2, "é" => "tail"}
    assert {:ok, root} = read(value, initial([]))
    assert Enum.map(root["children"], & &1["name"]) == Enum.sort(Map.keys(value))

    for {key, expected} <- value do
      assert {:ok, result} = read(value, initial([key]))
      assert result["target_type"] in ~w(null boolean number integer string)
      assert Map.get(result, "value", result["text"]) == expected
      assert result["complete"]
    end

    assert {:error, :invalid_saved_result_read} = read(value, initial(["missing"]))
    assert {:error, :invalid_saved_result_read} = read(value, initial([0]))
    assert {:error, :invalid_saved_result_read} = read(value, initial(["z"], 1))
  end

  test "empty containers and strings expose a complete terminal view" do
    value = %{"array" => [], "object" => %{}, "text" => ""}

    for key <- ~w(array object text) do
      assert {:ok, result} = read(value, initial([key]))
      assert result["complete"]
      assert result["next"] == nil
      assert result["offset"] == 0
    end
  end

  test "closed cursors reject foreign identity, kind mismatches and malformed paths" do
    value = %{"array" => [String.duplicate("x", 2000)]}
    assert {:ok, result} = read(value, initial(["array", 0]))
    cursor = result["next"]
    assert {:ok, _} = read(value, %{"cursor" => cursor})

    for bad <- [
          Map.put(cursor, "output_id", String.duplicate("c", 64)),
          Map.put(cursor, "source_sha256", String.duplicate("c", 64)),
          Map.put(cursor, "kind", "children"),
          Map.put(cursor, "kind", "key"),
          Map.put(cursor, "offset", -1),
          Map.put(cursor, "offset", 1.0),
          Map.put(cursor, "extra", true),
          Map.delete(cursor, "offset"),
          Map.put(cursor, "path", [%{"kind" => "array", "index" => 0}]),
          Map.put(cursor, "path", [%{"kind" => "object", "index" => -1}]),
          Map.put(cursor, "path", [%{"kind" => "object", "index" => 1}]),
          Map.put(cursor, "path", [%{"kind" => "object", "index" => 0, "key" => "array"}]),
          Map.put(cursor, "path", List.duplicate(%{"kind" => "object", "index" => 0}, 13))
        ] do
      assert {:error, :invalid_saved_result_read} = read(value, %{"cursor" => bad})
    end

    assert {:error, :invalid_saved_result_read} =
             read(value, %{"cursor" => cursor, "offset" => 0})

    assert {:error, :invalid_saved_result_read} = read(value, Map.put(initial([]), "extra", true))
    assert {:error, :invalid_saved_result_read} = read(value, %{"output_id" => @id})
    assert {:error, :invalid_saved_result_read} = read(value, initial(["array", -1]))
    assert {:error, :invalid_saved_result_read} = read(value, initial(["array", 1]))
  end

  test "descriptor syntax remains closed and references are bound to the original digest" do
    value = %{"x" => 1}

    for bad <- [
          Map.put(@descriptor, "version", 2),
          Map.put(@descriptor, "kind", "other"),
          Map.put(@descriptor, "historical_receipt", false),
          Map.put(@descriptor, "output_id", String.duplicate("A", 64)),
          Map.put(@descriptor, "sha256", "short"),
          Map.put(@descriptor, "byte_count", 0),
          Map.put(@descriptor, "byte_count", 4_194_305),
          Map.put(@descriptor, "extra", true),
          Map.delete(@descriptor, "version")
        ] do
      assert {:error, :invalid_saved_result_read} = ResultView.read(value, bad, initial([]))
    end
  end

  defp pages(value, request, found \\ []) do
    assert {:ok, response} = read(value, request)

    if response["next"] do
      assert response["complete"] == false
      assert response["next"]["offset"] > response["offset"]
      pages(value, %{"cursor" => response["next"]}, [response | found])
    else
      assert response["complete"]
      Enum.reverse([response | found])
    end
  end

  defp read(value, request) do
    result = ResultView.read(value, @descriptor, request)

    if match?({:ok, _}, result) do
      {:ok, response} = result
      assert Ipse.Extension.validate(response) == :ok
      assert byte_size(Jason.encode!(response)) <= 12_000
    end

    result
  end

  defp initial(path, offset \\ 0), do: %{"output_id" => @id, "path" => path, "offset" => offset}
end
