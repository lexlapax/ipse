defmodule Ipse.Extension.CollectionRestoreTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{CollectionStore, ResultSource}
  alias Ipse.Extension.CollectionStore.Restore
  alias Ipse.Extension.Collection.DocumentMigration
  alias Ipse.JSON

  defp reference(id \\ "a") do
    %{
      "version" => 1,
      "session_id" => String.duplicate(id, 32),
      "delivery" => %{
        "version" => 1,
        "kind" => "saved.result",
        "output_id" => String.duplicate("b", 64),
        "byte_count" => 2,
        "sha256" => Ipse.JSON.sha256("{}"),
        "historical_receipt" => true
      }
    }
  end

  defp read(reference, extra \\ %{}) do
    Map.merge(
      %{
        "op" => "collection.store",
        "scope" => "project",
        "request" => %{"op" => "restore.input.read", "offset" => 0},
        "result_input" => reference
      },
      extra
    )
  end

  defp parent(stage, arguments),
    do: %{"descriptor" => %{"stage" => stage}, "payload" => %{"arguments" => arguments}}

  test "saved result shape supplies data identity without operator selection" do
    ref = reference()
    assert ResultSource.valid_descriptor?(ref["delivery"])
    assert :ok = Restore.validate(read(ref))
    assert Restore.allowed?(read(ref), parent("invoke.command", %{"result_input" => ref}))
    refute Restore.allowed?(read(ref), parent("invoke.tool", %{"result_input" => ref}))
    refute Restore.allowed?(read(ref), parent("invoke.command", %{}))

    refute Restore.allowed?(
             read(reference("c")),
             parent("invoke.command", %{"result_input" => ref})
           )

    assert {:error, _} = Restore.validate(read(Map.put(ref, "path", "/private/journal")))
  end

  test "captured plan and page lists scope reads without letting workers replace the plan" do
    ref = reference()
    plan = reference("c")
    assert Restore.allowed?(read(ref), parent("invoke.command", %{"data_inputs" => [ref]}))
    assert Restore.allowed?(read(plan), parent("invoke.command", %{"plan_input" => plan}))
    request = read(ref, %{"plan_input" => plan})
    assert :ok = Restore.validate(request)
    assert Restore.allowed?(request, parent("invoke.command", %{"plan_input" => plan}))
    refute Restore.allowed?(request, parent("invoke.command", %{"plan_input" => ref}))
    # Actual membership is checked under the selected original plan lease;
    # matching the captured plan alone does not grant the requested page.
  end

  test "binding v3 is explicit and preserves the existing producer source-use fence" do
    v1 = %{
      "version" => 1,
      "id" => "documents",
      "scope" => "project",
      "profile" => "document_graph_v1"
    }

    v3 =
      Map.merge(v1, %{
        "version" => 3,
        "source_use" => nil,
        "input_validation" => %{
          "command_id" => "source",
          "action" => "restore_validate_page",
          "export_action" => "backup_page",
          "plan_action" => "backup_plan"
        }
      })

    assert CollectionStore.operator_binding?(v1)
    assert CollectionStore.operator_binding?(v3)
    refute CollectionStore.operator_binding?(Map.delete(v3, "input_validation"))
    refute CollectionStore.operator_binding?(put_in(v3, ["input_validation", "action"], ""))

    refute CollectionStore.operator_binding?(
             update_in(v3["input_validation"], &Map.delete(&1, "export_action"))
           )

    refute CollectionStore.operator_binding?(put_in(v3, ["input_validation", "plan_action"], ""))
    assert CollectionStore.trust_bindings?([Map.put(v3, "instance", "corpus")])

    identity = %{
      "scope" => "operator",
      "capabilities" => ["host.collection.store"],
      "collection_binding" => v3
    }

    refute CollectionStore.embedding_source_required?(identity)

    assert CollectionStore.embedding_source_required?(
             put_in(identity, ["collection_binding", "source_use"], "shared_producer_v1")
           )

    refute CollectionStore.trust_bindings?([
             Map.put(v3, "instance", "corpus") |> Map.delete("source_use")
           ])
  end

  test "internal large native exports are not accepted on the inline SDK action channel" do
    for op <- ~w(backup.plan backup.page) do
      assert {:error, _} =
               CollectionStore.validate(%{
                 "op" => "collection.store",
                 "scope" => "project",
                 "request" => %{"op" => op, "generation" => 0}
               })
    end

    assert :ok =
             CollectionStore.validate(%{
               "op" => "collection.store",
               "scope" => "project",
               "request" => %{"op" => "backup.describe", "generation" => 0}
             })
  end

  test "read receipts bind delivery, chunk bytes, offset, current owner and exact SDK request" do
    request = read(reference())
    operation = String.duplicate("d", 32)

    binding = %{
      "project" => %{"project_id" => String.duplicate("e", 64)},
      "session_id" => String.duplicate("f", 32),
      "identity_sha256" => String.duplicate("1", 64)
    }

    invocation = String.duplicate("2", 32)
    owner = Restore.actual_owner(binding, invocation)

    value = %{
      "version" => 3,
      "owner" => owner,
      "operation_id" => operation,
      "request_sha256" => Ipse.JSON.digest([request]),
      "result" => %{
        "delivery" => request["result_input"]["delivery"],
        "offset" => 0,
        "next" => nil,
        "data_base64" => Base.encode64("{}"),
        "sha256" => Ipse.JSON.sha256("{}"),
        "origin" => nil
      }
    }

    assert Restore.valid_outcome?(request, "ok", value, operation)

    event = %{
      "effect_binding" => binding,
      "parent_invocation_id" => invocation,
      "outcome" => %{"status" => "ok", "value" => value}
    }

    assert Restore.bound_outcome?(event)

    refute Restore.bound_outcome?(
             put_in(event, ["outcome", "value", "owner", "session_id"], String.duplicate("3", 32))
           )

    for changed <- [
          put_in(value, ["result", "sha256"], String.duplicate("0", 64)),
          put_in(value, ["result", "next"], 2),
          put_in(value, ["result", "offset"], 1),
          Map.put(value, "request_sha256", String.duplicate("0", 64))
        ] do
      refute Restore.valid_outcome?(request, "ok", changed, operation)
    end
  end

  defp exported_input do
    project = %{"project_id" => String.duplicate("e", 64)}
    invocation = String.duplicate("2", 32)

    binding = %{
      "project" => project,
      "session_id" => String.duplicate("a", 32),
      "identity_sha256" => String.duplicate("1", 64)
    }

    descriptor = %{
      "version" => 4,
      "profile" => "document_graph_v1",
      "project" => CollectionStore.namespace(project["project_id"]),
      "generation" => 5,
      "maintenance_epoch" => 1,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "floor_lineage_sha256" => JSON.digest([[]]),
      "records" => 0,
      "data_bytes" => 0,
      "records_sha256" => JSON.digest([[]]),
      "operations" => 0,
      "operations_sha256" => JSON.digest([[]]),
      "envelopes_sha256" => JSON.digest([[]])
    }

    compact = descriptor |> Map.delete("floor_lineage") |> Map.put("floor_lineage_count", 0)

    request = %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => %{
        "op" => "backup.metadata",
        "generation" => 5,
        "section" => "records",
        "offset" => 0,
        "limit" => 8
      }
    }

    operation = String.duplicate("d", 32)
    owner = Restore.actual_owner(binding, invocation)

    event = %{
      "type" => "extension_action_result",
      "parent_invocation_id" => invocation,
      "operation_id" => operation,
      "effect_binding" => binding,
      "request" => request,
      "outcome" => %{
        "status" => "ok",
        "value" => %{
          "version" => 3,
          "owner" => owner,
          "operation_id" => operation,
          "request_sha256" => JSON.digest([request]),
          "result" => %{
            "version" => 1,
            "generation" => 5,
            "section" => "records",
            "offset" => 0,
            "next" => nil,
            "descriptor" => compact,
            "rows" => []
          }
        }
      }
    }

    %{
      value: %{"descriptor" => descriptor},
      project_binding: project,
      action_results: [event],
      source_intent: %{
        "invocation_id" => invocation,
        "identity" => %{"artifact_sha256" => String.duplicate("9", 64)},
        "descriptor" => %{"stage" => "invoke.command", "id" => "source"},
        "payload" => %{"arguments" => %{"action" => "backup_page"}}
      }
    }
  end

  defp chunk_event(selected, bytes, offset, origin) do
    request = put_in(read(selected), ["request", "offset"], offset)
    chunk = binary_part(bytes, offset, min(6144, byte_size(bytes) - offset))

    %{
      "request" => request,
      "outcome" => %{
        "status" => "ok",
        "value" => %{
          "result" => %{
            "delivery" => selected["delivery"],
            "offset" => offset,
            "next" =>
              if(offset + byte_size(chunk) < byte_size(bytes), do: offset + byte_size(chunk)),
            "data_base64" => Base.encode64(chunk),
            "sha256" => JSON.sha256(chunk),
            "origin" => origin
          }
        }
      }
    }
  end

  test "export origin rejoins the producing invocation and every native descriptor field" do
    input = exported_input()
    assert DocumentMigration.descriptor?(input.value["descriptor"])
    [event] = input.action_results

    assert Restore.valid_outcome?(
             event["request"],
             "ok",
             event["outcome"]["value"],
             event["operation_id"]
           )

    assert {:ok, origin} = Restore.source_origin(input)
    assert origin["descriptor"]["maintenance_epoch"] === 1
    assert origin["owner"] === event["outcome"]["value"]["owner"]
    assert origin["artifact_sha256"] === input.source_intent["identity"]["artifact_sha256"]
    assert origin["metadata_sha256"] === JSON.digest([input.action_results])

    # Native calls for records and lineage legitimately share one snapshot.
    lineage =
      event
      |> put_in(["request", "request", "section"], "lineage")
      |> put_in(["outcome", "value", "result", "section"], "lineage")
      |> then(fn event ->
        put_in(event, ["outcome", "value", "request_sha256"], JSON.digest([event["request"]]))
      end)

    assert {:ok, combined} = Restore.source_origin(%{input | action_results: [event, lineage]})
    assert combined["descriptor"] === origin["descriptor"]
    refute combined["metadata_sha256"] === origin["metadata_sha256"]

    for field <-
          ~w(maintenance_epoch generation records_sha256 operations_sha256 envelopes_sha256) do
      changed =
        if field in ~w(maintenance_epoch generation), do: 6, else: String.duplicate("0", 64)

      assert {:error, _} =
               Restore.source_origin(put_in(input, [:value, "descriptor", field], changed))
    end

    for changed <- [
          %{input | action_results: []},
          %{
            input
            | action_results: [put_in(event, ["parent_invocation_id"], String.duplicate("3", 32))]
          },
          %{
            input
            | action_results: [
                put_in(
                  event,
                  ["effect_binding", "project", "project_id"],
                  String.duplicate("4", 64)
                )
              ]
          },
          %{
            input
            | action_results: [
                put_in(
                  event,
                  ["outcome", "value", "result", "descriptor", "project"],
                  String.duplicate("4", 64)
                )
              ]
          },
          %{
            input
            | action_results: [
                event,
                put_in(
                  event,
                  ["outcome", "value", "result", "descriptor", "maintenance_epoch"],
                  2
                )
              ]
          },
          put_in(input, [:value, "descriptor", "floor_lineage_sha256"], String.duplicate("0", 64))
        ] do
      assert {:error, _} = Restore.source_origin(changed)
    end

    # Plans use the same read API, but retain their actual distinct producing action.
    assert {:ok, plan_origin} =
             Restore.source_origin(
               put_in(input, [:source_intent, "payload", "arguments", "action"], "backup_plan")
             )

    assert plan_origin["action"] === "backup_plan"
  end

  test "selected bytes require one origin across the exact complete chunk sequence" do
    assert {:ok, origin} = Restore.source_origin(exported_input())
    bytes = String.duplicate("x", 6145)

    selected =
      reference()
      |> put_in(["delivery", "byte_count"], byte_size(bytes))
      |> put_in(["delivery", "sha256"], JSON.sha256(bytes))

    first = chunk_event(selected, bytes, 0, origin)
    last = chunk_event(selected, bytes, 6144, origin)
    assert {:ok, ^bytes, ^origin} = Restore.validated_input_bytes([first, last], selected)
    assert {:error, _} = Restore.validated_input_bytes([first], selected)
    assert {:error, _} = Restore.validated_input_bytes([last, first], selected)
    other = Map.put(origin, "artifact_sha256", String.duplicate("8", 64))

    assert {:error, _} =
             Restore.validated_input_bytes(
               [first, put_in(last, ["outcome", "value", "result", "origin"], other)],
               selected
             )

    assert {:error, _} =
             Restore.validated_input_bytes(
               [put_in(first, ["outcome", "value", "result", "origin"], nil), last],
               selected
             )

    assert {:error, _} =
             Restore.validated_input_bytes(
               [
                 first,
                 put_in(last, ["outcome", "value", "result", "sha256"], String.duplicate("0", 64))
               ],
               selected
             )
  end

  test "a full 6144-byte input chunk and native origin fit the complete worker response" do
    assert {:ok, origin} = Restore.source_origin(exported_input())
    bytes = String.duplicate("x", 6144)

    selected =
      reference()
      |> put_in(["delivery", "byte_count"], byte_size(bytes))
      |> put_in(["delivery", "sha256"], JSON.sha256(bytes))

    event = chunk_event(selected, bytes, 0, origin)
    operation = String.duplicate("d", 32)

    value = %{
      "version" => 3,
      "owner" => origin["owner"],
      "operation_id" => operation,
      "request_sha256" => JSON.digest([event["request"]]),
      "result" => event["outcome"]["value"]["result"]
    }

    assert Restore.valid_outcome?(event["request"], "ok", value, operation)

    action = %{
      "parent_invocation_id" => String.duplicate("f", 32),
      "operation_id" => operation,
      "step" => 64,
      "request" => event["request"],
      "outcome" => %{"status" => "ok", "value" => value}
    }

    payload = Ipse.Extension.Actions.resume(action)
    assert :ok = Ipse.Extension.validate(payload)

    assert {:ok, <<size::32, encoded::binary>>} =
             Ipse.Extension.Worker.frame(9_007_199_254_740_991, "host.actions", payload)

    assert size === byte_size(encoded)
    assert size < 16_384
  end

  test "classification trusts the current validator while requiring an authenticated export action" do
    input = exported_input()
    assert {:ok, origin} = Restore.source_origin(input)
    bytes = Jason.encode!(input.value)

    selected =
      reference()
      |> put_in(["delivery", "byte_count"], byte_size(bytes))
      |> put_in(["delivery", "sha256"], JSON.sha256(bytes))

    current = %{"artifact_sha256" => String.duplicate("7", 64)}

    page = %{
      value: input.value,
      dependencies: [],
      source_intent: %{
        "identity" => current,
        "descriptor" => %{"stage" => "invoke.command", "id" => "source"},
        "payload" => %{
          "arguments" => %{"action" => "restore_validate_page", "result_input" => selected}
        }
      },
      action_results: [chunk_event(selected, bytes, 0, origin)]
    }

    policy = %{
      "command_id" => "source",
      "action" => "restore_validate_page",
      "export_action" => "backup_page",
      "plan_action" => "backup_plan"
    }

    # The original export artifact is historical data provenance; the validator is current.
    refute origin["artifact_sha256"] === current["artifact_sha256"]
    assert :ok = Restore.classified_page(page, policy, current)

    for wrong <- [
          Map.put(policy, "export_action", "backup_plan"),
          Map.put(policy, "command_id", "other"),
          Map.put(policy, "action", "other")
        ] do
      assert {:error, _} = Restore.classified_page(page, wrong, current)
    end

    assert {:error, _} =
             Restore.classified_page(page, policy, %{
               "artifact_sha256" => String.duplicate("8", 64)
             })

    # A validator can accurately reread worker-supplied future-M JSON; that alone is insufficient.
    forged = put_in(input.value, ["descriptor", "maintenance_epoch"], 2)
    forged_bytes = Jason.encode!(forged)

    forged_ref =
      selected
      |> put_in(["delivery", "byte_count"], byte_size(forged_bytes))
      |> put_in(["delivery", "sha256"], JSON.sha256(forged_bytes))

    forged_page =
      page
      |> Map.put(:value, forged)
      |> put_in([:source_intent, "payload", "arguments", "result_input"], forged_ref)
      |> Map.put(:action_results, [chunk_event(forged_ref, forged_bytes, 0, origin)])

    assert {:ok, ^forged_bytes, ^origin} =
             Restore.validated_input_bytes(forged_page.action_results, forged_ref)

    assert {:error, _} = Restore.classified_page(forged_page, policy, current)

    assert {:error, _} =
             Restore.classified_page(
               %{page | action_results: [chunk_event(selected, bytes, 0, nil)]},
               policy,
               current
             )
  end

  test "a lost source confirmation cannot turn an observed native commit into known failure" do
    committed = {:ok, %{"generation" => 2}}
    assert Restore.settle_observed_result(committed, committed) === committed
    assert Restore.settle_observed_result({:error, :source_lost}, committed) === :unknown
    assert Restore.settle_observed_result({:error, :source_lost}, :attempting) === :unknown
    assert Restore.settle_observed_result({:error, :source_lost}, :unknown) === :unknown

    assert Restore.settle_observed_result({:error, :source_lost}, :none) ===
             {:error, :source_lost}
  end
end
