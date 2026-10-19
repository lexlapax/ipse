defmodule Ipse.LifecycleMetadataTest do
  use ExUnit.Case, async: true
  alias Ipse.Lifecycle.{Event, Source}

  test "saved result finals expose completion metadata without source bodies or descriptors" do
    record = %{
      "type" => "extension_invocation_result",
      "version" => 2,
      "invocation_id" => Ipse.Usage.id(),
      "action_count" => 2,
      "delivery" => %{"output_id" => "private-output", "sha256" => "private-sha"},
      "text" => "private-descriptor",
      "payload" => %{"arguments" => %{"secret" => "private-input"}}
    }

    reference = source(record)
    assert {:ok, event} = Event.project(reference, record, "metadata")
    assert event["type"] == "extension.invocation_recorded"
    assert event["data"] == %{"action_count" => 2}
    assert event["correlations"] == %{"invocation_id" => record["invocation_id"]}
    refute Jason.encode!(event) =~ "private-"
    assert {:ok, observation} = Ipse.Observability.Event.build(reference, record, 1, 0)
    assert observation["event"] == event

    for type <- ~w(extension_output_begin extension_output_chunk extension_output_seal),
        version <- [1, 2] do
      hidden = Map.merge(record, %{"type" => type, "version" => version})
      assert {:error, _} = Event.project(source(hidden), hidden, "metadata")
    end

    invalid = Map.put(record, "version", 3)
    assert {:error, _} = Event.project(source(invalid), invalid, "metadata")
  end

  test "version-two action metadata omits private bindings and keeps the closed vocabulary" do
    for {type, event_type} <- [
          {"extension_action_intent", "extension.action_admitted"},
          {"extension_action_result", "extension.action_recorded"}
        ] do
      record = %{
        "type" => type,
        "version" => 2,
        "parent_invocation_id" => Ipse.Usage.id(),
        "operation_id" => Ipse.Usage.id(),
        "effect_binding" => %{"alias" => "secret-route", "server" => "secret-server"},
        "request" => %{"arguments" => %{"query" => "secret-argument"}},
        "outcome" => %{"status" => "ok", "value" => %{"text" => "secret-result"}}
      }

      assert {:ok, event} = Event.project(source(record, Ipse.Usage.id()), record, "metadata")
      assert event["type"] == event_type
      assert event["correlations"]["operation_id"] == record["operation_id"]
      refute Jason.encode!(event) =~ "secret-"
      invalid = Map.put(record, "type", "extension_question")
      assert {:error, _} = Event.project(source(invalid, Ipse.Usage.id()), invalid, "metadata")
    end
  end

  test "request metadata keeps durable identity and causal links while excluding provider payloads" do
    session = Ipse.Usage.id()
    parent_session = Ipse.Usage.id()
    parent_request = Ipse.Usage.id()

    config = %{
      provider: :demo,
      model: "synthetic-model-secret",
      base_url: "https://synthetic-private-endpoint.invalid",
      delegation_origin: %{
        "parent_session_id" => parent_session,
        "parent_request_id" => parent_request
      }
    }

    record = Ipse.Usage.admission(session, config, "model", Ipse.Usage.id())
    source = source(record, session)
    assert {:ok, event} = Event.project(source, record, "metadata")
    assert event["type"] == "model.admitted"
    assert event["event_id"] == source["event_id"]
    assert event["data"] == %{"kind" => "model"}
    assert event["correlations"]["request_id"] == record["request_id"]
    assert event["correlations"]["parent_session_id"] == parent_session
    assert event["correlations"]["parent_request_id"] == parent_request

    refute String.contains?(Jason.encode!(event), [
             config.model,
             record["endpoint_sha256"],
             source["record_sha256"]
           ])

    assert {:error, :lifecycle_view_unavailable} = Event.project(source, record, "model.private")
    assert {:error, :invalid_lifecycle_event} = Event.project(source, record, nil)

    assert {:error, :invalid_lifecycle_event} =
             Event.project(source, Map.put(record, "attempt", 2), "metadata")
  end

  test "a closed vocabulary projects existing boundaries without exposing arbitrary fields" do
    records = [
      {%{"type" => "session", "metadata" => %{"secret" => "private"}}, "session.created"},
      {%{
         "type" => "tool_started",
         "approval" => "approved",
         "arguments" => %{"text" => "private"}
       }, "tool.started"},
      {%{
         "type" => "message",
         "message" => %{"role" => "tool", "content" => "private", "tool_call_id" => "private"}
       }, "tool.result_recorded"},
      {%{
         "type" => "message",
         "message" => %{
           "role" => "assistant",
           "content" => "private",
           "provider_data" => %{"native" => "private"}
         }
       }, "assistant.committed"},
      {%{
         "type" => "workspace_context_snapshot",
         "snapshot" => %{"sources" => [%{"path" => "private"}]}
       }, "context.workspace_committed"},
      {%{"type" => "mcp_catalog", "version" => 1, "tools" => [%{"description" => "private"}]},
       "context.catalog_committed"},
      {%{
         "type" => "extension_context_snapshot",
         "version" => 1,
         "request_id" => Ipse.Usage.id(),
         "content" => "private"
       }, "context.extensions_committed"},
      {%{"type" => "context_compacted", "summary" => "private"}, "context.compaction_committed"},
      {%{"type" => "compaction_failed", "reason" => "private"}, "context.compaction_failed"},
      {%{"type" => "operator_question", "version" => 1, "arguments" => %{"text" => "private"}},
       "question.waiting"},
      {%{"type" => "operator_answer", "version" => 1, "message" => "private"},
       "question.answered"},
      {%{"type" => "operator_question_closed", "version" => 1, "reason" => "private"},
       "question.closed"},
      {%{"type" => "delegation_started", "child_id" => Ipse.Usage.id(), "call_id" => "private"},
       "child.started"},
      {%{
         "type" => "lifecycle_turn_settling",
         "version" => 1,
         "turn_id" => Ipse.Usage.id(),
         "final_sha256" => "private"
       }, "turn.settling"},
      {%{"type" => "turn_finished", "status" => "ok"}, "turn.finished"},
      {%{"type" => "cancelled"}, "turn.cancelled"}
    ]

    for {record, type} <- records do
      source = source(record)
      assert {:ok, event} = Event.project(source, record, "metadata")
      assert event["type"] == type
      refute String.contains?(Jason.encode!(event), ["private", source["record_sha256"]])
    end

    record = %{"type" => "extension_invented_intent", "version" => 1}

    assert {:error, :unsupported_lifecycle_record} =
             Event.project(source(record), record, "metadata")
  end

  test "invalid dimensions and identifiers refuse rather than exporting or coercing them" do
    for record <- [
          %{"type" => "tool_started", "approval" => "synthetic-secret"},
          %{"type" => "turn_finished", "status" => "synthetic-secret"},
          %{
            "type" => "request_measured",
            "kind" => "model",
            "outcome" => "completed",
            "duration_ms" => -1
          },
          %{
            "type" => "request_measured",
            "kind" => "model",
            "outcome" => "completed",
            "duration_ms" => 1.5
          },
          %{"type" => "delegation_started", "child_id" => "synthetic-secret"},
          %{
            "type" => "extension_event_result",
            "version" => 1,
            "delivery_id" => Ipse.Usage.id(),
            "turn_id" => Ipse.Usage.id(),
            "outcome" => "synthetic-secret"
          }
        ] do
      assert {:error, :invalid_lifecycle_event} =
               Event.project(source(record), record, "metadata")
    end
  end

  test "extension receipts distinguish action results from arbitrary business assertions" do
    invocation = Ipse.Usage.id()
    operation = Ipse.Usage.id()

    record = %{
      "type" => "extension_action_result",
      "version" => 1,
      "parent_invocation_id" => invocation,
      "operation_id" => operation,
      "outcome" => %{"status" => "denied", "value" => %{"text" => "synthetic-private"}},
      "request" => %{"text" => "synthetic-private"}
    }

    assert {:ok, event} = Event.project(source(record), record, "metadata")
    assert event["data"] == %{"status" => "denied"}

    assert event["correlations"] == %{
             "parent_invocation_id" => invocation,
             "operation_id" => operation
           }

    result = %{
      "type" => "extension_invocation_result",
      "version" => 1,
      "invocation_id" => invocation,
      "action_count" => 1,
      "value" => %{"status" => "completed", "secret" => "synthetic-private"}
    }

    assert {:ok, event} = Event.project(source(result), result, "metadata")
    assert event["type"] == "extension.invocation_recorded"
    assert event["data"] == %{"action_count" => 1}
    refute String.contains?(Jason.encode!(event), ["synthetic-private", "completed"])
  end

  defp source(record, session \\ Ipse.Usage.id()) do
    {:ok, source} = Source.build(session, 0, record)
    source
  end
end
