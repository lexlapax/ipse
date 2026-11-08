defmodule Ipse.Extension.CollectionManagedRetentionTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection.ManagedRetention, as: Retention
  @day 86_400_000

  defp fixture do
    first = 1_800_000_000_000
    lineage = JSON.sha256("synthetic support")
    value = JSON.sha256("synthetic literal bytes")
    recipe = JSON.sha256("synthetic literal recipe")

    candidate = %{
      "kind" => "literal_source",
      "lineage" => lineage,
      "key" => "note." <> lineage,
      "recipe_sha256" => recipe,
      "category" => "ordinary",
      "max_age_ms" => 90 * @day
    }

    anchor = %{
      "clocks" => [first, first + 90 * @day, nil, nil],
      "choice" => nil,
      "retirement" => nil
    }

    live =
      Enum.map([lineage, value, recipe, JSON.sha256("original publication policy")], fn hash ->
        hash |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)
      end) ++ [number(first), number(first + 90 * @day), 0, 0]

    {candidate, value, anchor, live, first}
  end

  # Pure capsule syntax fixture, not a native permit or independently signed state.
  defp choice(candidate, value, policy, at) do
    challenge = String.duplicate("a", 16)

    %{
      "version" => 2,
      "kind" => "native_management",
      "event_id" => Usage.id(),
      "display_sha256" => JSON.sha256("complete synthetic review"),
      "challenge" => challenge,
      "target_key" => candidate["key"],
      "target_value_sha256" => value,
      "lineage" => candidate["lineage"],
      "observed_at_ms" => at,
      "policy" => policy,
      "reason" => "Explicit pure fixture",
      "input_sha256" => JSON.sha256(Retention.command(policy) <> " " <> challenge)
    }
  end

  defp number(nil), do: nil
  defp number(value), do: value |> Integer.to_string(36) |> String.downcase()

  @tag :managed_expiry
  test "automatic clocks expire exactly at the original baseline and a read never renews them" do
    {candidate, value, anchor, live, first} = fixture()
    assert {:ok, metadata} = Retention.metadata(candidate, value, anchor, live)
    refute Map.has_key?(metadata, "choice")
    assert Retention.eligible_metadata?(candidate, value, metadata, first + 90 * @day - 1)
    refute Retention.eligible_metadata?(candidate, value, metadata, first + 90 * @day)
    assert anchor["clocks"] == [first, first + 90 * @day, nil, nil]
    refute Retention.expired_metadata?(candidate, value, metadata, first + 90 * @day - 1)
    assert Retention.expired_metadata?(candidate, value, metadata, first + 90 * @day)
    assert Retention.expired_metadata?(candidate, value, metadata, first + 365 * @day)
  end

  @tag :managed_expiry
  test "a native choice has its own deadline while original baseline and source identity remain bound" do
    {candidate, value, anchor, live, first} = fixture()

    for policy <- [
          %{"kind" => "pin"},
          %{"kind" => "ordinary"},
          %{"kind" => "duration", "duration_ms" => 2 * @day}
        ] do
      at = first + @day
      capsule = choice(candidate, value, policy, at)
      assert {:ok, category, deadline} = Retention.selected(policy, at)

      live =
        live
        |> List.replace_at(5, number(deadline))
        |> List.replace_at(6, if(category == "pin", do: 3, else: 0))

      assert {:ok, metadata} =
               Retention.metadata(candidate, value, %{anchor | "choice" => capsule}, live)

      assert metadata["category"] == category and metadata["valid_until_ms"] == deadline
      assert metadata["choice"] == capsule
      assert Retention.eligible_metadata?(candidate, value, metadata, at)
      refute Retention.eligible_metadata?(candidate, value, metadata, at - 1)
      if deadline, do: refute(Retention.eligible_metadata?(candidate, value, metadata, deadline))

      if deadline,
        do: assert(Retention.expired_metadata?(candidate, value, metadata, deadline)),
        else: refute(Retention.expired_metadata?(candidate, value, metadata, first + 1000 * @day))

      refute Retention.eligible_metadata?(
               candidate,
               JSON.sha256("substituted value"),
               metadata,
               at
             )

      assert anchor["clocks"] == [first, first + 90 * @day, nil, nil]
    end
  end

  test "malformed or mismatched saved choices cannot become current retention metadata" do
    {candidate, value, anchor, live, first} = fixture()
    capsule = choice(candidate, value, %{"kind" => "pin"}, first)
    live = live |> List.replace_at(5, nil) |> List.replace_at(6, 3)

    for altered <- [
          Map.put(capsule, "lineage", JSON.sha256("other support")),
          Map.put(capsule, "target_value_sha256", JSON.sha256("other value")),
          Map.put(capsule, "input_sha256", JSON.sha256("yes")),
          Map.put(capsule, "observed_at_ms", first - 1),
          Map.put(capsule, "extra", "authority"),
          choice(candidate, value, %{"kind" => "session"}, first)
        ] do
      assert {:error, :managed_retention_refused} =
               Retention.metadata(candidate, value, %{anchor | "choice" => altered}, live)
    end

    assert {:error, :managed_retention_refused} =
             Retention.metadata(
               candidate,
               value,
               %{
                 anchor
                 | "choice" => capsule,
                   "retirement" => %{"target_kind" => "native_literal_note", "at_ms" => first}
               },
               live
             )
  end

  @tag :future_lineage
  test "unconnected future-lineage choice cannot authorize either current or changed value" do
    {candidate, value, anchor, live, first} = fixture()
    at = first + @day
    policy = %{"kind" => "duration", "duration_ms" => 2 * @day}
    original = choice(candidate, value, policy, at)
    future = original |> Map.put("version", 3) |> Map.put("kind", "native_lineage_management")
    later_value = JSON.sha256("later same-lineage literal value")

    packed_value =
      later_value |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)

    live = live |> List.replace_at(1, packed_value) |> List.replace_at(5, number(at + 2 * @day))

    assert {:error, _} =
             Retention.metadata(candidate, later_value, %{anchor | "choice" => future}, live)

    original_live =
      live
      |> List.replace_at(
        1,
        value |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)
      )

    assert {:error, _} =
             Retention.metadata(candidate, value, %{anchor | "choice" => future}, original_live)

    assert {:error, _} =
             Retention.metadata(candidate, later_value, %{anchor | "choice" => original}, live)
  end

  test "relative previews, duration overflow and coverage reductions use the closed production policies" do
    assert Retention.deadline_rule(%{"kind" => "ordinary"}) ==
             %{"basis" => "native_confirmation_time", "duration_ms" => 90 * @day}

    assert Retention.deadline_rule(%{"kind" => "pin"}) == nil

    assert {:error, :managed_retention_refused} =
             Retention.selected(
               %{"kind" => "duration", "duration_ms" => 9_007_199_254_740_991},
               1
             )

    for policy <- [
          %{"kind" => "duration", "duration_ms" => 0},
          %{"kind" => "pin", "extra" => true},
          %{"kind" => "history"}
        ] do
      refute Retention.policy?(policy)
    end

    assert Retention.history_gap?("current", %{"kind" => "ordinary"})
    assert Retention.history_gap?("pin", %{"kind" => "duration", "duration_ms" => @day})
    refute Retention.history_gap?("current", %{"kind" => "pin"})
  end
end
