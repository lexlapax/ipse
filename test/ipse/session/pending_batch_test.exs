Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.PendingBatchTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection.Migration, ManagedRecipe}
  alias Ipse.Session.{PendingAcceptance, PendingBatch}
  alias Ipse.Test.ManagedPolicy, as: F

  test "a chat card is bound to the same Session and journal" do
    f = fixture(1)
    chat = Map.put(f.context, "session_id", f.context["journal_id"])
    assert {:ok, card} = PendingAcceptance.prepare(chat, f.managed, [f.proof], 2000)
    assert PendingAcceptance.valid_facts?(card)

    other_session = Usage.id()
    refute other_session == chat["journal_id"]

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.prepare(
               Map.put(chat, "session_id", other_session),
               f.managed,
               [f.proof],
               2000
             )

    refute PendingAcceptance.valid_facts?(Map.put(card, "session_id", other_session))
    refute PendingAcceptance.valid_facts?(Map.put(card, "journal_id", other_session))
  end

  # Pure consistency and byte-bound fixtures, never source/native authority.
  test "eight distinct exact candidates share one immutable manifest and per-item membership" do
    fixtures = Enum.map(1..8, &fixture/1)
    cards = Enum.map(fixtures, & &1.card)

    assert {:ok, manifest} =
             PendingBatch.prepare(cards, IpseKnowledge.Knowledge.Contracts.recipe("note"), 90_000)

    assert PendingBatch.valid_manifest?(manifest)
    assert length(manifest["items"]) == 8

    for {f, index} <- Enum.with_index(fixtures) do
      assert {:ok, batch} = PendingBatch.binding(manifest, index)
      assert PendingBatch.member?(batch, f.card)

      assert {:ok, card} =
               PendingAcceptance.prepare(
                 Map.put(f.context, "batch", batch),
                 f.managed,
                 [f.proof],
                 2000
               )

      assert card["batch"] === batch
      assert Map.delete(card, "batch") === f.card
      assert PendingAcceptance.valid_facts?(card)
      refute PendingBatch.member?(batch, Enum.at(cards, rem(index + 1, 8)))

      refute PendingAcceptance.valid_facts?(
               put_in(card, ["batch", "manifest_sha256"], JSON.sha256("forged"))
             )

      refute PendingAcceptance.valid_facts?(Map.put(card, "session_id", card["journal_id"]))
    end

    assert Enum.all?(
             cards,
             &(PendingAcceptance.valid_facts?(&1) and not Map.has_key?(&1, "batch"))
           )

    assert {:error, :pending_batch_refused} =
             PendingBatch.prepare(
               cards ++ [hd(cards)],
               IpseKnowledge.Knowledge.Contracts.recipe("note"),
               90_000
             )

    assert {:error, :pending_batch_refused} =
             PendingBatch.prepare(
               [hd(cards), hd(cards)],
               IpseKnowledge.Knowledge.Contracts.recipe("note"),
               90_000
             )

    changed = Map.put(Enum.at(cards, 1), "root_sha256", JSON.sha256("other root"))

    assert {:error, :pending_batch_refused} =
             PendingBatch.prepare(
               [hd(cards), changed],
               IpseKnowledge.Knowledge.Contracts.recipe("note"),
               90_000
             )
  end

  test "manifest limits refuse the ninth item and the byte after 8 KiB without truncation" do
    cards = Enum.map(1..8, &fixture(&1).card)

    assert {:ok, original} =
             PendingBatch.prepare(cards, IpseKnowledge.Knowledge.Contracts.recipe("note"), 90_000)

    padding = 8192 - byte_size(Jason.encode!(original))
    assert padding > 0

    {items, 0} =
      Enum.map_reduce(original["items"], padding, fn item, remaining ->
        count = min(remaining, 2048 - byte_size(item["text"]))
        {Map.update!(item, "text", &(&1 <> String.duplicate("x", count))), remaining - count}
      end)

    boundary = Map.put(original, "items", items)
    assert byte_size(Jason.encode!(boundary)) == 8192
    assert PendingBatch.valid_manifest?(boundary)
    assert PendingBatch.binding(boundary, 7) |> elem(0) == :ok
    assert {:error, :pending_batch_refused} = PendingBatch.binding(boundary, 8)
    over = update_in(boundary, ["items", Access.at(7), "text"], &(&1 <> "x"))
    assert byte_size(Jason.encode!(over)) == 8193
    refute PendingBatch.valid_manifest?(over)
    refute PendingBatch.valid_manifest?(Map.update!(original, "items", &(&1 ++ [hd(&1)])))
    refute PendingBatch.valid_manifest?(Map.put(original, "unseen", true))
    refute PendingBatch.keys?([])
    refute PendingBatch.keys?(Enum.map(cards, & &1["pending_key"]) ++ [hd(cards)["pending_key"]])
  end

  test "manifest changes cannot reuse a selected card binding" do
    f = fixture(1)

    assert {:ok, manifest} =
             PendingBatch.prepare(
               [f.card, fixture(2).card],
               IpseKnowledge.Knowledge.Contracts.recipe("note"),
               90_000
             )

    assert {:ok, batch} = PendingBatch.binding(manifest, 0)

    for changed <- [
          put_in(batch, ["manifest", "items", Access.at(0), "text"], "edited"),
          put_in(batch, ["manifest", "policy_sha256"], JSON.sha256("other consent")),
          Map.put(batch, "index", 1),
          Map.put(batch, "index", -1)
        ] do
      refute PendingBatch.member?(changed, f.card)
    end

    changed_manifest =
      put_in(manifest, ["items", Access.at(0), "source", "origin"], "assistant_proposal")

    assert {:ok, rebound} = PendingBatch.binding(changed_manifest, 0)
    refute PendingBatch.member?(rebound, f.card)

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.prepare(
               Map.put(f.context, "batch", rebound),
               f.managed,
               [f.proof],
               2000
             )
  end

  defp fixture(index) do
    recipe = IpseKnowledge.Knowledge.Contracts.recipe("pending")
    proof = F.proof("unattended_input", "Original generated-task source")
    {:ok, lineage} = ManagedRecipe.source_identity(proof)
    text = "Proposed decision #{index}"
    {:ok, id} = ManagedRecipe.proposal_identity(lineage, text)
    key = "pending." <> id

    value = %{
      "version" => 1,
      "kind" => "proposal",
      "id" => id,
      "lineage" => lineage,
      "state" => "pending",
      "text" => text,
      "assigned_category" => "ordinary",
      "reason" => "proposal",
      "event_at_ms" => nil,
      "created_at_ms" => 500,
      "expires_at_ms" => 999_999,
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

    namespace = JSON.sha256("batch namespace")

    root = %{
      "version" => 5,
      "project" => namespace,
      "generation" => 1,
      "floor" => 1,
      "floor_anchor" => JSON.sha256("floor"),
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
      "policy_sha256" => JSON.sha256("publication"),
      "first_admitted_ms" => 1000,
      "valid_until_ms" => 100_000,
      "category" => "ordinary",
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

    context = %{
      "operation_id" => Usage.id(),
      "journal_id" => Usage.id(),
      "client_id" => Usage.id(),
      "session_id" => nil,
      "project_id" => JSON.sha256("project"),
      "namespace" => namespace,
      "binding_sha256" => JSON.sha256("binding"),
      "policy_sha256" => JSON.sha256("current policy"),
      "capture_epoch" => 3,
      "render_revision" => 1,
      "recipe" => recipe
    }

    {:ok, card} = PendingAcceptance.prepare(context, managed, [proof], 2000)
    %{card: card, context: context, managed: managed, proof: proof}
  end
end
