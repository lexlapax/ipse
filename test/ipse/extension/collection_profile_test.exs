defmodule Ipse.Extension.Collection.ProfileTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.Profile

  test "document physical allocation reserves the complete unchanged notes budget" do
    assert {:ok, notes} = Profile.fetch(Profile.notes())
    assert {:ok, documents} = Profile.fetch(Profile.documents())
    assert notes["value_bytes"] == 6144 and notes["data_bytes"] == 24 * 1024 * 1024
    assert notes["total_bytes"] == 64 * 1024 * 1024
    assert documents["notes_reserved_bytes"] == notes["total_bytes"]
    assert documents["total_bytes"] - documents["reserved_bytes"] == 192 * 1024 * 1024
    assert documents["data_bytes"] < documents["total_bytes"] - documents["reserved_bytes"]
    assert {:ok, targets} = Profile.targets(Profile.documents())

    assert Map.take(targets, ~w(sources extracted_bytes chunks entities assertions)) ==
             %{
               "sources" => 1000,
               "extracted_bytes" => 20 * 1024 * 1024,
               "chunks" => 10_000,
               "entities" => 5000,
               "assertions" => 20_000
             }

    refute targets["qualified"]
  end

  test "unknown budgets refuse and trusted temporary selection always restores" do
    assert {:error, :unknown_collection_profile} = Profile.fetch(%{"total_bytes" => 999_999_999})

    assert {:error, :unknown_collection_profile} =
             Profile.run("custom", fn -> flunk("custom budget entered") end)

    assert Profile.selected() == Profile.notes()

    assert_raise RuntimeError, fn ->
      Profile.run(Profile.documents(), fn ->
        assert Profile.limit(:value_bytes) == 65_536
        raise "selection cleanup"
      end)
    end

    assert Profile.selected() == Profile.notes()
  end
end
