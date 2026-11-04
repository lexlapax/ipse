defmodule Ipse.Session.ManagementRootTransitionTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session}
  alias Ipse.Session.{ManagedLineage, ManagedReference}

  defp fixture do
    f =
      __DIR__
      |> Path.join("fixtures/chat_management_root.json")
      |> File.read!()
      |> Jason.decode!()

    id = f["handoff"]["session_id"]
    old = f["old_dependencies"]
    # This extra structural v4 fixture has no deadline, so the pure verdict
    # guard remains independent of the historical accepted note's clock.
    record = %{
      "key" => "record.synthetic",
      "revision" => 1,
      "value_sha256" => JSON.sha256("synthetic record")
    }

    base = hd(f["current_dependencies"])

    v4 =
      Map.put(base, "version", 4)
      |> Map.put("subject", %{
        "kind" => "record_observation",
        "key" => record["key"],
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => record["key"]}]),
        "result_sha256" => JSON.sha256("synthetic observed result"),
        "publication_policy_sha256" => nil,
        "record" => record,
        "validity" => %{
          "recipe_sha256" => JSON.sha256("recipe"),
          "lineage" => JSON.sha256("lineage"),
          "source_versions" => [],
          "valid_until_ms" => nil,
          "status" => "eligible",
          "dependencies" => []
        }
      })

    assert ManagedReference.dependency?(v4)
    current = f["current_dependencies"] ++ [v4]

    call = %{
      "role" => "assistant",
      "content" => "",
      "provider_data" => %{"opaque" => "preserve exactly"},
      "tool_calls" => [
        %{
          "id" => "nomination",
          "function" => %{"name" => "ext__knowledge__nominate", "arguments" => "{}"}
        }
      ]
    }

    reply = %{"role" => "tool", "tool_call_id" => "nomination", "content" => "nominated"}
    reference = %{"role" => "user", "content" => "Synthetic current accepted-decision reference"}
    messages = [call, reply, reference, %{"role" => "user", "content" => "ordinary followup"}]
    {:ok, lineage} = ManagedLineage.new(id)

    {:ok, _, state} =
      ManagedReference.admit(
        lineage.reference,
        %{"kind" => "assistant", "id" => "nominate", "parent_id" => nil},
        0,
        call,
        old
      )

    {:ok, _, state} =
      ManagedReference.admit(
        state,
        %{"kind" => "reference", "id" => "recall", "parent_id" => nil},
        2,
        reference,
        current
      )

    {:ok, dependencies} = ManagedReference.union([old, current])
    successor = f["capture_successor"]
    dictionary = Map.new(dependencies ++ [successor], &{JSON.digest([&1]), &1})

    cache =
      dependencies
      |> Enum.filter(&(&1["version"] == 3))
      |> Map.new(&{JSON.digest([&1]), true})
      |> Map.put(JSON.digest([successor]), true)

    action = f["capture_action"]

    value = %{
      "action" => action,
      "dependencies" => old,
      "parent_sha256" => f["capture_parent_sha256"],
      "result_sha256" => f["capture_result_sha256"],
      "result_pending_key" => f["handoff"]["pending_key"],
      "handoff" => f["handoff"]
    }

    lineage = %{
      lineage
      | reference: state,
        admission: %{"pin" => f["handoff"]["pin"]},
        frozen_header: true,
        root_writes: %{action["operation_id"] => value},
        root_observations: cache,
        dictionary: dictionary,
        root_transitions: Map.new(old, &{JSON.digest([&1]), JSON.digest([successor])})
    }

    root = Enum.find(current, &(&1["version"] == 3))["collection"]
    {observation, inspected} = observation(root, action["outcome"]["value"]["receipt"])
    now = System.system_time(:millisecond)

    binding = %{
      "version" => 1,
      "session_id" => id,
      "turn_id" => String.duplicate("c", 32),
      "request_id" => String.duplicate("d", 32),
      "phase" => "model",
      "route_sha256" => JSON.sha256("route"),
      "tools_sha256" => JSON.sha256("tools"),
      "source_generation" => 1,
      "policy_generation" => f["handoff"]["pin"]["epoch"],
      "checked_at_ms" => now,
      "deadline_ms" => now + 30_000
    }

    %{
      f: f,
      state: lineage,
      messages: messages,
      dependencies: dependencies,
      binding: binding,
      observation: observation,
      inspected: inspected,
      management: f["management"]
    }
  end

  defp observation(root, capture) do
    public = Map.take(root, ~w(project generation floor floor_anchor)) |> Map.put("version", 1)

    descriptor =
      Enum.find_value([4, 5], fn version ->
        value =
          Map.take(root, ~w(project generation floor floor_anchor))
          |> Map.merge(%{"version" => version, "manifest" => root["manifest_sha256"]})

        if JSON.sha256(Jason.encode!(value)) === root["root_sha256"], do: value
      end)

    assert is_map(descriptor)

    witness = %{
      "version" => 2,
      "root_state" => "present",
      "root" => descriptor,
      "root_sha256" => root["root_sha256"],
      "manifest_sha256" => root["manifest_sha256"]
    }

    {%{
       "version" => 1,
       "request_sha256" => JSON.digest([%{"op" => "snapshot"}]),
       "result_sha256" => JSON.digest([public]),
       "value" => public,
       "witness" => witness
     }, Map.put(public, "operation", capture)}
  end

  defp project(c, management \\ nil),
    do:
      ManagedLineage.management_root_projection(
        c.state,
        c.messages,
        c.binding,
        c.observation,
        c.inspected,
        management || c.management
      )

  test "exact capture then standalone acceptance preserves opaque calls and every record dependency" do
    c = fixture()

    assert {:ok, %{action: action, handoff: handoff}} =
             ManagedLineage.management_root_candidate(c.state, c.dependencies)

    assert action === c.f["capture_action"] and handoff === c.f["handoff"]
    assert {:ok, event, messages, reference, _} = project(c)
    assert event["version"] === 2
    assert Enum.take(messages, length(c.messages)) === c.messages

    assert List.last(messages)["ipse_root_history"]["management_operation_id"] ===
             c.management["intent"]["operation_id"]

    assert List.last(messages)["content"] =~ "separate confirmed decision acceptance"
    assert {:ok, retained} = ManagedReference.dependencies(reference, messages)

    assert Enum.filter(retained, &(&1["version"] != 3)) ===
             Enum.filter(c.dependencies, &(&1["version"] != 3))

    assert Enum.any?(retained, &(&1["version"] == 6))
    assert byte_size(Jason.encode!(event)) < 65_536
    assert {:ok, ^event} = JSON.decode_unique(Jason.encode!(event))
  end

  test "candidate requires the actual capture parent, result, pending selection and classified cache" do
    c = fixture()
    operation = c.f["capture_action"]["operation_id"]

    for key <- ~w(parent_sha256 result_sha256 result_pending_key) do
      state = put_in(c.state.root_writes[operation][key], "changed")
      assert {:error, _} = ManagedLineage.management_root_candidate(state, c.dependencies)
    end

    assert {:error, _} =
             ManagedLineage.management_root_candidate(
               %{c.state | root_observations: %{}},
               c.dependencies
             )

    assert {:error, _} =
             ManagedLineage.management_root_candidate(
               %{c.state | root_writes: %{}},
               c.dependencies
             )

    assert {:error, _} =
             ManagedLineage.management_root_candidate(
               c.state,
               Enum.reject(c.dependencies, &(&1["version"] == 6))
             )
  end

  test "wrong, cancelled, unknown, forged and unrelated management evidence cannot map roots" do
    c = fixture()

    altered = [
      put_in(c.management, ["result", "status"], "unknown"),
      put_in(c.management, ["result", "receipt", "generation"], 3),
      put_in(c.management, ["result", "receipt", "request_sha256"], JSON.sha256("forged")),
      put_in(c.management, ["intent", "request", "expected_generation"], 0),
      put_in(c.management, ["event", "facts", "source_proof", "quote"], "forged"),
      put_in(c.management, ["handoff", "event", "capture_result_sha256"], JSON.sha256("foreign")),
      put_in(c.management, ["event", "facts", "operation_id"], String.duplicate("a", 32)),
      Map.delete(c.management, "result")
    ]

    for value <- altered, do: assert({:error, _} = project(c, value))

    assert {:error, _} =
             project(%{c | inspected: put_in(c.inspected, ["operation", "generation"], 9)})
  end

  test "an unrelated historical observation is never laundered by a cached root match" do
    c = fixture()

    extra =
      put_in(hd(c.f["old_dependencies"]), ["subject", "request_sha256"], JSON.sha256("unrelated"))

    message = %{"role" => "user", "content" => "unrelated old metadata"}

    {:ok, _, reference} =
      ManagedReference.admit(
        c.state.reference,
        %{"kind" => "reference", "id" => "foreign", "parent_id" => nil},
        length(c.messages),
        message,
        [extra]
      )

    state = %{
      c.state
      | reference: reference,
        root_observations: Map.put(c.state.root_observations, JSON.digest([extra]), true)
    }

    assert {:error, _} = project(%{c | state: state, messages: c.messages ++ [message]})
  end

  test "management fallback refuses stale record verdicts and duplicate result identities" do
    c = fixture()

    dependencies = Enum.reject(c.dependencies, &(&1["version"] == 6))

    good =
      Enum.map(dependencies, fn dependency ->
        %{
          "dependency_sha256" => JSON.digest([dependency]),
          "status" => if(dependency["version"] == 3, do: "unavailable", else: "eligible"),
          "current" => if(dependency["version"] == 3, do: nil, else: dependency)
        }
      end)

    assert Session.management_root_verdicts?(dependencies, good)

    bad =
      Enum.map(good, fn verdict ->
        if verdict["status"] == "eligible",
          do: %{verdict | "status" => "unavailable", "current" => nil},
          else: verdict
      end)

    refute Session.management_root_verdicts?(dependencies, bad)
    refute Session.management_root_verdicts?(dependencies, good ++ [hd(good)])
    refute Session.management_root_verdicts?(dependencies, tl(good))
  end
end
