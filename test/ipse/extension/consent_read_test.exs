defmodule Ipse.Extension.ConsentReadTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Consent, as: C
  alias Ipse.JSON

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-consent-read-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "control")
    project = JSON.sha256("bounded read fixture")

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("artifact"),
      "source_sha256" => JSON.sha256("sources"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.new(C.resources(), &{&1, 5}),
      "period_ms" => 1_000,
      "expires_at_ms" => 10_000,
      "headless" => true
    }

    assert {:ok, _} = C.replace(root, project, 0, policy, 1)

    %{
      root: root,
      project: project,
      policy: policy,
      hash: JSON.digest([policy]),
      control_file: Path.join([root, project, "control.json"])
    }
  end

  test "local reads check the exact policy without allocating durable operation identities", c do
    before = File.read!(c.control_file)

    for _ <- 1..40 do
      assert {:ok, %{"source" => "bounded data"}} =
               C.with_policy(c.root, c.project, 1, c.hash, 1, fn snapshot ->
                 assert snapshot == %{"epoch" => 1, "policy" => c.policy}
                 {:ok, %{"source" => "bounded data"}}
               end)
    end

    assert File.read!(c.control_file) == before

    assert {:ok, %{"sequence" => 0, "operations" => %{}, "compacted" => %{}}} =
             C.snapshot(c.root, c.project)
  end

  test "stale, malformed, revoked and expired pins cannot enter a read callback", c do
    parent = self()

    callback = fn _ ->
      send(parent, :unexpected_read)
      {:ok, "data"}
    end

    for {epoch, hash, now} <- [
          {0, c.hash, 1},
          {1.0, c.hash, 1},
          {1, JSON.sha256("different"), 1},
          {1, c.hash, 10_000},
          {1, c.hash, 1.0}
        ] do
      assert {:error, :consent_read_refused} =
               C.with_policy(c.root, c.project, epoch, hash, now, callback)
    end

    assert {:ok, _} = C.revoke(c.root, c.project, 1)

    assert {:error, :consent_read_refused} =
             C.with_policy(c.root, c.project, 1, c.hash, 1, callback)

    refute_received :unexpected_read
  end

  test "unreconciled measured overrun blocks consumer reads while inspection remains available",
       c do
    request = %{
      "id" => Ipse.Usage.id(),
      "operation" => "knowledge.capture",
      "artifact_sha256" => c.policy["artifact_sha256"],
      "source_sha256" => c.policy["source_sha256"],
      "policy_sha256" => c.hash,
      "request_sha256" => JSON.sha256("request"),
      "source_generation" => 1,
      "reserved" => Map.put(C.zero(), "operations", 1),
      "headless" => true
    }

    assert {:ok, ticket} = C.reserve(c.root, c.project, request, 1)
    assert {:ok, _} = C.admit(c.root, c.project, ticket, 1)

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.settle(c.root, c.project, ticket, {:known, Map.put(C.zero(), "operations", 2)})

    parent = self()

    assert {:error, :consent_read_refused} =
             C.with_policy(c.root, c.project, 1, c.hash, 1, fn _ ->
               send(parent, :unexpected_read)
               {:ok, "data"}
             end)

    refute_received :unexpected_read
    assert {:ok, %{"policy" => policy}} = C.snapshot(c.root, c.project)
    assert policy == c.policy
  end

  test "callback failures discard data and nested control entry refuses without changing policy",
       c do
    before = File.read!(c.control_file)

    assert {:error, :no_source} =
             C.with_policy(c.root, c.project, 1, c.hash, 1, fn _ -> {:error, :no_source} end)

    assert {:error, :consent_read_refused} =
             C.with_policy(c.root, c.project, 1, c.hash, 1, fn _ -> "untyped data" end)

    assert {:error, :consent_unavailable} =
             C.with_policy(c.root, c.project, 1, c.hash, 1, fn _ ->
               C.revoke(c.root, c.project, 1)
             end)

    assert File.read!(c.control_file) == before
  end

  test "budget observation is existing-only, metadata-only and consumes no ledger identity", c do
    before = File.read!(c.control_file)
    inode = File.stat!(c.control_file).inode

    for _ <- 1..3 do
      assert {:ok, summary} =
               C.with_existing_policy_budget(c.root, c.project, 1, c.hash, 1, &{:ok, &1})

      assert C.valid_budget_summary?(summary)
      assert summary["charged"] == C.zero()
      assert summary["limits"] == c.policy["limits"]
      refute Map.has_key?(summary, "policy")
      refute Map.has_key?(summary, "operations")
    end

    assert File.read!(c.control_file) == before
    assert File.stat!(c.control_file).inode == inode
    missing = Path.join(Path.dirname(c.root), "not-created")

    assert {:error, _} =
             C.with_existing_policy_budget(missing, c.project, 1, c.hash, 1, fn _ ->
               flunk("absent policy")
             end)

    refute File.exists?(missing)
  end

  test "budget callbacks refuse foreign, stale, revoked and expired current policies", c do
    callback = fn _ ->
      send(self(), :unexpected_budget)
      {:ok, %{}}
    end

    for {project, epoch, sha, now} <- [
          {JSON.sha256("foreign"), 1, c.hash, 1},
          {c.project, 2, c.hash, 1},
          {c.project, 1, JSON.sha256("changed"), 1},
          {c.project, 1, c.hash, 10_000}
        ] do
      assert {:error, _} =
               C.with_existing_policy_budget(c.root, project, epoch, sha, now, callback)
    end

    assert {:ok, summary} =
             C.with_existing_policy_budget(c.root, c.project, 1, c.hash, 1, &{:ok, &1})

    assert {:ok, _} = C.revoke(c.root, c.project, 1)
    assert {:error, _} = C.with_existing_policy_budget(c.root, c.project, 1, c.hash, 1, callback)
    refute_received :unexpected_budget
    # A structurally valid historical snapshot supplies no new policy/admission authority.
    assert C.valid_budget_summary?(summary)
    assert {:error, _} = C.reserve(c.root, c.project, budget_request(c), 1)
  end

  test "an actual unknown reservation stays charged in the next observed period", c do
    for _ <- 1..2 do
      request = budget_request(c)
      assert {:ok, ticket} = C.reserve(c.root, c.project, request, 1)
      assert {:ok, _} = C.admit(c.root, c.project, ticket, 1)
      assert {:ok, %{"status" => "unknown"}} = C.settle(c.root, c.project, ticket, :unknown)
    end

    assert {:ok, unknown} = C.existing_snapshot(c.root, c.project)
    assert unknown["sequence"] == 2 and map_size(unknown["operations"]) == 2

    assert Enum.all?(unknown["operations"], fn {_, row} ->
             row["status"] == "unknown" and row["reserved"]["operations"] == 1
           end)

    before = File.read!(c.control_file)

    assert {:ok, summary} =
             C.with_existing_policy_budget(c.root, c.project, 1, c.hash, 1001, &{:ok, &1})

    assert summary["charged"]["operations"] == 2
    assert summary["nonterminal_reserved"]["operations"] == 2
    assert summary["unknown_reserved"]["operations"] == 2
    assert File.read!(c.control_file) == before
  end

  test "observed 80 and 100 accounting boundaries never replace the final atomic reservation",
       c do
    policy = %{c.policy | "limits" => Map.put(C.zero(), "operations", 100)}
    assert {:ok, _} = C.replace(c.root, c.project, 1, policy, 1)
    c = %{c | policy: policy, hash: JSON.digest([policy])}

    for _ <- 1..80 do
      request = budget_request(c)
      assert {:ok, ticket} = C.reserve(c.root, c.project, request, 1)
      assert {:ok, _} = C.admit(c.root, c.project, ticket, 1)
      assert {:ok, _} = C.settle(c.root, c.project, ticket, {:known, request["reserved"]})
    end

    assert {:ok, settled} = C.existing_snapshot(c.root, c.project)
    assert settled["sequence"] == 80
    assert map_size(settled["operations"]) + map_size(settled["compacted"]) == 80

    assert {:ok, summary} =
             C.with_existing_policy_budget(c.root, c.project, 2, c.hash, 1, &{:ok, &1})

    assert summary["warning_dimensions"] == ["operations"]
    assert summary["available"]["operations"] == 20

    for _ <- 1..20 do
      assert {:ok, _} = C.reserve(c.root, c.project, budget_request(c), 1)
    end

    assert {:ok, all} = C.existing_snapshot(c.root, c.project)
    assert all["sequence"] == 100
    assert map_size(all["operations"]) + map_size(all["compacted"]) == 100
    assert Enum.count(all["operations"], fn {_, row} -> row["status"] == "reserved" end) == 20

    assert {:ok, full} =
             C.with_existing_policy_budget(c.root, c.project, 2, c.hash, 1, &{:ok, &1})

    assert full["exhausted_dimensions"] == ["operations"]
    before_refusal = File.read!(c.control_file)

    assert {:error, :consent_reservation_refused} =
             C.reserve(c.root, c.project, budget_request(c), 1)

    assert File.read!(c.control_file) == before_refusal
    assert summary["available"]["operations"] == 20
  end

  defp budget_request(c) do
    id = Ipse.Usage.id()

    %{
      "id" => id,
      "operation" => "knowledge.capture",
      "artifact_sha256" => c.policy["artifact_sha256"],
      "source_sha256" => c.policy["source_sha256"],
      "policy_sha256" => c.hash,
      "request_sha256" => JSON.digest(["budget request", id]),
      "source_generation" => 1,
      "reserved" => Map.put(C.zero(), "operations", 1),
      "headless" => true
    }
  end
end
