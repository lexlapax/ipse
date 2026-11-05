defmodule Ipse.Extension.ConsentBudgetTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{Consent, CollectionCall, Actions, SemanticConsent, Mode}
  alias Ipse.JSON

  defp vector(values \\ []),
    do: Map.merge(Consent.zero(), Map.new(values, fn {k, v} -> {Atom.to_string(k), v} end))

  defp hash(value), do: JSON.sha256(value)

  defp request,
    do: %{
      "op" => "collection.call",
      "purpose" => "saved_policy_budget_v1",
      "request" => %{"op" => "status"}
    }

  defp policy,
    do: %{
      "limits" => vector(operations: 100, input_bytes: 1000),
      "period_ms" => 1000,
      "private" => "private-policy-canary"
    }

  defp state(operations, compacted \\ %{}),
    do: %{
      "epoch" => 1,
      "policy" => policy(),
      "operations" => operations,
      "compacted" => compacted
    }

  defp operation(status, created, actual, reserved),
    do: %{
      "status" => status,
      "created_at_ms" => created,
      "actual" => actual,
      "reserved" => reserved,
      "receipt" => "private-receipt-canary"
    }

  defp used(n),
    do:
      state(%{
        "private-operation-canary" => operation("settled", 1000, vector(operations: n), vector())
      })

  test "charged balance uses the same current settled, compacted and all-period nonterminal accounting" do
    operations = %{
      "now" => operation("settled", 1100, vector(operations: 3, input_bytes: 7), vector()),
      "old" => operation("settled", 999, vector(operations: 9, input_bytes: 99), vector()),
      "unknown" => operation("unknown", 800, vector(), vector(operations: 2, input_bytes: 8)),
      "publishing" =>
        operation("publishing", 900, vector(), vector(operations: 1, input_bytes: 9)),
      "old-reconciled" => operation("reconciled_overrun", 900, vector(operations: 20), vector())
    }

    compacted = %{
      "current" => [
        1,
        1,
        hash("private-request"),
        1000,
        "settled",
        [5, 0, 11, 0, 0, 0],
        hash("private-receipt")
      ],
      "old" => [
        2,
        1,
        hash("private-request"),
        999,
        "settled",
        [100, 0, 100, 0, 0, 0],
        hash("private-receipt")
      ]
    }

    s = state(operations, compacted)
    assert {:ok, budget} = Consent.budget_summary(s, 1500)
    assert budget["charged"] == vector(operations: 11, input_bytes: 35)
    assert budget["nonterminal_reserved"] == vector(operations: 3, input_bytes: 17)
    assert budget["unknown_reserved"] == vector(operations: 2, input_bytes: 8)
    assert budget["period_start_ms"] == 1000 and budget["period_end_ms"] == 2000
    assert {:ok, next} = Consent.budget_summary(s, 2000)
    assert next["charged"] == vector(operations: 3, input_bytes: 17)
    assert next["unknown_reserved"] == budget["unknown_reserved"]
  end

  test "integer warning and exhaustion boundaries do not treat unused zero dimensions as exhausted" do
    for {n, warning, exhausted} <- [
          {79, [], []},
          {80, ["operations"], []},
          {99, ["operations"], []},
          {100, ["operations"], ["operations"]},
          {101, ["operations"], ["operations"]}
        ] do
      assert {:ok, v} = Consent.budget_summary(used(n), 1500)
      assert v["warning_dimensions"] == warning
      assert v["exhausted_dimensions"] == exhausted
      assert v["available"]["operations"] == max(100 - n, 0)
      assert v["available"]["model_calls"] == 0
    end

    s = state(%{"unknown" => operation("unknown", 0, vector(), vector(model_calls: 1))})
    assert {:ok, v} = Consent.budget_summary(s, 1500)
    assert v["warning_dimensions"] == [] and v["exhausted_dimensions"] == ["model_calls"]
  end

  test "the pure snapshot contains bounded accounting metadata and no raw protected ledger fields" do
    assert {:ok, v} = Consent.budget_summary(used(80), 1500)
    assert Consent.valid_budget_summary?(v)
    encoded = Jason.encode!(v)
    assert byte_size(encoded) < 2048

    for secret <- ~w(private-policy-canary private-operation-canary private-receipt-canary),
        do: refute(String.contains?(encoded, secret))

    for field <-
          ~w(policy operations compacted receipts settings routes credentials quarantine service_quarantine),
        do: refute(Map.has_key?(v, field))

    assert v["scope"] == "saved_policy" and v["policy_sha256"] == JSON.digest([policy()])
  end

  test "malformed accounting metadata cannot be presented as a budget fact" do
    assert {:ok, v} = Consent.budget_summary(used(80), 1500)

    for bad <- [
          Map.put(v, "operation_ids", []),
          Map.put(v, "epoch", 0),
          Map.put(v, "observed_at_ms", 2000),
          put_in(v, ["available", "operations"], 21),
          put_in(v, ["charged", "operations"], -1),
          put_in(v, ["unknown_reserved", "operations"], 1),
          Map.put(v, "warning_dimensions", []),
          Map.put(v, "policy_sha256", "bad"),
          Map.put(v, "period_start_ms", 1501)
        ] do
      refute Consent.valid_budget_summary?(bad)
    end

    assert {:error, :consent_read_refused} =
             Consent.budget_summary(
               state(%{
                 "overrun" =>
                   operation("overrun", 1000, vector(operations: 2), vector(operations: 1))
               }),
               1500
             )

    assert {:error, :consent_read_refused} = Consent.budget_summary(%{}, 1500)
  end

  test "only the exact read-only status purpose is admitted and ordinary status is unchanged" do
    assert :ok = CollectionCall.validate(request())
    assert Actions.capability(request()) == "host.collection.read"
    refute CollectionCall.mutating?(request())
    assert :ok = Actions.validate_operation(request())

    for bad <- [
          Map.put(request(), "home", "/tmp/foreign"),
          Map.put(request(), "now", 1500),
          Map.put(request(), "epoch", 1),
          Map.put(request(), "proofs", []),
          Map.put(request(), "purpose", "other"),
          put_in(request(), ["request", "op"], "snapshot"),
          put_in(request(), ["request", "path"], "foreign"),
          put_in(request(), ["request", "op"], "commit")
        ] do
      assert {:error, _} = CollectionCall.validate(bad)
    end

    assert {:ok, v} = Consent.budget_summary(used(80), 1500)
    value = Map.put(v, "project", hash("namespace"))
    assert CollectionCall.valid_outcome?(request(), "ok", value, nil)
    refute CollectionCall.valid_outcome?(request(), "conflict", value, nil)
    ordinary = Map.delete(request(), "purpose")
    assert :ok = CollectionCall.validate(ordinary)
    refute CollectionCall.valid_outcome?(ordinary, "ok", value, nil)
    refute CollectionCall.valid_outcome?(request(), "ok", Map.put(value, "raw_control", %{}), nil)

    assert CollectionCall.valid_outcome?(
             request(),
             "failed",
             %{"code" => "collection_consent_denied"},
             nil
           )
  end

  test "a recorded observation remains bound to its actual namespace, epoch and policy" do
    assert {:ok, v} = Consent.budget_summary(used(80), 1500)
    namespace = hash("namespace")

    event = %{
      "request" => request(),
      "namespace" => namespace,
      "effect_binding" => %{"pin" => %{"epoch" => 1, "policy_sha256" => v["policy_sha256"]}},
      "outcome" => %{"status" => "ok", "value" => Map.put(v, "project", namespace)}
    }

    assert CollectionCall.bound_outcome?(event)

    for bad <- [
          put_in(event, ["namespace"], hash("foreign")),
          put_in(event, ["effect_binding", "pin", "epoch"], 2),
          put_in(event, ["effect_binding", "pin", "policy_sha256"], hash("changed"))
        ] do
      refute CollectionCall.bound_outcome?(bad)
    end
  end

  # Existing pure semantic admission fixture; these shapes attest no native ownership.

  @now 100_000
  defp semantic_fixture do
    c =
      (
        binding = %{
          "version" => 1,
          "project_id" => hash("project"),
          "worktree_id" => hash("tree"),
          "scope" => "repository",
          "root" => "/fixture/worktree",
          "primary_root" => "/fixture/primary",
          "common_directory" => "/fixture/primary/.git",
          "binding_sha256" => hash("binding")
        }

        identity = %{
          "instance" => "notes",
          "artifact" => hash("artifact"),
          "artifact_sha256" => hash("artifact"),
          "options_sha256" => hash("options"),
          "exports_sha256" => hash("exports"),
          "requires_sha256" => hash("requires"),
          "subscriptions_sha256" => hash("subscriptions"),
          "services" => [],
          "scope" => "operator",
          "source_sha256" => hash("source"),
          "sdk" => 1,
          "protocol" => 1,
          "capabilities" => ~w(invoke.tool host.actions host.collection.read),
          "order" => 1,
          "lifetime" => "session",
          "expires_at" => nil,
          "runtime" => %{
            "architecture" => "fixture",
            "elixir" => "1.18.5",
            "erts" => "15",
            "otp" => "27"
          },
          "host_sha256" => hash("host"),
          "generation" => 1,
          "allow_children" => false
        }

        assert Ipse.Extension.Registry.valid_identity?(identity)

        routes = [
          %{
            "operation" => "main",
            "provider" => "ollama",
            "profile" => nil,
            "model" => "fixture",
            "endpoint" => "http://127.0.0.1:11434/api/chat",
            "service_id" => "local",
            "billing_mode" => "local",
            "processing_region" => nil,
            "storage_region" => nil,
            "cache_retention" => nil,
            "account_controls" => nil
          }
        ]

        mapping = %{
          "operation" => "notes.capture",
          "class" => "collection.read",
          "outer_sha256" => hash("outer"),
          "inner_op" => "collection.call"
        }

        selection = %{
          "domain" => "knowledge",
          "namespace" => elem(SemanticConsent.namespace(binding["project_id"], "notes"), 1),
          "scope" => %{"kind" => "project", "worktree_id" => nil},
          "sources" => %{"categories" => ~w(typed_host_outcome), "exclusions" => ["private/"]},
          "storage" => %{"kind" => "local_collection", "collection" => "notes"},
          "retention" => %{"automatic" => 90, "manual" => 3650},
          "routes" => routes,
          "effects" => [mapping],
          "limits" => vector(operations: 100, input_bytes: 1_000_000),
          "period_ms" => 86_400_000,
          "expires_at_ms" => @now + 1_000_000,
          "headless" => true
        }

        assert {:ok, policy} = SemanticConsent.prepare(binding, identity, selection)
        assert {:ok, mode} = Mode.capture(%{approval: :deny, approval_origin: :default_headless})

        context = %{
          "session_id" => String.duplicate("a", 32),
          "binding" => binding,
          "identity" => identity,
          "namespace" => selection["namespace"],
          "routes" => routes,
          "mode" => mode,
          "source_generation" => 3
        }

        snapshot = %{"epoch" => 2, "policy" => policy}
        assert {:ok, pin} = SemanticConsent.admit(snapshot, context, @now)

        effect =
          Map.merge(mapping, %{
            "id" => String.duplicate("b", 32),
            "request_sha256" => hash("request"),
            "source_generation" => 3,
            "sources" => [%{"category" => "typed_host_outcome", "path" => nil}],
            "reserved" => vector(operations: 1, input_bytes: 100)
          })

        %{
          binding: binding,
          identity: identity,
          selection: selection,
          policy: policy,
          context: context,
          snapshot: snapshot,
          pin: pin,
          effect: effect
        }
      )

    %{c | effect: c.effect |> Map.put("reserved", Consent.zero()) |> Map.put("sources", [])}
  end

  test "normal capability and semantic project, worktree, namespace, artifact and epoch fences remain required" do
    c = semantic_fixture()
    assert :ok = SemanticConsent.check(c.pin, c.snapshot, c.context, c.effect, @now)
    response = %{"api_version" => 1, "kind" => "host_call", "request" => request()}
    assert {:ok, _} = Actions.proposal(response, c.identity)

    assert {:error, _} =
             Actions.proposal(
               response,
               Map.put(c.identity, "capabilities", ~w(invoke.tool host.actions))
             )

    for changed <- [
          put_in(c.context, ["binding", "project_id"], hash("foreign project")),
          put_in(c.context, ["binding", "worktree_id"], hash("foreign worktree")),
          put_in(c.context, ["namespace"], hash("foreign namespace")),
          put_in(c.context, ["identity", "artifact_sha256"], hash("foreign artifact")),
          put_in(c.context, ["source_generation"], 4)
        ] do
      assert {:error, _} = SemanticConsent.check(c.pin, c.snapshot, changed, c.effect, @now)
    end

    assert {:error, _} =
             SemanticConsent.check(
               c.pin,
               Map.put(c.snapshot, "epoch", 3),
               c.context,
               c.effect,
               @now
             )

    assert {:error, _} =
             SemanticConsent.check(
               c.pin,
               Map.put(c.snapshot, "policy", nil),
               c.context,
               c.effect,
               @now
             )

    assert {:error, _} =
             SemanticConsent.check(
               c.pin,
               c.snapshot,
               c.context,
               c.effect,
               c.policy["expires_at_ms"]
             )

    {:ok, selectors} = Ipse.Extension.SemanticRoutes.selectors(c.selection["routes"])

    admission = %{
      "version" => 2,
      "binding" => c.binding,
      "instance" => c.identity["instance"],
      "pin" => c.pin,
      "policy" => c.policy,
      "selectors" => selectors,
      "status" => "active"
    }

    assert {:ok, binding} =
             CollectionCall.binding(%{semantic_admission: admission}, c.identity, request())

    assert CollectionCall.valid_binding?(binding, request(), c.identity, %{
             "semantic_admission" => admission
           })

    refute CollectionCall.valid_binding?(
             put_in(binding, ["pin", "identity_sha256"], hash("foreign")),
             request(),
             c.identity
           )

    refute CollectionCall.valid_binding?(
             binding,
             request(),
             Map.put(c.identity, "artifact_sha256", hash("foreign"))
           )
  end
end
