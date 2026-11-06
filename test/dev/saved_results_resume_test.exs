Code.require_file("../../dev/verification/saved_results.exs", __DIR__)
Code.require_file("../../dev/verification/scenarios.exs", __DIR__)

defmodule SavedResultsResumeTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.ReleaseReceipt
  alias IpseSavedResultsExample.Proof

  setup do
    session = String.duplicate("a", 32)

    origin = %{
      "version" => 1,
      "session_id" => session,
      "directory" => "/tmp/ipse-receipt-fixture",
      "major_device" => 5,
      "minor_device" => 0,
      "inode" => 42,
      "uid" => 1000
    }

    header = %{
      "type" => "session",
      "metadata" => %{
        "release_receipt_layout" => ReleaseReceipt.layout(),
        "source_origin_layout" => "journal_origin_v1",
        "source_origin" => origin
      }
    }

    make_pair = fn ->
      {:ok, owner} = ReleaseReceipt.owner_started(session)

      {:ok, intent, private} =
        ReleaseReceipt.prepare(
          session,
          owner["owner_id"],
          nil,
          nil,
          origin,
          %{device: 5, inode: 7},
          String.duplicate("c", 64)
        )

      {owner, intent, private}
    end

    {first_owner, first_intent, _} = make_pair.()
    {owner, intent, private} = make_pair.()
    before = [header, first_owner, first_intent]
    %{session: session, before: before, owner: owner, intent: intent, private: private}
  end

  defp bytes(events), do: IO.iodata_to_binary(Enum.map(events, &[Jason.encode!(&1), "\n"]))

  test "accepts only a valid new owner and its release intent after exact prefix", c do
    after_events = c.before ++ [c.owner, c.intent]

    assert {:ok, :signed_release_required} =
             Proof.validate_idle_resume(
               bytes(c.before),
               bytes(after_events),
               c.before,
               after_events,
               c.session
             )

    for suffix <- [
          [],
          [c.owner],
          [c.owner, c.intent, %{"type" => "extension_invocation_result"}],
          [c.owner, Map.put(c.intent, "owner_id", List.last(c.before)["owner_id"])],
          [c.owner, Map.put(c.intent, "session_id", String.duplicate("b", 32))],
          [c.owner, c.intent, c.owner, c.intent],
          [List.first(tl(c.before)), c.intent]
        ] do
      events = c.before ++ suffix

      assert {:error, :unexpected_resume_journal} =
               Proof.validate_idle_resume(
                 bytes(c.before),
                 bytes(events),
                 c.before,
                 events,
                 c.session
               )
    end

    assert {:error, :unexpected_resume_journal} =
             Proof.validate_idle_resume(
               "corrupt",
               bytes(after_events),
               c.before,
               after_events,
               c.session
             )
  end

  test "reports a signed claim only after checking the current signed intent", c do
    events = c.before ++ [c.owner, c.intent]
    assert {:ok, receipt} = ReleaseReceipt.seal(c.intent, c.private)

    assert {:ok, "signed_release_claim"} =
             Proof.validate_release_status(:signed_release_required, fn ->
               ReleaseReceipt.classify_current(events, c.session, receipt)
             end)

    for bad_receipt <- [nil, "bad", receipt <> "tampered"] do
      assert {:error, :release_claim_unconfirmed} =
               Proof.validate_release_status(:signed_release_required, fn ->
                 ReleaseReceipt.classify_current(events, c.session, bad_receipt)
               end)
    end

    assert {:ok, "legacy_unchanged"} =
             Proof.validate_release_status(:legacy_unchanged, fn ->
               raise "legacy mode must not inspect or claim a signed release"
             end)

    assert {:error, :release_claim_unconfirmed} =
             Proof.validate_release_status(:unknown, fn -> :signed_release_claim end)
  end

  test "scenario validation rejects inaccurate release reports" do
    expected =
      if :os.type() == {:unix, :linux}, do: "signed_release_claim", else: "legacy_unchanged"

    wrong =
      if expected == "signed_release_claim", do: "legacy_unchanged", else: "signed_release_claim"

    report = %{
      "byte_count" => 4_194_304,
      "fragment_count" => 1024,
      "historical_reads_exact" => true,
      "resume_inert" => true,
      "journal_prefix_preserved" => true,
      "resume_release_status" => expected,
      "worker_loads" => 1,
      "callbacks" => 1,
      "model_requests" => 0,
      "host_loaded_domain_modules" => false,
      "cleanup" => "confirmed"
    }

    scenario = %{name: "saved-results"}
    assert :ok = Ipse.Development.Verification.Scenarios.validate!(scenario, report, "default")

    for invalid <- [wrong, "unknown", nil] do
      assert_raise MatchError, fn ->
        Ipse.Development.Verification.Scenarios.validate!(
          scenario,
          Map.put(report, "resume_release_status", invalid),
          "default"
        )
      end
    end
  end

  test "legacy journal must stay byte-identical", c do
    header = update_in(hd(c.before), ["metadata"], &Map.delete(&1, "release_receipt_layout"))
    legacy = [header]

    assert {:ok, :legacy_unchanged} =
             Proof.validate_idle_resume(bytes(legacy), bytes(legacy), legacy, legacy, c.session)

    extra = legacy ++ [c.owner, c.intent]

    assert {:error, :unexpected_resume_journal} =
             Proof.validate_idle_resume(bytes(legacy), bytes(extra), legacy, extra, c.session)
  end
end
