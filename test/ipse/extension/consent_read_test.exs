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
end
