Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.AcceptedDecisionLifecycleTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{ManagedRecipe, Collection.Migration}
  alias Ipse.Session.{ManagedLifecycle, PendingAcceptance}

  # Consistency fixtures only. Actual signed rows and native Review authority
  # belong to the separate genuine capture/acceptance/forget CLI journey.
  setup do
    recipe = IpseKnowledge.Knowledge.Contracts.recipe("note")
    text = "An attributed proposed preference"

    source = %{
      "version" => 1,
      "session_id" => Usage.id(),
      "occurrence_id" => Usage.id(),
      "version_id" => Usage.id(),
      "kind" => "input.original",
      "origin" => "unattended_input",
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(text),
      "quote" => text,
      "quote_sha256" => JSON.sha256(text),
      "content_sha256" => JSON.sha256(text),
      "receipt_sha256" => JSON.sha256("synthetic source receipt")
    }

    {:ok, original} = ManagedRecipe.source_identity(source)
    {:ok, candidate} = ManagedRecipe.proposal_identity(original, text)
    lineage = JSON.digest(["ipse-knowledge", 1, "accepted_decision", candidate, original])
    key = "note." <> lineage
    event_sha = JSON.sha256("synthetic acceptance event")

    linked = %{
      "version" => 1,
      "kind" => "candidate_acceptance_link",
      "candidate_id" => candidate,
      "journal_id" => Usage.id(),
      "journal_kind" => "knowledge_management",
      "pending_key" => "pending." <> candidate,
      "pending_revision" => 1,
      "pending_value_sha256" => JSON.sha256("pending value"),
      "original_lineage" => original,
      "accepted_note_key" => key,
      "acceptance_event_sha256" => event_sha,
      "source_proof_sha256" => JSON.digest([source])
    }

    note = %{
      "version" => 1,
      "kind" => "accepted_decision",
      "lineage" => lineage,
      "candidate_id" => candidate,
      "text" => text,
      "category" => "ordinary",
      "reason" => "Native accepted proposal",
      "source_proof" => source,
      "acceptance_event_sha256" => event_sha,
      "acceptance_link_sha256" => JSON.sha256(Migration.encode(linked)),
      "accepted_at_ms" => 1100,
      "valid_until_ms" => 1800
    }

    operation = Usage.id()
    record = record(key, note, operation)
    link = record("accept." <> candidate, linked, operation)
    anchor = %{"clocks" => [1000, 2000, nil, nil], "choice" => nil, "retirement" => nil}

    live =
      Enum.map(
        [lineage, record["sha256"], JSON.digest([recipe]), JSON.sha256("historical policy")],
        &packed/1
      ) ++ ["rs", "1e0", 0, 3]

    %{recipe: recipe, record: record, link: link, anchor: anchor, live: live}
  end

  test "accepted target stays distinct from a literal and has no current-source or time grant",
       c do
    assert {:ok, metadata} = inspect_target(c)
    assert metadata["management_target"] == "accepted_decision"
    assert metadata["valid_until_ms"] == 1800
    assert metadata["first_admitted_ms"] == 1000

    assert {:error, _} =
             ManagedRecipe.extract(c.recipe, c.record["key"], c.record["value"], [
               c.record["value"]["source_proof"]
             ])
  end

  test "other signed eligibility tags, retirement and prior choices cannot become accepted targets",
       c do
    other_prefix = Map.put(c.recipe, "key_prefix", "other.")
    other_live = List.replace_at(c.live, 2, packed(JSON.digest([other_prefix])))
    assert {:error, _} = inspect_target(%{c | recipe: other_prefix, live: other_live})

    for tag <- [0, 1, 2, 4],
        do: assert({:error, _} = inspect_target(%{c | live: List.replace_at(c.live, 7, tag)}))

    assert {:error, _} =
             inspect_target(%{
               c
               | anchor:
                   put_in(c.anchor["retirement"], %{
                     "record_key" => c.record["key"],
                     "record_value_sha256" => c.record["sha256"],
                     "at_ms" => 1900
                   })
             })

    assert {:error, _} =
             inspect_target(%{c | anchor: put_in(c.anchor["choice"], %{"kind" => "untrusted"})})

    assert {:error, _} =
             inspect_target(%{
               c
               | live: List.replace_at(c.live, 2, packed(JSON.sha256("other recipe")))
             })
  end

  test "immutable link identity and original proof remain bound even without loading a journal",
       c do
    for field <-
          ~w(candidate_id original_lineage accepted_note_key acceptance_event_sha256 source_proof_sha256 journal_id pending_key pending_revision) do
      link = update_in(c.link["value"], &Map.put(&1, field, "changed"))
      assert {:error, _} = inspect_target(%{c | link: link})
    end

    assert {:error, _} = inspect_target(%{c | link: %{c.link | "revision" => 3}})
    assert {:error, _} = inspect_target(%{c | link: %{c.link | "operation_id" => Usage.id()}})

    assert {:error, _} =
             inspect_target(%{
               c
               | record:
                   put_in(
                     c.record["value"]["source_proof"]["origin"],
                     "native_operator_assertion"
                   )
             })

    assert {:error, _} = inspect_target(%{c | record: put_in(c.record["value"]["extra"], true)})
  end

  test "native accepted forgetting prepares one deletion and cannot enter literal retention", c do
    {:ok, metadata} = inspect_target(c)
    namespace = JSON.sha256("namespace")

    context = %{
      "session_id" => Usage.id(),
      "job_id" => Usage.id(),
      "client_id" => Usage.id(),
      "project_id" => JSON.sha256("project"),
      "namespace" => namespace,
      "binding_sha256" => JSON.sha256("binding"),
      "management_epoch" => 1,
      "management_sha256" => JSON.sha256("management"),
      "original_pin" => nil,
      "recipe" => c.recipe
    }

    root = %{
      "version" => 5,
      "project" => namespace,
      "generation" => 2,
      "floor" => 0,
      "floor_anchor" => nil,
      "manifest" => JSON.sha256("manifest")
    }

    managed = %{
      "metadata" => metadata,
      "observation" => %{
        "value" => %{"record" => c.record},
        "result_sha256" => JSON.digest([%{"record" => c.record}]),
        "witness" => %{
          "root_state" => "present",
          "root" => root,
          "root_sha256" => JSON.sha256(Jason.encode!(root)),
          "manifest_sha256" => root["manifest"]
        }
      }
    }

    assert {:ok, prepared} =
             ManagedLifecycle.prepare_accepted_forget(context, managed, "Forget this decision")

    assert prepared["facts"]["kind"] == "managed_accepted_decision_forget"

    assert prepared["request"]["changes"] == [
             %{"key" => c.record["key"], "expected_revision" => 2, "value" => nil}
           ]

    assert {:error, _} = ManagedLifecycle.prepare_accepted_expiry(context, managed, 1799)
    assert {:ok, expiry} = ManagedLifecycle.prepare_accepted_expiry(context, managed, 1800)
    assert expiry["request"] == prepared["request"]
    assert expiry["facts"]["kind"] == "managed_accepted_decision_expiry"
    assert expiry["facts"]["expired_at_ms"] == 1800
    assert expiry["facts"]["checked_at_ms"] == 1800
    refute Map.has_key?(expiry["facts"], "policy")

    assert expiry["facts"]["action_sha256"] ==
             JSON.digest([Map.delete(expiry["facts"], "action_sha256")])

    assert expiry["intent"]["facts"] == expiry["facts"]

    for invalid <- [nil, -1, "1800", 1799] do
      refute PendingAcceptance.expired_retained_decision_metadata?(metadata, invalid)
    end

    refute PendingAcceptance.expired_retained_decision_metadata?(
             Map.put(metadata, "valid_until_ms", nil),
             1800
           )

    refute PendingAcceptance.expired_retained_decision_metadata?(
             Map.put(metadata, "management_target", "literal_source"),
             1800
           )

    refute PendingAcceptance.expired_retained_decision_metadata?(
             Map.put(metadata, "extra", true),
             1800
           )

    assert {:error, _} = ManagedLifecycle.prepare(context, managed, "Cannot relabel this target")

    assert {:error, _} =
             ManagedLifecycle.prepare_retention(
               context,
               managed,
               %{"kind" => "pin"},
               "Cannot pin this target"
             )
  end

  defp inspect_target(c),
    do: PendingAcceptance.retained_decision_metadata(c.recipe, c.record, c.link, c.anchor, c.live)

  defp packed(hash), do: hash |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)

  defp record(key, value, operation) do
    bytes = Migration.encode(value)

    %{
      "key" => key,
      "value" => value,
      "revision" => 2,
      "operation_id" => operation,
      "bytes" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes)
    }
  end
end
