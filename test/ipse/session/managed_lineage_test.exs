defmodule Ipse.Session.ManagedLineageTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Session.{ManagedLineage, ManagedReference}

  defp dependency do
    %{
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
  end

  @tag managed_audit_pure: true
  test "pending native recovery uses the original call union rather than projected messages" do
    {:ok, lineage} = ManagedLineage.new(Usage.id())
    question = %{call: %{"id" => "question"}, arguments: %{"private" => "managed"}}
    dep = dependency()
    digest = JSON.digest([dep])
    tainted = %{lineage | calls: %{"question" => [digest]}, dictionary: %{digest => dep}}

    assert {nil, %{unavailable: true}, :managed_question_withheld} =
             Ipse.Session.Saved.recover_question(question, tainted, %{})

    assert {^question, ^lineage, nil} =
             Ipse.Session.Saved.recover_question(question, lineage, %{})

    assert {nil, _, :managed_question_withheld} =
             Ipse.Session.Saved.recover_question(question, %{lineage | unavailable: true}, %{})
  end

  @tag managed_audit_pure: true
  @tag managed_question_parent_binding: true
  test "extension question recovery requires a present producer and its entire observed union" do
    {:ok, lineage} = ManagedLineage.new(Usage.id())
    id = Usage.id()
    parent = %{"invocation_id" => id}
    question = %{kind: :extension, parent: parent, arguments: %{"private" => "managed"}}
    extension = %{parent: parent, managed_dependencies: []}

    assert {nil, _, :managed_question_withheld} =
             Ipse.Session.Saved.recover_question(question, lineage, extension)

    missing_parent = %{lineage | invocations: %{id => %{input: [], reads: []}}}

    assert {nil, _, :managed_question_withheld} =
             Ipse.Session.Saved.recover_question(question, missing_parent, extension)

    lineage = %{lineage | invocations: %{id => %{input: [], reads: [], parent: parent}}}

    assert {^question, ^lineage, nil} =
             Ipse.Session.Saved.recover_question(question, lineage, extension)

    different_parent = Map.put(parent, "payload", %{"different" => true})

    for {changed_lineage, changed_extension} <- [
          {%{lineage | invocations: %{id => %{input: [], reads: [], parent: different_parent}}},
           extension},
          {lineage, %{extension | parent: different_parent}}
        ] do
      assert {nil, _, :managed_question_withheld} =
               Ipse.Session.Saved.recover_question(question, changed_lineage, changed_extension)
    end

    assert {nil, _, :managed_question_withheld} =
             Ipse.Session.Saved.recover_question(question, lineage, %{
               extension
               | managed_dependencies: [dependency()]
             })

    assert {nil, _, :managed_question_withheld} =
             Ipse.Session.Saved.recover_question(question, lineage, %{extension | parent: %{}})
  end

  defp worker(state, before, dep, publish \\ false) do
    id = Usage.id()

    intent = %{
      "type" => "extension_invocation_intent",
      "invocation_id" => id,
      "descriptor" => %{"stage" => "invoke.tool"},
      "identity" => %{"instance" => "knowledge"}
    }

    {:ok, state} = ManagedLineage.advance(state, intent, before, before)
    op = Usage.id()
    receipt = %{"type" => "managed_read_observed", "operation_id" => op, "dependencies" => [dep]}
    {:ok, state} = ManagedLineage.advance(state, receipt, before, before)

    action = %{
      "type" => "extension_action_result",
      "parent_invocation_id" => id,
      "operation_id" => op,
      "request" => %{"op" => "collection.call"},
      "outcome" => %{"status" => "ok"}
    }

    {:ok, state} = ManagedLineage.advance(state, action, before, before)

    state =
      if publish do
        event = %{
          "type" => "extension_action_result",
          "parent_invocation_id" => id,
          "operation_id" => Usage.id(),
          "request" => %{"op" => "context.publish"},
          "outcome" => %{"status" => "ok"}
        }

        {:ok, state} = ManagedLineage.advance(state, event, before, before)
        state
      else
        state
      end

    message = %{
      "role" => "tool",
      "tool_call_id" => "read",
      "content" => "Synthetic managed text",
      "ipse_extension_result" => %{
        "invocation_id" => id,
        "artifact_sha256" => JSON.sha256("artifact"),
        "result_sha256" => JSON.sha256("result")
      }
    }

    result = %{"type" => "extension_invocation_result", "invocation_id" => id}
    {:ok, state} = ManagedLineage.advance(state, result, before, before ++ [message])
    {state, before ++ [message], id}
  end

  test "committed worker reads propagate to assistant and subsequent native tool outputs" do
    dep = dependency()
    assert ManagedReference.dependency?(dep)
    {:ok, state} = ManagedLineage.new(Usage.id())
    {state, messages, _} = worker(state, [], dep)
    request = %{"type" => "request_admitted", "request_id" => Usage.id()}
    assert {:ok, state} = ManagedLineage.advance(state, request, messages, messages)

    assistant = %{
      "role" => "assistant",
      "content" => "Derived answer",
      "tool_calls" => [
        %{"id" => "native", "function" => %{"name" => "read", "arguments" => "{}"}}
      ]
    }

    event = %{"type" => "message", "request_id" => request["request_id"], "message" => assistant}
    assert {:ok, state} = ManagedLineage.advance(state, event, messages, messages ++ [assistant])
    messages = messages ++ [assistant]
    result = %{"role" => "tool", "tool_call_id" => "native", "content" => "Derived native result"}

    assert {:ok, state} =
             ManagedLineage.advance(
               state,
               %{"type" => "message", "message" => result},
               messages,
               messages ++ [result]
             )

    assert {:ok, [^dep]} = ManagedLineage.dependencies(state, messages ++ [result])
    assert map_size(state.reference.occurrences) == 3
  end

  test "an uncommitted read observation cannot taint a successful later worker result" do
    {:ok, state} = ManagedLineage.new(Usage.id())

    receipt = %{
      "type" => "managed_read_observed",
      "operation_id" => Usage.id(),
      "dependencies" => [dependency()]
    }

    assert {:ok, state} = ManagedLineage.advance(state, receipt, [], [])
    assert {:ok, []} = ManagedLineage.dependencies(state, [])
  end

  test "a validated metadata-only event job inherits no conversation text but ordinary event views do" do
    dep = dependency()
    {:ok, initial} = ManagedLineage.new(Usage.id())
    {initial, messages, _} = worker(initial, [], dep)

    for {view, expected} <- [{"metadata", []}, {"prompt.effective", [dep]}] do
      id = Usage.id()

      intent = %{
        "type" => "extension_invocation_intent",
        "invocation_id" => id,
        "descriptor" => %{"stage" => "event.job"},
        "identity" => %{"instance" => "knowledge"},
        "payload" => %{"arguments" => %{"event" => %{"event" => %{"view" => view}}}}
      }

      assert {:ok, state} = ManagedLineage.advance(initial, intent, messages, messages)
      assert {:ok, ^expected} = ManagedLineage.invocation_dependencies(state, id)
    end
  end

  test "transparent native text requires its exact host request and selected provider route" do
    dep = dependency()
    id = Usage.id()
    {:ok, initial} = ManagedLineage.new(id)
    {initial, before, _} = worker(initial, [], dep)

    route = %{
      "operation" => "main",
      "profile" => nil,
      "provider" => "ollama",
      "model" => "synthetic",
      "billing_mode" => "local"
    }

    initial = %{initial | admission: %{"policy" => %{"settings" => %{"routes" => [route]}}}}
    admission = Usage.admission(id, %{provider: :ollama, model: "synthetic"}, "model", Usage.id())
    {:ok, initial} = ManagedLineage.advance(initial, admission, before, before)

    dispatch = %{
      "type" => "inference_dispatch_intent",
      "request_id" => admission["request_id"],
      "session_id" => id,
      "phase" => "model",
      "admission_sha256" => JSON.digest([admission]),
      "route_sha256" => JSON.digest([route])
    }

    message = %{
      "role" => "assistant",
      "content" => "same visible bytes",
      "provider_data" => %{
        "provider" => "ollama",
        "reported_model" => "synthetic",
        "message" => %{
          "role" => "assistant",
          "content" => "same visible bytes",
          "thinking" => "",
          "tool_calls" => []
        }
      }
    }

    for {event, native, kind} <- [
          {dispatch, message, "assistant.ollama_text"},
          {Map.put(dispatch, "route_sha256", JSON.sha256("foreign route")), message, "assistant"},
          {Map.put(dispatch, "admission_sha256", JSON.sha256("foreign admission")), message,
           "assistant"},
          {Map.put(dispatch, "request_id", Usage.id()), message, "assistant"},
          {Map.put(dispatch, "phase", "compaction"), message, "assistant"},
          {dispatch, put_in(message, ["provider_data", "reported_model"], "other-model"),
           "assistant"}
        ] do
      assert {:ok, state} = ManagedLineage.advance(initial, event, before, before)

      assert {:ok, state} =
               ManagedLineage.advance(
                 state,
                 %{"type" => "request_finished", "request_id" => admission["request_id"]},
                 before,
                 before
               )

      committed = %{
        "type" => "message",
        "request_id" => admission["request_id"],
        "message" => native
      }

      assert {:ok, state} = ManagedLineage.advance(state, committed, before, before ++ [native])

      [occurrence] =
        state.reference.occurrences
        |> Map.values()
        |> Enum.filter(&(&1.position == length(before)))

      assert occurrence.producer["kind"] == kind
    end
  end

  test "summary and excerpt projections retain source dependencies and refuse unsafe withdrawal" do
    dep = dependency()
    {:ok, state} = ManagedLineage.new(Usage.id())
    {state, before, _} = worker(state, [], dep)

    checkpoint = %{
      "role" => "assistant",
      "content" => "Derived summary",
      "ipse_checkpoint" => %{"version" => 1}
    }

    event = %{"type" => "context_compacted", "request_id" => Usage.id()}
    assert {:ok, state} = ManagedLineage.advance(state, event, before, [checkpoint])
    assert {:ok, [^dep]} = ManagedLineage.dependencies(state, [checkpoint])

    assert Enum.all?(state.reference.occurrences, fn {_, item} ->
             item.producer["kind"] == "checkpoint"
           end)

    assert {:ok, plan} = ManagedReference.plan(state.reference, [checkpoint])

    binding = %{
      "version" => 1,
      "session_id" => state.reference.session_id,
      "turn_id" => Usage.id(),
      "request_id" => Usage.id(),
      "phase" => "model",
      "route_sha256" => JSON.sha256("route"),
      "tools_sha256" => JSON.sha256("tools"),
      "source_generation" => 1,
      "policy_generation" => 1,
      "checked_at_ms" => 1,
      "deadline_ms" => 1000
    }

    verdict = %{
      "dependency_sha256" => JSON.digest([dep]),
      "status" => "unavailable",
      "current" => nil
    }

    assert {:error, :managed_reference_projection_unsafe} =
             ManagedReference.project(plan, [verdict], binding)
  end

  test "byte-identical transparent native answers retain distinct actual request provenance" do
    dep = dependency()
    id = Usage.id()
    {:ok, state} = ManagedLineage.new(id)
    {state, messages, _} = worker(state, [], dep)

    route = %{
      "operation" => "main",
      "profile" => nil,
      "provider" => "ollama",
      "model" => "synthetic",
      "billing_mode" => "local"
    }

    state = %{state | admission: %{"policy" => %{"settings" => %{"routes" => [route]}}}}

    message = %{
      "role" => "assistant",
      "content" => "same bytes",
      "provider_data" => %{
        "provider" => "ollama",
        "message" => %{
          "role" => "assistant",
          "content" => "same bytes",
          "thinking" => "",
          "tool_calls" => []
        }
      }
    }

    {state, messages, requests} =
      Enum.reduce(1..2, {state, messages, []}, fn _, {state, messages, requests} ->
        admission =
          Usage.admission(id, %{provider: :ollama, model: "synthetic"}, "model", Usage.id())

        {:ok, state} = ManagedLineage.advance(state, admission, messages, messages)

        event = %{
          "type" => "inference_dispatch_intent",
          "request_id" => admission["request_id"],
          "session_id" => id,
          "phase" => "model",
          "admission_sha256" => JSON.digest([admission]),
          "route_sha256" => JSON.digest([route])
        }

        {:ok, state} = ManagedLineage.advance(state, event, messages, messages)

        committed = %{
          "type" => "message",
          "request_id" => admission["request_id"],
          "message" => message
        }

        {:ok, state} = ManagedLineage.advance(state, committed, messages, messages ++ [message])
        {state, messages ++ [message], requests ++ [admission["request_id"]]}
      end)

    occurrences =
      state.reference.occurrences
      |> Map.values()
      |> Enum.filter(&(&1.producer["kind"] == "assistant.ollama_text"))

    assert length(occurrences) == 2
    assert length(Enum.uniq_by(occurrences, & &1.producer["id"])) == 2
    assert Enum.sort(Enum.map(occurrences, & &1.producer["parent_id"])) == Enum.sort(requests)
    assert {:ok, [^dep]} = ManagedLineage.dependencies(state, messages)
  end

  test "context publishers inherit all preceding reads even without a visible result message" do
    dep = dependency()
    {:ok, state} = ManagedLineage.new(Usage.id())
    {state, before, _} = worker(state, [], dep, true)
    assert state.publishers["knowledge"] != []
    reference = %{"role" => "user", "content" => "Current untrusted reference"}

    assert {:ok, state} =
             ManagedLineage.advance(
               state,
               %{
                 "type" => "reference_envelope",
                 "content" =>
                   Ipse.Session.Reference.content(%{"extensions" => "Synthetic publisher"})
               },
               before,
               before ++ [reference]
             )

    assert {:ok, [^dep]} = ManagedLineage.dependencies(state, before ++ [reference])
  end

  test "legacy managed reads without observed roots remain inspectable but unavailable for use" do
    {:ok, state} = ManagedLineage.new(Usage.id())
    id = Usage.id()

    parent = %{
      "type" => "extension_invocation_intent",
      "invocation_id" => id,
      "descriptor" => %{"stage" => "invoke.tool"},
      "identity" => %{"instance" => "knowledge"}
    }

    mapping = %{
      "class" => "collection.read",
      "inner_op" => "collection.call",
      "managed_read" => [JSON.sha256("recipe")],
      "outer_sha256" => JSON.digest([parent["descriptor"]])
    }

    header = %{
      "type" => "session",
      "metadata" => %{
        "semantic_admission" => %{"policy" => %{"settings" => %{"effects" => [mapping]}}}
      }
    }

    assert {:ok, state} = ManagedLineage.advance(state, header, [], [])
    assert {:ok, state} = ManagedLineage.advance(state, parent, [], [])

    read = %{
      "type" => "extension_action_result",
      "parent_invocation_id" => id,
      "operation_id" => Usage.id(),
      "request" => %{"op" => "collection.call", "request" => %{"op" => "snapshot"}},
      "outcome" => %{"status" => "ok"}
    }

    assert {:ok, state} = ManagedLineage.advance(state, read, [], [])
    assert state.unavailable
    assert {:error, :managed_lineage_unavailable} = ManagedLineage.dependencies(state, [])
    message = %{"role" => "assistant", "content" => "Historical result"}

    assert {:ok, ^state} =
             ManagedLineage.advance(state, %{"type" => "message", "message" => message}, [], [
               message
             ])
  end

  test "ordinary histories stay usable and capacity exhaustion refuses without evicting lineage" do
    {:ok, state} = ManagedLineage.new(Usage.id())
    header = %{"type" => "session", "metadata" => %{}}
    assert {:ok, state} = ManagedLineage.advance(state, header, [], [])
    assert {:ok, []} = ManagedLineage.dependencies(state, [])
    {state, messages, _} = worker(state, [], dependency())
    [ref] = Map.keys(state.dictionary)
    retained = Map.new(1..2048, &{Integer.to_string(&1), [ref]})
    state = %{state | requests: retained}

    assert {:ok, refused} =
             ManagedLineage.advance(
               state,
               %{"type" => "request_admitted", "request_id" => Usage.id()},
               messages,
               messages
             )

    assert refused.unavailable and refused.requests == retained
    assert {:error, :managed_lineage_unavailable} = ManagedLineage.dependencies(refused, messages)

    assert {:ok, ^refused} =
             ManagedLineage.with_capacity_cache(fn ->
               ManagedLineage.advance(
                 state,
                 %{"type" => "request_admitted", "request_id" => Usage.id()},
                 messages,
                 messages
               )
             end)
  end

  test "replay capacity caching preserves exact encoded sizes and clears its scope" do
    samples = [
      %{},
      %{requests: %{}, native_requests: %{}},
      %{requests: %{"one" => ["café", "\"\\\n"]}, native_requests: %{}},
      %{requests: %{"one" => ["café", "\"\\\n"]}, native_requests: %{"two" => true}},
      %{requests: %{"one" => ["changed"]}},
      %{requests: %{"signed_zero" => 0.0}},
      %{requests: %{"signed_zero" => -0.0}},
      %{"string-key" => %{"nested" => [nil, 1, 1.0]}}
    ]

    base = byte_size(Jason.encode!(%{requests: ""}))
    at_limit = %{requests: String.duplicate("x", 4_194_304 - base)}
    over_limit = %{requests: at_limit.requests <> "x"}
    many = Map.new(1..70, fn n -> {String.to_atom("ipse_capacity_fixture_#{n}"), n} end)

    ManagedLineage.with_capacity_cache(fn ->
      for maps <- samples ++ [at_limit, over_limit, many] ++ samples do
        assert ManagedLineage.capacity_bytes(maps) == byte_size(Jason.encode!(maps))
      end

      assert ManagedLineage.capacity_bytes(at_limit) == 4_194_304
      assert ManagedLineage.capacity_bytes(over_limit) == 4_194_305
      assert ManagedLineage.capacity_bytes(many) == byte_size(Jason.encode!(many))
      cache = Process.get({ManagedLineage, :capacity_cache})
      assert map_size(cache) == 64

      assert Enum.reduce(cache, 0, fn {_, {signature, _}}, n -> n + byte_size(signature) end) <=
               4_194_304

      ManagedLineage.with_capacity_cache(fn ->
        assert ManagedLineage.capacity_bytes(hd(samples)) == 2
      end)

      assert ManagedLineage.capacity_bytes(over_limit) == 4_194_305
    end)

    assert Process.get({ManagedLineage, :capacity_cache}) == nil

    Process.put({ManagedLineage, :capacity_cache}, :absent)
    assert :ok == ManagedLineage.with_capacity_cache(fn -> :ok end)
    assert Process.get({ManagedLineage, :capacity_cache}) == :absent
    Process.delete({ManagedLineage, :capacity_cache})

    assert_raise RuntimeError, fn ->
      ManagedLineage.with_capacity_cache(fn -> raise "synthetic failure" end)
    end

    assert Process.get({ManagedLineage, :capacity_cache}) == nil
  end

  test "a frozen reference envelope inherits only the publisher fields actually selected" do
    dep = dependency()
    {:ok, state} = ManagedLineage.new(Usage.id())
    {state, _, _} = worker(state, [], dep, true)
    {:ok, empty_reference} = ManagedReference.new(state.reference.session_id)
    state = %{state | frozen_header: true, reference: empty_reference}
    assert {:ok, []} = ManagedLineage.dependencies(state, [])
    message = %{"role" => "user", "content" => "Synthetic selected data"}

    event = %{
      "type" => "reference_envelope",
      "content" => Ipse.Session.Reference.content(%{"runtime" => %{}})
    }

    assert {:ok, omitted} = ManagedLineage.advance(state, event, [], [message])
    assert {:ok, []} = ManagedLineage.dependencies(omitted, [message])

    selected = %{
      event
      | "content" => Ipse.Session.Reference.content(%{"extensions" => "Synthetic publisher"})
    }

    assert {:ok, selected} = ManagedLineage.advance(state, selected, [], [message])
    assert {:ok, [^dep]} = ManagedLineage.dependencies(selected, [message])
  end

  test "compaction refuses a withdrawal instead of clearing lineage while retaining cached summary input" do
    id = Usage.id()
    dep = dependency()
    {:ok, state} = ManagedLineage.new(id)

    message = %{
      "role" => "user",
      "content" => "Managed text also present in cached summary input"
    }

    producer = %{"kind" => "reference", "id" => Usage.id(), "parent_id" => nil}
    {:ok, _, reference} = ManagedReference.admit(state.reference, producer, 0, message, [dep])

    route = %{
      "operation" => "main",
      "profile" => nil,
      "provider" => "ollama",
      "model" => "synthetic",
      "billing_mode" => "local"
    }

    state = %{
      state
      | reference: reference,
        frozen_header: true,
        admission: %{
          "pin" => %{"epoch" => 1},
          "policy" => %{"settings" => %{"routes" => [route]}}
        }
    }

    admission =
      Usage.admission(
        id,
        %{provider: :ollama, model: "synthetic", execution: %{id: "named-main"}},
        "compaction",
        Usage.id()
      )

    assert admission["selected_profile"] == "named-main"

    assert {:ok, state} = ManagedLineage.advance(state, admission, [message], [message])
    now = System.system_time(:millisecond)

    intent = %{
      "type" => "managed_preflight_intent",
      "version" => 1,
      "intent_id" => Usage.id(),
      "session_id" => id,
      "turn_id" => admission["turn_id"],
      "request_id" => admission["request_id"],
      "phase" => "compaction",
      "admission_sha256" => JSON.digest([admission]),
      "before_sha256" => JSON.digest([message]),
      "dependencies_sha256" => JSON.digest([dep]),
      "input_sha256" => JSON.sha256("cached summary input"),
      "tools_sha256" => JSON.digest([[]]),
      "snapshot_sha256" => JSON.sha256("actual summary snapshot"),
      "route_sha256" => JSON.digest([route]),
      "source_generation" => 1,
      "policy_generation" => 1,
      "checked_at_ms" => now,
      "deadline_ms" => now + 1000
    }

    assert {:ok, state} = ManagedLineage.advance(state, intent, [message], [message])
    binding = ManagedLineage.preflight_binding(intent)

    verdicts = [
      %{"dependency_sha256" => JSON.digest([dep]), "status" => "unavailable", "current" => nil}
    ]

    {:ok, plan} = ManagedReference.plan(reference, [message])
    assert {:ok, projection, [withdrawn], _} = ManagedReference.project(plan, verdicts, binding)
    assert withdrawn != message

    event = %{
      "type" => "managed_preflight_result",
      "version" => 1,
      "intent_id" => intent["intent_id"],
      "projection" => projection,
      "verdicts" => nil
    }

    assert {:error, :managed_lineage_unavailable} =
             ManagedLineage.replay_projection(state, event, [message])

    assert {:ok, [^dep]} = ManagedLineage.dependencies(state, [message])

    refused = %{
      "type" => "managed_preflight_refused",
      "version" => 1,
      "intent_id" => intent["intent_id"]
    }

    assert {:ok, cleared} = ManagedLineage.advance(state, refused, [message], [message])
    assert cleared.preflight == nil
    assert {:ok, [^dep]} = ManagedLineage.dependencies(cleared, [message])

    assert {:ok, recovered} =
             ManagedLineage.advance(state, %{"type" => "managed_recovery"}, [message], [message])

    assert recovered.preflight == nil
    assert {:ok, [^dep]} = ManagedLineage.dependencies(recovered, [message])
  end
end
