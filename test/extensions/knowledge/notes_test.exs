Code.require_file("../../../extensions/knowledge/src/notes.ex", __DIR__)

defmodule IpseKnowledge.NotesTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Notes, as: N
  @day 86_400_000

  defp attrs(category \\ "ordinary") do
    %{
      "id" => Ipse.JSON.sha256("claim"),
      "lineage" => Ipse.JSON.sha256("admitted span"),
      "text" => "Acme has owner Alex",
      "evidence" => %{"quote" => "Alex owns Acme", "source" => "event:1"},
      "category" => category,
      "reason" => "direct admitted observation",
      "observed_at_ms" => 0,
      "event_at_ms" => nil
    }
  end

  test "ordinary notes expire at 90 days; reads do not renew persistent categories" do
    assert {:ok, ordinary} = N.new(attrs(), 0)
    assert ordinary["expires_at_ms"] == 90 * @day
    assert N.eligible?(ordinary, 89 * @day)
    refute N.eligible?(ordinary, 90 * @day)

    for category <- ~w(pin preference current) do
      assert {:ok, note} = N.new(attrs(category), 0)
      assert N.eligible?(note, 365 * @day)
      assert note["expires_at_ms"] == nil
      assert N.coverage(note, 365 * @day)["event_at_ms"] == nil
    end
  end

  test "first temporal update after day 90 retains prior support for a further year" do
    assert {:ok, old} = N.new(attrs("current"), 0)
    replacement = attrs("current") |> Map.put("text", "Acme has owner Blair")
    assert {:ok, result} = N.supersede(old, replacement, 100 * @day)
    assert result["history"]["evidence"] == old["evidence"]
    assert result["history"]["expires_at_ms"] == 465 * @day
    assert N.eligible?(result["history"], 464 * @day)
    refute N.eligible?(result["history"], 465 * @day)
    assert N.eligible?(result["current"], 900 * @day)
    assert {:ok, pin} = N.new(attrs("pin"), 0)
    assert {:ok, pinned} = N.supersede(pin, replacement, 100 * @day)
    assert pinned["history"]["expires_at_ms"] == nil
  end

  test "one-step downgrade persists against paraphrases with the same admitted lineage" do
    assert {:ok, current} = N.new(attrs("preference"), 0)

    assert {:ok, reduced} =
             N.retention(current, %{"kind" => "ordinary"}, "operator override", 10 * @day)

    assert reduced["advance_floor"]
    assert reduced["note"]["category"] == "ordinary"
    assert reduced["note"]["expires_at_ms"] == 100 * @day

    assert {:ok, recaptured} =
             N.new(
               Map.put(attrs("preference"), "text", "Same preference paraphrased"),
               99 * @day,
               reduced["override"]
             )

    assert recaptured["category"] == "ordinary"
    assert recaptured["expires_at_ms"] == 100 * @day
    refute N.eligible?(recaptured, 101 * @day)
    assert {:ok, forgotten} = N.forget(current, "operator forget", 11 * @day)
    assert forgotten["note"] == nil
    assert {:suppressed, _} = N.new(attrs("pin"), 1000 * @day, forgotten["override"])

    assert {:error, :invalid_retention} =
             N.new(
               Map.put(attrs(), "lineage", Ipse.JSON.sha256("other")),
               0,
               forgotten["override"]
             )
  end

  test "historical reductions disclose gaps without deleting unrelated shared evidence" do
    assert {:ok, old} = N.new(attrs("current"), 0)
    assert {:ok, result} = N.supersede(old, attrs("current"), 100 * @day)

    assert {:ok, reduced} =
             N.retention(
               result["history"],
               %{"kind" => "duration", "duration_ms" => @day},
               "selected history only",
               101 * @day
             )

    assert reduced["historical_gap"]
    assert reduced["note"]["expires_at_ms"] == 102 * @day
    assert result["current"]["expires_at_ms"] == nil
    assert {:ok, [expired]} = N.expired([reduced["note"], result["current"]], 103 * @day)
    assert expired == reduced["note"]
    assert N.valid_override?(reduced["override"])
  end

  test "complete record plus evidence must fit maximum value; malformed policy cannot promote" do
    assert {:error, :invalid_note} =
             N.new(Map.put(attrs(), "evidence", %{"quote" => String.duplicate("x", 6144)}), 0)

    assert {:ok, note} = N.new(attrs(), 0)

    assert {:error, :invalid_retention} =
             N.retention(note, %{"kind" => "ordinary", "extra" => true}, "override", 0)

    assert {:error, :invalid_retention} =
             N.retention(note, %{"kind" => "duration", "duration_ms" => -1}, "override", 0)
  end

  test "exact maximum current values retain their full evidence through history and operator policy changes" do
    attrs = attrs("current") |> put_in(["evidence", "padding"], "")
    assert {:ok, initial} = N.new(attrs, 0)
    padding = String.duplicate("x", 6144 - byte_size(Jason.encode!(initial)))
    attrs = put_in(attrs, ["evidence", "padding"], padding)
    assert {:ok, current} = N.new(attrs, 0)
    assert byte_size(Jason.encode!(current)) == 6144
    assert {:ok, result} = N.supersede(current, attrs("current"), 100 * @day)
    assert result["history"]["evidence"] == current["evidence"]
    assert byte_size(Jason.encode!(result["history"])) <= 6144

    assert {:ok, changed} =
             N.retention(current, %{"kind" => "ordinary"}, String.duplicate("r", 256), 101 * @day)

    assert changed["note"]["evidence"] == current["evidence"]
    assert byte_size(Jason.encode!(changed["note"])) <= 6144
    assert changed["override"]["reason"] == String.duplicate("r", 256)
  end
end
