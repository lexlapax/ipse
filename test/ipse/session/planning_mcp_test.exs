defmodule Ipse.Session.PlanningMCPTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session.PlanningMCP}

  test "a valid terminal journal limit permits inspection before the initial declared-read epoch" do
    session = String.duplicate("a", 32)

    reads = %{
      "mcp__notes__lookup" => %{
        "version" => 1,
        "server_id" => "notes",
        "tool" => "lookup",
        "endpoint_sha256" => JSON.sha256("endpoint"),
        "descriptor_sha256" => JSON.sha256("descriptor")
      }
    }

    {:ok, mode} = Ipse.Extension.Mode.capture(%{approval: :ask})

    header = %{
      "metadata" => %{
        "execution_mode" => mode,
        "planning_mcp_protocol" => 1,
        "configuration" => %{"planning_mcp_reads" => reads}
      }
    }

    limit = Ipse.Journal.limit_receipt(Ipse.Journal.limits(), 10, 1, "events")
    assert :ok = PlanningMCP.validate_events([header, limit], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([header, limit, %{"type" => "tool_started"}], session)
  end

  test "undeclared MCP starts remain forbidden after a planning checkpoint and a completed draft" do
    session = String.duplicate("a", 32)
    turn = String.duplicate("b", 32)
    draft = String.duplicate("c", 32)
    {:ok, normal} = Ipse.Extension.Mode.capture(%{approval: :ask})
    {:ok, planning} = Ipse.Extension.Mode.inherit(normal, %{execution_mode: :planning})
    header = %{"metadata" => %{"execution_mode" => normal}}

    checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 1,
      "session_id" => session,
      "previous_sha256" => JSON.digest([normal]),
      "mode" => planning
    }

    start = %{"type" => "tool_started", "name" => "mcp__notes__lookup"}

    draft_start = %{
      "type" => "draft_started",
      "session_id" => session,
      "turn_id" => turn,
      "draft_id" => draft
    }

    assert :ok = PlanningMCP.validate_events([header, start], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([header, checkpoint, start], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               [%{"metadata" => %{}}, Map.put(checkpoint, "version", 3)],
               session
             )

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               [header, draft_start, %{"type" => "draft_completed"}, start],
               session
             )

    for terminal <- ["draft_cancelled", "draft_consumed"] do
      assert :ok =
               PlanningMCP.validate_events(
                 [
                   header,
                   draft_start,
                   %{"type" => "draft_completed"},
                   %{"type" => terminal},
                   start
                 ],
                 session
               )

      assert {:error, :invalid_planning_mcp_history} =
               PlanningMCP.validate_events(
                 [header, draft_start, checkpoint, %{"type" => terminal}, start],
                 session
               )
    end
  end

  test "resumed planning mode uses an explicit bound epoch and cannot widen an earlier ceiling" do
    session = String.duplicate("1", 32)
    first_id = String.duplicate("2", 32)
    second_id = String.duplicate("3", 32)

    reads = %{
      "mcp__notes__lookup" => %{
        "version" => 1,
        "server_id" => "notes",
        "tool" => "lookup",
        "endpoint_sha256" => JSON.sha256("endpoint"),
        "descriptor_sha256" => JSON.sha256("descriptor")
      }
    }

    {:ok, initial} = Ipse.Extension.Mode.capture(%{approval: :ask, execution_mode: :planning})

    {:ok, resumed} =
      Ipse.Extension.Mode.inherit(initial, %{approval: :allow, execution_mode: :normal})

    header = %{
      "metadata" => %{
        "execution_mode" => initial,
        "planning_mcp_protocol" => 1,
        "configuration" => %{"planning_mcp_reads" => reads}
      }
    }

    first = PlanningMCP.epoch(session, first_id, nil, "fresh", initial, reads)
    second = PlanningMCP.epoch(session, second_id, first_id, "resume", resumed, reads)
    assert :ok = PlanningMCP.validate_events([header, first, second], session)
    forged = put_in(second, ["execution_mode", "enclosing_ceiling"], "normal")

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([header, first, forged], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([header, second], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([header, first, first], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([header, %{"type" => "input_received"}], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               [header, Map.put(first, "declaration_sha256", JSON.sha256("other"))],
               session
             )

    {:ok, denied} = Ipse.Extension.Mode.capture(%{approval: :deny, approval_origin: :explicit})
    deny_header = put_in(header, ["metadata", "execution_mode"], denied)
    deny_epoch = PlanningMCP.epoch(session, first_id, nil, "fresh", denied, reads)
    forged_allow = PlanningMCP.epoch(session, second_id, first_id, "resume", resumed, reads)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([deny_header, deny_epoch, forged_allow], session)
  end

  test "replay binds a restricted MCP start to the operator declaration, catalog and model call" do
    session = String.duplicate("a", 32)
    turn = String.duplicate("b", 32)
    draft = String.duplicate("c", 32)
    request = String.duplicate("d", 32)
    name = "mcp__notes__lookup"
    endpoint = JSON.sha256("endpoint")
    descriptor = JSON.sha256("descriptor")
    epoch_id = String.duplicate("f", 32)

    declaration = %{
      "version" => 1,
      "server_id" => "notes",
      "tool" => "lookup",
      "endpoint_sha256" => endpoint,
      "descriptor_sha256" => descriptor
    }

    {:ok, mode} = Ipse.Extension.Mode.capture(%{approval: :ask})

    header = %{
      "metadata" => %{
        "configuration" => %{"planning_mcp_reads" => %{name => declaration}},
        "execution_mode" => mode,
        "mcp_servers" => [endpoint],
        "planning_mcp_protocol" => 1
      }
    }

    manifest = %{
      "tool_id" => name,
      "server_id" => "notes",
      "name" => "lookup",
      "descriptor_sha256" => descriptor,
      "origin" => %{"configured_endpoint_fingerprint" => endpoint}
    }

    catalog = %{"type" => "mcp_catalog", "version" => 1, "tools" => [manifest]}

    started = %{
      "type" => "draft_started",
      "session_id" => session,
      "turn_id" => turn,
      "draft_id" => draft
    }

    admitted = %{
      "type" => "request_admitted",
      "kind" => "model",
      "session_id" => session,
      "turn_id" => turn,
      "request_id" => request
    }

    call = %{"id" => "call-1", "function" => %{"name" => name, "arguments" => ~s({"q":"x"})}}

    assistant = %{
      "type" => "message",
      "request_id" => request,
      "message" => %{"role" => "assistant", "tool_calls" => [call]}
    }

    start = %{
      "type" => "tool_started",
      "call_id" => "call-1",
      "name" => name,
      "arguments" => %{"q" => "x"},
      "approval" => "approved",
      "approval_source" => "approved",
      "sandbox_requested" => "off",
      "mcp" => manifest
    }

    reads = %{name => declaration}
    epoch = PlanningMCP.epoch(session, epoch_id, nil, "fresh", mode, reads)
    intent = PlanningMCP.intent(session, turn, draft, epoch_id, start, declaration)
    prefix = [header, epoch, catalog, started, admitted, assistant]
    assert :ok = PlanningMCP.validate_events(prefix ++ [intent, start], session)
    assert :ok = PlanningMCP.validate_events(prefix ++ [intent], session)

    {:ok, owner} = Ipse.Session.ReleaseReceipt.owner_started(session)

    marked_header =
      put_in(header, ["metadata", "release_receipt_layout"], Ipse.Session.ReleaseReceipt.layout())

    marked_header =
      put_in(marked_header, ["metadata", "source_origin"], %{"session_id" => session})

    assert :ok = PlanningMCP.validate_events([marked_header, owner, epoch], session)
    assert :ok = PlanningMCP.validate_events([marked_header, owner], nil)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               [marked_header, Map.put(owner, "session_id", String.duplicate("f", 32))],
               nil
             )

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([marked_header, owner, start], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events([header, owner, epoch], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               [marked_header, Map.put(owner, "owner_id", "bad"), epoch],
               session
             )

    marked_prefix = [marked_header, epoch, catalog, started, admitted, assistant]
    assert :ok = PlanningMCP.validate_events(marked_prefix ++ [intent, owner], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(marked_prefix ++ [intent, owner, start], session)

    sealed =
      prefix ++
        [
          intent,
          Ipse.Journal.limit_receipt(Ipse.Journal.limits(), 10, length(prefix) + 1, "events")
        ]

    assert :ok = PlanningMCP.validate_events(sealed, session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(sealed ++ [start], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               prefix ++ [%{"type" => "draft_completed"}, intent, start],
               session
             )

    {:ok, planning_on_resume} =
      Ipse.Extension.Mode.inherit(mode, %{approval: :ask, execution_mode: :planning})

    {:ok, resumed_draft_mode} =
      planning_on_resume
      |> Ipse.Extension.Mode.config()
      |> Ipse.Session.Draft.draft_config()
      |> Ipse.Extension.Mode.capture()

    resume_checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 1,
      "session_id" => session,
      "previous_sha256" => JSON.digest([mode]),
      "mode" => planning_on_resume
    }

    ordinary_before_epoch = PlanningMCP.ordinary_intent(session, turn, epoch_id, start)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               [
                 header,
                 epoch,
                 catalog,
                 admitted,
                 assistant,
                 resume_checkpoint,
                 ordinary_before_epoch,
                 start
               ],
               session
             )

    draft_epoch =
      PlanningMCP.epoch(
        session,
        String.duplicate("8", 32),
        epoch_id,
        "resume",
        resumed_draft_mode,
        reads
      )

    assert :ok =
             PlanningMCP.validate_events(
               prefix ++ [intent, start, resume_checkpoint, draft_epoch],
               session
             )

    {:ok, recovered_mode} = Ipse.Extension.Mode.inherit(planning_on_resume, %{approval: :ask})

    {:ok, recovered_draft_mode} =
      recovered_mode
      |> Ipse.Extension.Mode.config()
      |> Ipse.Session.Draft.draft_config()
      |> Ipse.Extension.Mode.capture()

    recovered_checkpoint = %{
      resume_checkpoint
      | "previous_sha256" => JSON.digest([planning_on_resume]),
        "mode" => recovered_mode
    }

    recovered_epoch = Map.put(draft_epoch, "execution_mode", recovered_draft_mode)

    assert :ok =
             PlanningMCP.validate_events(
               prefix ++ [intent, start, resume_checkpoint, recovered_checkpoint, recovered_epoch],
               session
             )

    wrong_epoch = Map.put(draft_epoch, "execution_mode", mode)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               prefix ++ [intent, start, resume_checkpoint, wrong_epoch],
               session
             )

    {:ok, normal_draft_mode} =
      mode
      |> Ipse.Extension.Mode.config()
      |> Ipse.Session.Draft.draft_config()
      |> Ipse.Extension.Mode.capture()

    normal_draft_epoch =
      PlanningMCP.epoch(
        session,
        String.duplicate("7", 32),
        epoch_id,
        "resume",
        normal_draft_mode,
        reads
      )

    ordinary = PlanningMCP.ordinary_intent(session, turn, normal_draft_epoch["epoch_id"], start)
    resumed_prefix = [header, epoch, catalog, started, normal_draft_epoch]

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               resumed_prefix ++
                 [%{"type" => "draft_completed"}, admitted, assistant, ordinary, start],
               session
             )

    for terminal <- ["draft_cancelled", "draft_consumed"] do
      assert :ok =
               PlanningMCP.validate_events(
                 resumed_prefix ++ [%{"type" => terminal}, admitted, assistant, ordinary, start],
                 session
               )
    end

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(prefix ++ [intent, start, intent, start], session)

    resumed_epoch_id = String.duplicate("9", 32)
    resumed_epoch = PlanningMCP.epoch(session, resumed_epoch_id, epoch_id, "resume", mode, reads)

    resumed_intent =
      PlanningMCP.intent(session, turn, draft, resumed_epoch_id, start, declaration)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               prefix ++ [intent, start, resumed_epoch, resumed_intent, start],
               session
             )

    next_request = String.duplicate("e", 32)
    admitted_next = Map.put(admitted, "request_id", next_request)
    assistant_next = Map.put(assistant, "request_id", next_request)

    assert :ok =
             PlanningMCP.validate_events(
               prefix ++ [intent, start, admitted_next, assistant_next, intent, start],
               session
             )

    ordinary_intent = PlanningMCP.ordinary_intent(session, turn, epoch_id, start)
    ordinary_prefix = [header, epoch, catalog, admitted, assistant]

    assert :ok =
             PlanningMCP.validate_events(ordinary_prefix ++ [ordinary_intent, start], session)

    assert {:error, :invalid_planning_mcp_history} =
             PlanningMCP.validate_events(
               ordinary_prefix ++ [ordinary_intent, start, ordinary_intent, start],
               session
             )

    {:ok, allow_mode} = Ipse.Extension.Mode.capture(%{approval: :allow})
    allow_header = put_in(header, ["metadata", "execution_mode"], allow_mode)

    allow_start =
      Map.merge(start, %{"approval" => "session_allow", "approval_source" => "session_allow"})

    allow_epoch = PlanningMCP.epoch(session, epoch_id, nil, "fresh", allow_mode, reads)
    allow_intent = PlanningMCP.intent(session, turn, draft, epoch_id, allow_start, declaration)

    assert :ok =
             PlanningMCP.validate_events(
               [
                 allow_header,
                 allow_epoch,
                 catalog,
                 started,
                 admitted,
                 assistant,
                 allow_intent,
                 allow_start
               ],
               session
             )

    {:ok, planning_mode} =
      Ipse.Extension.Mode.capture(%{approval: :ask, execution_mode: :planning})

    planning_header = put_in(header, ["metadata", "execution_mode"], planning_mode)
    planning_epoch = PlanningMCP.epoch(session, epoch_id, nil, "fresh", planning_mode, reads)
    planning_intent = PlanningMCP.intent(session, turn, nil, epoch_id, start, declaration)

    assert :ok =
             PlanningMCP.validate_events(
               [
                 planning_header,
                 planning_epoch,
                 catalog,
                 admitted,
                 assistant,
                 planning_intent,
                 start
               ],
               session
             )

    assert :ok =
             PlanningMCP.validate_events(
               prefix ++
                 [
                   intent,
                   PlanningMCP.epoch(
                     session,
                     String.duplicate("e", 32),
                     epoch_id,
                     "resume",
                     mode,
                     reads
                   )
                 ],
               session
             )

    for events <- [
          prefix ++ [start],
          prefix ++ [Map.put(start, "mcp", nil)],
          prefix ++ [intent, intent, start],
          prefix ++ [intent, Map.put(start, "arguments", %{"q" => "changed"})],
          prefix ++ [Map.put(intent, "turn_id", String.duplicate("e", 32)), start],
          [
            put_in(header, ["metadata", "mcp_servers"], []),
            epoch,
            catalog,
            started,
            admitted,
            assistant,
            intent,
            start
          ],
          [
            header,
            epoch,
            %{catalog | "tools" => []},
            started,
            admitted,
            assistant,
            intent,
            start
          ],
          [
            put_in(header, ["metadata", "configuration", "planning_mcp_reads"], %{}),
            epoch,
            catalog,
            started,
            admitted,
            assistant,
            intent,
            start
          ],
          [
            put_in(header, ["metadata", "execution_mode", "enclosing_ceiling"], "read_only"),
            epoch,
            catalog,
            started,
            admitted,
            assistant,
            intent,
            start
          ],
          [
            put_in(header, ["metadata", "execution_mode", "approval"], "deny"),
            epoch,
            catalog,
            started,
            admitted,
            assistant,
            intent,
            start
          ]
        ] do
      assert {:error, :invalid_planning_mcp_history} =
               PlanningMCP.validate_events(events, session)
    end
  end
end
