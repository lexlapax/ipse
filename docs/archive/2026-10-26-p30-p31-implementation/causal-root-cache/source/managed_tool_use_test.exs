defmodule Ipse.Session.ManagedToolUseTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Session.{ManagedLineage, ManagedToolUse}

  defp prepared do
    dependency = %{
      "version" => 3,
      "project_id" => JSON.sha256("project"),
      "namespace" => JSON.sha256("namespace"),
      "pin_sha256" => JSON.sha256("pin"),
      "policy_generation" => 1,
      "collection" => %{
        "project" => JSON.sha256("namespace"),
        "generation" => 0,
        "floor" => 0,
        "floor_anchor" => nil,
        "root_state" => "absent",
        "root_sha256" => nil,
        "manifest_sha256" => nil
      },
      "subject" => %{
        "kind" => "root_observation",
        "request_sha256" => JSON.sha256("request"),
        "result_sha256" => JSON.sha256("result")
      }
    }

    session = Usage.id()
    request = Usage.id()
    arguments = %{"path" => "result.txt", "content" => "Synthetic derived value"}

    call = %{
      "id" => "call_current",
      "function" => %{"name" => "write", "arguments" => Jason.encode!(arguments)}
    }

    started = %{
      "type" => "tool_started",
      "call_id" => call["id"],
      "name" => "write",
      "approval" => "approved",
      "mcp" => nil
    }

    binding = %{call: call, request_id: request}
    {:ok, lineage} = ManagedLineage.new(session)
    digest = JSON.digest([dependency])

    lineage = %{
      lineage
      | tool_layout: ManagedToolUse.layout(),
        active_tool: started,
        dictionary: %{digest => dependency},
        calls: %{call["id"] => [digest]},
        call_bindings: %{call["id"] => binding}
    }

    input = ManagedToolUse.input(session, request, call, arguments, "approved", nil)
    target = ManagedToolUse.native_binding("write", arguments)
    now = System.system_time(:millisecond)

    record = %{
      "type" => "managed_tool_effect_admitted",
      "version" => 1,
      "effect_id" => Usage.id(),
      "session_id" => session,
      "request_id" => request,
      "call_id" => call["id"],
      "input_sha256" => JSON.digest([input]),
      "snapshot_sha256" => JSON.digest([input, [dependency]]),
      "dependencies_sha256" => JSON.digest([dependency]),
      "binding" => target,
      "binding_sha256" => JSON.digest([target]),
      "checked_at_ms" => now,
      "deadline_ms" => now + 1000
    }

    state = %{
      id: session,
      phase: :tool,
      task: %{pid: self()},
      job_ref: make_ref(),
      calls: [call],
      managed_lineage: lineage,
      last_request_id: request,
      tool_decision: "approved",
      mcp_tools: [],
      config: %{managed_tool_layout: ManagedToolUse.layout()},
      cwd: "/fixture",
      dir: "/fixture/history",
      managed_tool_effect: nil,
      managed_tool_result: nil,
      messages: []
    }

    %{
      record: record,
      lineage: lineage,
      state: state,
      call_binding: binding,
      started: started,
      dependency: dependency,
      target: target
    }
  end

  @tag managed_audit_pure: true
  @tag document_decision_lineage: true
  test "managed mutation classification includes inherited reads and unavailable lineage" do
    c = prepared()
    id = Usage.id()
    parent = %{"invocation_id" => id}
    digest = JSON.digest([c.dependency])
    entry = %{parent: parent, input: [], reads: []}

    lineage = %{
      c.lineage
      | active_invocation: id,
        invocations: %{id => entry},
        dictionary: %{digest => c.dependency}
    }

    state = %{
      managed_lineage: lineage,
      invocation: %{parent: parent, managed_reads: []}
    }

    refute ManagedToolUse.managed_invocation?(state)

    assert ManagedToolUse.managed_invocation?(
             put_in(state, [:managed_lineage, Access.key(:invocations), id, :input], [digest])
           )

    assert ManagedToolUse.managed_invocation?(
             put_in(state, [:managed_lineage, Access.key(:invocations), id, :reads], [digest])
           )

    assert ManagedToolUse.managed_invocation?(
             put_in(state, [:invocation, :managed_reads], [c.dependency])
           )

    assert ManagedToolUse.managed_invocation?(%{
             state
             | managed_lineage: %{lineage | unavailable: true}
           })

    assert ManagedToolUse.managed_invocation?(
             put_in(state, [:managed_lineage, Access.key(:invocations), id, :input], [
               JSON.sha256("missing")
             ])
           )
  end

  @tag managed_audit_pure: true, publication_prerequisite: true
  test "publication permits only its exact host root-only CAS prerequisites" do
    c = prepared()
    id = Usage.id()
    parent = %{"invocation_id" => id}

    pin = %{
      "epoch" => 1,
      "project_id" => c.dependency["project_id"],
      "namespace" => c.dependency["namespace"]
    }

    value = %{
      "version" => 3,
      "project" => c.dependency["namespace"],
      "generation" => 0,
      "floor" => 0,
      "floor_anchor" => nil
    }

    snapshot = %{
      "type" => "extension_action_result",
      "parent_invocation_id" => id,
      "namespace" => c.dependency["namespace"],
      "effect_binding" => %{"pin" => pin},
      "request" => %{"op" => "collection.call", "request" => %{"op" => "snapshot"}},
      "outcome" => %{"status" => "ok", "value" => value}
    }

    dependency = %{
      c.dependency
      | "pin_sha256" => JSON.digest([pin]),
        "subject" => %{
          "kind" => "root_observation",
          "request_sha256" => JSON.digest([%{"op" => "snapshot"}]),
          "result_sha256" => JSON.digest([value])
        }
    }

    sha = JSON.digest([dependency])
    entry = %{parent: parent, input: [], reads: [sha]}

    lineage = %{
      c.lineage
      | active_invocation: id,
        invocations: %{id => entry},
        dictionary: %{sha => dependency},
        root_observations: %{sha => true}
    }

    state = %{
      managed_lineage: lineage,
      invocation: %{parent: parent, managed_reads: [dependency], results: [snapshot]}
    }

    request = %{"op" => "collection.managed", "request" => %{"expected_generation" => 0}}
    binding = %{"namespace" => dependency["namespace"], "pin" => pin}
    assert ManagedToolUse.publication_prerequisites?(state, request, binding)

    refute ManagedToolUse.publication_prerequisites?(
             state,
             put_in(request, ["request", "expected_generation"], 1),
             binding
           )

    refute ManagedToolUse.publication_prerequisites?(state, request, %{
             binding
             | "namespace" => JSON.sha256("other")
           })

    refute ManagedToolUse.publication_prerequisites?(
             put_in(state, [:managed_lineage, Access.key(:root_observations)], %{}),
             request,
             binding
           )

    inherited = %{
      state
      | managed_lineage: %{lineage | invocations: %{id => %{entry | input: [sha]}}}
    }

    refute ManagedToolUse.publication_prerequisites?(inherited, request, binding)
    other = put_in(dependency, ["subject", "request_sha256"], JSON.sha256("other actual read"))

    refute ManagedToolUse.publication_prerequisites?(
             put_in(state, [:invocation, :managed_reads], [dependency, other]),
             request,
             binding
           )

    refute ManagedToolUse.publication_prerequisites?(
             %{state | managed_lineage: %{lineage | unavailable: true}},
             request,
             binding
           )
  end

  @tag publication_prerequisite: true
  test "distinct own absence reads need no synthetic snapshot but retain every root dependency" do
    {state, request, binding} = absent_publication()
    assert ManagedToolUse.publication_prerequisites?(state, request, binding)

    [first | _] = state.invocation.managed_reads

    missing =
      update_in(state, [:managed_lineage, Access.key(:root_observations)], fn cache ->
        Map.delete(cache, JSON.digest([first]))
      end)

    refute ManagedToolUse.publication_prerequisites?(missing, request, binding)

    invalid =
      put_in(state, [:managed_lineage, Access.key(:root_observations), JSON.digest([first])], 1)

    refute ManagedToolUse.publication_prerequisites?(invalid, request, binding)

    id = state.invocation.parent["invocation_id"]
    entry = state.managed_lineage.invocations[id]

    inherited =
      put_in(state, [:managed_lineage, Access.key(:invocations), id, :input], entry.reads)

    refute ManagedToolUse.publication_prerequisites?(inherited, request, binding)
  end

  @tag publication_prerequisite: true
  test "individually matching observations cannot mix roots, policy or scans" do
    {state, request, binding} = absent_publication()
    [first, second] = state.invocation.managed_reads

    changed =
      put_in(
        second,
        ["collection"],
        Map.merge(second["collection"], %{
          "root_state" => "present",
          "root_sha256" => JSON.sha256("different root"),
          "manifest_sha256" => JSON.sha256("different manifest")
        })
      )

    mixed = replace_publication_reads(state, [first, changed])
    refute ManagedToolUse.publication_prerequisites?(mixed, request, binding)

    refute ManagedToolUse.publication_prerequisites?(state, request, %{
             binding
             | "pin" => Map.put(binding["pin"], "epoch", 2)
           })

    [event | rest] = state.invocation.results

    scan =
      put_in(event, ["request", "request"], %{
        "op" => "scan",
        "after" => nil,
        "generation" => 0,
        "limit" => 1
      })

    value =
      scan["outcome"]["value"]
      |> Map.delete("record")
      |> Map.merge(%{"records" => [], "next" => nil})

    scan = put_in(scan, ["outcome", "value"], value)

    dependency =
      put_in(first, ["subject"], %{
        "kind" => "root_observation",
        "request_sha256" => JSON.digest([scan["request"]["request"]]),
        "result_sha256" => JSON.digest([value])
      })

    scan_state =
      state
      |> put_in([:invocation, :results], [scan | rest])
      |> replace_publication_reads([dependency, second])

    refute ManagedToolUse.publication_prerequisites?(scan_state, request, binding)
  end

  defp absent_publication do
    c = prepared()
    id = Usage.id()
    parent = %{"invocation_id" => id}
    namespace = c.dependency["namespace"]
    pin = %{"epoch" => 1, "project_id" => c.dependency["project_id"], "namespace" => namespace}

    value = %{
      "version" => 3,
      "project" => namespace,
      "generation" => 0,
      "floor" => 0,
      "floor_anchor" => nil,
      "record" => nil
    }

    events =
      for key <- ["override." <> JSON.sha256("lineage"), "note." <> JSON.sha256("lineage")] do
        %{
          "type" => "extension_action_result",
          "parent_invocation_id" => id,
          "namespace" => namespace,
          "effect_binding" => %{"pin" => pin},
          "request" => %{"op" => "collection.call", "request" => %{"op" => "get", "key" => key}},
          "outcome" => %{"status" => "ok", "value" => value}
        }
      end

    reads =
      Enum.map(events, fn event ->
        %{
          c.dependency
          | "pin_sha256" => JSON.digest([pin]),
            "subject" => %{
              "kind" => "root_observation",
              "request_sha256" => JSON.digest([event["request"]["request"]]),
              "result_sha256" => JSON.digest([value])
            }
        }
      end)

    lineage = %{
      c.lineage
      | active_invocation: id,
        invocations: %{id => %{parent: parent, input: [], reads: []}}
    }

    state = %{
      managed_lineage: lineage,
      invocation: %{parent: parent, managed_reads: [], results: events}
    }

    state = replace_publication_reads(state, reads)

    state =
      put_in(
        state,
        [:managed_lineage, Access.key(:root_observations)],
        Map.new(reads, &{JSON.digest([&1]), true})
      )

    {state, %{"op" => "collection.managed", "request" => %{"expected_generation" => 0}},
     %{"namespace" => namespace, "pin" => pin}}
  end

  defp replace_publication_reads(state, reads) do
    id = state.invocation.parent["invocation_id"]
    dictionary = Map.new(reads, &{JSON.digest([&1]), &1})

    state
    |> put_in([:invocation, :managed_reads], reads)
    |> put_in([:managed_lineage, Access.key(:dictionary)], dictionary)
    |> put_in(
      [:managed_lineage, Access.key(:invocations), id, :reads],
      Enum.map(reads, &JSON.digest([&1]))
    )
  end

  test "effect receipts bind actual call, approval, complete dependency union and target once" do
    c = prepared()

    assert ManagedToolUse.valid_record?(c.record, c.state.id, c.call_binding, c.started, [
             c.dependency
           ])

    assert {:ok, consumed} = ManagedLineage.advance(c.lineage, c.record, [], [])

    assert {:error, :managed_lineage_unavailable} =
             ManagedLineage.advance(consumed, c.record, [], [])

    assert {:error, :managed_lineage_unavailable} =
             ManagedLineage.advance(consumed, Map.put(c.record, "effect_id", Usage.id()), [], [])

    for changed <- [
          Map.put(c.record, "snapshot_sha256", JSON.sha256("foreign")),
          Map.put(c.record, "dependencies_sha256", JSON.digest([])),
          Map.put(c.record, "call_id", "another"),
          Map.put(c.record, "request_id", Usage.id()),
          Map.put(c.record, "deadline_ms", c.record["checked_at_ms"]),
          Map.put(
            c.record,
            "binding",
            ManagedToolUse.native_binding("shell", %{"command" => "true"})
          ),
          Map.put(c.record, "unknown", true)
        ] do
      refute ManagedToolUse.valid_record?(changed, c.state.id, c.call_binding, c.started, [
               c.dependency
             ])
    end

    refute ManagedToolUse.valid_record?(
             c.record,
             c.state.id,
             c.call_binding,
             %{c.started | "approval" => "session_allow"},
             [c.dependency]
           )
  end

  test "owner preparation preserves the full union and rejects altered or unavailable input" do
    c = prepared()
    assert {:reply, {:ok, spec}, next} = ManagedToolUse.prepare(c.state, self(), c.target)
    assert spec.dependencies == [c.dependency]
    assert spec.context.source_binding == {:snapshot, "tool.effect", c.record["snapshot_sha256"]}
    assert next.managed_tool_effect.snapshot.input["approval"] == "approved"

    assert {:reply, {:error, :managed_tool_inputs_unavailable}, _} =
             ManagedToolUse.prepare(next, self(), c.target)

    assert {:reply, {:error, :managed_tool_inputs_unavailable}, _} =
             ManagedToolUse.prepare(%{c.state | config: %{}}, self(), c.target)

    assert {:reply, {:error, :managed_tool_inputs_unavailable}, _} =
             ManagedToolUse.prepare(
               %{c.state | managed_lineage: %{c.lineage | unavailable: true}},
               self(),
               c.target
             )

    ordinary = %{c.state | config: %{}, managed_lineage: %{c.lineage | calls: %{}}}

    assert {:reply, {:ok, :ordinary}, ^ordinary} =
             ManagedToolUse.prepare(ordinary, self(), c.target)
  end

  test "fresh effect layout rejects null or unknown declarations" do
    assert {:ok, nil} = ManagedToolUse.marker(%{})
    assert {:ok, _} = ManagedToolUse.marker(%{"managed_tool_layout" => ManagedToolUse.layout()})

    for value <- [nil, "future", 1, %{}] do
      assert {:error, :managed_tool_inputs_unavailable} =
               ManagedToolUse.marker(%{"managed_tool_layout" => value})
    end
  end

  @tag managed_action_protocol: true
  test "extension effects bind the actual action and its complete inherited read union" do
    c = prepared()
    parent = %{"invocation_id" => Usage.id()}

    action = %{
      "parent_invocation_id" => parent["invocation_id"],
      "operation_id" => Usage.id(),
      "request" => %{
        "op" => "tool.call",
        "name" => "write",
        "arguments" => %{"path" => "x", "content" => "derived"}
      },
      "approval" => "approved"
    }

    input = ManagedToolUse.action_input(c.state.id, parent, action)
    target = ManagedToolUse.native_binding("write", action["request"]["arguments"])

    event =
      c.record
      |> Map.drop(~w(request_id call_id))
      |> Map.merge(%{
        "version" => 2,
        "parent_invocation_id" => parent["invocation_id"],
        "operation_id" => action["operation_id"],
        "input_sha256" => JSON.digest([input]),
        "snapshot_sha256" => JSON.digest([input, [c.dependency]]),
        "binding" => target,
        "binding_sha256" => JSON.digest([target])
      })

    state = %{
      c.lineage
      | active_action: action,
        active_invocation: parent["invocation_id"],
        action_layout: ManagedToolUse.action_layout(),
        invocations: %{
          parent["invocation_id"] => %{
            parent: parent,
            input: [JSON.digest([c.dependency])],
            reads: []
          }
        }
    }

    assert ManagedToolUse.valid_action_record?(event, c.state.id, parent, action, [c.dependency])
    assert {:ok, admitted} = ManagedLineage.advance(state, event, [], [])

    assert {:error, _} =
             ManagedLineage.advance(admitted, Map.put(event, "effect_id", Usage.id()), [], [])

    refute ManagedToolUse.valid_action_record?(event, c.state.id, parent, action, [])

    refute ManagedToolUse.valid_action_record?(
             event,
             c.state.id,
             parent,
             put_in(action, ["request", "arguments", "content"], "changed"),
             [c.dependency]
           )
  end

  @tag managed_action_protocol: true
  test "managed discovery requires exact original input, confirmed stage cleanup and inert recovery" do
    c = prepared()
    tool = Ipse.MCP.Config.tool_id("local", "write_note")

    server = %{
      "id" => "local",
      "command" => "/usr/bin/elixir",
      "args" => [],
      "tools" => ["write_note"],
      "resources" => [],
      "prompts" => [],
      "env_names" => [],
      "timeout_ms" => 1000,
      "sandbox" => "off"
    }

    server = Map.put(server, "fingerprint", Ipse.MCP.Config.public_fingerprint(server))

    request = %{
      "op" => "mcp.call",
      "version" => 1,
      "binding" => "notes",
      "arguments" => %{},
      "timeout_ms" => 1000
    }

    parent = %{
      "invocation_id" => Usage.id(),
      "payload" => %{"session_id" => c.state.id},
      "identity" => %{"mcp_bindings" => [%{"alias" => "notes", "tool" => tool}]}
    }

    intent = %{
      "type" => "managed_mcp_discovery_intent",
      "version" => 1,
      "discovery_id" => Usage.id(),
      "session_id" => c.state.id,
      "parent_invocation_id" => parent["invocation_id"],
      "parent_sha256" => JSON.digest([parent]),
      "request" => request,
      "request_sha256" => JSON.digest([request]),
      "server" => server,
      "server_sha256" => JSON.digest([server]),
      "tool_id" => tool,
      "initialize_params" => Ipse.MCP.managed_discovery_initialize_params(),
      "dependencies_sha256" => JSON.digest([c.dependency])
    }

    state = %{
      c.lineage
      | action_layout: ManagedToolUse.action_layout(),
        active_invocation: parent["invocation_id"],
        mcp_servers: [server["fingerprint"]],
        invocations: %{
          parent["invocation_id"] => %{
            parent: parent,
            input: [JSON.digest([c.dependency])],
            reads: []
          }
        }
    }

    assert ManagedToolUse.valid_discovery_intent?(intent, parent, [c.dependency])
    assert {:ok, pending} = ManagedLineage.advance(state, intent, [], [])
    assert {:error, _} = ManagedLineage.advance(pending, intent, [], [])

    start = %{
      "kind" => "mcp.discovery.start",
      "discovery_id" => intent["discovery_id"],
      "server_sha256" => intent["server_sha256"]
    }

    input = ManagedToolUse.discovery_input(c.state.id, parent, intent)

    event =
      c.record
      |> Map.drop(~w(request_id call_id))
      |> Map.merge(%{
        "version" => 3,
        "parent_invocation_id" => parent["invocation_id"],
        "discovery_id" => intent["discovery_id"],
        "input_sha256" => JSON.digest([input]),
        "snapshot_sha256" => JSON.digest([input, [c.dependency]]),
        "binding" => start,
        "binding_sha256" => JSON.digest([start])
      })

    assert {:ok, started} = ManagedLineage.advance(pending, event, [], [])

    send_binding =
      Map.merge(start, %{
        "kind" => "mcp.discovery.send",
        "request" => %{
          "jsonrpc" => "2.0",
          "id" => 0,
          "method" => "initialize",
          "params" => intent["initialize_params"]
        }
      })

    refute ManagedLineage.discovery_stage?(started, send_binding)

    cleanup = %{
      "type" => "managed_tool_effect_cleanup",
      "version" => 1,
      "effect_id" => event["effect_id"],
      "admission_sha256" => JSON.digest([event]),
      "status" => "confirmed"
    }

    assert {:ok, clean} = ManagedLineage.advance(started, cleanup, [], [])
    assert ManagedLineage.discovery_stage?(clean, send_binding)
    refute ManagedLineage.discovery_stage?(clean, start)

    refute ManagedLineage.discovery_stage?(
             clean,
             put_in(send_binding, ["request", "method"], "tools/call")
           )

    assert {:ok, recovered} =
             ManagedLineage.advance(clean, %{"type" => "managed_recovery"}, [], [])

    assert recovered.unavailable

    refute ManagedToolUse.valid_discovery_intent?(
             Map.put(intent, "dependencies_sha256", JSON.digest([])),
             parent,
             [c.dependency]
           )

    refute ManagedToolUse.valid_discovery_intent?(
             put_in(intent, ["server", "command"], "other"),
             parent,
             [c.dependency]
           )
  end

  @tag managed_action_protocol: true
  test "a later ordinary result cannot clear unavailable lineage and withheld output binds the exact receipt" do
    c = prepared()
    parent = Usage.id()

    event = %{
      "type" => "extension_action_result",
      "parent_invocation_id" => parent,
      "operation_id" => Usage.id(),
      "request" => %{"op" => "tool.call"},
      "outcome" => %{"status" => "unknown", "value" => %{}}
    }

    state = %{c.lineage | unavailable: true}
    assert {:ok, after_result} = ManagedLineage.advance(state, event, [], [])
    assert after_result.unavailable
    assert {:ok, after_result} = ManagedLineage.advance(c.lineage, event, [], [])
    refute after_result.unavailable
    refusal = ManagedToolUse.action_withheld(event)
    assert ManagedToolUse.valid_action_withheld?(refusal, event)
    assert {:ok, withheld} = ManagedLineage.advance(after_result, refusal, [], [])
    assert withheld.unavailable

    refute ManagedToolUse.valid_action_withheld?(
             Map.put(refusal, "result_sha256", JSON.sha256("foreign")),
             event
           )

    assert {:error, _} = ManagedLineage.advance(c.lineage, refusal, [], [])
  end

  test "private tool results require exact causal release and unknown cleanup withholds them" do
    c = prepared()

    message =
      Ipse.Session.Turn.tool_message(
        c.call_binding.call,
        "PRIVATE_SYNTHETIC_RESULT",
        "result_recorded",
        "approved"
      )

    now = System.system_time(:millisecond)

    observed = %{
      "type" => "managed_tool_result_observed",
      "version" => 1,
      "result_id" => Usage.id(),
      "session_id" => c.state.id,
      "request_id" => c.state.last_request_id,
      "call_id" => c.call_binding.call["id"],
      "input_sha256" => c.record["input_sha256"],
      "dependencies_sha256" => JSON.digest([c.dependency]),
      "message" => message,
      "message_sha256" => JSON.digest([message]),
      "checked_at_ms" => now,
      "deadline_ms" => now + 1000
    }

    release = %{
      "type" => "managed_tool_result_release",
      "version" => 1,
      "result_id" => observed["result_id"],
      "observed_sha256" => JSON.digest([observed]),
      "decision" => "current",
      "projection_sha256" => JSON.digest([message]),
      "checked_at_ms" => now,
      "deadline_ms" => now + 1000
    }

    cleanup = %{
      "type" => "managed_tool_result_cleanup",
      "version" => 1,
      "result_id" => observed["result_id"],
      "release_sha256" => JSON.digest([release]),
      "status" => "confirmed"
    }

    assert ManagedToolUse.valid_observed?(observed, c.state.id, c.call_binding, c.started, [
             c.dependency
           ])

    assert {:error, _} = ManagedLineage.advance(c.lineage, release, [], [])
    assert {:ok, private} = ManagedLineage.advance(c.lineage, observed, [], [])
    assert {:ok, private} = ManagedLineage.advance(private, release, [], [])
    assert {:error, _} = ManagedLineage.advance(private, cleanup, [], [])

    assert {:ok, committed} =
             ManagedLineage.advance(private, %{"type" => "message", "message" => message}, [], [
               message
             ])

    assert {:ok, finished} = ManagedLineage.advance(committed, cleanup, [message], [message])
    assert finished.tool_result_release == nil
    assert {:error, _} = ManagedLineage.advance(finished, observed, [message], [message])
    projected = ManagedToolUse.withhold_result([message], committed)
    refute Jason.encode!(projected) =~ "PRIVATE_SYNTHETIC_RESULT"

    assert {:ok, uncertain} =
             ManagedLineage.advance(
               committed,
               Map.put(cleanup, "status", "unknown"),
               [message],
               projected
             )

    assert uncertain.unavailable

    assert {:error, :managed_lineage_unavailable} =
             ManagedLineage.dependencies(uncertain, projected)
  end

  test "MCP send requires a separate confirmed start and cannot reuse either stage" do
    c = prepared()
    args = %{"value" => "derived"}

    descriptor = %{
      tool_id: "mcp__fixture__read",
      name: "read",
      digest: JSON.sha256("descriptor"),
      server: %{
        id: "fixture",
        fingerprint: JSON.sha256("endpoint"),
        transport: :stdio,
        sandbox: :off
      }
    }

    manifest = descriptor |> Ipse.MCP.manifest() |> Jason.encode!() |> Jason.decode!()

    call = %{
      c.call_binding.call
      | "function" => %{"name" => descriptor.tool_id, "arguments" => Jason.encode!(args)}
    }

    started = %{c.started | "name" => descriptor.tool_id, "mcp" => manifest}

    base = %{
      c.lineage
      | active_tool: started,
        call_bindings: %{call["id"] => %{call: call, request_id: c.state.last_request_id}}
    }

    input =
      ManagedToolUse.input(c.state.id, c.state.last_request_id, call, args, "approved", manifest)

    start = %{"kind" => "mcp.start", "descriptor_sha256" => descriptor.digest}

    send_binding = %{
      "kind" => "mcp.send",
      "descriptor_sha256" => descriptor.digest,
      "request" => %{
        "jsonrpc" => "2.0",
        "id" => "request1",
        "method" => "tools/call",
        "params" => %{"name" => "read", "arguments" => args}
      }
    }

    record = fn binding ->
      %{
        c.record
        | "effect_id" => Usage.id(),
          "input_sha256" => JSON.digest([input]),
          "snapshot_sha256" => JSON.digest([input, [c.dependency]]),
          "binding" => binding,
          "binding_sha256" => JSON.digest([binding])
      }
    end

    start_record = record.(start)
    send_record = record.(send_binding)
    assert {:error, _} = ManagedLineage.advance(base, send_record, [], [])
    assert {:ok, pending} = ManagedLineage.advance(base, start_record, [], [])
    assert {:error, _} = ManagedLineage.advance(pending, send_record, [], [])

    cleanup = %{
      "type" => "managed_tool_effect_cleanup",
      "version" => 1,
      "effect_id" => start_record["effect_id"],
      "admission_sha256" => JSON.digest([start_record]),
      "status" => "confirmed"
    }

    assert {:ok, confirmed} = ManagedLineage.advance(pending, cleanup, [], [])
    assert {:ok, _} = ManagedLineage.advance(confirmed, send_record, [], [])

    assert {:ok, uncertain} =
             ManagedLineage.advance(pending, Map.put(cleanup, "status", "unknown"), [], [])

    assert {:error, _} = ManagedLineage.advance(uncertain, send_record, [], [])
    assert {:error, _} = ManagedLineage.advance(confirmed, cleanup, [], [])
  end

  test "missing effect cleanup makes live interruption and Saved recovery unavailable" do
    c = prepared()
    assert {:ok, admitted} = ManagedLineage.advance(c.lineage, c.record, [], [])

    assert {:ok, recovered} =
             ManagedLineage.advance(admitted, %{"type" => "managed_recovery"}, [], [])

    assert recovered.unavailable
    {:reply, {:ok, _}, pending} = ManagedToolUse.prepare(c.state, self(), c.target)

    pending = %{
      pending
      | managed_lineage: admitted,
        managed_tool_effect: %{pending.managed_tool_effect | admitted: true, admission: c.record}
    }

    assert ManagedToolUse.interrupted(pending).managed_lineage.unavailable

    assert {:reply, {:error, :managed_tool_inputs_unavailable}, refused} =
             ManagedToolUse.prepare_result(pending, self(), "result_recorded", "must not publish")

    assert refused.managed_lineage.unavailable
  end
end
