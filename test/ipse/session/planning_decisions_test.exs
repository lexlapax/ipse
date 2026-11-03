defmodule Ipse.Session.PlanningDecisionsTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session.PlanningDecisions, Session.PlanningTransition}
  alias Ipse.Extension.Mode

  defp observation(text, display, id) do
    %{
      "version" => 2,
      "event_id" => String.duplicate(id, 32),
      "text_sha256" => JSON.sha256(text),
      "display_sha256" => JSON.sha256(display),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }
  end

  defp fixture do
    session = String.duplicate("a", 32)
    channel = String.duplicate("b", 32)
    {:ok, normal} = Mode.capture(%{approval: :ask})
    planning = Map.put(normal, "ceiling", "planning")
    header = %{"metadata" => %{"execution_mode" => normal}}

    checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 2,
      "session_id" => session,
      "previous_sha256" => JSON.digest([normal]),
      "mode" => planning
    }

    entry = PlanningTransition.entry(session, checkpoint, observation("/plan", "you> ", "c"))
    command = "/plan decide Use a local fixture."
    {:ok, render} = PlanningDecisions.render(session, channel, entry, "Use a local fixture.")
    input = "accept " <> render["code"]

    {:ok, receipt} =
      PlanningDecisions.accept(
        render,
        command,
        observation(command, "you> ", "d"),
        input,
        observation(input, render["display"], "e")
      )

    exit =
      PlanningTransition.exit(session, entry, planning, observation("/plan exit", "you> ", "f"))

    save = "/plan save " <> receipt["id"]
    started = PlanningDecisions.save_started(session, receipt, observation(save, "you> ", "1"))
    {session, [header, checkpoint, entry], receipt, exit, started}
  end

  test "acceptance stays deferred across exit and a save intent is one-shot" do
    {session, prefix, receipt, exit, started} = fixture()
    assert PlanningDecisions.valid_accepted?(receipt, session)
    assert {:ok, deferred} = PlanningDecisions.restore(prefix ++ [receipt], session)
    assert %{exited: false, attempted: false} = deferred[receipt["id"]]
    assert {:error, _} = PlanningDecisions.restore(prefix ++ [receipt, started], session)

    assert {:ok, exited} = PlanningDecisions.restore(prefix ++ [receipt, exit], session)
    assert %{exited: true, attempted: false} = exited[receipt["id"]]

    assert {:error, _} =
             PlanningDecisions.restore(
               prefix ++ [receipt, Map.put(exit, "previous_sha256", JSON.sha256("forged"))],
               session
             )

    assert {:ok, attempted} =
             PlanningDecisions.restore(prefix ++ [receipt, exit, started], session)

    assert %{exited: true, attempted: true, asserted: false} = attempted[receipt["id"]]

    assert {:error, _} =
             PlanningDecisions.restore(prefix ++ [receipt, exit, started, started], session)
  end

  test "replay rejects changed or unwitnessed choices and broken save links" do
    {session, prefix, receipt, exit, started} = fixture()

    for changed <- [
          put_in(receipt, ["observation", "text_sha256"], JSON.sha256("yes")),
          Map.put(receipt, "text", "Different decision"),
          Map.put(receipt, "entry_sha256", JSON.sha256("another entry")),
          Map.put(receipt, "session_id", String.duplicate("b", 32))
        ] do
      assert {:error, _} = PlanningDecisions.restore(prefix ++ [changed], session)
    end

    assert {:error, _} = PlanningDecisions.restore(prefix ++ [receipt, receipt], session)

    assert {:error, _} =
             PlanningDecisions.restore(
               prefix ++
                 [receipt, exit, Map.put(started, "accepted_sha256", JSON.sha256("other"))],
               session
             )

    assertion = %{
      "type" => "operator_assertion",
      "planning_decision" => receipt,
      "text" => receipt["text"],
      "category" => "ordinary"
    }

    assert {:error, _} = PlanningDecisions.restore(prefix ++ [receipt, exit, assertion], session)

    assert {:ok, linked} =
             PlanningDecisions.restore(prefix ++ [receipt, exit, started, assertion], session)

    assert linked[receipt["id"]].asserted
    refused = PlanningDecisions.refused_unstarted(session, receipt)

    assert {:ok, resolved} =
             PlanningDecisions.restore(
               prefix ++ [receipt, exit, started, assertion, refused],
               session
             )

    assert resolved[receipt["id"]].refused

    assert {:error, _} =
             PlanningDecisions.restore(prefix ++ [receipt, exit, started, refused], session)

    assert {:error, _} =
             PlanningDecisions.restore(
               prefix ++
                 [
                   receipt,
                   exit,
                   started,
                   assertion,
                   %{"type" => "extension_invocation_intent"},
                   refused
                 ],
               session
             )

    assert {:error, _} =
             PlanningDecisions.restore(
               prefix ++ [receipt, exit, started, assertion, assertion],
               session
             )

    assert {:error, _} =
             PlanningDecisions.restore(
               prefix ++ [receipt, exit, started, Map.put(assertion, "text", "different")],
               session
             )

    normal = exit["mode"]
    planning = Map.put(normal, "ceiling", "planning")

    checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 2,
      "session_id" => session,
      "previous_sha256" => JSON.digest([normal]),
      "mode" => planning
    }

    reentry = PlanningTransition.entry(session, checkpoint, observation("/plan", "you> ", "2"))
    tampered = prefix ++ [receipt, exit, started, checkpoint, reentry, assertion]
    assert :ok = PlanningTransition.validate_events(tampered, session)
    assert {:error, _} = PlanningDecisions.restore(tampered, session)

    tampered_result = prefix ++ [receipt, exit, started, assertion, checkpoint, reentry, refused]
    assert :ok = PlanningTransition.validate_events(tampered_result, session)
    assert {:error, _} = PlanningDecisions.restore(tampered_result, session)
  end

  test "native observation IDs cannot be reused by deferred and other input" do
    {_, _, receipt, _, _} = fixture()
    reused = %{"type" => "input_received", "observation" => receipt["observation"]}

    assert {:error, :duplicate_operator_observation} =
             Ipse.Session.DraftAcceptance.validate_observation_uniqueness([receipt, reused])
  end

  test "a later unrelated invocation conservatively fences refusal without claiming attribution" do
    {session, prefix, receipt, exit, started} = fixture()

    assertion = %{
      "type" => "operator_assertion",
      "planning_decision" => receipt,
      "text" => receipt["text"],
      "category" => "ordinary"
    }

    unrelated = %{"type" => "extension_invocation_intent", "descriptor" => %{"id" => "other"}}
    refused = PlanningDecisions.refused_unstarted(session, receipt)
    history = prefix ++ [receipt, exit, started, assertion]

    assert {:ok, unknown} = PlanningDecisions.restore(history ++ [unrelated], session)
    assert unknown[receipt["id"]].later_invocation_seen
    refute unknown[receipt["id"]].refused
    assert {:error, _} = PlanningDecisions.restore(history ++ [unrelated, refused], session)

    assert {:ok, known} = PlanningDecisions.restore(history ++ [refused, unrelated], session)
    assert known[receipt["id"]].refused
    refute known[receipt["id"]].later_invocation_seen
  end
end
