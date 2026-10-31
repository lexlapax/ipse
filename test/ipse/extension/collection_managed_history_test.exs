defmodule Ipse.Extension.CollectionManagedHistoryTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON
  alias Ipse.Extension.Collection.ManagedRetention, as: Retention
  @day 86_400_000

  defp history(category, deadline) do
    first = 1_800_000_000_000
    at = first + @day
    lineage = JSON.sha256("old support")
    value = JSON.sha256("old value")
    recipe = JSON.sha256("recipe")
    next = JSON.sha256("new support")

    candidate = %{
      "kind" => "literal_source",
      "lineage" => lineage,
      "key" => "note." <> lineage,
      "recipe_sha256" => recipe,
      "category" => category,
      "max_age_ms" => if(category == "ordinary", do: 90 * @day, else: nil)
    }

    baseline = if category == "ordinary", do: first + 90 * @day, else: nil

    anchor = %{
      "clocks" => [first, baseline, nil, nil],
      "choice" => nil,
      "retirement" => %{
        "record_key" => "note." <> next,
        "record_value_sha256" => JSON.sha256("new value"),
        "at_ms" => at
      }
    }

    packed = fn hash ->
      hash |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)
    end

    number = fn n -> if n, do: n |> Integer.to_string(36) |> String.downcase(), else: nil end

    live =
      Enum.map([lineage, value, recipe, JSON.sha256("policy")], packed) ++
        [number.(first), number.(deadline.(first, at)), 4, 2]

    {candidate, value, anchor, live, first, at}
  end

  test "ordinary history preserves the original deadline and authenticates the exact successor edge" do
    {candidate, value, anchor, live, first, at} =
      history("ordinary", fn first, _ -> first + 90 * @day end)

    assert {:ok, metadata} = Retention.history_metadata(candidate, value, anchor, live)
    assert metadata["category"] == "history" and metadata["previous_category"] == "ordinary"
    assert metadata["valid_until_ms"] == first + 90 * @day
    assert metadata["successor"]["key"] == anchor["retirement"]["record_key"]
    assert Retention.eligible_history_metadata?(metadata, at)
    refute Retention.eligible_history_metadata?(metadata, first + 90 * @day)

    assert {:error, :managed_retention_refused} =
             Retention.metadata(candidate, value, anchor, live)

    assert {:error, :managed_retention_refused} =
             Retention.history_metadata(candidate, value, anchor, List.replace_at(live, 7, 0))

    assert {:error, :managed_retention_refused} =
             Retention.history_metadata(candidate, value, anchor, List.replace_at(live, 5, nil))

    same = put_in(anchor, ["retirement", "record_key"], candidate["key"])

    assert {:error, :managed_retention_refused} =
             Retention.history_metadata(candidate, value, same, live)
  end

  test "temporal history expires 365 days after review without changing the original first admission" do
    {candidate, value, anchor, live, first, at} =
      history("current", fn _, at -> at + 365 * @day end)

    assert {:ok, metadata} = Retention.history_metadata(candidate, value, anchor, live)
    assert metadata["first_admitted_ms"] == first
    assert metadata["valid_until_ms"] == at + 365 * @day
    assert Retention.eligible_history_metadata?(metadata, at + 365 * @day - 1)
    refute Retention.eligible_history_metadata?(metadata, at + 365 * @day)

    assert {:error, :managed_retention_refused} =
             Retention.history_metadata(candidate, value, anchor, List.replace_at(live, 5, nil))
  end

  test "pinned history remains persistent and cannot be interpreted as ordinary correction" do
    assert Retention.history_rule(%{"category" => "pin", "valid_until_ms" => nil}, "temporal") ==
             nil

    assert {:ok, nil} =
             Retention.history_deadline(
               %{"category" => "pin", "valid_until_ms" => nil},
               "temporal",
               100
             )

    assert {:error, :managed_retention_refused} =
             Retention.history_rule(%{"category" => "pin", "valid_until_ms" => nil}, "ordinary")
  end
end
