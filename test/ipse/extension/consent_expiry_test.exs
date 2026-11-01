defmodule Ipse.Extension.ConsentExpiryTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Consent

  # These are control-ledger syntax fixtures. The callback does not mutate a
  # Collection or prove that a target's stored metadata is authentic.
  setup do
    directory = Path.join(System.tmp_dir!(), "ipse-consent-expiry-" <> Usage.id())
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    project = JSON.sha256("synthetic expiry ledger")
    root = Path.join(directory, "control")
    now = System.system_time(:millisecond)

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("synthetic artifact"),
      "source_sha256" => JSON.sha256("synthetic source"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.put(Consent.zero(), "operations", 1),
      "period_ms" => 1000,
      "expires_at_ms" => now + 1000,
      "headless" => false
    }

    assert {:ok, _} = Consent.replace(root, project, 0, policy, now)
    assert {:ok, _} = Consent.revoke(root, project, 1)
    fingerprint = Consent.management_sha256(project, 2, nil)

    metadata = %{
      "category" => "ordinary",
      "first_admitted_ms" => now - 100,
      "valid_until_ms" => now - 1,
      "policy_sha256" => JSON.sha256("original signed policy fixture")
    }

    body = %{
      "version" => 1,
      "kind" => "managed_literal_expiry",
      "operation_id" => Usage.id(),
      "context" => %{
        "project_id" => project,
        "management_epoch" => 2,
        "management_sha256" => fingerprint
      },
      "collection" => %{},
      "target" => %{},
      "metadata" => metadata,
      "reason" => "Expired signed policy fixture; no collection mutation",
      "request_sha256" => JSON.sha256("synthetic collection request"),
      "scope" => "synthetic control component only",
      "expired_at_ms" => metadata["valid_until_ms"],
      "checked_at_ms" => now
    }

    facts = seal(body)
    request = request(facts, policy["artifact_sha256"])
    %{root: root, project: project, now: now, facts: facts, request: request}
  end

  test "revoked capture permits one deferred expiry packet and requires separate settlement", c do
    assert {:ok, packet} = call(c, fn -> {:ok, c.request["reserved"], receipt(c.facts)} end)
    assert {:ok, state} = Consent.existing_snapshot(c.root, c.project)
    assert state["policy"] == nil
    assert state["operations"][c.request["id"]]["status"] == "publishing"

    assert {:error, :consent_management_refused} = call(c, fn -> flunk("replayed expiry") end)

    assert {:ok, _} =
             Consent.settle(
               c.root,
               c.project,
               packet["ticket"],
               {:known, packet["actual"], packet["receipt"]}
             )

    assert {:ok, state} = Consent.existing_snapshot(c.root, c.project)
    assert state["operations"][c.request["id"]]["status"] == "settled"
  end

  test "wrong operation, headless, services and changed epoch never enter callback", c do
    before = File.read!(Path.join([c.root, c.project, "control.json"]))

    for request <- [
          Map.put(c.request, "operation", "collection.retention"),
          Map.put(c.request, "headless", true),
          put_in(c.request, ["reserved", "model_calls"], 1),
          put_in(c.request, ["reserved", "download_bytes"], 1),
          Map.put(c.request, "policy_sha256", JSON.sha256("wrong epoch"))
        ] do
      assert {:error, :consent_management_refused} =
               call(%{c | request: request}, fn -> flunk("widened expiry") end)

      assert File.read!(Path.join([c.root, c.project, "control.json"])) == before
    end

    assert {:error, :consent_management_refused} =
             Consent.expire_deferred(c.root, c.project, 1, c.request, c.facts, c.now, fn ->
               flunk("stale epoch")
             end)
  end

  test "nonordinary, unexpired, future and altered facts refuse before publishing", c do
    before = File.read!(Path.join([c.root, c.project, "control.json"]))
    body = Map.delete(c.facts, "action_sha256")

    for body <- [
          put_in(body, ["metadata", "category"], "pin"),
          Map.put(body, "expired_at_ms", c.now + 1),
          Map.put(body, "checked_at_ms", c.now + 1),
          Map.put(body, "unexpected", true)
        ] do
      facts = seal(body)
      request = request(facts, c.request["artifact_sha256"])

      assert {:error, :consent_management_refused} =
               call(%{c | facts: facts, request: request}, fn -> flunk("invalid expiry") end)

      assert File.read!(Path.join([c.root, c.project, "control.json"])) == before
    end
  end

  test "callback loss or changed receipt retains publishing liability and never retries", c do
    assert {:unknown, :publication_unconfirmed} =
             call(c, fn -> raise "synthetic callback loss" end)

    assert {:error, :consent_management_refused} =
             call(c, fn -> flunk("replayed unknown expiry") end)

    assert {:ok, state} = Consent.existing_snapshot(c.root, c.project)
    assert state["operations"][c.request["id"]]["status"] == "publishing"

    body = Map.delete(c.facts, "action_sha256") |> Map.put("operation_id", Usage.id())
    facts = seal(body)
    selected = %{c | facts: facts, request: request(facts, c.request["artifact_sha256"])}
    invalid = put_in(receipt(facts), ["publication", "normalization", "checked_at_ms"], c.now - 1)

    assert {:unknown, :publication_unconfirmed} =
             call(selected, fn -> {:ok, selected.request["reserved"], invalid} end)

    assert {:error, :consent_management_refused} =
             call(selected, fn -> flunk("replayed invalid receipt") end)
  end

  @tag :history_expiry_consent
  test "history expiry requires the exact history kind and category, and settles only its matching receipt",
       c do
    body =
      c.facts |> Map.delete("action_sha256") |> Map.put("kind", "managed_literal_history_expiry")

    body = put_in(body, ["metadata", "category"], "history")
    facts = seal(body)
    selected = %{c | facts: facts, request: request(facts, c.request["artifact_sha256"])}

    for {kind, category} <- [
          {"managed_literal_expiry", "history"},
          {"managed_literal_history_expiry", "ordinary"},
          {"managed_literal_history_expiry", "pin"}
        ] do
      invalid =
        body |> Map.put("kind", kind) |> put_in(["metadata", "category"], category) |> seal()

      assert {:error, :consent_management_refused} =
               call(
                 %{c | facts: invalid, request: request(invalid, c.request["artifact_sha256"])},
                 fn -> flunk("cross-kind expiry") end
               )
    end

    assert {:ok, packet} =
             call(selected, fn -> {:ok, selected.request["reserved"], receipt(facts)} end)

    assert {:ok, _} =
             Consent.settle(
               c.root,
               c.project,
               packet["ticket"],
               {:known, packet["actual"], packet["receipt"]}
             )

    assert {:ok, state} = Consent.existing_snapshot(c.root, c.project)
    assert state["operations"][facts["operation_id"]]["status"] == "settled"

    assert {:error, :consent_management_refused} =
             call(selected, fn -> flunk("replayed history expiry") end)

    changed = body |> Map.put("operation_id", Usage.id()) |> seal()
    second = %{c | facts: changed, request: request(changed, c.request["artifact_sha256"])}
    wrong = receipt(changed)
    normalized = put_in(wrong, ["publication", "normalization", "kind"], "managed_literal_expiry")

    normalized =
      put_in(
        normalized,
        ["publication", "binding", "normalization_sha256"],
        JSON.digest([normalized["publication"]["normalization"]])
      )

    assert {:unknown, :publication_unconfirmed} =
             call(second, fn -> {:ok, second.request["reserved"], normalized} end)

    assert {:error, :consent_management_refused} =
             call(second, fn -> flunk("replayed mismatched receipt") end)
  end

  test "accepted expiry stays typed, finite and zero-service after capture revocation", c do
    metadata =
      Map.merge(c.facts["metadata"], %{
        "lineage" => JSON.sha256("synthetic accepted lineage"),
        "recipe_sha256" => JSON.sha256("synthetic accepted recipe"),
        "management_target" => "accepted_decision"
      })

    body =
      c.facts
      |> Map.delete("action_sha256")
      |> Map.put("kind", "managed_accepted_decision_expiry")
      |> Map.put("metadata", metadata)

    before = File.read!(Path.join([c.root, c.project, "control.json"]))

    for changed <- [
          Map.put(metadata, "category", "pin"),
          Map.put(metadata, "management_target", "literal_source"),
          Map.put(metadata, "valid_until_ms", nil),
          Map.put(metadata, "valid_until_ms", c.now + 1),
          Map.put(metadata, "extra", true)
        ] do
      facts = body |> Map.put("metadata", changed) |> seal()
      selected = %{c | facts: facts, request: request(facts, c.request["artifact_sha256"])}

      assert {:error, :consent_management_refused} =
               call(selected, fn -> flunk("invalid accepted expiry") end)

      assert File.read!(Path.join([c.root, c.project, "control.json"])) == before
    end

    facts = seal(body)
    requested = request(facts, c.request["artifact_sha256"])

    for changed <- [
          Map.put(requested, "headless", true),
          Map.put(requested, "operation", "collection.retention"),
          put_in(requested, ["reserved", "model_calls"], 1),
          put_in(requested, ["reserved", "download_bytes"], 1)
        ] do
      assert {:error, :consent_management_refused} =
               call(%{c | facts: facts, request: changed}, fn ->
                 flunk("widened accepted expiry")
               end)

      assert File.read!(Path.join([c.root, c.project, "control.json"])) == before
    end

    for category <- ~w(ordinary preference current) do
      facts =
        body
        |> Map.put("operation_id", Usage.id())
        |> put_in(["metadata", "category"], category)
        |> seal()

      selected = %{c | facts: facts, request: request(facts, c.request["artifact_sha256"])}

      assert {:ok, packet} =
               call(selected, fn -> {:ok, selected.request["reserved"], receipt(facts)} end)

      assert {:error, :consent_management_refused} =
               call(selected, fn -> flunk("replayed accepted expiry") end)

      assert {:ok, _} =
               Consent.settle(
                 c.root,
                 c.project,
                 packet["ticket"],
                 {:known, packet["actual"], packet["receipt"]}
               )
    end
  end

  defp call(c, fun),
    do: Consent.expire_deferred(c.root, c.project, 2, c.request, c.facts, c.now, fun)

  defp seal(body), do: Map.put(body, "action_sha256", JSON.digest([body]))

  defp request(facts, artifact) do
    %{
      "id" => facts["operation_id"],
      "operation" => "collection.expire",
      "artifact_sha256" => artifact,
      "source_sha256" => JSON.digest([facts]),
      "policy_sha256" => facts["context"]["management_sha256"],
      "request_sha256" => facts["action_sha256"],
      "source_generation" => 1,
      "headless" => false,
      "reserved" =>
        Map.merge(Consent.zero(), %{
          "operations" => 1,
          "input_bytes" => 65_536,
          "output_bytes" => 16_384
        })
    }
  end

  defp receipt(facts) do
    normalized = %{
      "version" => 3,
      "kind" => facts["kind"],
      "action_sha256" => facts["action_sha256"],
      "eligibility" => "expired",
      "first_admitted_ms" => facts["metadata"]["first_admitted_ms"],
      "valid_until_ms" => facts["expired_at_ms"],
      "checked_at_ms" => facts["checked_at_ms"],
      "policy_sha256" => facts["metadata"]["policy_sha256"]
    }

    %{
      "action_sha256" => facts["action_sha256"],
      "publication" => %{
        "normalization" => normalized,
        "binding" => %{"normalization_sha256" => JSON.digest([normalized])}
      }
    }
  end
end
