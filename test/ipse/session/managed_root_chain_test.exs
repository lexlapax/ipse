defmodule Ipse.Session.ManagedRootChainTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session}
  alias Ipse.Session.{ManagedLineage, ManagedReference}

  @journal "docs/archive/2026-10-26-p30-p31-implementation/own-root-transition/journals/model.jsonl"

  # Reuse the public single-write protocol fixture, constructing three distinct
  # valid actions and classified roots. This supplies no live publication authority.
  defp fixture do
    events =
      @journal |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    id = get_in(hd(events), ["metadata", "source_origin", "session_id"])

    index =
      Enum.find_index(events, &(get_in(&1, ["projection", "type"]) == "managed_root_transition"))

    result = Enum.at(events, index)
    {:ok, saved} = Session.Saved.restore(Enum.take(events, index), id)
    base = saved.managed_lineage
    [{_, template}] = Map.to_list(base.root_writes)
    [old | _] = template["dependencies"]
    roots = for generation <- 0..3, do: root(old, generation)
    records = for n <- 1..4, do: record(hd(roots), n)

    messages =
      for n <- 0..3, do: %{"role" => "user", "content" => "Constructed root observation #{n}."}

    {:ok, reference} = ManagedReference.new(id)

    reference =
      Enum.reduce(Enum.with_index(messages), reference, fn {message, n}, reference ->
        {:ok, _, reference} =
          ManagedReference.admit(
            reference,
            %{"kind" => "reference", "id" => "root.#{n}", "parent_id" => nil},
            n,
            message,
            [Enum.at(roots, n) | records]
          )

        reference
      end)

    writes =
      for generation <- 0..2, into: %{} do
        action = action(template["action"], generation)
        key = hd(action["request"]["request"]["changes"])["key"]

        {action["operation_id"],
         %{
           "action" => action,
           "dependencies" => [Enum.at(roots, generation) | records],
           "result_sha256" =>
             JSON.digest([%{"invocation_id" => action["parent_invocation_id"], "key" => key}]),
           "result_pending_key" => key
         }}
      end

    dependencies = Enum.sort_by(roots ++ records, &JSON.digest([&1]))

    state = %{
      base
      | reference: reference,
        root_writes: writes,
        dictionary: Map.new(dependencies, &{JSON.digest([&1]), &1}),
        root_observations: Map.new(roots, &{JSON.digest([&1]), true}),
        root_transitions:
          Map.new(
            0..2,
            &{JSON.digest([Enum.at(roots, &1)]), JSON.digest([Enum.at(roots, &1 + 1)])}
          ),
        outputs:
          Map.new(writes, fn {_, value} -> {value["action"]["parent_invocation_id"], []} end),
        preflight: nil
    }

    intent =
      Enum.find(
        events,
        &(&1["type"] == "managed_preflight_intent" and &1["intent_id"] == result["intent_id"])
      )
      |> Map.put("before_sha256", JSON.digest(messages))
      |> Map.put("input_sha256", JSON.digest([base.header ++ messages]))
      |> Map.put("dependencies_sha256", JSON.digest(dependencies))
      |> Map.put("snapshot_sha256", JSON.digest(["model", base.header ++ messages, dependencies]))

    admission =
      Enum.find(
        events,
        &(&1["type"] == "request_admitted" and &1["request_id"] == intent["request_id"])
      )

    state = %{state | preflight: intent, admissions: %{intent["request_id"] => admission}}
    binding = ManagedLineage.preflight_binding(intent)
    last = writes[operation(2)]["action"]

    {observation, inspection} =
      observation(List.last(roots)["collection"], last["outcome"]["value"]["receipt"])

    %{
      state: state,
      messages: messages,
      deps: dependencies,
      roots: roots,
      records: records,
      binding: binding,
      observation: observation,
      inspection: inspection,
      intent: intent,
      old_result: result
    }
  end

  defp operation(n), do: String.pad_leading(Integer.to_string(n + 1, 16), 32, "0")

  defp root(template, generation) do
    namespace = template["namespace"]
    manifest = JSON.sha256("constructed manifest #{generation}")

    descriptor = %{
      "version" => 4,
      "project" => namespace,
      "generation" => generation,
      "floor" => generation,
      "floor_anchor" => if(generation == 0, do: nil, else: operation(generation - 1)),
      "manifest" => manifest
    }

    public = descriptor |> Map.drop(~w(manifest)) |> Map.put("version", 1)

    collection =
      descriptor
      |> Map.drop(~w(version manifest))
      |> Map.merge(%{
        "root_state" => "present",
        "root_sha256" => JSON.sha256(Jason.encode!(descriptor)),
        "manifest_sha256" => manifest
      })

    dependency =
      template
      |> Map.put("collection", collection)
      |> Map.put("subject", %{
        "kind" => "root_observation",
        "request_sha256" => JSON.digest([%{"op" => "snapshot"}]),
        "result_sha256" => JSON.digest([public])
      })

    assert ManagedReference.dependency?(dependency)
    dependency
  end

  defp record(template, n) do
    key = "record.constructed.#{n}"

    dependency =
      template
      |> Map.put("version", 4)
      |> Map.put("subject", %{
        "kind" => "record_observation",
        "key" => key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => JSON.sha256("constructed observed record #{n}"),
        "publication_policy_sha256" => nil,
        "record" => %{"key" => key, "revision" => 1, "value_sha256" => JSON.sha256(key)},
        "validity" => %{
          "recipe_sha256" => JSON.sha256("recipe"),
          "lineage" => JSON.sha256(key),
          "source_versions" => [],
          "valid_until_ms" => nil,
          "status" => "eligible",
          "dependencies" => []
        }
      })

    assert ManagedReference.dependency?(dependency)
    dependency
  end

  defp action(template, generation) do
    request =
      template["request"]
      |> put_in(["request", "expected_generation"], generation)
      |> put_in(
        ["request", "changes", Access.at(0), "key"],
        "pending." <> JSON.sha256("capture #{generation}")
      )

    normalization =
      template["outcome"]["value"]["normalization"]
      |> Map.put("record_key", hd(request["request"]["changes"])["key"])

    binding =
      template["outcome"]["value"]["binding"]
      |> Map.put("original_request_sha256", JSON.digest([request["request"]]))
      |> Map.put("normalization_sha256", JSON.digest([normalization]))

    receipt =
      template["outcome"]["value"]["receipt"]
      |> Map.merge(%{
        "generation" => generation + 1,
        "floor" => generation + 1,
        "managed_binding_sha256" => JSON.digest([binding])
      })

    outcome = %{
      "status" => "ok",
      "value" => %{
        "version" => 1,
        "binding" => binding,
        "normalization" => normalization,
        "receipt" => receipt
      }
    }

    action =
      template
      |> Map.put("request", request)
      |> Map.put("operation_id", operation(generation))
      |> Map.put("parent_invocation_id", String.duplicate(Integer.to_string(generation + 4), 32))
      |> Map.put("request_sha256", JSON.digest([request]))
      |> put_in(["effect_binding", "request_sha256"], JSON.digest([request["request"]]))
      |> Map.put("outcome", outcome)
      |> Map.put("outcome_sha256", JSON.digest([outcome]))

    assert Ipse.Extension.Actions.valid_result?(action)
    assert Ipse.Extension.ManagedCollectionCall.bound_outcome?(action)
    action
  end

  defp observation(root, receipt) do
    public = root |> Map.take(~w(project generation floor floor_anchor)) |> Map.put("version", 1)

    descriptor =
      root
      |> Map.take(~w(project generation floor floor_anchor))
      |> Map.merge(%{"version" => 4, "manifest" => root["manifest_sha256"]})

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
     }, Map.put(public, "operation", receipt)}
  end

  defp project(c, state \\ nil),
    do:
      ManagedLineage.root_projection(
        state || c.state,
        c.messages,
        c.binding,
        c.observation,
        c.inspection
      )

  defp result(c, event),
    do: %{
      "type" => "managed_preflight_result",
      "version" => 1,
      "intent_id" => c.intent["intent_id"],
      "projection" => event,
      "verdicts" => nil
    }

  test "three successive known captures retain four records and all original messages in live and Saved replay projection" do
    c = fixture()
    assert {:error, _} = ManagedLineage.root_candidate(c.state, c.deps)
    assert {:ok, action} = ManagedLineage.root_projection_candidate(c.state, c.deps)
    assert action["operation_id"] === operation(2)
    assert {:ok, event, messages, reference, next} = project(c)
    assert event["version"] === 3
    assert Enum.map(event["root_chain"], & &1["operation_id"]) === Enum.map(0..2, &operation/1)
    assert event["old_dependencies"] === c.deps
    assert Enum.take(messages, 4) === c.messages
    assert {:ok, active} = ManagedReference.dependencies(reference, messages)

    assert Enum.filter(active, &(&1["version"] === 4)) ===
             Enum.sort_by(c.records, &JSON.digest([&1]))

    assert Enum.filter(active, &(&1["version"] === 3)) === [event["fresh_dependency"]]
    assert byte_size(Jason.encode!(result(c, event))) <= 65_536

    assert {:ok, ^messages, replayed} =
             ManagedLineage.replay_projection(c.state, result(c, event), c.messages)

    assert replayed.root_writes === next.root_writes
    assert replayed.root_transitions === next.root_transitions
  end

  test "every missing mapping, classification and settled write refuses the whole chain" do
    c = fixture()

    for dependency <- Enum.take(c.roots, 3) do
      digest = JSON.digest([dependency])

      assert {:error, _} =
               project(c, %{
                 c.state
                 | root_transitions: Map.delete(c.state.root_transitions, digest)
               })

      assert {:error, _} =
               project(c, %{
                 c.state
                 | root_observations: Map.delete(c.state.root_observations, digest)
               })
    end

    for op <- Enum.map(0..2, &operation/1) do
      assert {:error, _} =
               project(c, %{c.state | root_writes: Map.delete(c.state.root_writes, op)})
    end
  end

  test "unknown, incomplete, ambiguous and cross-scope writes cannot be historical authority" do
    c = fixture()
    value = c.state.root_writes[operation(1)]

    variants = [
      Map.delete(value, "result_sha256"),
      put_in(value, ["action", "outcome", "status"], "unknown"),
      put_in(value, ["action", "outcome", "status"], "failed"),
      put_in(value, ["dependencies", Access.at(0), "namespace"], JSON.sha256("foreign")),
      put_in(value, ["dependencies", Access.at(0), "policy_generation"], 999)
    ]

    for value <- variants do
      assert {:error, _} =
               project(c, %{
                 c.state
                 | root_writes: Map.put(c.state.root_writes, operation(1), value)
               })
    end

    assert {:error, _} =
             project(c, %{
               c.state
               | outputs: Map.delete(c.state.outputs, value["action"]["parent_invocation_id"])
             })

    assert {:error, _} =
             project(c, %{
               c.state
               | root_writes: Map.put(c.state.root_writes, operation(9), value)
             })

    for id <- [JSON.digest([hd(c.roots)])] do
      assert {:error, _} =
               project(c, %{
                 c.state
                 | root_transitions:
                     Map.put(c.state.root_transitions, id, JSON.digest([List.last(c.roots)]))
               })
    end
  end

  test "Saved projection replay refuses gap, reorder, branch, substituted receipt, float tag and fresh-root mismatch" do
    c = fixture()
    assert {:ok, event, _, _, _} = project(c)
    [first | rest] = event["root_chain"]

    variants = [
      Map.put(event, "root_chain", rest),
      Map.put(event, "root_chain", Enum.reverse(event["root_chain"])),
      Map.put(event, "root_chain", [first, first | rest]),
      Map.put(event, "version", 3.0),
      put_in(event, ["root_chain", Access.at(0), "receipt_sha256"], JSON.sha256("forged")),
      put_in(
        event,
        ["root_chain", Access.at(0), "to_dependency_sha256"],
        JSON.digest([List.last(c.roots)])
      )
    ]

    for event <- variants do
      assert {:error, _} = ManagedLineage.replay_projection(c.state, result(c, event), c.messages)
    end

    assert {:error, _} =
             project(%{c | observation: put_in(c.observation, ["value", "generation"], 4)})
  end
end
