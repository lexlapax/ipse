defmodule Ipse.Session.SourceEffectProducerTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Session.{ManagedLineage, SourceIndex, SourceWindow}

  defp open do
    {:ok, state} = ManagedLineage.new(Usage.id())

    parent = %{
      "type" => "extension_invocation_intent",
      "invocation_id" => Usage.id(),
      "descriptor" => %{"stage" => "invoke.command"},
      "identity" => %{"instance" => "ordinary"}
    }

    {:ok, state} = ManagedLineage.advance(state, parent, [], [])
    {state, parent}
  end

  defp result(parent, operation, id \\ Usage.id()) do
    %{
      "type" => "extension_action_result",
      "parent_invocation_id" => parent["invocation_id"],
      "operation_id" => id,
      "request" => %{"op" => operation},
      "outcome" => %{"status" => "ok"}
    }
  end

  test "more than 2048 empty internal frames retain available lineage without source markers" do
    {state, parent} = open()
    operations = ~w(tool.call collection.store collection.call context.publish)

    state =
      Enum.reduce(1..2055, state, fn ordinal, state ->
        action = result(parent, Enum.at(operations, rem(ordinal, length(operations))))
        assert {:ok, next} = ManagedLineage.advance(state, action, [], [])
        refute next.unavailable
        next
      end)

    assert state.effects == %{} and state.source_producers == %{}
    assert {:ok, []} = ManagedLineage.dependencies(state, [])
  end

  test "genuine zero-dependency effect sources remain known and forged producers refuse" do
    {state, parent} = open()

    for operation <- ~w(mcp.call embedding.create decision.create) do
      id = Usage.id()
      assert SourceWindow.source_effect_operation?(operation)
      assert {:ok, known} = ManagedLineage.advance(state, result(parent, operation, id), [], [])
      assert known.source_producers["effects:#{id}"] === true
      assert known.effects === %{}
      known = %{known | calls: %{"lookup" => []}}
      row = %{"provenance" => %{"operation_id" => id}}

      assert {:ok, _, []} =
               ManagedLineage.add_selected_source_dependencies(known, "lookup", [row])

      assert {:error, _} =
               ManagedLineage.add_selected_source_dependencies(known, "lookup", [
                 %{"provenance" => %{"operation_id" => Usage.id()}}
               ])
    end

    id = Usage.id()

    assert {:ok, internal} =
             ManagedLineage.advance(state, result(parent, "tool.call", id), [], [])

    internal = %{internal | calls: %{"lookup" => []}}

    assert {:error, _} =
             ManagedLineage.add_selected_source_dependencies(internal, "lookup", [
               %{"provenance" => %{"operation_id" => id}}
             ])
  end

  test "nonempty internal effect dependencies retain their complete union and marker" do
    {state, parent} = open()

    dependency = %{
      "version" => 3,
      "project_id" => JSON.sha256("project"),
      "namespace" => JSON.sha256("namespace"),
      "pin_sha256" => JSON.sha256("pin"),
      "policy_generation" => 1,
      "collection" => %{
        "project" => JSON.sha256("namespace"),
        "generation" => 0,
        "floor" => 0,
        "floor_anchor" => nil,
        "root_state" => "absent",
        "root_sha256" => nil,
        "manifest_sha256" => nil
      },
      "subject" => %{
        "kind" => "root_observation",
        "request_sha256" => JSON.sha256("request"),
        "result_sha256" => JSON.sha256("result")
      }
    }

    digest = JSON.digest([dependency])
    state = %{state | dictionary: %{digest => dependency}}
    state = put_in(state.invocations[parent["invocation_id"]].reads, [digest])
    id = Usage.id()
    assert {:ok, kept} = ManagedLineage.advance(state, result(parent, "tool.call", id), [], [])
    assert kept.effects[id] === [digest]
    assert kept.source_producers["effects:#{id}"] === true
    assert kept.dictionary === state.dictionary
    assert kept.invocations[parent["invocation_id"]].reads === [digest]
  end

  test "the genuine source-marker capacity remains bounded without eviction" do
    {state, parent} = open()
    producers = Map.new(1..2048, &{"effects:#{&1}", true})
    state = %{state | source_producers: producers}
    assert {:ok, refused} = ManagedLineage.advance(state, result(parent, "mcp.call"), [], [])
    assert refused.unavailable
    assert refused.source_producers === producers
  end

  test "real native tool source provenance remains request based" do
    path =
      "docs/archive/2026-10-26-p30-p31-implementation/remember-terminal-headless-controls/journals/headless-direct.jsonl"

    events = path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    id = get_in(hd(events), ["metadata", "source_origin", "session_id"])

    position =
      Enum.find_index(
        events,
        &(&1["type"] === "extension_action_result" and
            get_in(&1, ["request", "op"]) === "source.read")
      )

    read = Enum.at(events, position)
    {:ok, window} = SourceWindow.restore(Enum.take(events, position), id)

    assert {:ok, [row]} =
             SourceIndex.saved_read_provenances(
               window.index,
               "source.read",
               Map.delete(read["request"], "op"),
               read["outcome"]["value"],
               window.historical_window
             )

    assert is_binary(row["provenance"]["tool_id"])
    request_id = row["provenance"]["request_id"]
    assert is_binary(request_id)
    refute Map.has_key?(row["provenance"], "operation_id")
    {:ok, state} = ManagedLineage.new(id)

    assert {:ok, state} =
             ManagedLineage.advance(
               state,
               %{"type" => "request_admitted", "request_id" => request_id},
               [],
               []
             )

    assert state.source_producers["requests:#{request_id}"] === true
    state = %{state | calls: %{"lookup" => []}}
    assert {:ok, _, []} = ManagedLineage.add_selected_source_dependencies(state, "lookup", [row])
    missing = %{state | source_producers: %{}}
    assert {:error, _} = ManagedLineage.add_selected_source_dependencies(missing, "lookup", [row])
  end
end
