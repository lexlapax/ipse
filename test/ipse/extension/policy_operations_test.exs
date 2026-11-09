defmodule Ipse.Extension.PolicyOperationsTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  alias Ipse.Extension.Consent, as: C
  alias Ipse.JSON

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-policy-operations-" <> Ipse.Usage.id())
    File.mkdir_p!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    project = JSON.sha256("Synthetic policy operations")

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("artifact"),
      "source_sha256" => JSON.sha256("source"),
      "operations" => ["notes.capture"],
      "settings" => %{},
      "limits" => Map.put(C.zero(), "operations", 128),
      "period_ms" => 1000,
      "expires_at_ms" => 10_000,
      "headless" => false
    }

    root = Path.join(parent, "control")
    assert {:ok, _} = C.replace(root, project, 0, policy, 1)
    %{parent: parent, root: root, project: project, policy: policy}
  end

  defp reserve(c) do
    request = %{
      "id" => Ipse.Usage.id(),
      "operation" => "notes.capture",
      "artifact_sha256" => c.policy["artifact_sha256"],
      "source_sha256" => c.policy["source_sha256"],
      "policy_sha256" => JSON.digest([c.policy]),
      "request_sha256" => JSON.sha256("synthetic request"),
      "source_generation" => 0,
      "reserved" => Map.put(C.zero(), "operations", 1),
      "headless" => false
    }

    assert {:ok, ticket} = C.reserve(c.root, c.project, request, 1)
    ticket
  end

  defp inspect_selected(c, ids, callback),
    do: C.with_policy_operations(c.root, c.project, 1, JSON.digest([c.policy]), 1, ids, callback)

  test "selected receipt projection preserves ordinary callback shape and writes no ledger bytes",
       c do
    first = reserve(c)
    other = reserve(c)
    path = Path.join([c.root, c.project, "control.json"])
    before = File.read!(path)
    missing = Ipse.Usage.id()

    assert {:ok, :checked} =
             inspect_selected(c, [first["id"], missing], fn snapshot ->
               assert Enum.sort(Map.keys(snapshot)) === ~w(epoch operations policy)
               assert Map.keys(snapshot["operations"]) === [first["id"]]
               assert snapshot["operations"][first["id"]]["status"] === "reserved"
               refute Map.has_key?(snapshot["operations"], other["id"])
               {:ok, :checked}
             end)

    assert File.read!(path) === before

    assert {:ok, :checked} =
             C.with_policy(c.root, c.project, 1, JSON.digest([c.policy]), 1, fn snapshot ->
               assert Enum.sort(Map.keys(snapshot)) === ~w(epoch policy)
               {:ok, :checked}
             end)
  end

  test "current policy, revocation, closed IDs and finite selection are required", c do
    ticket = reserve(c)
    never = fn _ -> flunk("invalid read reached callback") end

    excess =
      Enum.map(
        0..C.operation_limit(),
        &(Integer.to_string(&1, 16) |> String.pad_leading(32, "0"))
      )

    for ids <- [
          [ticket["id"], ticket["id"]],
          ["invalid"],
          excess
        ] do
      assert {:error, _} = inspect_selected(c, ids, never)
    end

    assert {:error, _} =
             C.with_policy_operations(c.root, c.project, 2, JSON.digest([c.policy]), 1, [], never)

    assert {:error, _} =
             C.with_policy_operations(
               c.root,
               c.project,
               1,
               JSON.sha256("different policy"),
               1,
               [],
               never
             )

    assert {:error, _} =
             C.with_policy_operations(
               c.root,
               c.project,
               1,
               JSON.digest([c.policy]),
               10_000,
               [],
               never
             )

    absent = Path.join(c.parent, "absent")

    assert {:error, _} =
             C.with_policy_operations(absent, c.project, 1, JSON.digest([c.policy]), 1, [], never)

    refute File.exists?(absent)
    assert {:ok, _} = C.revoke(c.root, c.project, 1)
    assert {:error, _} = inspect_selected(c, [], never)
  end

  test "selected compacted rows preserve request identity and receipt digest without full receipt revival",
       c do
    tickets =
      for _ <- 1..65 do
        ticket = reserve(c)
        assert {:ok, _} = C.admit(c.root, c.project, ticket, 1)

        assert {:ok, _} =
                 C.settle(c.root, c.project, ticket, {:known, C.zero(), %{"refused" => true}})

        ticket
      end

    first = hd(tickets)
    last = List.last(tickets)

    assert {:ok, :checked} =
             inspect_selected(c, [first["id"], last["id"]], fn snapshot ->
               compact = snapshot["operations"][first["id"]]
               assert compact["receipt_compacted"] === true
               assert compact["receipt_sha256"] === JSON.digest([%{"refused" => true}])
               refute Map.has_key?(compact, "receipt")
               assert compact["id"] === first["id"] and compact["status"] === "settled"
               assert snapshot["operations"][last["id"]]["receipt"] === %{"refused" => true}
               {:ok, :checked}
             end)
  end

  test "a competing admission cannot change a selected reserved row while the actual read owner is held",
       c do
    ticket = reserve(c)
    parent = self()

    worker =
      spawn(fn ->
        receive do
          {:admit, observer} ->
            send(observer, {:admission_started, self()})
            result = C.admit(c.root, c.project, ticket, 1)
            send(observer, {:admission_result, self(), result})
            send(parent, {:completed_admission, self(), result})
        end
      end)

    assert {:ok, :checked} =
             inspect_selected(c, [ticket["id"]], fn snapshot ->
               send(worker, {:admit, self()})
               assert_receive {:admission_started, ^worker}, 1000
               refute_receive {:admission_result, ^worker, {:ok, _}}, 50
               assert snapshot["operations"][ticket["id"]]["status"] === "reserved"
               {:ok, :checked}
             end)

    assert_receive {:completed_admission, ^worker, result}, 5000

    case result do
      {:ok, _} -> :ok
      {:error, _} -> assert {:ok, _} = C.admit(c.root, c.project, ticket, 1)
    end

    assert {:ok, operation} = C.operation(c.root, c.project, ticket["id"])
    assert operation["status"] === "admitted"
  end
end
