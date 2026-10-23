defmodule Ipse.LifecycleChildTest do
  use ExUnit.Case, async: false
  alias Ipse.Tools.Delegation
  alias Ipse.Journal
  alias Ipse.Session.Lifecycle

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-child-source-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, id} = Journal.create(root, %{"synthetic" => true})

    request =
      Ipse.Usage.admission(id, %{provider: :demo, model: "fixture"}, "model", Ipse.Usage.id())

    :ok = Journal.append(root, id, request)

    started = %{
      "type" => "delegation_started",
      "child_id" => Ipse.Usage.id(),
      "call_id" => "private-call"
    }

    {:ok, source} = Journal.append_with_source(root, id, started)

    resource = %{
      id: started["child_id"],
      source: source,
      turn: request["turn_id"],
      request: request["request_id"],
      started: System.monotonic_time(:millisecond)
    }

    finished = Delegation.child_finished(resource, "result_recorded", "completed", true)
    {:ok, receipt_source} = Journal.append_with_source(root, id, finished)
    {:ok, events} = Journal.load(root, id)

    %{
      root: root,
      id: id,
      resource: resource,
      started: started,
      finished: finished,
      source: receipt_source,
      events: events
    }
  end

  test "source-bound child receipts project only closed host metadata", c do
    assert {:ok, saved} = Delegation.restore_children(c.events)
    assert saved.children[c.resource.id].ended
    assert :ok = Delegation.validate_child_sources(c.root, c.id, c.events)
    assert {:ok, event} = Lifecycle.project(c.source, c.finished, "metadata")
    assert Lifecycle.valid_metadata?(event)
    assert event["type"] == "child.finished"
    assert event["correlations"]["causing_event_id"] == c.resource.source["event_id"]
    assert event["correlations"]["child_id"] == c.resource.id
    assert event["data"]["status"] == "result_recorded"
    refute Jason.encode!(event) =~ "private-call"
    refute Jason.encode!(event) =~ "sha256"

    assert {:error, :lifecycle_view_unavailable} =
             Lifecycle.project(c.source, c.finished, "child.result")
  end

  test "malformed, duplicate and mismatched completion receipts refuse restoration", c do
    for changed <- [
          Map.put(c.finished, "child_id", Ipse.Usage.id()),
          Map.put(c.finished, "request_id", Ipse.Usage.id()),
          Map.put(c.finished, "turn_id", Ipse.Usage.id()),
          Map.put(c.finished, "duration_ms", -1),
          Map.put(c.finished, "cleanup_confirmed", false),
          Map.put(c.finished, "reason", "arbitrary private error"),
          Map.put(c.finished, "status", "business_success")
        ] do
      assert {:error, :invalid_child_lifecycle} =
               Delegation.restore_children(Enum.drop(c.events, -1) ++ [changed])
    end

    assert {:error, :invalid_child_lifecycle} =
             Delegation.restore_children(c.events ++ [c.finished])

    assert {:ok, saved} = Delegation.restore_children(Enum.drop(c.events, -1))
    refute saved.children[c.resource.id].ended
    refute Delegation.valid_child_record?(nil)
  end

  test "coherent forged positions still need actual journal source resolution", c do
    {:ok, wrong} = Journal.source(c.id, c.resource.source["byte_offset"] + 1, c.started)
    forged = Map.put(c.finished, "started_source", wrong)
    events = Enum.drop(c.events, -1) ++ [forged]
    assert {:ok, _} = Delegation.restore_children(events)

    assert {:error, :invalid_child_lifecycle} =
             Delegation.validate_child_sources(c.root, c.id, events)
  end

  test "a dead process supplies no cleanup acknowledgment", c do
    {pid, ref} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert :ok = Ipse.Session.close(pid)
    assert {:error, :cleanup_unconfirmed} = Ipse.Session.close_confirmed(pid)
    unknown = Delegation.child_finished(c.resource, "unknown", "child_down", false)
    assert Delegation.valid_child_record?(unknown)
    assert {:ok, _} = Delegation.restore_children(Enum.drop(c.events, -1) ++ [unknown])
  end
end
