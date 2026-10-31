defmodule Ipse.Session.ManagedRootTransitionTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session}
  alias Ipse.Session.ManagedLineage

  @journal "docs/archive/2026-10-26-p30-p31-implementation/own-root-transition/journals/model.jsonl"

  defp fixture do
    events =
      @journal |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    id = get_in(hd(events), ["metadata", "source_origin", "session_id"])

    index =
      Enum.find_index(
        events,
        &(&1["type"] == "managed_preflight_result" and
            get_in(&1, ["projection", "type"]) == "managed_root_transition")
      )

    event = Enum.at(events, index)
    {:ok, before} = Session.Saved.restore(Enum.take(events, index), id)
    {events, id, index, event, before}
  end

  test "chronological replay preserves old inputs, guards the notice, and projects the full own-write union" do
    {events, id, _, event, before} = fixture()
    assert {:ok, saved} = Session.Saved.restore(events, id)
    p = event["projection"]
    old_messages = before.messages
    lineage = saved.managed_lineage
    assert map_size(lineage.root_writes) == 1
    assert map_size(lineage.root_transitions) == 3

    assert Enum.all?(lineage.root_transitions, fn {old, new} ->
             Map.has_key?(lineage.dictionary, old) and Map.has_key?(lineage.dictionary, new) and
               lineage.root_observations[old] === true and lineage.root_observations[new] === true
           end)

    notice = Enum.find(saved.messages, &Map.has_key?(&1, "ipse_root_history"))

    assert notice["ipse_root_history"] == %{
             "version" => 1,
             "old_generation" => 0,
             "new_generation" => 1
           }

    assert String.contains?(notice["content"], "historical")
    assert Enum.take(saved.messages, length(old_messages)) === old_messages
    assert JSON.digest(old_messages) == p["before_sha256"]

    assert Enum.any?(lineage.reference.occurrences, fn {_, entry} ->
             entry.position == length(old_messages) and
               entry.dependency_ids == [JSON.digest([p["fresh_dependency"]])]
           end)

    assert Enum.count(events, &(&1["type"] == "input_received")) == 1
    assert Enum.count(events, &(&1["type"] == "managed_source_lookup_prepared")) == 4
  end

  test "forged, missing, moved and altered transition evidence cannot replay" do
    {events, id, index, event, _} = fixture()

    invalid = [
      put_in(event, ["projection", "own_action_sha256"], String.duplicate("0", 64)),
      put_in(event, ["projection", "receipt_sha256"], String.duplicate("0", 64)),
      put_in(event, ["projection", "notice_sha256"], String.duplicate("0", 64)),
      put_in(event, ["projection", "inspection", "floor_anchor"], String.duplicate("0", 32)),
      put_in(event, ["projection", "fresh_observation", "value", "generation"], 2),
      put_in(
        event,
        ["projection", "old_dependencies", Access.at(0), "collection", "generation"],
        9
      ),
      put_in(event, ["projection", "fresh_dependency", "policy_generation"], 99)
    ]

    for altered <- invalid do
      assert {:error, _} = Session.Saved.restore(List.replace_at(events, index, altered), id)
    end

    assert {:error, _} = Session.Saved.restore(List.delete_at(events, index), id)

    action_index =
      Enum.find_index(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "collection.managed")
      )

    assert {:error, _} = Session.Saved.restore(List.delete_at(events, action_index), id)
  end

  @tag :candidate_root
  test "candidate requires the known own action and every original cached payload-free prerequisite" do
    {_, _, _, event, before} = fixture()
    state = before.managed_lineage
    {:ok, deps} = ManagedLineage.dependencies(state, before.messages)
    assert {:ok, action} = ManagedLineage.root_candidate(state, deps)
    assert length(state.root_writes[action["operation_id"]]["dependencies"]) == 3
    projection = event["projection"]
    binding = event["projection"]["binding"]

    assert {:ok, _, _, _, _} =
             ManagedLineage.root_projection(
               state,
               before.messages,
               binding,
               projection["fresh_observation"],
               projection["inspection"]
             )

    assert {:error, _} = ManagedLineage.root_candidate(%{state | root_writes: %{}}, deps)
    [one | _] = state.root_writes[action["operation_id"]]["dependencies"]
    id = JSON.digest([one])

    assert {:error, _} =
             ManagedLineage.root_candidate(
               %{state | root_observations: Map.put(state.root_observations, id, false)},
               deps
             )

    assert {:error, _} =
             ManagedLineage.root_candidate(
               %{state | root_observations: Map.delete(state.root_observations, id)},
               deps
             )

    altered_action = put_in(action, ["outcome", "status"], "unknown")
    altered_writes = put_in(state.root_writes, [action["operation_id"], "action"], altered_action)

    assert {:error, _} =
             ManagedLineage.root_candidate(%{state | root_writes: altered_writes}, deps)

    altered_action = put_in(action, ["outcome", "value", "receipt", "generation"], 99)
    altered_writes = put_in(state.root_writes, [action["operation_id"], "action"], altered_action)

    assert {:error, _} =
             ManagedLineage.root_candidate(%{state | root_writes: altered_writes}, deps)

    fresh = projection["fresh_dependency"]
    {:ok, mixed} = Ipse.Session.ManagedReference.union([deps, [fresh]])
    mixed_cache = Map.put(state.root_observations, JSON.digest([fresh]), true)

    assert {:error, _} =
             ManagedLineage.root_candidate(%{state | root_observations: mixed_cache}, mixed)

    record =
      hd(deps)
      |> Map.put("version", 4)
      |> Map.put("subject", %{
        "kind" => "record_observation",
        "key" => "record.0",
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => "record.0"}]),
        "result_sha256" => JSON.digest([%{"record" => nil}]),
        "publication_policy_sha256" => nil,
        "record" => nil,
        "validity" => nil
      })

    assert Ipse.Session.ManagedReference.dependency?(record)
    {:ok, with_record} = Ipse.Session.ManagedReference.union([deps, [record]])
    record_cache = Map.put(state.root_observations, JSON.digest([record]), true)

    altered_writes =
      update_in(state.root_writes, [action["operation_id"], "dependencies"], &(&1 ++ [record]))

    assert {:error, _} =
             ManagedLineage.root_candidate(
               %{state | root_observations: record_cache, root_writes: altered_writes},
               with_record
             )

    assert {:error, _} =
             ManagedLineage.root_projection(
               state,
               before.messages,
               binding,
               projection["fresh_observation"],
               put_in(projection["inspection"], ["generation"], 2)
             )

    assert {:error, _} =
             ManagedLineage.root_projection(
               state,
               before.messages,
               binding,
               projection["fresh_observation"],
               put_in(projection["inspection"], ["operation"], nil)
             )

    assert {:error, _} =
             ManagedLineage.root_projection(
               state,
               before.messages,
               binding,
               projection["fresh_observation"],
               Map.put(projection["inspection"], "unexpected", true)
             )
  end
end
