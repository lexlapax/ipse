defmodule Ipse.Session.PlanningTransitionTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session.PlanningTransition}
  alias Ipse.Extension.Mode

  test "entry binds an observed command to the immediately preceding restrictive checkpoint" do
    session = String.duplicate("a", 32)
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

    observation = %{
      "version" => 2,
      "event_id" => String.duplicate("b", 32),
      "text_sha256" => JSON.sha256("/plan"),
      "display_sha256" => JSON.sha256("you> "),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    receipt = PlanningTransition.entry(session, checkpoint, observation)
    epoch = %{"type" => "planning_mcp_epoch", "startup" => "resume", "execution_mode" => planning}
    assert :ok = PlanningTransition.validate_events([header, checkpoint, receipt], session)
    assert :ok = PlanningTransition.validate_events([header, checkpoint, epoch, receipt], session)
    assert :ok = PlanningTransition.validate_events([header, checkpoint], session)

    {:ok, draft_mode} =
      planning |> Mode.config() |> Ipse.Session.Draft.draft_config() |> Mode.capture()

    draft_epoch = Map.put(epoch, "execution_mode", draft_mode)
    assert :ok = PlanningTransition.validate_events([header, checkpoint, draft_epoch], session)

    assert {:error, :invalid_planning_transition} =
             PlanningTransition.validate_events(
               [header, checkpoint, draft_epoch, receipt],
               session
             )

    startup = PlanningTransition.startup_selected(session, checkpoint)

    assert :ok =
             PlanningTransition.validate_events(
               [header, checkpoint, draft_epoch, startup],
               session
             )

    for invalid <- [
          [header, receipt],
          [header, checkpoint, receipt, receipt],
          [header, checkpoint, %{"type" => "message"}, receipt],
          [header, checkpoint, Map.put(receipt, "session_id", String.duplicate("c", 32))],
          [
            header,
            checkpoint,
            put_in(receipt, ["observation", "text_sha256"], JSON.sha256("other"))
          ],
          [header, checkpoint, Map.put(receipt, "checkpoint_sha256", JSON.sha256("other"))],
          [header, checkpoint, Map.put(receipt, "extra", true)],
          [header, Map.put(checkpoint, "mode", Map.put(planning, "approval", "allow")), receipt],
          [header, checkpoint, Map.put(epoch, "execution_mode", normal), receipt]
        ] do
      assert {:error, :invalid_planning_transition} =
               PlanningTransition.validate_events(invalid, session)
    end
  end

  test "planning entry observations cannot be reused by another operator input" do
    id = String.duplicate("a", 32)
    observation = %{"event_id" => id}

    events = [
      %{"type" => "planning_entry_observed", "observation" => observation},
      %{"type" => "input_received", "observation" => observation}
    ]

    assert {:error, :duplicate_operator_observation} =
             Ipse.Session.DraftAcceptance.validate_observation_uniqueness(events)
  end

  test "exit requires a witnessed local entry and preserves the current authority floors" do
    session = String.duplicate("a", 32)
    {:ok, normal} = Mode.capture(%{approval: :deny, approval_origin: :explicit})
    planning = Map.put(normal, "ceiling", "planning")
    header = %{"metadata" => %{"execution_mode" => normal}}

    checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 2,
      "session_id" => session,
      "previous_sha256" => JSON.digest([normal]),
      "mode" => planning
    }

    observation = fn text, id ->
      %{
        "version" => 2,
        "event_id" => String.duplicate(id, 32),
        "text_sha256" => JSON.sha256(text),
        "display_sha256" => JSON.sha256("you> "),
        "input_limit" => 1_048_576,
        "display_limit" => 16_777_216
      }
    end

    entry = PlanningTransition.entry(session, checkpoint, observation.("/plan", "b"))
    exit = PlanningTransition.exit(session, entry, planning, observation.("/plan exit", "c"))
    events = [header, checkpoint, entry, exit]
    assert {:ok, ^normal} = Ipse.Session.Saved.execution_mode(events, session)
    assert :ok = PlanningTransition.validate_events(events, session)

    {:ok, inherited} =
      Mode.resume(planning, %{
        approval: :allow,
        approval_origin: :yes,
        enclosing_mode: :read_only,
        knowledge_ceiling: :disabled
      })

    resume = %{
      "type" => "execution_mode_resumed",
      "version" => 2,
      "session_id" => session,
      "previous_sha256" => JSON.digest([planning]),
      "mode" => inherited
    }

    inherited_exit =
      PlanningTransition.exit(session, entry, inherited, observation.("/plan exit", "d"))

    assert {:ok, inherited_result} =
             Ipse.Session.Saved.execution_mode(
               [header, checkpoint, entry, resume, inherited_exit],
               session
             )

    assert inherited_result["ceiling"] == "normal"
    assert inherited_result["enclosing_ceiling"] == "read_only"
    assert inherited_result["approval"] == "deny"
    assert inherited_result["knowledge"] == "disabled"

    {:ok, legacy_mode} = Mode.inherit(planning, %{approval: :ask, execution_mode: :planning})
    assert legacy_mode["ceiling"] == "planning" and legacy_mode["enclosing_ceiling"] == "planning"
    legacy = %{resume | "version" => 1, "mode" => legacy_mode}

    legacy_exit =
      PlanningTransition.exit(session, entry, legacy_mode, observation.("/plan exit", "e"))

    assert {:error, _} =
             Ipse.Session.Saved.execution_mode(
               [header, checkpoint, entry, legacy, legacy_exit],
               session
             )

    for invalid <- [
          [header, checkpoint, exit],
          [header, checkpoint, entry, exit, exit],
          [header, checkpoint, entry, put_in(exit, ["mode", "approval"], "allow")],
          [header, checkpoint, entry, Map.put(exit, "entry_sha256", JSON.sha256("other"))],
          [
            header,
            checkpoint,
            entry,
            put_in(exit, ["observation", "text_sha256"], JSON.sha256("/plan"))
          ],
          [header, checkpoint, entry, Map.put(exit, "session_id", String.duplicate("d", 32))]
        ] do
      assert {:error, _} = Ipse.Session.Saved.execution_mode(invalid, session)
    end
  end

  test "explicit startup selection is bound to a new header or a normal-to-planning checkpoint" do
    session = String.duplicate("a", 32)
    {:ok, planning} = Mode.capture(%{approval: :ask, execution_mode: :planning})
    marker = PlanningTransition.startup(session, planning)
    header = %{"metadata" => %{"execution_mode" => planning, "planning_local_start" => marker}}

    observation = %{
      "version" => 2,
      "event_id" => String.duplicate("b", 32),
      "text_sha256" => JSON.sha256("/plan exit"),
      "display_sha256" => JSON.sha256("you> "),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    exit = PlanningTransition.exit(session, marker, planning, observation)
    assert {:ok, exited} = Ipse.Session.Saved.execution_mode([header, exit], session)
    assert exited["ceiling"] == "normal"

    assert {:error, _} =
             Ipse.Session.Saved.execution_mode(
               [put_in(header, ["metadata", "delegation_origin"], %{}), exit],
               session
             )

    {:ok, normal} = Mode.capture(%{approval: :ask})

    {:ok, selected} =
      Mode.resume(normal, %{approval: :allow, approval_origin: :yes, execution_mode: :planning})

    checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 2,
      "session_id" => session,
      "previous_sha256" => JSON.digest([normal]),
      "mode" => selected
    }

    resumed_marker = PlanningTransition.startup_selected(session, checkpoint)
    resumed_exit = PlanningTransition.exit(session, resumed_marker, selected, observation)
    normal_header = %{"metadata" => %{"execution_mode" => normal}}

    assert {:ok, mode} =
             Ipse.Session.Saved.execution_mode(
               [normal_header, checkpoint, resumed_marker, resumed_exit],
               session
             )

    assert mode["ceiling"] == "normal" and mode["approval"] == "allow"

    assert {:error, _} =
             Ipse.Session.Saved.execution_mode([normal_header, checkpoint, resumed_exit], session)

    assert {:error, _} =
             Ipse.Session.Saved.execution_mode(
               [
                 normal_header,
                 checkpoint,
                 Map.put(resumed_marker, "checkpoint_sha256", JSON.sha256("other")),
                 resumed_exit
               ],
               session
             )
  end
end
