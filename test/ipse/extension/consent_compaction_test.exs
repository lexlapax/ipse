defmodule Ipse.Extension.ConsentCompactionTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Consent, as: C
  alias Ipse.JSON

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-consent-compact-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    project = JSON.sha256("compaction fixture project")
    root = Path.join(parent, "control")

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("artifact"),
      "source_sha256" => JSON.sha256("source"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.new(C.resources(), &{&1, 100_000}),
      "period_ms" => 1_000,
      "expires_at_ms" => 31_536_000_000,
      "headless" => true
    }

    assert {:ok, _} = C.replace(root, project, 0, policy, 1)

    %{
      root: root,
      project: project,
      policy: policy,
      control_file: Path.join([root, project, "control.json"])
    }
  end

  defp request(c, id \\ Ipse.Usage.id()) do
    %{
      "id" => id,
      "operation" => "knowledge.capture",
      "artifact_sha256" => c.policy["artifact_sha256"],
      "source_sha256" => c.policy["source_sha256"],
      "policy_sha256" => JSON.digest([c.policy]),
      "request_sha256" => JSON.sha256("request-" <> id),
      "source_generation" => 1,
      "reserved" => C.zero() |> Map.merge(%{"operations" => 1, "model_calls" => 1}),
      "headless" => true
    }
  end

  defp seed_compacted(c, count) do
    assert {:ok, state} = C.snapshot(c.root, c.project)

    compacted =
      Map.new(1..count, fn sequence ->
        id = sequence |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

        {id,
         [
           sequence,
           1,
           JSON.sha256("request-" <> id),
           1,
           "settled",
           [1, 1, 0, 0, 0, 0],
           JSON.digest([%{}])
         ]}
      end)

    state = %{state | "sequence" => count, "compacted" => compacted}
    write_fixture(c, state)
    state
  end

  defp write_fixture(c, state) do
    File.write!(c.control_file, Jason.encode!(state))
    File.chmod!(c.control_file, 0o600)
  end

  test "terminal compaction retains durable identities, charges and receipt digests", c do
    pending = request(c)
    assert {:ok, pending_ticket} = C.reserve(c.root, c.project, pending, 1)
    assert {:ok, _} = C.admit(c.root, c.project, pending_ticket, 1)
    assert {:ok, _} = C.settle(c.root, c.project, pending_ticket, :unknown)

    completed =
      for _ <- 1..70 do
        r = request(c)
        assert {:ok, ticket} = C.reserve(c.root, c.project, r, 1)

        assert {:ok, _} =
                 C.publish(c.root, c.project, ticket, 1, fn ->
                   {:ok, r["reserved"], %{"item" => r["id"]}}
                 end)

        {r, ticket}
      end

    assert {:ok, state} = C.snapshot(c.root, c.project)
    assert state["version"] == 2
    assert map_size(state["operations"]) == 65
    assert map_size(state["compacted"]) == 6
    assert state["operations"][pending["id"]]["status"] == "unknown"
    {first, ticket} = hd(completed)

    assert {:ok, %{"existing" => inspection}} =
             C.reserve(
               c.root,
               c.project,
               %{first | "request_sha256" => JSON.sha256("different")},
               2_001
             )

    assert inspection["receipt_compacted"] == true
    assert inspection["actual"] == first["reserved"]
    assert inspection["receipt_sha256"] == JSON.digest([%{"item" => first["id"]}])
    assert inspection["request_sha256"] == first["request_sha256"]
    assert {:error, :consent_admission_refused} = C.admit(c.root, c.project, ticket, 2_001)
    assert {:error, :consent_settlement_refused} = C.settle(c.root, c.project, ticket, :unknown)

    narrow = %{c.policy | "limits" => Map.new(C.resources(), &{&1, 71})}
    assert {:ok, _} = C.replace(c.root, c.project, 1, narrow, 1)
    next = %{c | policy: narrow}
    assert {:error, :consent_reservation_refused} = C.reserve(c.root, c.project, request(next), 1)
    assert {:ok, _} = C.reserve(c.root, c.project, request(next), 2_001)
  end

  @tag timeout: 120_000
  test "twenty thousand retained IDs survive policy changes and bounded future writes", c do
    seed_compacted(c, 20_000)
    assert File.stat!(c.control_file).size < 8_388_608
    assert {:ok, state} = C.snapshot(c.root, c.project)
    assert state["sequence"] == 20_000

    assert {:ok, %{"existing" => %{"receipt_compacted" => true}}} =
             C.reserve(c.root, c.project, request(c, String.pad_leading("1", 32, "0")), 2_001)

    policy = %{
      c.policy
      | "period_ms" => 31_536_000_000,
        "limits" => Map.new(C.resources(), &{&1, 20_000})
    }

    assert {:ok, _} = C.replace(c.root, c.project, 1, policy, 2_001)
    changed = %{c | policy: policy}

    assert {:error, :consent_reservation_refused} =
             C.reserve(c.root, c.project, request(changed), 2_001)

    assert {:ok, _} = C.revoke(c.root, c.project, 2)
    policy = %{policy | "limits" => Map.new(C.resources(), &{&1, 20_001})}
    assert {:ok, _} = C.replace(c.root, c.project, 3, policy, 2_001)
    changed = %{c | policy: policy}
    r = request(changed)
    assert {:ok, ticket} = C.reserve(c.root, c.project, r, 2_001)
    assert {:ok, _} = C.settle(c.root, c.project, ticket, :unstarted)
    assert {:ok, state} = C.snapshot(c.root, c.project)
    assert state["sequence"] == 20_001
    assert map_size(state["compacted"]) == 20_000
    assert File.stat!(c.control_file).size < 8_388_608
  end

  test "malformed compact rows, duplicate sequences and namespace collisions refuse", c do
    state = seed_compacted(c, 2)
    [id, other] = Enum.sort(Map.keys(state["compacted"]))
    row = state["compacted"][id]

    for bad_row <- [
          List.replace_at(row, 0, 2),
          List.replace_at(row, 1, 1.0),
          List.replace_at(row, 4, "unknown"),
          List.replace_at(row, 5, [1]),
          List.replace_at(row, 5, [1, -1, 0, 0, 0, 0]),
          List.replace_at(row, 6, "invalid"),
          row ++ ["extra"]
        ] do
      write_fixture(c, put_in(state, ["compacted", id], bad_row))
      assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
    end

    write_fixture(
      c,
      put_in(state, ["compacted", id], List.replace_at(row, 0, hd(state["compacted"][other])))
    )

    assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
    write_fixture(c, Map.put(state, "version", 1))
    assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
  end

  test "closed v1 ledgers remain readable and upgrade only on a successful mutation", c do
    assert {:ok, state} = C.snapshot(c.root, c.project)
    legacy = state |> Map.delete("compacted") |> Map.put("version", 1)
    write_fixture(c, legacy)
    original = File.read!(c.control_file)
    assert {:ok, %{"version" => 2, "compacted" => %{}}} = C.snapshot(c.root, c.project)
    assert File.read!(c.control_file) == original
    assert {:ok, _} = C.revoke(c.root, c.project, 1)
    assert Jason.decode!(File.read!(c.control_file))["version"] == 2
    write_fixture(c, Map.put(legacy, "unexpected", true))
    assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
  end

  @tag timeout: 120_000
  test "lifetime capacity refuses visibly while retained duplicate IDs stay inspectable", c do
    seed_compacted(c, 32_768)
    assert {:error, :consent_capacity} = C.reserve(c.root, c.project, request(c), 2_001)

    assert {:ok, %{"existing" => %{"sequence" => 1}}} =
             C.reserve(c.root, c.project, request(c, String.pad_leading("1", 32, "0")), 2_001)
  end

  @tag timeout: 180_000
  test "large recent receipts leave revocation and pending settlement writable", c do
    seed_compacted(c, 25_000)
    request = request(c)
    assert {:ok, outstanding} = C.reserve(c.root, c.project, request, 2_001)
    assert {:ok, _} = C.admit(c.root, c.project, outstanding, 2_001)
    receipt = %{"payload" => String.duplicate("x", 8_178)}
    assert byte_size(Jason.encode!(receipt)) == 8_192

    for _ <- 1..65 do
      next = request(c)
      assert {:ok, ticket} = C.reserve(c.root, c.project, next, 2_001)

      assert {:ok, _} =
               C.publish(c.root, c.project, ticket, 2_001, fn ->
                 {:ok, next["reserved"], receipt}
               end)
    end

    assert {:ok, _} = C.revoke(c.root, c.project, 1)
    assert {:ok, _} = C.settle(c.root, c.project, outstanding, :unknown)
    assert {:ok, _} = C.settle(c.root, c.project, outstanding, {:reconciled, request["reserved"]})
    assert {:ok, state} = C.snapshot(c.root, c.project)
    assert state["policy"] == nil
    assert map_size(state["compacted"]) == 25_002
    assert map_size(state["operations"]) == 64
    assert File.stat!(c.control_file).size < 6 * 1024 * 1024
  end

  test "capacity refusal precedes the publication callback and retains unresolved overrun", c do
    original = request(c)
    assert {:ok, ticket} = C.reserve(c.root, c.project, original, 1)
    assert {:ok, _} = C.admit(c.root, c.project, ticket, 1)
    overrun = Map.put(original["reserved"], "model_calls", 2)

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.settle(c.root, c.project, ticket, {:known, overrun})

    assert {:error, :consent_reservation_refused} = C.reserve(c.root, c.project, request(c), 1)
    parent = self()

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, ticket, 1, fn ->
               send(parent, :unexpected_publication)
               {:ok, C.zero(), %{}}
             end)

    refute_received :unexpected_publication
    assert {:ok, _} = C.revoke(c.root, c.project, 1)
    assert {:ok, state} = C.snapshot(c.root, c.project)
    assert state["operations"][original["id"]]["actual"] == overrun
    assert state["operations"][original["id"]]["status"] == "overrun"
    assert state["compacted"] == %{}
  end

  @tag timeout: 180_000
  test "boundary overrun and policy changes consume their reserved maintenance space", c do
    count = 27_690
    compact = seed_compacted(c, count)
    requests = Enum.map(1..3, fn _ -> request(c) end)

    build = fn policy ->
      operations =
        requests
        |> Enum.with_index(count + 1)
        |> Map.new(fn {request, sequence} ->
          request = Map.put(request, "policy_sha256", JSON.digest([policy]))

          {request["id"],
           Map.merge(request, %{
             "sequence" => sequence,
             "epoch" => 1,
             "created_at_ms" => 1,
             "status" => "reserved",
             "actual" => nil,
             "receipt" => nil
           })}
        end)

      %{compact | "sequence" => count + 3, "operations" => operations, "policy" => policy}
    end

    # This is the independently reproduced boundary of the former additive
    # margin. It admitted a reservation but could not persist its later overrun.
    before = build.(c.policy)
    limit = 6 * 1024 * 1024 - 65_536
    previous_required = byte_size(Jason.encode!(before)) - 12 + 64 * 8192 + 3 * 256 + 32_768
    slack = limit - previous_required
    assert slack in 8..16_380
    policy = %{c.policy | "settings" => %{"pad" => String.duplicate("x", slack - 8)}}
    state = build.(policy)
    [first, measured, later] = Enum.map(requests, &state["operations"][&1["id"]])

    seed = %{
      state
      | "sequence" => count + 2,
        "operations" => Map.delete(state["operations"], later["id"])
    }

    write_fixture(c, seed)

    ticket = fn operation ->
      operation
      |> Map.take(~w(id sequence epoch request_sha256))
      |> Map.put("project", c.project)
    end

    assert {:ok, later_ticket} =
             C.reserve(c.root, c.project, request(%{c | policy: policy}, later["id"]), 1)

    assert {:ok, _} = C.admit(c.root, c.project, ticket.(measured), 1)
    actual = Map.new(C.resources(), &{&1, 9_007_199_254_740_991})

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.settle(c.root, c.project, ticket.(measured), {:known, actual})

    assert {:ok, after_overrun} = C.snapshot(c.root, c.project)
    assert after_overrun["operations"][measured["id"]]["status"] == "overrun"
    assert after_overrun["operations"][measured["id"]]["actual"] == actual
    assert {:error, :consent_admission_refused} = C.admit(c.root, c.project, later_ticket, 1)
    assert {:ok, _} = C.revoke(c.root, c.project, 1)
    maximum = %{policy | "settings" => %{"pad" => String.duplicate("x", 16_374)}}
    assert byte_size(Jason.encode!(maximum["settings"])) == 16_384
    assert {:ok, _} = C.replace(c.root, c.project, 2, maximum, 1)
    assert {:ok, _} = C.settle(c.root, c.project, ticket.(first), :unstarted)
  end
end
