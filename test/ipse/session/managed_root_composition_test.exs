defmodule Ipse.Session.ManagedRootCompositionTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session}
  alias Ipse.Session.{ManagedLineage, ManagedReference}

  @journal "docs/archive/2026-10-26-p30-p31-implementation/own-root-transition/journals/model.jsonl"

  defp prepared do
    events =
      @journal |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    id = get_in(hd(events), ["metadata", "source_origin", "session_id"])

    index =
      Enum.find_index(
        events,
        &(&1["type"] == "managed_preflight_result" and
            get_in(&1, ["projection", "type"]) == "managed_root_transition")
      )

    projection = Enum.at(events, index)["projection"]
    {:ok, before} = Session.Saved.restore(Enum.take(events, index), id)
    {:ok, old} = ManagedLineage.dependencies(before.managed_lineage, before.messages)

    {:ok, _, _, _, settled} =
      ManagedLineage.root_projection(
        before.managed_lineage,
        before.messages,
        projection["binding"],
        projection["fresh_observation"],
        projection["inspection"]
      )

    guard = projection["fresh_dependency"]

    fresh =
      put_in(guard, ["subject"], %{
        "kind" => "root_observation",
        "request_sha256" =>
          JSON.digest([%{"op" => "index", "prefix" => "note.", "cursor" => nil, "limit" => 1}]),
        "result_sha256" => JSON.sha256("synthetic empty current index")
      })

    assert ManagedReference.dependency?(fresh)
    cache = Map.put(settled.root_observations, JSON.digest([fresh]), true)
    settled = %{settled | root_observations: cache}
    {:ok, mixed} = ManagedReference.union([old, [guard, fresh]])
    {before, projection, settled, old, guard, fresh, mixed}
  end

  test "model carries committed successor metadata without weakening worker input" do
    {before, projection, settled, _old, guard, fresh, mixed} = prepared()
    assert {:error, _} = ManagedLineage.root_projection_candidate(before.managed_lineage, mixed)
    assert {:ok, action} = ManagedLineage.root_projection_candidate(settled, mixed)
    assert action["operation_id"] === projection["operation_id"]
    assert {:error, _} = ManagedLineage.root_candidate(settled, mixed)

    message = %{"role" => "user", "content" => "Synthetic current root-only metadata."}
    producer = %{"kind" => "reference", "id" => "fresh_metadata", "parent_id" => nil}

    {:ok, _, reference} =
      ManagedReference.admit(
        before.managed_lineage.reference,
        producer,
        length(before.messages),
        message,
        [guard, fresh]
      )

    state = %{settled | reference: reference}
    messages = before.messages ++ [message]

    assert {:ok, event, projected, retained, _} =
             ManagedLineage.root_projection(
               state,
               messages,
               projection["binding"],
               projection["fresh_observation"],
               projection["inspection"]
             )

    assert event["old_dependencies"] === mixed
    assert event["old_dependencies_sha256"] === JSON.digest(mixed)
    assert Enum.take(projected, length(messages)) === messages
    assert {:ok, remaining} = ManagedReference.dependencies(retained, projected)
    assert guard in remaining and fresh in remaining

    assert Enum.all?(
             remaining,
             &(get_in(&1, ["collection", "generation"]) == guard["collection"]["generation"])
           )

    entry =
      Enum.find_value(retained.occurrences, fn {_, entry} ->
        if entry.position == length(before.messages), do: entry
      end)

    assert JSON.digest([fresh]) in entry.dependency_ids
    assert JSON.digest([guard]) in entry.dependency_ids
  end

  test "missing, nonempty-index, foreign and changed-root metadata cannot join the transition" do
    {_before, _projection, settled, old, guard, fresh, mixed} = prepared()
    fresh_id = JSON.digest([fresh])

    for cache <- [
          Map.delete(settled.root_observations, fresh_id),
          Map.put(settled.root_observations, fresh_id, "metadata_only")
        ] do
      assert {:error, _} =
               ManagedLineage.root_projection_candidate(
                 %{settled | root_observations: cache},
                 mixed
               )
    end

    for altered <- [
          put_in(fresh, ["policy_generation"], fresh["policy_generation"] + 1),
          put_in(fresh, ["collection", "generation"], guard["collection"]["generation"] + 1),
          put_in(fresh, ["collection", "root_sha256"], JSON.sha256("foreign root")),
          Map.put(fresh, "pin_sha256", JSON.sha256("foreign pin"))
        ] do
      {:ok, union} = ManagedReference.union([old, [guard, altered]])

      state = %{
        settled
        | root_observations: Map.put(settled.root_observations, JSON.digest([altered]), true)
      }

      assert {:error, _} = ManagedLineage.root_projection_candidate(state, union)
    end

    assert {:error, _} =
             ManagedLineage.root_projection_candidate(%{settled | root_writes: %{}}, mixed)

    assert {:error, _} =
             ManagedLineage.root_projection_candidate(%{settled | root_transitions: %{}}, mixed)
  end

  test "selected current metadata retains its identity without selecting the historical snapshot guard" do
    {before, projection, settled, old, guard, fresh, _} = prepared()
    {:ok, mixed} = ManagedReference.union([old, [fresh]])
    refute guard in mixed
    assert {:ok, _} = ManagedLineage.root_projection_candidate(settled, mixed)
    assert {:error, _} = ManagedLineage.root_candidate(settled, mixed)

    message = %{
      "role" => "user",
      "content" => "Synthetic independently selected current metadata."
    }

    producer = %{"kind" => "reference", "id" => "current_metadata", "parent_id" => nil}

    {:ok, _, reference} =
      ManagedReference.admit(
        before.managed_lineage.reference,
        producer,
        length(before.messages),
        message,
        [fresh]
      )

    messages = before.messages ++ [message]

    assert {:ok, event, projected, retained, _} =
             ManagedLineage.root_projection(
               %{settled | reference: reference},
               messages,
               projection["binding"],
               projection["fresh_observation"],
               projection["inspection"]
             )

    assert event["old_dependencies"] === mixed
    assert Enum.take(projected, length(messages)) === messages
    assert {:ok, remaining} = ManagedReference.dependencies(retained, projected)
    assert fresh in remaining and guard in remaining
    missing = Map.delete(settled.root_observations, JSON.digest([guard]))

    assert {:error, _} =
             ManagedLineage.root_projection_candidate(
               %{settled | root_observations: missing},
               mixed
             )

    [target] = settled.root_transitions |> Map.values() |> Enum.uniq()
    wrong_guard = put_in(guard, ["collection", "root_sha256"], JSON.sha256("wrong target root"))
    wrong_target = %{settled | dictionary: Map.put(settled.dictionary, target, wrong_guard)}
    assert {:error, _} = ManagedLineage.root_projection_candidate(wrong_target, mixed)

    future = put_in(fresh, ["collection", "generation"], fresh["collection"]["generation"] + 1)
    {:ok, no_carried} = ManagedReference.union([old, [future]])
    assert {:error, _} = ManagedLineage.root_projection_candidate(settled, no_carried)

    unknown_writes =
      Map.new(settled.root_writes, fn {operation, value} ->
        {operation, put_in(value, ["action", "outcome", "status"], "unknown")}
      end)

    assert {:error, _} =
             ManagedLineage.root_projection_candidate(
               %{settled | root_writes: unknown_writes},
               mixed
             )
  end

  test "an independently introduced record dependency is never treated as root-only metadata" do
    {_before, _projection, settled, old, guard, fresh, _mixed} = prepared()
    key = "record.synthetic"

    record =
      fresh
      |> Map.put("version", 4)
      |> Map.put("subject", %{
        "kind" => "record_observation",
        "key" => key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => JSON.sha256("synthetic record response"),
        "publication_policy_sha256" => JSON.sha256("synthetic publication policy"),
        "record" => %{
          "key" => key,
          "revision" => 1,
          "value_sha256" => JSON.sha256("synthetic record value")
        },
        "validity" => %{
          "recipe_sha256" => JSON.sha256("synthetic recipe"),
          "lineage" => JSON.sha256("synthetic lineage"),
          "source_versions" => [],
          "valid_until_ms" => nil,
          "status" => "eligible",
          "dependencies" => []
        }
      })

    assert ManagedReference.dependency?(record)
    {:ok, union} = ManagedReference.union([old, [guard, fresh, record]])

    state = %{
      settled
      | root_observations: Map.put(settled.root_observations, JSON.digest([record]), true)
    }

    assert {:error, _} = ManagedLineage.root_projection_candidate(state, union)
  end
end
