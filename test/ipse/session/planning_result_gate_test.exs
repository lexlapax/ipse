Code.require_file("../../support/planning_result_gate.ex", __DIR__)

defmodule Ipse.Session.PlanningResultGateTest do
  use ExUnit.Case, async: true

  alias Ipse.Test.PlanningResultGate

  test "only a valid successful pending managed result holds the real writer" do
    # Extracted with jq -c from the fresh merged-candidate synthetic positive
    # journey on 2026-11-06, in /tmp/ipse-p31i-merged.9edA7QWD. It is distinct
    # from the earlier private-copy positive journey; both use synthetic data.
    bytes = File.read!("test/support/fixtures/planning_pending_result.json")

    assert Ipse.JSON.sha256(bytes) ==
             "eb4a6e257c2bb96a4c918f8c3990cc24efd5b9f51b3934ebe6a1793e4a5b614b"

    event = Jason.decode!(bytes)

    assert Ipse.Extension.Actions.valid_result?(event)
    message = {:in, {:"$gen_call", {self(), make_ref()}, {:append, :plain, event}}}
    assert {:ok, ^event} = PlanningResultGate.target(message)

    for other <- [
          {:in,
           {:"$gen_call", {self(), make_ref()},
            {:append, :plain, %{event | "type" => "extension_action_intent"}}}},
          {:in,
           {:"$gen_call", {self(), make_ref()},
            {:append, :plain, put_in(event, ["outcome", "status"], "unknown")}}},
          {:in,
           {:"$gen_call", {self(), make_ref()},
            {:append, :plain, put_in(event, ["request", "op"], "source.read")}}},
          {:in,
           {:"$gen_call", {self(), make_ref()},
            {:append, :plain,
             put_in(
               event,
               ["request", "request", "changes", Access.at(0), "key"],
               "note.synthetic"
             )}}},
          {:in,
           {:"$gen_call", {self(), make_ref()},
            {:append, :plain, Map.put(event, "outcome_sha256", String.duplicate("0", 64))}}},
          {:out, event}
        ] do
      assert PlanningResultGate.target(other) == :ignore
    end

    owner = self()
    gate = PlanningResultGate.hook(owner)
    task = Task.async(fn -> gate.(:preserved, message, nil) end)
    assert_receive {:managed_result_after_dispatch, writer, ^event}
    assert writer == task.pid
    assert Task.yield(task, 10) == nil
    send(task.pid, :release_planning_result_gate)
    assert Task.await(task) == :preserved
  end
end
