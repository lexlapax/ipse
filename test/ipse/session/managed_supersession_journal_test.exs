Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.ManagedSupersessionJournalTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON
  alias Ipse.Session.ManagedSupersession
  alias Ipse.Test.ManagedPolicy, as: F

  test "reviewed relation binds the complete old and new proof set to exact facts" do
    recipe =
      F.policy()["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    old = F.proof("native_operator_assertion", "old synthetic fact")
    new = F.proof("native_operator_assertion", "new synthetic fact")

    body = %{
      "kind" => "managed_literal_supersession",
      "context" => %{"recipe" => recipe},
      "target" => %{"value" => %{"evidence" => %{"sources" => [old]}}},
      "replacement" => %{"value" => %{"evidence" => %{"sources" => [new]}}},
      "new_source_sha256" => JSON.digest([[new]])
    }

    facts = Map.put(body, "action_sha256", JSON.digest([body]))
    assert {:ok, [^old, ^new]} = ManagedSupersession.reviewed_source_set(facts, recipe)

    same =
      body
      |> put_in(["replacement", "value", "evidence", "sources"], [old])
      |> Map.put("new_source_sha256", JSON.digest([[old]]))

    same = Map.put(same, "action_sha256", JSON.digest([same]))
    assert {:ok, [^old]} = ManagedSupersession.reviewed_source_set(same, recipe)

    forged = put_in(facts, ["replacement", "value", "evidence", "sources"], [old])

    assert {:error, :managed_supersession_refused} =
             ManagedSupersession.reviewed_source_set(forged, recipe)

    forged = Map.put(forged, "action_sha256", JSON.digest([Map.delete(forged, "action_sha256")]))

    assert {:error, :managed_supersession_refused} =
             ManagedSupersession.reviewed_source_set(forged, recipe)

    extra = put_in(body, ["target", "value", "evidence", "sources"], [old, new])
    extra = Map.put(extra, "action_sha256", JSON.digest([extra]))

    assert {:error, :managed_supersession_refused} =
             ManagedSupersession.reviewed_source_set(extra, recipe)

    assert {:error, :managed_supersession_refused} =
             ManagedSupersession.reviewed_source_set(
               facts,
               Map.put(recipe, "override_prefix", "other.")
             )
  end

  test "legacy sessions without the layout do not acquire lifecycle semantics" do
    events = [%{"metadata" => %{}}, %{"type" => "operator_assertion", "legacy" => true}]
    assert :ok = ManagedSupersession.validate_events(events, nil)

    assert {:error, :managed_supersession_refused} =
             ManagedSupersession.validate_events(
               events ++ [%{"type" => "managed_supersession_intent"}],
               nil
             )

    assert {:error, :managed_supersession_refused} =
             ManagedSupersession.validate_events(
               [%{"metadata" => %{"managed_supersession_layout" => "future"}}],
               nil
             )
  end
end
