defmodule Ipse.Extension.CollectionCompactChoiceTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.ManagedPages
  alias Ipse.JSON

  test "signed-page syntax binds a full native capsule to a versioned compact commitment" do
    lineage = JSON.sha256("lineage")

    choice = %{
      "version" => 2,
      "kind" => "native_management",
      "lineage" => lineage,
      "event_id" => String.duplicate("a", 32),
      "display_sha256" => JSON.sha256("display"),
      "challenge" => "0123456789abcdef",
      "target_key" => "note." <> lineage,
      "target_value_sha256" => JSON.sha256("value"),
      "observed_at_ms" => 1_800_000_000_000,
      "policy" => %{"kind" => "duration", "duration_ms" => 1_000},
      "reason" => "Original review",
      "input_sha256" => JSON.sha256("duration 0123456789abcdef")
    }

    assert {:ok, commitment} = ManagedPages.compact_choice(lineage, choice)
    assert ManagedPages.compact_choice?(lineage, commitment, choice)
    refute ManagedPages.compact_choice?(lineage, commitment, Map.put(choice, "reason", "Altered"))
    refute ManagedPages.compact_choice?(JSON.sha256("different"), commitment, choice)
    refute ManagedPages.compact_choice?(lineage, Map.put(commitment, "version", 2), choice)

    row = %{
      "clocks" => [1_800_000_000_000, 1_800_000_001_000, nil, nil],
      "choice" => commitment,
      "retirement" => %{
        "record_key" => "note." <> JSON.sha256("successor"),
        "record_value_sha256" => JSON.sha256("new"),
        "at_ms" => 1_800_000_000_500
      }
    }

    assert {:ok, body} = ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => row})
    assert {:ok, page} = ManagedPages.unpack(:anchor, ManagedPages.zero(:anchor), body)
    assert page.entries[lineage] == row
  end
end
