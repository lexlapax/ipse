defmodule Ipse.Extension.CanonicalDigestTest do
  use ExUnit.Case, async: true

  test "public canonical hashes preserve list order and ignore object insertion order" do
    values = [%{"b" => [true, nil, 3], "a" => "é"}]
    reordered = [Map.new([{"a", "é"}, {"b", [true, nil, 3]}])]
    assert {:ok, digest} = Ipse.Extension.canonical_digest(values)
    assert {:ok, ^digest} = Ipse.Extension.canonical_digest(reordered)
    assert digest == Ipse.JSON.digest(values)
    refute Ipse.Extension.canonical_digest([1, 2]) == Ipse.Extension.canonical_digest([2, 1])
  end

  test "private terms and over-bound values refuse before canonical encoding" do
    for values <- [%{}, [:private], [%{private: "key"}], [self()], [String.duplicate("x", 8193)]] do
      assert {:error, :invalid_extension_value} = Ipse.Extension.canonical_digest(values)
    end

    assert {:error, :invalid_extension_value} =
             Ipse.Extension.canonical_digest(Enum.map(1..4097, fn _ -> nil end))
  end
end
