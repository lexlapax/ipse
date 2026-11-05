unless Code.ensure_loaded?(Ipse.Test.ManagedPolicy),
  do: Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Extension.ManagedEventOutputReplayTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Journal, Session}

  alias Ipse.Extension.{
    Actions,
    Catalog,
    CollectionCall,
    Invocation,
    Mode,
    Registry,
    SemanticAdmission,
    SemanticConsent,
    SemanticRoutes,
    Subscriptions
  }

  alias Ipse.Session.{ManagedOutput, ManagedReads}
  alias Ipse.Test.ManagedPolicy, as: F

  # Constructed replay protocol only: no App, owner, artifact or source authority.
  def fixture(decision \\ "withdrawn", cleanup \\ "confirmed") do
    id = String.duplicate("a", 32)
    turn = String.duplicate("b", 32)

    descriptor = fn name ->
      %{
        "id" => name,
        "description" => "Constructed replay fixture",
        "arguments_schema" => %{"type" => "object", "additionalProperties" => true},
        "result_schema" => %{"type" => "object", "additionalProperties" => true}
      }
    end

    exports =
      Catalog.empty()
      |> Catalog.normalize()
      |> Map.put("tools", [descriptor.("unused")])
      |> Map.put("jobs", [descriptor.("recall")])

    declaration = %{
      "id" => "recall",
      "event" => "prompt.effective_committed",
      "event_version" => 1,
      "view" => "metadata",
      "mode" => "job",
      "required" => false,
      "handler" => "recall",
      "schedule" => "before_request"
    }

    identity =
      F.identity()
      |> Map.put("exports_sha256", Catalog.digest(exports))
      |> Map.put("subscriptions_sha256", Subscriptions.digest([declaration]))
      |> Map.update!("capabilities", &Enum.sort(["event.job" | &1]))

    assert Registry.valid_identity?(identity)
    entry = %{identity: identity, exports: exports, subscriptions: [declaration]}
    config = %{extensions: [entry]}
    {:ok, catalog} = Catalog.snapshot(config)
    job = Enum.find(catalog["entries"], &(&1["stage"] == "event.job"))

    policy =
      F.policy()
      |> put_in(["settings", "identity_sha256"], JSON.digest([identity]))
      |> put_in(["settings", "activation", "capabilities"], identity["capabilities"])
      |> update_in(["settings", "effects"], fn es ->
        Enum.map(es, fn e ->
          if e["class"] == "collection.read",
            do: Map.put(e, "outer_sha256", JSON.digest([job])),
            else: e
        end)
      end)

    assert SemanticConsent.policy?(policy)
    {:ok, mode} = Mode.capture(%{approval: :ask, approval_origin: :interactive})

    context = %{
      "session_id" => id,
      "binding" => F.binding(),
      "identity" => identity,
      "namespace" => policy["settings"]["namespace"],
      "routes" => policy["settings"]["routes"],
      "mode" => mode,
      "source_generation" => 0
    }

    {:ok, pin} = SemanticConsent.admit(%{"epoch" => 1, "policy" => policy}, context, 1000)
    {:ok, selectors} = SemanticRoutes.selectors(policy["settings"]["routes"])

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
      "extension_subscriptions" => Subscriptions.snapshot(config),
      "execution_mode" => mode,
      "semantic_admission" => admission,
      "managed_read_layout" => ManagedReads.layout(),
      "managed_output_layout" => ManagedOutput.layout()
    }

    header = %{"type" => "session", "metadata" => metadata}
    received = Subscriptions.received(turn, "Constructed ordinary prompt")
    {:ok, received_source} = Journal.source(id, byte_size(Jason.encode!(header)) + 1, received)

    message = %{
      "type" => "message",
      "message" => %{"role" => "user", "content" => "Constructed ordinary prompt"}
    }

    committed =
      Subscriptions.committed(
        turn,
        "Constructed ordinary prompt",
        message["message"],
        received_source
      )

    prefix = [header, received, message]

    {:ok, effective_source} =
      Journal.source(
        id,
        Enum.sum(Enum.map(prefix, &(byte_size(Jason.encode!(&1)) + 1))),
        committed
      )

    {delivery, payload} =
      Subscriptions.intent(identity, declaration, effective_source, committed, turn)

    outer = %{
      "kind" => "semantic.outer",
      "version" => 1,
      "class" => "collection.read",
      "namespace" => pin["namespace"],
      "pin" => pin,
      "artifact_sha256" => identity["artifact_sha256"],
      "descriptor_sha256" => JSON.digest([job])
    }

    {:ok, parent} =
      Invocation.prepare_event(
        config,
        entry,
        delivery,
        payload,
        %{
          received: %{source: received_source, record: received},
          effective: %{source: effective_source, record: committed}
        },
        id,
        turn,
        outer
      )

    request = %{"op" => "collection.call", "request" => %{"op" => "snapshot"}}
    {:ok, binding} = CollectionCall.binding(%{semantic_admission: admission}, identity, request)

    {:ok, action} =
      Actions.intent(parent, request, 1, "not_required", metadata["cwd"], nil, nil, binding)

    value = %{
      "version" => 3,
      "project" => pin["namespace"],
      "generation" => 0,
      "floor" => 0,
      "floor_anchor" => nil
    }

    dep = %{
      "version" => 3,
      "project_id" => pin["project_id"],
      "namespace" => pin["namespace"],
      "pin_sha256" => JSON.digest([pin]),
      "policy_generation" => pin["epoch"],
      "collection" =>
        Map.merge(Map.take(value, ~w(project generation floor floor_anchor)), %{
          "root_state" => "absent",
          "root_sha256" => nil,
          "manifest_sha256" => nil
        }),
      "subject" => %{
        "kind" => "root_observation",
        "request_sha256" => JSON.digest([request["request"]]),
        "result_sha256" => JSON.digest([value])
      }
    }

    {:ok, observed} = ManagedReads.prepare(id, action, value, [dep], parent)
    {:ok, result} = Actions.result(action, %{"status" => "ok", "value" => value})

    {:ok, raw} =
      Invocation.build_result(
        parent,
        %{"api_version" => 1, "kind" => "result", "value" => %{"status" => "ok"}},
        [result]
      )

    intent = ManagedOutput.intent(id, parent, raw, [dep], 1001, 2000)
    admitted = ManagedOutput.admission(intent, raw, decision, [], 1002, 2000)
    cleaned = ManagedOutput.cleanup(intent, admitted, cleanup)
    outcome = if decision == "current", do: "completed", else: "failed"
    finished = Subscriptions.result(delivery, outcome, true)

    before =
      prefix ++
        [committed, delivery, parent, action, observed, result, intent, raw, admitted, cleaned]

    %{
      id: id,
      before: before,
      events: before ++ [finished],
      delivery: delivery,
      finished: finished,
      parent: parent,
      intent: intent,
      raw: raw,
      admitted: admitted,
      cleaned: cleaned
    }
  end

  test "confirmed withdrawn output records failed after successful actions and restores Saved" do
    f = fixture()
    assert :ok = Subscriptions.validate_events(f.before)
    assert :ok = Subscriptions.validate_events(f.events)
    assert {:ok, _} = Actions.restore(f.events)
    assert {:ok, _} = Session.Saved.restore(f.events, f.id)

    assert {:ok, _} =
             Session.Saved.restore(
               f.events ++ [%{"type" => "turn_finished", "status" => "error"}],
               f.id
             )
  end

  test "current output and ordinary completed event outcomes remain strict" do
    f = fixture("current")
    assert :ok = Subscriptions.validate_events(f.events)
    assert {:ok, _} = Session.Saved.restore(f.events, f.id)
    failed = List.replace_at(f.events, -1, Subscriptions.result(f.delivery, "failed", true))
    assert {:error, _} = Subscriptions.validate_events(failed)
    ordinary = Enum.reject(f.events, &String.starts_with?(&1["type"], "managed_output_release_"))
    assert :ok = Subscriptions.validate_events(ordinary)

    assert {:error, _} =
             Subscriptions.validate_events(
               List.replace_at(ordinary, -1, Subscriptions.result(f.delivery, "failed", true))
             )
  end

  test "unknown or missing cleanup cannot authenticate a failed completed job" do
    for cleanup <- ["unknown", nil] do
      f = fixture("withdrawn", cleanup || "confirmed")

      events =
        if is_nil(cleanup),
          do: Enum.reject(f.events, &(&1["type"] == "managed_output_release_cleanup")),
          else: f.events

      assert {:error, _} = Subscriptions.validate_events(events)
      assert {:error, _} = Session.Saved.restore(events, f.id)
    end
  end

  test "unknown cleanup can remain explicitly unknown without creating current output" do
    f = fixture("withdrawn", "unknown")
    events = List.replace_at(f.events, -1, Subscriptions.result(f.delivery, "unknown", false))
    assert :ok = Subscriptions.validate_events(events)
    assert {:ok, saved} = Session.Saved.restore(events, f.id)
    assert saved.managed_lineage.unavailable
    refute Map.has_key?(saved.extension_state.contributions, "knowledge")
  end

  test "foreign delivery, invocation, release and changed hashes refuse" do
    f = fixture()

    for {kind, field, changed} <- [
          {"extension_event_result", "delivery_id", String.duplicate("f", 32)},
          {"managed_output_release_intent", "parent_invocation_id", String.duplicate("f", 32)},
          {"managed_output_release_result", "release_id", String.duplicate("f", 32)},
          {"managed_output_release_result", "projection_sha256", JSON.sha256("changed")},
          {"managed_output_release_cleanup", "result_sha256", JSON.sha256("changed")},
          {"managed_output_release_intent", "actions_sha256", JSON.sha256("changed")},
          {"extension_invocation_result", "invocation_id", String.duplicate("f", 32)},
          {"managed_output_release_result", "intent_sha256", JSON.sha256("changed")}
        ] do
      changed =
        Enum.map(f.events, fn e ->
          if e["type"] == kind, do: Map.put(e, field, changed), else: e
        end)

      assert {:error, _} = Subscriptions.validate_events(changed)
    end
  end

  test "a bare or incomplete withdrawal string is not an outcome exception" do
    f = fixture()

    for missing <-
          ~w(managed_output_release_intent managed_output_release_result extension_invocation_result) do
      assert {:error, _} =
               Subscriptions.validate_events(Enum.reject(f.events, &(&1["type"] == missing)))
    end

    duplicated = f.before ++ [f.cleaned, f.finished]
    assert {:error, _} = Subscriptions.validate_events(duplicated)
    completed = List.replace_at(f.events, -1, Subscriptions.result(f.delivery, "completed", true))
    assert {:error, _} = Subscriptions.validate_events(completed)
  end
end
