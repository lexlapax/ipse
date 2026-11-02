Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.PendingCorrectionTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection.Migration, ManagedRecipe}
  alias Ipse.Session.PendingCorrection

  # Pure consistency fixtures: these shapes attest no source, domain, policy,
  # storage, native input or effect. Actual owners belong to integration tests.
  setup do
    recipe = IpseKnowledge.Knowledge.Contracts.recipe("pending")
    quote = "An unattended proposed reporting preference"

    proof = %{
      "version" => 1,
      "session_id" => Usage.id(),
      "occurrence_id" => Usage.id(),
      "version_id" => Usage.id(),
      "kind" => "input.original",
      "origin" => "unattended_input",
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(quote),
      "quote" => quote,
      "quote_sha256" => JSON.sha256(quote),
      "content_sha256" => JSON.sha256(quote),
      "receipt_sha256" => JSON.sha256("synthetic receipt")
    }

    {:ok, lineage} = ManagedRecipe.source_identity(proof)
    {:ok, id} = ManagedRecipe.proposal_identity(lineage, quote)
    key = "pending." <> id

    value = %{
      "version" => 1,
      "kind" => "proposal",
      "id" => id,
      "lineage" => lineage,
      "state" => "pending",
      "text" => quote,
      "assigned_category" => "preference",
      "reason" => "original proposed reason",
      "event_at_ms" => nil,
      "created_at_ms" => 500,
      "expires_at_ms" => 700_000,
      "evidence" => %{"sources" => [proof]}
    }

    record = %{
      "key" => key,
      "revision" => 1,
      "operation_id" => Usage.id(),
      "value" => value,
      "sha256" => JSON.sha256(Migration.encode(value)),
      "bytes" => byte_size(Migration.encode(value))
    }

    namespace = JSON.sha256("namespace")

    root = %{
      "version" => 5,
      "project" => namespace,
      "generation" => 1,
      "floor" => 1,
      "floor_anchor" => JSON.sha256("floor anchor"),
      "manifest" => JSON.sha256("manifest")
    }

    witness = %{
      "root_state" => "present",
      "root" => root,
      "root_sha256" => JSON.sha256(Jason.encode!(root)),
      "manifest_sha256" => root["manifest"]
    }

    metadata = %{
      "lineage" => lineage,
      "recipe_sha256" => JSON.digest([recipe]),
      "policy_sha256" => JSON.sha256("original publication policy"),
      "first_admitted_ms" => 1000,
      "valid_until_ms" => 100_000,
      "category" => "preference",
      "eligibility" => "never_current"
    }

    managed = %{
      "metadata" => metadata,
      "observation" => %{
        "version" => 1,
        "value" => %{"record" => record},
        "witness" => witness,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => JSON.digest([%{"record" => record}])
      }
    }

    journal = Usage.id()
    project = JSON.sha256("project")
    binding = JSON.sha256("binding")

    pin = %{
      "version" => 1,
      "session_id" => journal,
      "project_id" => project,
      "worktree_id" => JSON.sha256("tree"),
      "binding_sha256" => binding,
      "epoch" => 3,
      "policy_sha256" => JSON.sha256("current publication policy"),
      "identity_sha256" => JSON.sha256("identity"),
      "namespace" => namespace,
      "routes_sha256" => JSON.sha256("routes"),
      "source_sha256" => JSON.sha256("sources")
    }

    context = %{
      "session_id" => journal,
      "job_id" => Usage.id(),
      "client_id" => Usage.id(),
      "project_id" => project,
      "namespace" => namespace,
      "binding_sha256" => binding,
      "management_epoch" => 3,
      "management_sha256" => JSON.sha256("current management policy"),
      "original_pin" => pin,
      "recipe" => recipe
    }

    %{context: context, managed: managed, proof: proof, value: value}
  end

  test "editing creates a new pending identity while preserving original provenance, category and clocks",
       c do
    text = "Prefer ISO dates in shared reports."
    assert {:ok, prepared} = PendingCorrection.prepare(c.context, c.managed, text, 90_000, 2000)
    facts = prepared["facts"]
    assert PendingCorrection.valid_facts?(facts)
    assert PendingCorrection.current_review?(facts, 89_999)
    refute PendingCorrection.current_review?(facts, 90_000)
    refute PendingCorrection.current_review?(facts, 999)
    assert facts["source_card"]["source_proof"] === c.proof
    [removed, inserted, suppressed] = prepared["request"]["changes"]
    assert removed["key"] === c.managed["observation"]["value"]["record"]["key"]
    assert removed["value"] === nil
    assert inserted["key"] !== removed["key"]
    assert inserted["value"]["text"] === text
    assert inserted["value"]["kind"] === "proposal" and inserted["value"]["state"] === "pending"
    assert Map.drop(inserted["value"], ~w(id text)) === Map.drop(c.value, ~w(id text))
    assert suppressed["value"]["replacement_key"] === inserted["key"]
    assert facts["metadata"] === c.managed["metadata"]
    assert facts["publish_before_ms"] === 90_000
    assert facts["request"] === prepared["request"]
    assert prepared["intent"]["facts"] === facts
    assert facts["operation_id"] === c.context["job_id"]
  end

  test "same, empty, invalid, oversized or expired edits produce no proposal", c do
    for text <- [c.value["text"], "", " \n ", <<255>>, String.duplicate("x", 2049)] do
      assert {:error, :pending_correction_refused} =
               PendingCorrection.prepare(c.context, c.managed, text, 90_000, 2000)
    end

    for {deadline, now} <- [{2000, 2000}, {1900, 2000}, {200_000, 100_000}, {200_000, 999}] do
      assert {:error, :pending_correction_refused} =
               PendingCorrection.prepare(c.context, c.managed, "new pending text", deadline, now)
    end

    assert {:error, :pending_correction_refused} =
             PendingCorrection.prepare(
               %{c.context | "original_pin" => nil},
               c.managed,
               "new pending text",
               90_000,
               2000
             )

    assert {:error, :pending_correction_refused} =
             PendingCorrection.prepare(
               put_in(c.context, ["original_pin", "epoch"], 2),
               c.managed,
               "new pending text",
               90_000,
               2000
             )

    assert {:error, :pending_correction_refused} =
             PendingCorrection.prepare(
               put_in(c.context, ["original_pin", "session_id"], Usage.id()),
               c.managed,
               "new pending text",
               90_000,
               2000
             )
  end

  test "source, pending-state, retention, text and exact request changes invalidate displayed facts",
       c do
    assert {:ok, prepared} =
             PendingCorrection.prepare(c.context, c.managed, "new pending text", 200_000, 2000)

    facts = prepared["facts"]
    assert facts["publish_before_ms"] === facts["metadata"]["valid_until_ms"]

    for changed <- [
          put_in(facts, ["source_card", "source_proof", "origin"], "interactive_operator"),
          put_in(facts, ["request", "changes", Access.at(1), "value", "state"], "accepted"),
          put_in(facts, ["request", "changes", Access.at(1), "value", "expires_at_ms"], 800_000),
          put_in(
            facts,
            ["request", "changes", Access.at(1), "value", "assigned_category"],
            "ordinary"
          ),
          Map.put(facts, "publish_before_ms", 300_000),
          Map.put(facts, "request_sha256", JSON.sha256("different request")),
          Map.put(facts, "unseen", "extra facts")
        ] do
      refute PendingCorrection.valid_facts?(changed)
    end
  end
end
