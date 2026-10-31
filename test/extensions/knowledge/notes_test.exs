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

  test "a note or historical version is unavailable before its own creation" do
    assert {:ok, current} = N.new(attrs("current"), 10 * @day)
    refute N.eligible?(current, 9 * @day)
    refute N.coverage(current, 9 * @day)["available"]
    assert N.eligible?(current, 10 * @day)

    assert {:ok, changed} = N.supersede(current, attrs("current"), 100 * @day)
    refute N.eligible?(changed["history"], 99 * @day)
    assert N.eligible?(changed["history"], 100 * @day)
    refute N.valid?(Map.put(changed["history"], "superseded_at_ms", 9 * @day))

    assert {:error, :invalid_note} =
             N.new(Map.put(attrs(), "observed_at_ms", 11 * @day), 10 * @day)
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
    assert {:ok, preference} = N.new(attrs("preference"), 0)
    assert {:ok, changed} = N.supersede(preference, attrs("preference"), 100 * @day)
    assert changed["history"]["expires_at_ms"] == 465 * @day
  end

  test "same-lineage duration and session overrides bind current and historical derivatives without renewal" do
    assert {:ok, old} = N.new(attrs("current"), 0)

    assert {:ok, changed} =
             N.retention(
               old,
               %{"kind" => "duration", "duration_ms" => 7 * @day},
               "operator choice",
               10 * @day
             )

    assert {:ok, result} = N.supersede(old, attrs("current"), 20 * @day, changed["override"])
    assert result["current"]["expires_at_ms"] == 17 * @day
    assert result["history"]["expires_at_ms"] == 17 * @day
    refute N.eligible?(result["history"], 20 * @day)

    assert {:error, :lineage_override_required} =
             N.supersede(changed["note"], attrs("current"), 20 * @day)

    assert {:ok, forgotten} = N.forget(old, "operator forget", 11 * @day)

    assert {:suppressed, override} =
             N.supersede(old, attrs("current"), 1000 * @day, forgotten["override"])

    assert override == forgotten["override"]
  end

  test "a new unrelated claim cannot lend its override to old support; ordinary corrections keep their deadline" do
    assert {:ok, old} = N.new(attrs("current"), 0)

    replacement =
      Map.put(attrs("current"), "lineage", Ipse.JSON.sha256("unrelated admitted source"))

    assert {:ok, other} = N.new(replacement, 0)

    assert {:ok, changed} =
             N.retention(other, %{"kind" => "ordinary"}, "new claim only", 10 * @day)

    assert {:error, :separate_lineage_overrides_required} =
             N.supersede(old, replacement, 20 * @day, changed["override"])

    assert {:ok, ordinary} = N.new(attrs(), 0)
    assert {:ok, corrected} = N.supersede(ordinary, attrs(), 20 * @day)
    assert corrected["history"]["expires_at_ms"] == 90 * @day
    assert corrected["current"]["expires_at_ms"] == 90 * @day

    assert {:error, :invalid_note} = N.supersede(ordinary, attrs(), 90 * @day)

    for category <- ~w(pin preference current) do
      assert {:error, :invalid_note} = N.supersede(ordinary, attrs(category), 20 * @day)
    end

    assert {:ok, selected} =
             N.retention(ordinary, %{"kind" => "pin"}, "explicit choice", 20 * @day)

    assert {:ok, pinned} = N.supersede(ordinary, attrs("pin"), 30 * @day, selected["override"])
    assert pinned["current"]["category"] == "pin"

    new_source = Map.put(attrs(), "lineage", Ipse.JSON.sha256("new evidence"))
    assert {:ok, fresh} = N.supersede(ordinary, new_source, 100 * @day)
    assert fresh["current"]["expires_at_ms"] == 190 * @day
  end

  test "one-step downgrade persists against paraphrases with the same admitted lineage" do
    assert {:ok, current} = N.new(attrs("preference"), 0)

    assert {:ok, reduced} =
             N.retention(current, %{"kind" => "ordinary"}, "operator override", 10 * @day)

    assert reduced["advance_floor"]
    assert reduced["note"]["category"] == "ordinary"
    assert reduced["note"]["expires_at_ms"] == 100 * @day

    assert {:error, :invalid_note} = N.new(attrs("preference"), 9 * @day, reduced["override"])

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

  test "reducing a current temporal claim discloses the loss of its future history policy" do
    assert {:ok, current} = N.new(attrs("current"), 0)

    for policy <- [
          %{"kind" => "ordinary"},
          %{"kind" => "duration", "duration_ms" => 7 * @day},
          %{"kind" => "session"}
        ] do
      assert {:ok, receipt} = N.retention(current, policy, "operator choice", 10 * @day)
      assert receipt["historical_gap"]
    end

    assert {:ok, pinned} = N.retention(current, %{"kind" => "pin"}, "operator choice", 10 * @day)
    refute pinned["historical_gap"]
  end

  test "reducing pinned and enduring preference notes warns of potential historical coverage loss" do
    for category <- ~w(pin preference),
        policy <- [%{"kind" => "ordinary"}, %{"kind" => "session"}] do
      assert {:ok, note} = N.new(attrs(category), 0)
      assert {:ok, receipt} = N.retention(note, policy, "reduce", 10 * @day)
      assert receipt["historical_gap"]
    end

    assert {:ok, ordinary} = N.new(attrs(), 0)
    assert {:ok, receipt} = N.retention(ordinary, %{"kind" => "ordinary"}, "ordinary", @day)
    refute receipt["historical_gap"]
  end

  test "new retention choices cannot predate the selected record or its supersession" do
    assert {:ok, current} = N.new(attrs("current"), 10 * @day)

    assert {:error, :invalid_retention} =
             N.retention(current, %{"kind" => "ordinary"}, "earlier", 9 * @day)

    assert {:ok, changed} = N.supersede(current, attrs("current"), 100 * @day)
    history = changed["history"]

    assert {:error, :invalid_retention} =
             N.retention(history, %{"kind" => "session"}, "before supersession", 99 * @day)

    assert {:ok, _} =
             N.retention(history, %{"kind" => "ordinary"}, "at supersession", 100 * @day)
  end

  test "a later retention choice must match and follow the selected prior override" do
    assert {:ok, current} = N.new(attrs("current"), 0)
    assert {:ok, first} = N.retention(current, %{"kind" => "ordinary"}, "first", 20 * @day)
    note = first["note"]
    prior = first["override"]

    assert {:error, :invalid_retention} =
             N.retention(note, %{"kind" => "pin"}, "missing", 21 * @day)

    assert {:error, :invalid_retention} =
             N.retention(note, %{"kind" => "pin"}, "earlier", 19 * @day, prior)

    for bad <- [
          Map.put(prior, "lineage", Ipse.JSON.sha256("other")),
          Map.put(prior, "policy", %{"kind" => "pin"}),
          Map.put(prior, "updated_at_ms", 21 * @day)
        ] do
      assert {:error, :invalid_retention} =
               N.retention(note, %{"kind" => "pin"}, "mismatch", 22 * @day, bad)
    end

    assert {:ok, second} = N.retention(note, %{"kind" => "pin"}, "second", 21 * @day, prior)
    assert second["note"]["category"] == "pin"

    # Matching the effective note cannot authenticate the retained operator reason.
    assert {:ok, _} =
             N.retention(
               note,
               %{"kind" => "pin"},
               "second",
               21 * @day,
               Map.put(prior, "reason", "unverified alternative")
             )

    assert {:ok, forgotten} = N.forget(second["note"], "forget", 22 * @day, second["override"])
    assert is_nil(forgotten["note"])
  end

  test "an ordinary source reason equal to the override marker can use host-checked absence" do
    assert {:ok, note} = N.new(Map.put(attrs(), "reason", "operator override"), 0)
    assert {:error, :invalid_retention} = N.retention(note, %{"kind" => "pin"}, "choice", @day)
    assert {:error, :lineage_override_required} = N.supersede(note, attrs(), @day)
    assert {:ok, correction} = N.supersede(note, attrs(), @day, :absent)
    assert correction["current"]["expires_at_ms"] == 90 * @day

    assert {:ok, result} =
             N.retention(note, %{"kind" => "pin"}, "choice", @day, :absent)

    assert result["note"]["category"] == "pin"

    # The marker is a caller assertion; it cannot prove protected-store absence.
    assert {:ok, _} =
             N.retention(result["note"], %{"kind" => "ordinary"}, "later", 2 * @day, :absent)
  end

  test "an expired note cannot be revived by changing retention without fresh evidence" do
    assert {:ok, note} = N.new(attrs(), 0)

    for policy <- [
          %{"kind" => "pin"},
          %{"kind" => "ordinary"},
          %{"kind" => "duration", "duration_ms" => @day}
        ] do
      assert {:error, :invalid_retention} = N.retention(note, policy, "too late", 90 * @day)
    end

    assert {:ok, forgotten} = N.forget(note, "suppress recapture", 90 * @day)
    assert is_nil(forgotten["note"])
  end

  test "complete record plus evidence must fit maximum value; malformed policy cannot promote" do
    nested = Enum.reduce(1..16, %{"quote" => "support"}, fn _, value -> %{"nested" => value} end)
    assert {:error, :invalid_note} = N.new(Map.put(attrs(), "evidence", nested), 0)

    assert {:error, :invalid_note} =
             N.new(put_in(attrs(), ["evidence", "quote"], String.duplicate("x", 9000)), 0)

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
