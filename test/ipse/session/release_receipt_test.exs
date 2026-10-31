defmodule Ipse.Session.ReleaseReceiptTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session.ReleaseReceipt}

  setup do
    session = String.duplicate("a", 32)
    epoch = String.duplicate("b", 32)

    origin = %{
      "version" => 1,
      "session_id" => session,
      "directory" => "/tmp/ipse-receipt-fixture",
      "major_device" => 5,
      "minor_device" => 0,
      "inode" => 42,
      "uid" => 1000
    }

    helper = String.duplicate("c", 64)
    {:ok, owner_marker} = ReleaseReceipt.owner_started(session)
    owner = owner_marker["owner_id"]

    closure = %{
      "type" => "lifecycle_epoch_closed",
      "version" => 1,
      "session_id" => session,
      "epoch_id" => epoch,
      "closure" => "close",
      "cleanup_confirmed" => false
    }

    {:ok, intent, private} =
      ReleaseReceipt.prepare(
        session,
        owner,
        epoch,
        closure,
        origin,
        %{device: 5, inode: 7},
        helper
      )

    header = %{
      "type" => "session",
      "metadata" => %{"source_origin_layout" => "journal_origin_v1", "source_origin" => origin}
    }

    started = %{
      "type" => "lifecycle_epoch_started",
      "version" => 1,
      "session_id" => session,
      "epoch_id" => epoch,
      "mode" => "fresh",
      "previous_epoch_id" => nil,
      "previous_state" => "none"
    }

    %{
      session: session,
      owner: owner,
      owner_marker: owner_marker,
      epoch: epoch,
      origin: origin,
      closure: closure,
      intent: intent,
      private: private,
      header: header,
      started: started
    }
  end

  test "valid receipt binds the full intent and missing remains unknown", c do
    assert {:ok, bytes} = ReleaseReceipt.seal(c.intent, c.private)
    assert :ok = ReleaseReceipt.verify(c.intent, bytes)
    assert :signed_release_claim == ReleaseReceipt.classify(c.intent, bytes)
    assert :unknown == ReleaseReceipt.classify(c.intent, nil)
    refute Map.has_key?(c.intent, "private_key")

    refute String.contains?(
             Jason.encode!(c.intent),
             Base.url_encode64(c.private.bytes, padding: false)
           )

    refute String.contains?(bytes, Base.url_encode64(c.private.bytes, padding: false))
    assert inspect(c.private) == "#Session.ReleaseReceipt.SigningKey<private>"

    assert {:ok, [c.intent]} ==
             ReleaseReceipt.intents(
               [c.header, c.owner_marker, c.started, c.closure, c.intent],
               c.session
             )
  end

  test "tampering, replay and signatures from the wrong domain refuse", c do
    {:ok, bytes} = ReleaseReceipt.seal(c.intent, c.private)
    receipt = Jason.decode!(bytes)
    forged = put_in(receipt, ["body", "native_outcome"], "unconfirmed") |> Jason.encode!()
    assert :unknown == ReleaseReceipt.classify(c.intent, forged)

    for {field, value} <- [
          {"operation_id", String.duplicate("d", 32)},
          {"owner_id", String.duplicate("d", 32)},
          {"origin_sha256", String.duplicate("d", 64)},
          {"helper_sha256", String.duplicate("e", 64)},
          {"lock_inode", 8},
          {"session_id", String.duplicate("e", 32)}
        ] do
      assert {:error, :invalid_release_receipt} =
               ReleaseReceipt.verify(Map.put(c.intent, field, value), bytes)
    end

    wrong_domain =
      :crypto.sign(:eddsa, :none, JSON.digest([c.intent, receipt["body"]]), [
        c.private.bytes,
        :ed25519
      ])

    wrong =
      Map.put(receipt, "signature", Base.url_encode64(wrong_domain, padding: false))
      |> Jason.encode!()

    assert {:error, :invalid_release_receipt} = ReleaseReceipt.verify(c.intent, wrong)

    {:ok, other_intent, other_private} =
      ReleaseReceipt.prepare(
        c.session,
        c.owner,
        c.epoch,
        c.closure,
        c.origin,
        %{device: 5, inode: 7},
        String.duplicate("c", 64)
      )

    assert {:error, :invalid_release_receipt} = ReleaseReceipt.seal(c.intent, other_private)
    assert {:error, :invalid_release_receipt} = ReleaseReceipt.verify(other_intent, bytes)
    duplicate_body = "{\"body\":{}," <> binary_part(bytes, 1, byte_size(bytes) - 1)
    assert {:error, :invalid_release_receipt} = ReleaseReceipt.verify(c.intent, duplicate_body)
    assert :unknown == ReleaseReceipt.classify(c.intent, ~s({"body":{},"signature":"bad"}))

    random_signature =
      Map.put(
        receipt,
        "signature",
        Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false)
      )
      |> Jason.encode!()

    assert :unknown == ReleaseReceipt.classify(c.intent, random_signature)
    assert :unknown == ReleaseReceipt.classify(c.intent, bytes <> "extra")
  end

  test "intent must follow its exact closure and original source, once", c do
    assert {:error, _} =
             ReleaseReceipt.intents(
               [c.header, c.owner_marker, c.started, c.intent, c.closure],
               c.session
             )

    assert {:error, _} =
             ReleaseReceipt.intents(
               [c.header, c.owner_marker, c.started, c.closure, c.intent, c.intent],
               c.session
             )

    other_origin = put_in(c.header, ["metadata", "source_origin", "inode"], 99)

    assert {:error, _} =
             ReleaseReceipt.intents(
               [other_origin, c.owner_marker, c.started, c.closure, c.intent],
               c.session
             )

    altered_closure = Map.put(c.closure, "closure", "cleanup_failure")

    assert {:error, _} =
             ReleaseReceipt.intents(
               [c.header, c.owner_marker, c.started, altered_closure, c.intent],
               c.session
             )

    other_epoch =
      c.started
      |> Map.put("epoch_id", String.duplicate("e", 32))
      |> Map.put("mode", "resume")
      |> Map.put("previous_epoch_id", c.epoch)
      |> Map.put("previous_state", "closed")

    assert {:error, _} =
             ReleaseReceipt.intents(
               [c.header, c.owner_marker, c.started, c.closure, other_epoch, c.intent],
               c.session
             )

    assert {:ok, []} = ReleaseReceipt.intents([c.header, c.started, c.closure], c.session)

    assert {:ok, []} =
             ReleaseReceipt.intents([%{"type" => "session", "metadata" => %{}}], c.session)
  end

  test "intent without opt-in lifecycle still binds original source", c do
    {:ok, intent, private} =
      ReleaseReceipt.prepare(
        c.session,
        c.owner,
        nil,
        nil,
        c.origin,
        %{device: 5, inode: 7},
        String.duplicate("c", 64)
      )

    assert {:ok, [intent]} ==
             ReleaseReceipt.intents([c.header, c.owner_marker, intent], c.session)

    {:ok, bytes} = ReleaseReceipt.seal(intent, private)
    assert :ok = ReleaseReceipt.verify(intent, bytes)

    {:ok, newer_owner} = ReleaseReceipt.owner_started(c.session)
    assert {:error, _} = ReleaseReceipt.intents([c.header, intent], c.session)

    assert {:error, _} =
             ReleaseReceipt.intents([c.header, c.owner_marker, c.started, intent], c.session)

    assert {:error, _} =
             ReleaseReceipt.intents([c.header, c.owner_marker, newer_owner, intent], c.session)

    assert {:error, _} =
             ReleaseReceipt.intents([c.header, c.owner_marker, c.owner_marker, intent], c.session)

    assert {:error, _} =
             ReleaseReceipt.intents(
               [%{"type" => "session", "metadata" => %{}}, c.owner_marker, intent],
               c.session
             )
  end

  test "only the creating process can use the private key", c do
    parent = self()
    spawn(fn -> send(parent, {:foreign_seal, ReleaseReceipt.seal(c.intent, c.private)}) end)
    assert_receive {:foreign_seal, {:error, :invalid_release_receipt}}, 1_000
    assert {:ok, _} = ReleaseReceipt.seal(c.intent, c.private)
  end

  test "a delayed old-owner receipt remains historical after reopening", c do
    {:ok, bytes} = ReleaseReceipt.seal(c.intent, c.private)
    before = [c.header, c.owner_marker, c.started, c.closure, c.intent]
    assert {:ok, c.intent} == ReleaseReceipt.current_intent(before, c.session)
    assert :signed_release_claim == ReleaseReceipt.classify_current(before, c.session, bytes)
    {:ok, next_owner} = ReleaseReceipt.owner_started(c.session)
    reopened = before ++ [next_owner]
    assert {:ok, [c.intent]} == ReleaseReceipt.intents(reopened, c.session)
    assert :ok == ReleaseReceipt.verify(c.intent, bytes)
    assert {:ok, nil} == ReleaseReceipt.current_intent(reopened, c.session)
    assert :unknown == ReleaseReceipt.classify_current(reopened, c.session, bytes)

    {:ok, next_intent, _} =
      ReleaseReceipt.prepare(
        c.session,
        next_owner["owner_id"],
        nil,
        nil,
        c.origin,
        %{device: 5, inode: 7},
        String.duplicate("c", 64)
      )

    assert {:ok, next_intent} ==
             ReleaseReceipt.current_intent(reopened ++ [next_intent], c.session)

    assert :unknown == ReleaseReceipt.classify(next_intent, bytes)
  end

  test "recording exhaustion leaves current cleanup unknown", c do
    waits =
      for n <- 1..4_999, reduce: [] do
        acc ->
          id = n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

          started = %{
            "type" => "lifecycle_wait_started",
            "version" => 1,
            "session_id" => c.session,
            "epoch_id" => c.epoch,
            "wait_id" => id,
            "kind" => "question",
            "domain" => "native_question",
            "turn_id" => nil,
            "request_id" => nil,
            "parent_invocation_id" => nil,
            "operation_id" => nil,
            "child_id" => nil,
            "subject_source" => nil
          }

          finished =
            started
            |> Map.put("type", "lifecycle_wait_finished")
            |> Map.put("outcome", "answered")
            |> Map.put("duration_ms", 0)

          [finished, started | acc]
      end
      |> Enum.reverse()

    stopped = %{
      "type" => "lifecycle_recording_stopped",
      "version" => 1,
      "session_id" => c.session,
      "epoch_id" => c.epoch,
      "reason" => "limit"
    }

    {:ok, prior_intent, prior_key} =
      ReleaseReceipt.prepare(
        c.session,
        c.owner,
        nil,
        nil,
        c.origin,
        %{device: 5, inode: 7},
        String.duplicate("c", 64)
      )

    {:ok, prior_bytes} = ReleaseReceipt.seal(prior_intent, prior_key)
    events = [c.header, c.owner_marker, prior_intent, c.started] ++ waits ++ [stopped]

    assert {:ok, %{stopped: true, epoch: epoch}} =
             Ipse.Session.RuntimeLifecycle.restore(events, c.session)

    assert epoch == c.epoch
    assert {:ok, [prior_intent]} == ReleaseReceipt.intents(events, c.session)
    assert :ok == ReleaseReceipt.verify(prior_intent, prior_bytes)
    assert {:ok, nil} == ReleaseReceipt.current_intent(events, c.session)
    assert {:error, _} = ReleaseReceipt.intents(events ++ [c.intent], c.session)

    {:ok, next_owner} = ReleaseReceipt.owner_started(c.session)

    {:ok, nil_intent, _} =
      ReleaseReceipt.prepare(
        c.session,
        next_owner["owner_id"],
        nil,
        nil,
        c.origin,
        %{device: 5, inode: 7},
        String.duplicate("c", 64)
      )

    assert {:error, _} = ReleaseReceipt.intents(events ++ [next_owner, nil_intent], c.session)
  end

  test "base64 fields have exact encoded lengths while JSON formatting may vary", c do
    {:ok, bytes} = ReleaseReceipt.seal(c.intent, c.private)
    receipt = Jason.decode!(bytes)
    assert :ok == ReleaseReceipt.verify(c.intent, Jason.encode!(receipt, pretty: true))

    for bad <- [String.duplicate("A", 100_000), c.intent["public_key"] <> "="] do
      refute ReleaseReceipt.valid_intent?(Map.put(c.intent, "public_key", bad))
    end

    for field <-
          ~w(session_id owner_id operation_id epoch_id closure_sha256 origin_sha256 helper_sha256) do
      refute ReleaseReceipt.valid_intent?(
               Map.put(c.intent, field, String.duplicate("a", 100_000))
             )
    end

    refute ReleaseReceipt.valid_intent?(
             Map.put(c.intent, "unexpected", String.duplicate("a", 100_000))
           )

    for bad <- [String.duplicate("A", 1_000), receipt["signature"] <> "="] do
      assert {:error, _} =
               ReleaseReceipt.verify(c.intent, Jason.encode!(Map.put(receipt, "signature", bad)))
    end
  end
end
