defmodule Ipse.Session.ManagedRootCacheTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session}
  alias Ipse.Session.ManagedReads

  @journal "docs/archive/2026-10-26-p30-p31-implementation/remember-terminal-headless-controls/journals/headless-direct.jsonl"

  defp events do
    {:ok, data} = File.read(@journal)
    records = data |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    {records, get_in(hd(records), ["metadata", "source_origin", "session_id"])}
  end

  defp result_for(events, receipt),
    do:
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            &1["operation_id"] == receipt["operation_id"])
      )

  test "only a committed matched result creates root classification and replay rebuilds it" do
    {events, id} = events()
    index = Enum.find_index(events, &(&1["type"] == "managed_read_observed"))
    receipt = Enum.at(events, index)
    [dependency] = receipt["dependencies"]
    key = JSON.digest([dependency])
    assert {:ok, pending} = Session.Saved.restore(Enum.take(events, index + 1), id)
    refute Map.has_key?(pending.managed_lineage.root_observations, key)
    assert map_size(pending.managed_lineage.root_pending) == 1
    assert {:ok, committed} = Session.Saved.restore(Enum.take(events, index + 2), id)
    assert committed.managed_lineage.root_observations[key] === true
    assert committed.managed_lineage.root_pending == %{}
    assert {:ok, restored} = Session.Saved.restore(events, id)
    assert map_size(restored.managed_lineage.root_observations) == 3
  end

  test "forged, missing, out-of-order and failed observations never rebuild a cache entry" do
    {events, id} = events()
    index = Enum.find_index(events, &(&1["type"] == "managed_read_observed"))
    receipt = Enum.at(events, index)
    result = Enum.at(events, index + 1)

    forged =
      put_in(
        receipt,
        ["dependencies", Access.at(0), "subject", "request_sha256"],
        JSON.sha256("forged")
      )

    for altered <- [
          List.delete_at(events, index),
          List.delete_at(events, index + 1),
          List.replace_at(events, index, forged),
          events |> List.replace_at(index, result) |> List.replace_at(index + 1, receipt)
        ] do
      assert {:error, _} = Session.Saved.restore(altered, id)
    end

    failed = put_in(result, ["outcome", "status"], "failed")
    assert {:error, _} = Session.Saved.restore(List.replace_at(events, index + 1, failed), id)
  end

  test "only closed root-only snapshot, nil get and empty initial metadata index qualify" do
    {events, _} = events()
    receipts = Enum.filter(events, &(&1["type"] == "managed_read_observed"))

    for receipt <- receipts do
      event = result_for(events, receipt)
      [dependency] = receipt["dependencies"]
      binding = %{"namespace" => event["namespace"], "pin" => event["effect_binding"]["pin"]}
      assert ManagedReads.root_prerequisite?(dependency, event, binding, 0)

      assert ManagedReads.cached_root_prerequisite?(
               dependency,
               %{JSON.digest([dependency]) => true},
               binding,
               0
             )

      refute ManagedReads.cached_root_prerequisite?(dependency, %{}, binding, 0)

      refute ManagedReads.cached_root_prerequisite?(
               dependency,
               %{JSON.digest([dependency]) => 1},
               binding,
               0
             )

      refute ManagedReads.cached_root_prerequisite?(
               dependency,
               %{JSON.digest([dependency]) => true},
               binding,
               1
             )

      refute ManagedReads.cached_root_prerequisite?(
               dependency,
               %{JSON.digest([dependency]) => true},
               put_in(binding, ["pin", "epoch"], 999),
               0
             )

      inner = event["request"]["request"]

      bad =
        case inner["op"] do
          "index" -> put_in(event, ["outcome", "value", "count"], 1)
          "get" -> put_in(event, ["outcome", "value", "record"], %{"key" => "not-empty"})
        end

      refute ManagedReads.root_prerequisite?(dependency, bad, binding, 0)
    end
  end

  test "self-consistent nonempty indexes and later pages are not root-only evidence" do
    {events, _} = events()

    receipt =
      Enum.find(events, fn event ->
        event["type"] == "managed_read_observed" and
          get_in(result_for(events, event), ["request", "request", "op"]) == "index"
      end)

    event = result_for(events, receipt)
    [dependency] = receipt["dependencies"]
    binding = %{"namespace" => event["namespace"], "pin" => event["effect_binding"]["pin"]}

    row = %{
      "key" => "note." <> JSON.sha256("fixture"),
      "revision" => 1,
      "bytes" => 1,
      "sha256" => JSON.sha256("fixture")
    }

    value = event["outcome"]["value"] |> Map.put("count", 1) |> Map.put("records", [row])
    changed = put_in(event, ["outcome", "value"], value)
    changed_dep = put_in(dependency, ["subject", "result_sha256"], JSON.digest([value]))

    assert Ipse.Extension.CollectionCall.valid_outcome?(
             changed["request"],
             "ok",
             value,
             changed["operation_id"]
           )

    refute ManagedReads.root_prerequisite?(changed_dep, changed, binding, 0)

    later = put_in(event, ["request", "request", "cursor"], "opaque-later-page")

    later_dep =
      put_in(
        dependency,
        ["subject", "request_sha256"],
        JSON.digest([later["request"]["request"]])
      )

    assert Ipse.Extension.CollectionCall.valid_outcome?(
             later["request"],
             "ok",
             later["outcome"]["value"],
             later["operation_id"]
           )

    refute ManagedReads.root_prerequisite?(later_dep, later, binding, 0)
  end
end
