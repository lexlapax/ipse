Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Extension.ModeHistoryTest do
  use ExUnit.Case, async: true

  alias Ipse.{JSON, Session.PlanningTransition}

  alias Ipse.Extension.{
    Actions,
    Catalog,
    Invocation,
    Mode,
    SemanticAdmission,
    SemanticConsent,
    SemanticRoutes
  }

  alias Ipse.Test.ManagedPolicy, as: F

  # These are constructed replay records with a structurally reviewed fixture
  # policy. They start no worker and supply no current artifact admission.
  setup do
    id = String.duplicate("a", 32)
    turn = String.duplicate("b", 32)
    request = String.duplicate("c", 32)

    descriptor = fn name ->
      %{
        "id" => name,
        "description" => "Constructed mode replay fixture",
        "arguments_schema" => %{"type" => "object", "additionalProperties" => true},
        "result_schema" => %{"type" => "object", "additionalProperties" => true}
      }
    end

    exports =
      Catalog.empty()
      |> Catalog.normalize()
      |> Map.put("tools", [descriptor.("nominate")])
      |> Map.put("commands", [descriptor.("capture")])

    identity =
      F.identity()
      |> Map.put("exports_sha256", Catalog.digest(exports))
      |> Map.put("subscriptions_sha256", Ipse.Extension.Subscriptions.digest([]))
      |> Map.update!("capabilities", &Enum.sort(["invoke.command" | &1]))

    assert {:ok, catalog} =
             Catalog.snapshot(%{extensions: [%{identity: identity, exports: exports}]})

    nomination = Enum.find(catalog["entries"], &(&1["id"] == "nominate"))
    capture = Enum.find(catalog["entries"], &(&1["id"] == "capture"))

    policy =
      F.policy()
      |> put_in(["settings", "identity_sha256"], JSON.digest([identity]))
      |> put_in(["settings", "activation", "capabilities"], identity["capabilities"])
      |> update_in(["settings", "effects"], fn effects ->
        Enum.map(effects, fn mapping ->
          if mapping["class"] == "collection.publish",
            do: Map.put(mapping, "outer_sha256", JSON.digest([capture])),
            else: mapping
        end)
      end)

    assert SemanticConsent.policy?(policy)
    assert {:ok, normal} = Mode.capture(%{approval: :ask, approval_origin: :interactive})
    planning = Map.put(normal, "ceiling", "planning")
    marker = PlanningTransition.startup(id, planning)

    context = %{
      "session_id" => id,
      "binding" => F.binding(),
      "identity" => identity,
      "namespace" => policy["settings"]["namespace"],
      "routes" => policy["settings"]["routes"],
      "mode" => planning,
      "source_generation" => 0
    }

    assert {:ok, pin} = SemanticConsent.admit(%{"epoch" => 1, "policy" => policy}, context, 1000)
    assert {:ok, selectors} = SemanticRoutes.selectors(policy["settings"]["routes"])

    admission = %{
      "version" => 2,
      "status" => "active",
      "binding" => F.binding(),
      "instance" => "knowledge",
      "pin" => pin,
      "selectors" => selectors,
      "policy" => policy
    }

    assert SemanticAdmission.valid?(admission, id)

    metadata = %{
      "cwd" => "/fixture/project",
      "extensions" => [identity],
      "extension_catalog" => catalog,
      "execution_mode" => planning,
      "planning_local_start" => marker,
      "semantic_admission" => admission
    }

    header = %{"type" => "session", "metadata" => metadata}
    assert :ok = Ipse.Extension.Subscriptions.validate_events([header])

    observation = %{
      "version" => 2,
      "event_id" => String.duplicate("d", 32),
      "text_sha256" => JSON.sha256("/plan exit"),
      "display_sha256" => JSON.sha256("you> "),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    exit = PlanningTransition.exit(id, marker, planning, observation)

    bound = fn descriptor, class ->
      %{
        "kind" => "semantic.outer",
        "version" => 1,
        "class" => class,
        "namespace" => pin["namespace"],
        "pin" => pin,
        "artifact_sha256" => identity["artifact_sha256"],
        "descriptor_sha256" => JSON.digest([descriptor])
      }
    end

    nomination =
      Invocation.intent(
        identity,
        nomination,
        %{},
        id,
        turn,
        "nominate",
        request,
        "saved_consent",
        bound.(nomination, "nomination.select")
      )

    assert {:ok, nominated} =
             Invocation.build_result(
               nomination,
               %{"api_version" => 1, "kind" => "result", "value" => %{"status" => "nominated"}}
             )

    capture =
      Invocation.intent(
        identity,
        capture,
        %{},
        id,
        turn,
        nil,
        nil,
        "saved_consent",
        bound.(capture, "collection.publish")
      )

    assert {:ok, action} =
             Actions.intent(
               capture,
               %{"op" => "source.list", "limit" => 1},
               1,
               "not_required",
               metadata["cwd"]
             )

    assert {:ok, action_result} =
             Actions.result(
               action,
               %{"status" => "failed", "value" => %{"code" => "source_refused"}}
             )

    assert {:ok, captured} =
             Invocation.build_result(
               capture,
               %{"api_version" => 1, "kind" => "result", "value" => %{"status" => "unavailable"}},
               [action_result]
             )

    transcript = [
      %{
        "type" => "request_admitted",
        "kind" => "model",
        "session_id" => id,
        "turn_id" => turn,
        "request_id" => request
      },
      %{
        "type" => "message",
        "request_id" => request,
        "message" => %{
          "role" => "assistant",
          "content" => "",
          "tool_calls" => [
            %{
              "id" => "nominate",
              "type" => "function",
              "function" => %{
                "name" => "ext__knowledge__nominate",
                "arguments" => "{}"
              }
            }
          ]
        }
      },
      %{
        "type" => "tool_started",
        "version" => 2,
        "call_id" => "nominate",
        "name" => "ext__knowledge__nominate",
        "arguments" => %{},
        "approval" => "saved_consent",
        "semantic_binding" => nomination["semantic_binding"]
      },
      nomination,
      nominated,
      %{"type" => "message", "message" => Invocation.tool_message(nominated)},
      capture,
      action,
      action_result,
      captured,
      %{"type" => "turn_finished", "status" => "ok"}
    ]

    %{
      id: id,
      metadata: metadata,
      header: header,
      planning: planning,
      normal: normal,
      exit: exit,
      transcript: transcript,
      nomination: nomination,
      capture: capture
    }
  end

  test "startup planning exit validates nomination and capture at their original positions", c do
    events = [c.header, c.exit | c.transcript]
    normal = c.normal
    assert {:ok, ^normal, nil} = PlanningTransition.reconstruct(events, c.id)
    assert {:ok, [{0, planning}, {1, normal}]} = PlanningTransition.mode_timeline(events, c.id)
    assert planning === c.planning and normal === c.normal
    assert :ok = Invocation.validate_events(events)
    assert {:ok, restored} = Actions.restore(events)
    assert restored.metadata === c.metadata
    assert restored.parent === nil and restored.action === nil
    assert {:error, _} = Invocation.validate_intent(c.nomination, c.metadata)
    assert {:error, _} = Invocation.validate_intent(c.capture, c.metadata)
  end

  test "protected tool replay uses witnessed current mode and retains original metadata", c do
    events = [c.header, c.exit | tool_transcript(c.transcript)]
    assert {:ok, saved} = Ipse.Session.ToolLifecycle.restore(events, c.id)
    assert saved.metadata === c.metadata
    assert saved.started.record["semantic_binding"] === c.nomination["semantic_binding"]
    assert {:ok, inferred} = Ipse.Session.ToolLifecycle.restore(events)
    assert inferred.metadata === c.metadata
  end

  test "tool replay refuses missing, future, forged and cross Session planning exits", c do
    transcript = tool_transcript(c.transcript)

    for events <- [
          [c.header | transcript],
          [c.header | transcript] ++ [c.exit],
          [
            c.header,
            put_in(c.exit, ["observation", "text_sha256"], JSON.sha256("other")) | transcript
          ],
          [c.header, Map.put(c.exit, "session_id", String.duplicate("e", 32)) | transcript],
          [c.header, Map.put(c.exit, "previous_sha256", JSON.sha256("other")) | transcript],
          [
            update_in(c.header, ["metadata"], &Map.delete(&1, "planning_local_start")),
            c.exit | transcript
          ]
        ] do
      assert {:error, :invalid_tool_lifecycle} = Ipse.Session.ToolLifecycle.restore(events, c.id)
      assert {:error, :invalid_tool_lifecycle} = Ipse.Session.ToolLifecycle.restore(events)
    end
  end

  defp tool_transcript(events) do
    Enum.map(events, fn
      %{"type" => "tool_started"} = event ->
        Map.merge(event, %{
          "approval_source" => "saved_consent",
          "mcp" => nil,
          "sandbox_requested" => "off"
        })

      event ->
        event
    end)
  end

  test "a future exit, changed witness, missing entry, or different Session never authorizes earlier intents",
       c do
    for events <- [
          [c.header | c.transcript],
          [c.header | c.transcript] ++ [c.exit],
          [
            c.header,
            put_in(c.exit, ["observation", "text_sha256"], JSON.sha256("other")) | c.transcript
          ],
          [c.header, Map.put(c.exit, "session_id", String.duplicate("e", 32)) | c.transcript],
          [c.header, Map.put(c.exit, "previous_sha256", JSON.sha256("other")) | c.transcript],
          [
            update_in(c.header, ["metadata"], &Map.delete(&1, "planning_local_start")),
            c.exit | c.transcript
          ]
        ] do
      assert {:error, _} = Invocation.validate_events(events)
      assert {:error, _} = Actions.restore(events)
    end
  end

  test "mode timeline stays sparse and legacy action slices preserve their missing marker", c do
    padding = List.duplicate(%{"type" => "fixture_observation"}, 1_000)

    assert {:ok, [{0, planning}, {1001, normal}] = timeline} =
             PlanningTransition.mode_timeline([c.header | padding] ++ [c.exit], c.id)

    assert planning === c.planning and normal === c.normal
    assert {^planning, ^timeline} = PlanningTransition.mode_at(timeline, 1000)
    assert {^normal, [{1001, ^normal}]} = PlanningTransition.mode_at(timeline, 1001)

    header = %{
      "type" => "session",
      "metadata" => %{"cwd" => "/fixture/project", "extensions" => []}
    }

    assert {:ok, nil, nil} = PlanningTransition.reconstruct([header], c.id)
    assert {:ok, [{0, nil}]} = PlanningTransition.mode_timeline([header], c.id)
    assert :ok = Invocation.validate_events([header])
    assert {:ok, restored} = Actions.restore([header])
    refute Map.has_key?(restored.metadata, "execution_mode")
    assert {:error, :invalid_extension_action} = Actions.restore([])

    assert {:error, :invalid_extension_action} =
             Actions.restore([%{"type" => "fixture_observation"}])

    assert {:error, :invalid_extension_invocation} = Invocation.validate_events([])

    assert {:error, :invalid_extension_invocation} =
             Invocation.validate_events([%{"type" => "fixture_observation"}])
  end

  test "an exit preserves a narrower enclosing ceiling instead of admitting protected work", c do
    assert {:ok, restricted} =
             Mode.resume(c.planning, %{
               approval: :ask,
               approval_origin: :interactive,
               execution_mode: :planning,
               enclosing_mode: :read_only
             })

    checkpoint = %{
      "type" => "execution_mode_resumed",
      "version" => 2,
      "session_id" => c.id,
      "previous_sha256" => JSON.digest([c.planning]),
      "mode" => restricted
    }

    marker = c.metadata["planning_local_start"]
    exit = PlanningTransition.exit(c.id, marker, restricted, c.exit["observation"])
    events = [c.header, checkpoint, exit | c.transcript]
    assert {:ok, mode, nil} = PlanningTransition.reconstruct(events, c.id)
    assert mode["ceiling"] === "normal" and mode["enclosing_ceiling"] === "read_only"
    assert {:error, _} = Invocation.validate_events(events)
    assert {:error, _} = Actions.restore(events)
  end
end
