defmodule Ipse.JSONTest do
  use ExUnit.Case, async: true

  test "bounded decoding counts encoded bytes before parsing" do
    boundary = "\"" <> String.duplicate("x", 32_766) <> "\""
    assert {:ok, value} = Ipse.JSON.decode_bounded(boundary)
    assert byte_size(value) == 32_766
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded(" " <> boundary)
    assert {:ok, 0} = Ipse.JSON.decode_bounded("0", 1)
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded(" 0", 1)

    for limit <- [0, -1, 1_048_577, nil, "10"] do
      assert {:error, :invalid_json} = Ipse.JSON.decode_bounded("0", limit)
    end

    assert {:ok, nil} = Ipse.JSON.decode_bounded("null", 1_048_576)
    maximum = "\"" <> String.duplicate("x", 1_048_574) <> "\""
    assert {:ok, _} = Ipse.JSON.decode_bounded(maximum, 1_048_576)
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded(" " <> maximum, 1_048_576)
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded(nil)
  end

  test "decoded duplicate keys refuse even when escaped or nested" do
    for bytes <- [
          ~s({"a":1,"a":2}),
          ~S({"a":1,"\u0061":2}),
          ~s([{"outer":{"a":1,"a":2}}])
        ] do
      assert {:error, :duplicate_key} = Ipse.JSON.decode_bounded(bytes)
    end

    assert {:ok, [%{"a" => 1}, %{"a" => 2}]} =
             Ipse.JSON.decode_bounded(~s([{"a":1},{"a":2}]))

    assert {:error, %Jason.DecodeError{}} = Ipse.JSON.decode_bounded("{")
  end

  test "the bounded decoder retains its depth limit and unique decoding has an explicit depth" do
    sixteen = String.duplicate("[", 16) <> "0" <> String.duplicate("]", 16)
    assert {:ok, _} = Ipse.JSON.decode_bounded(sixteen)
    assert {:error, :invalid_json} = Ipse.JSON.decode_bounded("[" <> sixteen <> "]")
    assert {:ok, 0} = Ipse.JSON.decode_unique("0", 0)
    assert {:error, :invalid_json} = Ipse.JSON.decode_unique("[0]", 0)
  end

  test "raw SHA-256 hashes bytes and accepts iodata" do
    expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    assert Ipse.JSON.sha256("abc") == expected
    assert Ipse.JSON.sha256(["a", [98], <<99>>]) == expected
    assert Ipse.JSON.sha256(<<0, 255>>) != Ipse.JSON.sha256(<<0>>)
  end

  test "persisted list digests sort nested keys and preserve JSON scalar encoding" do
    values = [%{"z" => 1, "a" => [%{two: 2, one: 1}]}, [true, nil, -0.0], "é 🐚"]
    canonical = ~s([{"a":[{"one":1,"two":2}],"z":1},[true,null,-0.0],"é 🐚"])
    assert Ipse.JSON.digest(values) == Ipse.JSON.sha256(canonical)

    assert Ipse.JSON.digest([]) ==
             "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"

    assert Ipse.JSON.digest(values) ==
             Ipse.JSON.digest(Jason.decode!(Jason.encode!(values)))

    assert Ipse.JSON.digest([%{"alpha" => 2, alpha: 1}]) ==
             Ipse.JSON.sha256(~s([{"alpha":1,"alpha":2}]))

    assert_raise FunctionClauseError, fn -> apply(Ipse.JSON, :digest, [%{}]) end
    assert_raise Protocol.UndefinedError, fn -> Ipse.JSON.digest([{:not, :json}]) end
  end
end
