defmodule Ipse.LifecycleToolTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.ToolLifecycle
  alias Ipse.Session.RuntimeLifecycle
  alias Ipse.Journal
  alias Ipse.Session.Lifecycle

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-tool-source-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, id} = Journal.create(root, %{"synthetic" => true})
    {runtime, [epoch]} = RuntimeLifecycle.open(%{}, %{"mode" => "local"}, [], id, false)
    append(root, id, epoch)
    turn = Ipse.Usage.id()
    request = Ipse.Usage.admission(id, %{provider: :demo, model: "fixture"}, "model", turn)
    append(root, id, request)

    call = %{
      "id" => "raw-call-secret",
      "function" => %{"name" => "read", "arguments" => ~s({"path":"private-path"})}
    }

    assistant = %{
      "type" => "message",
      "request_id" => request["request_id"],
      "message" => %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [call],
        "provider_data" => %{"native" => "private-native"}
      }
    }

    proposal_source = append(root, id, assistant)
    config = %{extensions: [%{identity: %{"capabilities" => ~w(lifecycle.tools)}}]}
    {ctx, []} = ToolLifecycle.open(config, [], id, runtime, root, nil)
    {ctx, []} = ToolLifecycle.proposal(ctx, proposal_source, assistant, turn)

    legacy = %{
      "type" => "tool_started",
      "call_id" => call["id"],
      "name" => "read",
      "approval" => "not_required",
      "arguments" => nil,
      "mcp" => nil,
      "sandbox_requested" => "off"
    }

    intent_source = append(root, id, legacy)
    {ctx, [intent]} = ToolLifecycle.start(ctx, intent_source, legacy, call, 1)
    source = append(root, id, intent)
    ctx = ToolLifecycle.bind(ctx, source, intent)

    result = %{
      "type" => "message",
      "message" => %{
        "role" => "tool",
        "tool_call_id" => call["id"],
        "content" => "private-result",
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "not_required"}
      }
    }

    result_source = append(root, id, result)
    {ctx, [outcome]} = ToolLifecycle.finish(ctx, result_source, result)
    outcome_source = append(root, id, outcome)
    {:ok, events} = Journal.load(root, id)

    %{
      root: root,
      id: id,
      runtime: runtime,
      epoch: epoch,
      config: config,
      ctx: ctx,
      call: call,
      legacy: legacy,
      assistant: assistant,
      result: result,
      request: request,
      intent: intent,
      source: source,
      outcome: outcome,
      outcome_source: outcome_source,
      events: events
    }
  end

  defp append(root, id, event) do
    {:ok, source} = Journal.append_with_source(root, id, event)
    source
  end

  test "structured private views retain identity while metadata excludes content and raw IDs",
       c do
    assert {:ok, saved} = ToolLifecycle.restore(c.events, c.id)
    assert saved.tools[c.intent["tool_id"]].ended
    assert :ok = ToolLifecycle.validate_sources(c.root, c.id, c.events)
    assert {:ok, input} = Lifecycle.project(c.source, c.intent, "tool.input")
    assert input["data"] == %{"name" => "read", "arguments_json" => ~s({"path":"private-path"})}
    assert {:ok, result} = Lifecycle.project(c.outcome_source, c.outcome, "tool.result")
    assert result["data"] == %{"text" => "private-result"}

    for {record, source} <- [{c.intent, c.source}, {c.outcome, c.outcome_source}] do
      assert {:ok, event} = Lifecycle.project(source, record, "metadata")
      assert Lifecycle.valid_metadata?(event)
      assert event["event_id"] == source["event_id"]
      refute String.contains?(Jason.encode!(event), ["private", "raw-call-secret", "sha256"])
    end

    assert c.outcome["duration_ms"] >= 0

    assert {:error, :lifecycle_view_unavailable} =
             Lifecycle.project(c.source, c.intent, "tool.result")

    assert {:error, :lifecycle_view_unavailable} =
             Lifecycle.project(c.outcome_source, c.outcome, "tool.input")
  end

  test "self-consistent private text changes and mismatched host correlations are rejected", c do
    data = %{"name" => "read", "arguments_json" => "{}"}

    forged = %{
      c.intent
      | "input" => data,
        "input_bytes" => byte_size(Jason.encode!(data)),
        "input_sha256" => Ipse.JSON.digest([data])
    }

    assert ToolLifecycle.valid?(forged)

    assert {:error, _} =
             ToolLifecycle.restore(
               Enum.map(c.events, fn e -> if e == c.intent, do: forged, else: e end),
               c.id
             )

    for bad <- [
          Map.put(c.outcome, "request_id", Ipse.Usage.id()),
          Map.put(c.outcome, "tool_id", Ipse.Usage.id()),
          Map.put(c.outcome, "duration_ms", -1),
          Map.put(c.outcome, "status", "business_success")
        ] do
      assert {:error, _} =
               ToolLifecycle.restore(
                 Enum.map(c.events, fn e -> if e == c.outcome, do: bad, else: e end),
                 c.id
               )
    end

    refute ToolLifecycle.valid?(Map.put(c.intent, "input", %{"private" => self()}))
    assert {:error, _} = ToolLifecycle.restore(c.events ++ [c.outcome], c.id)
  end

  test "plausible source objects still resolve against actual journal positions", c do
    {:ok, wrong} = Journal.source(c.id, c.intent["proposal_source"]["byte_offset"] + 1, c.legacy)
    forged_intent = Map.put(c.intent, "intent_source", wrong)
    {:ok, forged_source} = Journal.source(c.id, c.source["byte_offset"], forged_intent)
    forged_outcome = Map.put(c.outcome, "tool_source", forged_source)

    forged =
      Enum.map(c.events, fn e ->
        cond do
          e == c.intent -> forged_intent
          e == c.outcome -> forged_outcome
          true -> e
        end
      end)

    assert {:ok, _} = ToolLifecycle.restore(forged, c.id)

    assert {:error, :invalid_tool_lifecycle} =
             ToolLifecycle.validate_sources(c.root, c.id, forged)
  end

  test "recording limits remain durable and do not invent a result for an interrupted tool", c do
    records =
      Enum.flat_map(1..div(ToolLifecycle.limit(), 2), fn i ->
        request_id = Ipse.Usage.id()
        request = %{c.request | "request_id" => request_id}
        assistant = %{c.assistant | "request_id" => request_id}
        {:ok, proposal} = Journal.source(c.id, i * 10 + 1, assistant)
        {:ok, intent_source} = Journal.source(c.id, i * 10 + 2, c.legacy)

        intent = %{
          c.intent
          | "tool_id" => Ipse.Usage.id(),
            "request_id" => request_id,
            "proposal_source" => proposal,
            "intent_source" => intent_source
        }

        {:ok, source} = Journal.source(c.id, i * 10 + 3, intent)
        {:ok, result_source} = Journal.source(c.id, i * 10 + 4, c.result)

        outcome = %{
          c.outcome
          | "tool_id" => intent["tool_id"],
            "request_id" => request_id,
            "tool_source" => source,
            "result_source" => result_source
        }

        [request, assistant, c.legacy, intent, c.result, outcome]
      end)

    events = [hd(c.events), c.epoch] ++ records
    assert {:ok, %{count: 10_000}} = ToolLifecycle.restore(events, c.id)
    {ctx, []} = ToolLifecycle.open(c.config, events, c.id, c.runtime, c.root, nil)
    {ctx, [stop]} = ToolLifecycle.start(ctx, c.intent["intent_source"], c.legacy, c.call, 1)
    assert stop["reason"] == "limit"
    assert {:ok, %{stopped: true}} = ToolLifecycle.restore(events ++ [stop], c.id)
    refute ToolLifecycle.recording?(ctx)
    assert {^ctx, []} = ToolLifecycle.start(ctx, c.intent["intent_source"], c.legacy, c.call, 1)
    unfinished = Enum.drop(c.events, -2)
    assert {:ok, saved} = ToolLifecycle.restore(unfinished, c.id)
    refute saved.tools[c.intent["tool_id"]].ended
    {restored, []} = ToolLifecycle.open(c.config, unfinished, c.id, c.runtime, c.root, nil)
    refute ToolLifecycle.active?(restored)
    assert {^restored, []} = ToolLifecycle.finish(restored, c.outcome["result_source"], c.result)
  end
end
