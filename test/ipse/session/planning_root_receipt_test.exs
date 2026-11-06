defmodule Ipse.Session.PlanningRootReceiptTest do
  use ExUnit.Case, async: true

  alias Ipse.JSON
  alias Ipse.Session.{ManagedLineage, ManagedReads, ManagedReference, Saved}

  # Historical synthetic-only journey documented and hashed in the archive's
  # own-root-transition.md and manifest; this test reads the journal as data.
  @journal "docs/archive/2026-10-26-p30-p31-implementation/own-root-transition/journals/model.jsonl"
  @sha "3bcc8ba35e6159305001e1c3ba36bf72ea3d5d001061d779b27df0d492ec4037"

  defp fixture do
    bytes = File.read!(@journal)
    assert JSON.sha256(bytes) == @sha
    events = bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    session = get_in(hd(events), ["metadata", "source_origin", "session_id"])

    limit =
      Enum.find_index(events, fn event ->
        event["type"] == "managed_preflight_result" and
          get_in(event, ["projection", "type"]) == "managed_root_transition"
      end)

    prefix = Enum.take(events, limit)
    {:ok, saved} = Saved.restore(prefix, session)
    {:ok, dependencies} = ManagedLineage.dependencies(saved.managed_lineage, saved.messages)
    [root] = dependencies

    receipt_index =
      Enum.find_index(prefix, fn event ->
        event["type"] == "managed_read_observed" and root in (event["dependencies"] || [])
      end)

    receipt = Enum.at(prefix, receipt_index)

    action_index =
      Enum.find_index(prefix, fn event ->
        event["type"] == "extension_action_result" and
          event["operation_id"] == receipt["operation_id"]
      end)

    action = Enum.at(prefix, action_index)

    intent_index =
      Enum.find_index(prefix, fn event ->
        event["type"] == "extension_action_intent" and
          event["operation_id"] == receipt["operation_id"]
      end)

    intent = Enum.at(prefix, intent_index)

    assert Ipse.Extension.Actions.valid_result?(action)
    assert Ipse.Extension.Actions.result_intent(action) == intent
    assert ManagedReads.valid?(receipt, session, intent, action["outcome"]["value"])

    {prefix, session, saved, root, receipt_index, receipt, action_index, action, intent_index,
     intent}
  end

  test "actual committed root receipts permit planning; forged observations or results do not replay" do
    {events, session, saved, root, receipt_index, receipt, action_index, action, _, _} = fixture()
    state = saved.managed_lineage
    assert state.root_observations[JSON.digest([root])] === true

    for type <- ~w(planning_decision_accepted planning_decision_save_started) do
      assert {:ok, ^state} =
               ManagedLineage.advance(
                 state,
                 %{"type" => type, "version" => 2},
                 saved.messages,
                 saved.messages
               )
    end

    record_key = "note." <> JSON.sha256("synthetic record")

    record =
      root
      |> Map.put("version", 4)
      |> Map.put("subject", %{
        "kind" => "record_observation",
        "key" => record_key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => record_key}]),
        "result_sha256" => JSON.digest([%{"record" => nil}]),
        "publication_policy_sha256" => nil,
        "record" => nil,
        "validity" => nil
      })

    assert ManagedReference.dependency?(record)
    message = %{"role" => "assistant", "content" => "Synthetic mixed proposal."}
    producer = %{"kind" => "assistant", "id" => Ipse.Usage.id(), "parent_id" => nil}

    {:ok, _, reference} =
      ManagedReference.admit(state.reference, producer, length(saved.messages), message, [
        root,
        record
      ])

    mixed = %{state | reference: reference}
    mixed_messages = saved.messages ++ [message]

    assert {:error, :managed_lineage_unavailable} =
             ManagedLineage.advance(
               mixed,
               %{"type" => "planning_decision_accepted", "version" => 2},
               mixed_messages,
               mixed_messages
             )

    for altered <- [
          List.replace_at(
            events,
            receipt_index,
            Map.put(receipt, "result_sha256", JSON.sha256("forged"))
          ),
          List.replace_at(
            events,
            action_index,
            put_in(action, ["outcome", "value", "generation"], 999)
          ),
          List.update_at(
            events,
            0,
            &put_in(&1, ["metadata", "semantic_admission", "pin", "epoch"], 999)
          )
        ] do
      assert {:error, _} = Saved.restore(altered, session)
    end
  end

  test "validated nonempty metadata index cannot become a root-only planning prerequisite" do
    {events, session, saved, root, _, _, _, action, intent_index, intent} = fixture()
    {:ok, before} = Saved.restore(Enum.take(events, intent_index), session)
    messages = before.messages
    {:ok, state} = ManagedLineage.advance(before.managed_lineage, intent, messages, messages)

    value =
      action["outcome"]["value"]
      |> Map.put("generation", 1)
      |> Map.put("count", 1)
      |> Map.put("records", [
        %{
          "key" => "note." <> JSON.sha256("synthetic"),
          "revision" => 1,
          "bytes" => 12,
          "sha256" => JSON.sha256("synthetic value")
        }
      ])

    dependency =
      root
      |> put_in(["collection", "generation"], 1)
      |> put_in(["collection", "root_state"], "present")
      |> put_in(["collection", "root_sha256"], JSON.sha256("synthetic root"))
      |> put_in(["collection", "manifest_sha256"], JSON.sha256("synthetic manifest"))
      |> put_in(["subject", "result_sha256"], JSON.digest([value]))

    assert ManagedReference.dependency?(dependency)
    {:ok, receipt} = ManagedReads.prepare(session, intent, value, [dependency])
    {:ok, result} = Ipse.Extension.Actions.result(intent, %{"status" => "ok", "value" => value})
    assert ManagedReads.valid?(receipt, session, intent, value)
    {:ok, state} = ManagedLineage.advance(state, receipt, messages, messages)
    {:ok, state} = ManagedLineage.advance(state, result, messages, messages)
    assert state.root_observations[JSON.digest([dependency])] == "metadata_only"

    message = %{"role" => "assistant", "content" => "Synthetic proposal."}
    producer = %{"kind" => "assistant", "id" => Ipse.Usage.id(), "parent_id" => nil}

    {:ok, _, reference} =
      ManagedReference.admit(state.reference, producer, length(messages), message, [dependency])

    state = %{state | reference: reference}
    input = messages ++ [message]

    for type <- ~w(planning_decision_accepted planning_decision_save_started) do
      assert {:error, :managed_lineage_unavailable} =
               ManagedLineage.advance(state, %{"type" => type, "version" => 2}, input, input)
    end

    {:ok, _, mixed_reference} =
      ManagedReference.admit(
        before.managed_lineage.reference,
        producer,
        length(messages),
        message,
        [root, dependency]
      )

    mixed = %{
      state
      | reference: mixed_reference,
        root_observations:
          Map.merge(saved.managed_lineage.root_observations, state.root_observations)
    }

    assert {:error, :managed_lineage_unavailable} =
             ManagedLineage.advance(
               mixed,
               %{"type" => "planning_decision_accepted", "version" => 2},
               input,
               input
             )
  end
end
