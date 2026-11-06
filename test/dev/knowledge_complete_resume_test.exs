Code.require_file("../../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../../dev/verification/saved_results.exs", __DIR__)
Code.require_file("../../dev/verification/knowledge_complete.exs", __DIR__)

defmodule KnowledgeCompleteResumeTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Verification.Scenarios

  test "declares exactly the independent helper and complete-result harness modules" do
    spec = Scenarios.fetch!("knowledge-complete")

    assert spec.sources == [
             "dev/verification/saved_results.exs",
             "dev/verification/knowledge_complete.exs"
           ]

    assert spec.modules == [
             IpseSavedResultsExample.Proof,
             IpseSavedResultsExample.Proof.NoModel,
             IpseKnowledgeExample.CompleteResultProof,
             IpseKnowledgeExample.CompleteResultProof.NoModel
           ]

    assert spec.module == IpseKnowledgeExample.CompleteResultProof
  end

  test "first close admits only the current owner's exact signed release lifecycle" do
    alias Ipse.Session.ReleaseReceipt
    alias IpseKnowledgeExample.CompleteResultProof, as: Proof
    alias IpseSavedResultsExample.Proof, as: SavedProof

    session = String.duplicate("a", 32)

    origin = %{
      "version" => 1,
      "session_id" => session,
      "directory" => "/tmp/ipse-fixture",
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

    {:ok, owner} = ReleaseReceipt.owner_started(session)
    {:ok, other} = ReleaseReceipt.owner_started(session)

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

    before = [header, owner, %{"type" => "extension_invocation_result"}]
    bytes = fn events -> IO.iodata_to_binary(Enum.map(events, &[Jason.encode!(&1), "\n"])) end
    after_events = before ++ [intent]

    assert {:ok, :signed_release_required} =
             Proof.validate_first_close(
               bytes.(before),
               bytes.(after_events),
               before,
               after_events,
               session
             )

    assert {:ok, receipt} = ReleaseReceipt.seal(intent, private)

    assert {:ok, "signed_release_claim"} =
             SavedProof.validate_release_status(:signed_release_required, fn ->
               ReleaseReceipt.classify_current(after_events, session, receipt)
             end)

    for missing_or_bad <- [nil, "bad", receipt <> "tampered"] do
      assert {:error, :release_claim_unconfirmed} =
               SavedProof.validate_release_status(:signed_release_required, fn ->
                 ReleaseReceipt.classify_current(after_events, session, missing_or_bad)
               end)
    end

    for suffix <- [
          [],
          [intent, %{"type" => "extension_action_result"}],
          [%{"type" => "extension_action_intent"}, intent],
          [other, intent],
          [Map.put(intent, "owner_id", other["owner_id"])],
          [intent, intent]
        ] do
      events = before ++ suffix

      assert {:error, :unexpected_first_close_journal} =
               Proof.validate_first_close(bytes.(before), bytes.(events), before, events, session)
    end

    assert {:error, :unexpected_first_close_journal} =
             Proof.validate_first_close(
               "changed",
               bytes.(after_events),
               before,
               after_events,
               session
             )

    legacy_header = update_in(header, ["metadata"], &Map.delete(&1, "release_receipt_layout"))
    legacy = [legacy_header]

    assert {:ok, :legacy_unchanged} =
             Proof.validate_first_close(bytes.(legacy), bytes.(legacy), legacy, legacy, session)

    assert {:error, :unexpected_first_close_journal} =
             Proof.validate_first_close(
               bytes.(legacy),
               bytes.(legacy ++ [intent]),
               legacy,
               legacy ++ [intent],
               session
             )
  end

  test "requires preserved prefix and accurate platform release status" do
    expected =
      if :os.type() == {:unix, :linux}, do: "signed_release_claim", else: "legacy_unchanged"

    wrong =
      if expected == "signed_release_claim", do: "legacy_unchanged", else: "signed_release_claim"

    report = %{
      "checks" => 5,
      "research_evidence" => 10,
      "corpus_evidence" => 10,
      "graph_evidence" => 1,
      "graph_claims" => 8,
      "research_bytes" => 12_001,
      "corpus_bytes" => 12_001,
      "graph_bytes" => 12_001,
      "escaped_citation_bytes" => 4097,
      "citation_crosses_fragment" => true,
      "unranked_claim_bases_preserved" => true,
      "complete_hashes_verified" => true,
      "opposing_assertions_preserved" => true,
      "corpus_graph_conflict" => true,
      "historical_reads_exact" => true,
      "resume_inert" => true,
      "journal_prefix_preserved" => true,
      "first_release_status" => expected,
      "resume_release_status" => expected,
      "model_requests" => 0,
      "host_loaded_domain_modules" => false,
      "cleanup" => "confirmed"
    }

    scenario = %{name: "knowledge-complete"}
    assert :ok = Scenarios.validate!(scenario, report, "default")

    for field <- ["first_release_status", "resume_release_status"],
        invalid <- [wrong, "unknown", nil] do
      assert_raise MatchError, fn ->
        Scenarios.validate!(scenario, Map.put(report, field, invalid), "default")
      end
    end

    assert_raise MatchError, fn ->
      Scenarios.validate!(scenario, Map.put(report, "journal_prefix_preserved", false), "default")
    end
  end
end
