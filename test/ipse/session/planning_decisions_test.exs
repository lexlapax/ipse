Code.require_file("../../support/managed_policy.exs", __DIR__)

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

  test "assistant command requires an exact, bounded nonblank quote" do
    assert {:ok, "quoted text"} =
             PlanningDecisions.parse_assistant("/plan decide-assistant quoted text")

    assert {:error, _} = PlanningDecisions.parse_assistant("/plan decide-assistant ")
    assert {:error, _} = PlanningDecisions.parse_assistant("/plan decide-assistant   ")

    assert {:error, _} =
             PlanningDecisions.parse_assistant(
               "/plan decide-assistant " <> String.duplicate("x", 1025)
             )

    assert {:error, _} = PlanningDecisions.parse_assistant("/plan decide quoted text")
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

  test "assistant decisions bind an exact committed reply and cannot become operator assertions" do
    {session, prefix, _, exit, _} = fixture()
    entry = List.last(prefix)
    turn = Ipse.Usage.id()
    request = Ipse.Usage.id()
    channel = Ipse.Usage.id()
    message = %{"role" => "assistant", "content" => "Use the local fixture for this decision."}
    committed = %{"type" => "message", "request_id" => request, "message" => message}
    {:ok, source} = Ipse.Journal.source(session, 0, %{"type" => "message"})
    answer = Ipse.Session.Lifecycle.answer(turn, request, message, message["content"], source)
    history = prefix ++ [committed, answer]
    {:ok, window} = Ipse.Session.SourceWindow.restore(history, session)
    quote = "local fixture"

    {:ok, selection} =
      Ipse.Session.SourceWindow.planning_answer_request(window, entry, turn, request, quote)

    {:ok, %{"proof" => proof}} = Ipse.Session.SourceIndex.resolve_proof(window.index, selection)

    {:ok, render} =
      PlanningDecisions.render_assistant(session, channel, entry, quote, turn, request, proof)

    command = "/plan decide-assistant " <> quote
    input = "accept " <> render["code"]

    {:ok, accepted} =
      PlanningDecisions.accept(
        render,
        command,
        observation(command, "you> ", "3"),
        input,
        observation(input, render["display"], "4")
      )

    assert proof["origin"] == "assistant_proposal"
    assert {:ok, decisions} = PlanningDecisions.restore(history ++ [accepted, exit], session)
    assert decisions[accepted["id"]].exited

    {:ok, before_later_turn} =
      Ipse.Session.SourceWindow.restore(history ++ [accepted, exit], session)

    assert Ipse.Session.SourceWindow.planning_answer_current?(
             before_later_turn,
             accepted["entry_sha256"],
             turn,
             request,
             proof
           )

    assert PlanningDecisions.status(decisions[accepted["id"]], true) == "ready_for_save_review"

    later_history = history ++ [accepted, exit, %{"type" => "input_received"}]
    {:ok, after_later_turn} = Ipse.Session.SourceWindow.restore(later_history, session)

    refute Ipse.Session.SourceWindow.planning_answer_current?(
             after_later_turn,
             accepted["entry_sha256"],
             turn,
             request,
             proof
           )

    assert {:ok, resumed_decisions} = PlanningDecisions.restore(later_history, session)

    assert PlanningDecisions.status(resumed_decisions[accepted["id"]], false) ==
             "source_unavailable_for_save"

    assert {:error, _} = PlanningDecisions.restore(prefix ++ [accepted], session)

    assert {:error, _} =
             PlanningDecisions.restore(
               history ++
                 [put_in(accepted, ["source_proof", "origin"], "native_operator_assertion")],
               session
             )

    assert {:error, _} =
             PlanningDecisions.restore(
               history ++ [%{"type" => "input_received"}, accepted],
               session
             )

    assert {:error, _} =
             Ipse.Session.SourceWindow.planning_answer_request(
               window,
               entry,
               turn,
               request,
               "fixture for this decision. absent"
             )

    rewritten =
      Ipse.Session.Lifecycle.answer(turn, request, message, "Different visible answer", source)

    {:ok, rewritten_window} =
      Ipse.Session.SourceWindow.restore(prefix ++ [committed, rewritten], session)

    assert {:error, _} =
             Ipse.Session.SourceWindow.planning_answer_request(
               rewritten_window,
               entry,
               turn,
               request,
               quote
             )

    assertion = %{
      "type" => "operator_assertion",
      "planning_decision" => accepted,
      "text" => quote,
      "category" => "ordinary"
    }

    refute Ipse.Session.OperatorAssertion.valid_event?(assertion, session)

    binding = Ipse.Test.ManagedPolicy.binding()
    policy = Ipse.Test.ManagedPolicy.policy()
    {:ok, selectors} = Ipse.Extension.SemanticRoutes.selectors(policy["settings"]["routes"])

    pin = %{
      "version" => 1,
      "session_id" => session,
      "epoch" => 1,
      "project_id" => binding["project_id"],
      "worktree_id" => binding["worktree_id"],
      "binding_sha256" => binding["binding_sha256"],
      "namespace" => policy["settings"]["namespace"],
      "policy_sha256" => JSON.digest([policy]),
      "identity_sha256" => policy["settings"]["identity_sha256"],
      "routes_sha256" => JSON.digest([policy["settings"]["routes"]]),
      "source_sha256" => policy["source_sha256"]
    }

    admission = %{
      "version" => 2,
      "binding" => binding,
      "instance" => "knowledge",
      "pin" => pin,
      "policy" => policy,
      "selectors" => selectors,
      "status" => "active"
    }

    assert Ipse.Extension.SemanticAdmission.valid?(admission, session)
    {:ok, scope} = Ipse.Session.OperatorAssertion.scope(admission)
    {:ok, review} = PlanningDecisions.stage_render(session, channel, accepted, scope)

    save = "/plan save " <> accepted["id"]
    stage = "stage " <> review["code"]
    command_observation = observation(save, "you> ", "5")
    stage_observation = observation(stage, review["display"], "6")

    assert {:ok, started} =
             PlanningDecisions.stage_started(
               review,
               accepted,
               command_observation,
               stage,
               stage_observation
             )

    assert {:error, _} =
             PlanningDecisions.stage_started(
               review,
               accepted,
               command_observation,
               "stage incorrect",
               stage_observation
             )

    assert {:error, _} = PlanningDecisions.restore(history ++ [accepted, started], session)

    legacy_save = PlanningDecisions.save_started(session, accepted, command_observation)

    assert {:error, _} =
             PlanningDecisions.restore(history ++ [accepted, exit, legacy_save], session)

    # A missing saved admission cannot authorize replay even after exit.
    assert {:error, _} = PlanningDecisions.restore(history ++ [accepted, exit, started], session)

    [header | rest] = history
    pinned = [put_in(header, ["metadata", "semantic_admission"], admission) | rest]
    assert {:ok, staged} = PlanningDecisions.restore(pinned ++ [accepted, exit, started], session)
    assert staged[accepted["id"]].attempted

    assert {:error, _} =
             PlanningDecisions.restore(pinned ++ [accepted, exit, started, started], session)

    assert {:error, :duplicate_operator_observation} =
             Ipse.Session.DraftAcceptance.validate_observation_uniqueness([
               accepted,
               started,
               %{"type" => "input_received", "observation" => command_observation}
             ])
  end
end
