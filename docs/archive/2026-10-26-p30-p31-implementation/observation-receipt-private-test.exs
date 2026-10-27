defmodule Ipse.Session.ObservationReceiptDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Session.{ManagedReference, ObservationReceipt}

  setup do
    dir = Path.join(System.tmp_dir!(), "ipse-observation-receipt-" <> Usage.id())
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{root: Path.join(dir, "collections"), namespace: JSON.sha256("synthetic-namespace")}
  end

  defp intent(namespace, request) do
    identity = %{"instance" => "synthetic"}

    pin = %{
      "version" => 1,
      "session_id" => Usage.id(),
      "project_id" => JSON.sha256("project"),
      "worktree_id" => JSON.sha256("worktree"),
      "binding_sha256" => JSON.sha256("binding"),
      "epoch" => 1,
      "policy_sha256" => JSON.sha256("policy"),
      "identity_sha256" => JSON.digest([identity]),
      "namespace" => namespace,
      "routes_sha256" => JSON.sha256("routes"),
      "source_sha256" => JSON.sha256("source")
    }

    binding = %{
      "kind" => "collection",
      "version" => 1,
      "namespace" => namespace,
      "pin" => pin,
      "inner_op" => request["op"],
      "request_sha256" => JSON.digest([request])
    }

    {%{
       "type" => "extension_action_intent",
       "version" => 2,
       "parent_invocation_id" => Usage.id(),
       "operation_id" => Usage.id(),
       "step" => 1,
       "identity_sha256" => JSON.digest([identity]),
       "namespace" => namespace,
       "context_sha256" => nil,
       "service" => nil,
       "request" => %{"op" => "collection.call", "request" => request},
       "request_sha256" => JSON.digest([%{"op" => "collection.call", "request" => request}]),
       "approval" => "not_required",
       "effect_binding" => binding
     }, identity}
  end

  defp put(c, generation, key, text) do
    Collection.execute(
      c.root,
      c.namespace,
      %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => false,
        "changes" => [%{"key" => key, "expected_revision" => 0, "value" => %{"text" => text}}]
      },
      Usage.id()
    )
  end

  test "absent root observation binds exact host request, outcome and pin", c do
    request = %{"op" => "get", "key" => "note.absent"}
    {intent, identity} = intent(c.namespace, request)
    assert {:ok, observation} = ObservedRead.read(c.root, c.namespace, request)
    assert {:ok, result} = ObservationReceipt.prepare(intent, identity, observation)
    assert result.value == observation["value"]
    assert ManagedReference.dependency?(result.dependency)
    assert result.dependency["collection"]["root_state"] == "absent"
    assert result.dependency["subject"]["result_sha256"] == JSON.digest([result.value])

    assert {:ok, action} =
             Ipse.Extension.Actions.result(intent, %{"status" => "ok", "value" => result.value})

    assert {:ok, receipt} = ObservationReceipt.bind(intent, identity, observation, action)
    assert receipt["action_sha256"] == JSON.digest([action])
    assert :ok = ObservationReceipt.verify(action, receipt)

    for bad <- [
          Map.delete(receipt, "dependency"),
          Map.put(receipt, "operation_id", Usage.id()),
          put_in(receipt, ["dependency", "subject", "result_sha256"], JSON.sha256("other")),
          Map.put(receipt, "extra", true)
        ] do
      assert {:error, :observation_receipt_refused} = ObservationReceipt.verify(action, bad)
    end

    # A syntactically valid substituted digest is not authenticated by this
    # pure replay check; journal provenance and same-view ownership are required.
    assert :ok =
             ObservationReceipt.verify(
               action,
               Map.put(receipt, "observation_sha256", JSON.sha256("invented"))
             )

    assert {:error, _} =
             ObservationReceipt.bind(
               intent,
               identity,
               observation,
               put_in(action, ["outcome", "value", "record"], %{})
             )

    for altered <- [
          Map.put(observation, "extra", true),
          put_in(observation, ["value", "generation"], 1),
          put_in(observation, ["witness", "root_state"], "present"),
          Map.put(observation, "request_sha256", JSON.sha256("other"))
        ] do
      assert {:error, :observation_receipt_refused} =
               ObservationReceipt.prepare(intent, identity, altered)
    end

    assert {:error, _} = ObservationReceipt.prepare(intent, %{"instance" => "other"}, observation)
  end

  test "scan binds exact host-shortened continuation, not merely the original full page", c do
    for n <- 0..3, do: assert({:ok, _} = put(c, n, "note.#{n}", String.duplicate("x", 5000)))
    request = %{"op" => "scan", "after" => nil, "generation" => 4, "limit" => 4}
    {intent, identity} = intent(c.namespace, request)
    assert {:ok, observation} = ObservedRead.read(c.root, c.namespace, request)
    assert length(observation["value"]["records"]) == 4
    assert {:ok, result} = ObservationReceipt.prepare(intent, identity, observation)
    assert length(result.value["records"]) in 1..3
    assert result.value["next"] == List.last(result.value["records"])["key"]
    refute result.dependency["subject"]["result_sha256"] == observation["result_sha256"]
    assert result.dependency["subject"]["result_sha256"] == JSON.digest([result.value])
    assert result.observation_sha256 == JSON.digest([observation])
    assert ManagedReference.dependency?(result.dependency)

    assert {:error, _} =
             ObservationReceipt.prepare(
               put_in(intent, ["effect_binding", "pin", "namespace"], JSON.sha256("other")),
               identity,
               observation
             )
  end
end
