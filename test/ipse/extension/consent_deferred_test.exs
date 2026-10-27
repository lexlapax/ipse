defmodule Ipse.Extension.ConsentDeferredTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Consent, as: C

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-consent-deferred-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    project = Ipse.JSON.sha256("deferred project")
    root = Path.join(parent, "control")
    reserved = C.zero() |> Map.merge(%{"operations" => 1, "input_bytes" => 64})

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => Ipse.JSON.sha256("artifact"),
      "source_sha256" => Ipse.JSON.sha256("source"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => reserved,
      "period_ms" => 1_000,
      "expires_at_ms" => 10_000,
      "headless" => true
    }

    c = %{parent: parent, root: root, project: project, policy: policy, reserved: reserved}
    assert {:ok, _} = C.replace(root, project, 0, policy, 1)
    c
  end

  defp request(c) do
    %{
      "id" => Ipse.Usage.id(),
      "operation" => "knowledge.capture",
      "artifact_sha256" => c.policy["artifact_sha256"],
      "source_sha256" => c.policy["source_sha256"],
      "policy_sha256" => Ipse.JSON.digest([c.policy]),
      "request_sha256" => Ipse.JSON.sha256("deferred request"),
      "source_generation" => 1,
      "reserved" => c.reserved,
      "headless" => true
    }
  end

  defp ticket(c) do
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)
    assert {:ok, ^t} = C.admit(c.root, c.project, t, 1)
    t
  end

  defp operation(c, t) do
    assert {:ok, s} = C.snapshot(c.root, c.project)
    s["operations"][t["id"]]
  end

  defp assert_pending(c, t, status \\ "publishing") do
    r = operation(c, t)
    assert r["status"] == status
    assert r["reserved"] == c.reserved
    assert r["actual"] == nil
    assert r["receipt"] == nil
  end

  test "provisional publication retains full liability until exact receipt settlement", c do
    t = ticket(c)
    actual = %{c.reserved | "operations" => 0, "input_bytes" => 7}
    receipt = %{"request_sha256" => Ipse.JSON.sha256("normalized"), "generation" => 1}

    assert {:ok, packet} =
             C.publish_deferred(c.root, c.project, t, 1, fn -> {:ok, actual, receipt} end)

    assert packet == %{"version" => 1, "ticket" => t, "actual" => actual, "receipt" => receipt}
    assert_pending(c, t)
    assert {:error, :consent_reservation_refused} = C.reserve(c.root, c.project, request(c), 1)

    assert {:ok, %{"status" => "settled", "receipt" => ^receipt}} =
             C.settle(c.root, c.project, t, {:known, packet["actual"], packet["receipt"]})

    assert operation(c, t)["actual"] == actual
    assert operation(c, t)["receipt"] == receipt
    next = put_in(request(c), ["reserved", "input_bytes"], 57)
    assert {:ok, _} = C.reserve(c.root, c.project, next, 1)

    assert {:error, :consent_settlement_refused} =
             C.settle(c.root, c.project, t, {:known, actual, receipt})
  end

  test "finalizing already admitted work requires no fresh policy grant", c do
    t = ticket(c)

    assert {:ok, packet} =
             C.publish_deferred(c.root, c.project, t, 1, fn ->
               {:ok, C.zero(), %{"done" => true}}
             end)

    assert {:ok, _} = C.revoke(c.root, c.project, 1)

    assert {:ok, %{"receipt" => %{"done" => true}}} =
             C.settle(c.root, c.project, t, {:known, packet["actual"], packet["receipt"]})
  end

  test "reserved publication compatibility does not permit replay or an unstarted refund", c do
    assert {:ok, t} = C.reserve(c.root, c.project, request(c), 1)

    assert {:ok, _} =
             C.publish_deferred(c.root, c.project, t, 1, fn -> {:ok, C.zero(), %{}} end)

    assert_pending(c, t)

    assert {:error, :consent_publication_refused} =
             C.publish_deferred(c.root, c.project, t, 1, fn -> flunk("replayed") end)

    assert {:error, :consent_settlement_refused} = C.settle(c.root, c.project, t, :unstarted)
    assert {:ok, _} = C.settle(c.root, c.project, t, :unknown)
    assert_pending(c, t, "unknown")

    assert {:error, :consent_settlement_refused} =
             C.settle(c.root, c.project, t, {:known, C.zero(), %{}})
  end

  test "receipt settlement retains finish validation and measured overrun quarantine", c do
    t = ticket(c)

    assert {:ok, _} =
             C.publish_deferred(c.root, c.project, t, 1, fn -> {:ok, C.zero(), %{}} end)

    assert {:unknown, :consent_receipt_invalid} =
             C.settle(
               c.root,
               c.project,
               t,
               {:known, C.zero(), %{"large" => String.duplicate("x", 8_192)}}
             )

    assert_pending(c, t)

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.settle(c.root, c.project, t, {:known, %{c.reserved | "input_bytes" => 0.0}, %{}})

    assert_pending(c, t)
    overrun = %{c.reserved | "input_bytes" => 65}

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.settle(c.root, c.project, t, {:known, overrun, %{}})

    assert operation(c, t)["status"] == "overrun"
    assert operation(c, t)["actual"] == overrun

    assert {:error, :consent_reservation_refused} =
             C.reserve(c.root, c.project, request(c), 2_000)
  end

  test "known receipt settlement supports admitted work but refuses reserved and wrong tickets",
       c do
    t = ticket(c)

    assert {:error, :consent_settlement_refused} =
             C.settle(
               c.root,
               c.project,
               %{t | "sequence" => t["sequence"] + 1},
               {:known, C.zero(), %{}}
             )

    assert {:ok, _} = C.settle(c.root, c.project, t, {:known, C.zero(), %{"direct" => true}})
    assert {:ok, reserved} = C.reserve(c.root, c.project, request(c), 1)

    assert {:error, :consent_settlement_refused} =
             C.settle(c.root, c.project, reserved, {:known, C.zero(), %{}})

    assert {:ok, _} = C.settle(c.root, c.project, reserved, :unstarted)
  end

  test "expiry, revocation and forged tickets never enter the callback", c do
    t = ticket(c)
    callback = fn -> flunk("refused callback entered") end

    assert {:error, :consent_publication_refused} =
             C.publish_deferred(c.root, c.project, t, 10_000, callback)

    assert {:error, :consent_publication_refused} =
             C.publish_deferred(c.root, c.project, %{t | "epoch" => 1.0}, 1, callback)

    assert {:ok, _} = C.revoke(c.root, c.project, 1)

    assert {:error, :consent_publication_refused} =
             C.publish_deferred(c.root, c.project, t, 2, callback)

    assert_pending(c, t, "admitted")
  end

  test "malformed actual vectors leave full publishing liability", c do
    for actual <- [
          nil,
          %{},
          %{c.reserved | "operations" => 0.0},
          %{c.reserved | "input_bytes" => -1}
        ] do
      t = ticket(c)

      assert {:unknown, :consent_settlement_exceeds_reservation} =
               C.publish_deferred(c.root, c.project, t, 1, fn -> {:ok, actual, %{}} end)

      assert_pending(c, t)
      assert {:ok, _} = C.settle(c.root, c.project, t, :unknown)

      assert {:error, :consent_settlement_refused} =
               C.settle(c.root, c.project, t, {:known, C.zero(), %{}})

      assert {:ok, _} = C.settle(c.root, c.project, t, {:reconciled, C.zero()})
    end
  end

  test "bad and oversized receipts cannot release the reservation", c do
    for receipt <- [nil, %{"too_large" => String.duplicate("x", 8_192)}] do
      t = ticket(c)

      assert {:unknown, :consent_receipt_invalid} =
               C.publish_deferred(c.root, c.project, t, 1, fn -> {:ok, C.zero(), receipt} end)

      assert_pending(c, t)
      assert {:ok, _} = C.settle(c.root, c.project, t, {:known, C.zero(), %{}})
    end
  end

  test "overrun remains durably measured and quarantines new work", c do
    t = ticket(c)
    actual = %{c.reserved | "input_bytes" => 65}

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.publish_deferred(c.root, c.project, t, 1, fn -> {:ok, actual, %{}} end)

    r = operation(c, t)
    assert r["status"] == "overrun"
    assert r["actual"] == actual
    assert r["receipt"] == nil

    assert {:error, :consent_reservation_refused} =
             C.reserve(c.root, c.project, request(c), 2_000)
  end

  test "callback errors, exceptions and repeats never imply unstarted or replay", c do
    for result <- [:raised, {:error, :storage_failed}, :unexpected] do
      t = ticket(c)

      assert {:unknown, :publication_unconfirmed} =
               C.publish_deferred(c.root, c.project, t, 1, fn ->
                 if result == :raised, do: raise("lost receipt"), else: result
               end)

      assert_pending(c, t)

      assert {:error, :consent_publication_refused} =
               C.publish_deferred(c.root, c.project, t, 1, fn -> flunk("replayed") end)

      assert {:error, :consent_settlement_refused} = C.settle(c.root, c.project, t, :unstarted)
      assert {:ok, _} = C.settle(c.root, c.project, t, :unknown)
      assert {:ok, _} = C.settle(c.root, c.project, t, {:reconciled, C.zero()})
    end
  end

  test "actual native owner loss withholds even a valid provisional packet", c do
    t = ticket(c)

    assert {:unknown, _} =
             C.publish_deferred(c.root, c.project, t, 1, fn ->
               cap = Process.get({C, :lock_held})
               Port.close(cap.port)
               {:ok, C.zero(), %{"done" => true}}
             end)

    assert_pending(c, t)

    assert {:error, :consent_publication_refused} =
             C.publish_deferred(c.root, c.project, t, 1, fn -> flunk("replayed") end)
  end

  test "original caller death stops the native owner and retains publishing", c do
    t = ticket(c)
    observer = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        C.publish_deferred(c.root, c.project, t, 1, fn ->
          cap = Process.get({C, :lock_held})
          send(observer, {:callback, self(), cap.controller})

          receive do
            :finish -> {:ok, C.zero(), %{}}
          after
            5_000 -> raise "callback timeout"
          end
        end)
      end)

    assert_receive {:callback, worker, controller}, 5_000
    controller_monitor = Process.monitor(controller)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 5_000
    assert_receive {:DOWN, ^controller_monitor, :process, ^controller, _}, 5_000
    send(worker, :finish)
    assert_pending(c, t)
  end
end
