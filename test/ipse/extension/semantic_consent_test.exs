defmodule Ipse.Extension.SemanticConsentTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{SemanticConsent, Mode, Consent}
  alias Ipse.Config.Semantics
  alias Ipse.JSON
  @now 100_000

  setup do
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
      "capabilities" => ~w(invoke.tool host.actions host.state.read),
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
      "class" => "collection.publish",
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
  end

  test "exact reviewed policy and host effect produce a finite headless reservation", c do
    assert Consent.valid_policy?(c.policy)

    assert {:ok, request} =
             SemanticConsent.authorize(c.pin, c.snapshot, c.context, c.effect, @now)

    assert request["headless"] == true
    assert request["artifact_sha256"] == c.identity["artifact_sha256"]
    assert request["policy_sha256"] == JSON.digest([c.policy])
    assert request["reserved"] == c.effect["reserved"]
    refute Map.has_key?(request, "class")
  end

  test "reviewed publication constraints stay policy-owned and base mappings remain unique", c do
    constraints = %{
      "version" => 1,
      "key_prefix" => "note.",
      "value_schema" => %{
        "type" => "object",
        "properties" => %{"evidence" => %{"type" => "array", "items" => %{"type" => "string"}}},
        "required" => ["evidence"],
        "additionalProperties" => false
      },
      "evidence_path" => ["evidence"],
      "source_categories" => ["typed_host_outcome"],
      "allow_delete" => false
    }

    [base] = c.selection["effects"]
    mapping = Map.put(base, "constraints", constraints)
    assert Ipse.Extension.CollectionPolicy.valid_constraints?(constraints)

    assert {:ok, policy} =
             SemanticConsent.prepare(c.binding, c.identity, %{
               c.selection
               | "effects" => [mapping]
             })

    snapshot = %{c.snapshot | "policy" => policy}
    assert {:ok, pin} = SemanticConsent.admit(snapshot, c.context, @now)
    assert {:ok, _} = SemanticConsent.authorize(pin, snapshot, c.context, c.effect, @now)

    assert {:error, _} =
             SemanticConsent.authorize(
               pin,
               snapshot,
               c.context,
               Map.put(c.effect, "constraints", constraints),
               @now
             )

    for mappings <- [
          [Map.put(mapping, "constraints", %{})],
          [Map.put(mapping, "class", "collection.read")],
          [mapping, Map.put(mapping, "constraints", %{constraints | "allow_delete" => true})],
          [base, mapping]
        ] do
      assert {:error, _} =
               SemanticConsent.prepare(c.binding, c.identity, %{
                 c.selection
                 | "effects" => mappings
               })
    end
  end

  test "enable after Session creation never upgrades an absent pin, including on resume", c do
    assert {:ok, nil} = SemanticConsent.admit(%{c.snapshot | "policy" => nil}, c.context, @now)
    assert {:ok, nil} = SemanticConsent.resume(nil, c.context)
    assert {:error, _} = SemanticConsent.authorize(nil, c.snapshot, c.context, c.effect, @now)
    assert {:ok, _} = SemanticConsent.admit(c.snapshot, c.context, @now)
  end

  test "revoke, replace, epoch float, expiry and altered policy refuse the old Session pin", c do
    for snapshot <- [
          %{c.snapshot | "policy" => nil},
          %{c.snapshot | "epoch" => 3},
          %{c.snapshot | "epoch" => 2.0},
          put_in(c.snapshot, ["policy", "expires_at_ms"], @now),
          put_in(c.snapshot, ["policy", "settings", "retention", "automatic"], 365)
        ] do
      assert {:error, _} = SemanticConsent.authorize(c.pin, snapshot, c.context, c.effect, @now)
    end

    # Revocation does not require rewriting native conversation history.
    assert {:ok, pin} = SemanticConsent.resume(c.pin, c.context)
    assert pin === c.pin
  end

  test "identity, namespace, Session, worktree, binding, concrete model and endpoint are exact",
       c do
    changes = [
      put_in(c.context, ["session_id"], String.duplicate("f", 32)),
      put_in(c.context, ["identity", "artifact_sha256"], hash("replacement")),
      put_in(c.context, ["identity", "options_sha256"], hash("new-options")),
      put_in(c.context, ["namespace"], hash("other")),
      put_in(c.context, ["binding", "worktree_id"], hash("other-tree")),
      put_in(c.context, ["binding", "binding_sha256"], hash("replacement-root")),
      update_in(c.context, ["routes"], fn [r] -> [%{r | "model" => "other"}] end),
      update_in(c.context, ["routes"], fn [r] ->
        [%{r | "endpoint" => "https://example.invalid"}]
      end)
    ]

    for context <- changes do
      assert {:error, _} = SemanticConsent.resume(c.pin, context)
      assert {:error, _} = SemanticConsent.authorize(c.pin, c.snapshot, context, c.effect, @now)
    end
  end

  test "source-window generations change per effect without refreshing Session authority", c do
    context = %{c.context | "source_generation" => 4}
    assert {:ok, _} = SemanticConsent.resume(c.pin, context)
    assert {:error, _} = SemanticConsent.authorize(c.pin, c.snapshot, context, c.effect, @now)
    effect = %{c.effect | "source_generation" => 4}
    assert {:ok, _} = SemanticConsent.authorize(c.pin, c.snapshot, context, effect, @now)
  end

  test "worker labels, unreviewed exports, excluded paths and generated prose cannot self-qualify",
       c do
    for effect <- [
          %{c.effect | "class" => "tool.call"},
          %{c.effect | "inner_op" => "shell"},
          %{c.effect | "outer_sha256" => hash("unreviewed-export")},
          %{c.effect | "sources" => [%{"category" => "assistant_proposal", "path" => nil}]},
          %{c.effect | "sources" => [%{"category" => "unattended_input", "path" => nil}]},
          %{
            c.effect
            | "sources" => [%{"category" => "typed_host_outcome", "path" => "private/key.txt"}]
          },
          %{
            c.effect
            | "sources" => [%{"category" => "typed_host_outcome", "path" => "../private/key.txt"}]
          },
          %{
            c.effect
            | "sources" => [%{"category" => "typed_host_outcome", "path" => "private\\key.txt"}]
          }
        ] do
      assert {:error, _} = SemanticConsent.authorize(c.pin, c.snapshot, c.context, effect, @now)
    end
  end

  test "yes never supplies a grant or overcomes enclosing modes and saved headless opt-out", c do
    for config <- [
          %{approval: :allow, approval_origin: :yes, enclosing_mode: :planning},
          %{approval: :allow, approval_origin: :yes, execution_mode: :read_only},
          %{approval: :allow, approval_origin: :yes, execution_mode: :draft},
          %{approval: :allow, approval_origin: :yes, knowledge_ceiling: :paused},
          %{approval: :deny}
        ] do
      assert {:ok, mode} = Mode.capture(config)

      assert {:error, _} =
               SemanticConsent.authorize(
                 c.pin,
                 c.snapshot,
                 %{c.context | "mode" => mode},
                 c.effect,
                 @now
               )
    end

    assert {:ok, mode} = Mode.capture(%{approval: :allow, approval_origin: :yes})

    assert {:error, _} =
             SemanticConsent.authorize(
               nil,
               c.snapshot,
               %{c.context | "mode" => mode},
               c.effect,
               @now
             )

    policy = %{c.policy | "headless" => false}
    snapshot = %{c.snapshot | "policy" => policy}
    assert {:ok, pin} = SemanticConsent.admit(snapshot, c.context, @now)
    assert {:error, _} = SemanticConsent.authorize(pin, snapshot, c.context, c.effect, @now)

    assert {:ok, yes_headless} =
             Mode.capture(%{approval: :allow, approval_origin: :yes, headless: true})

    assert {:error, _} =
             SemanticConsent.authorize(
               pin,
               snapshot,
               %{c.context | "mode" => yes_headless},
               c.effect,
               @now
             )
  end

  test "finite strict resource vectors refuse floats, overflow, extra counters and model call leakage",
       c do
    for reserved <- [
          Map.put(c.effect["reserved"], "operations", 1.0),
          Map.put(c.effect["reserved"], "operations", 0),
          Map.put(c.effect["reserved"], "input_bytes", 1_000_001),
          Map.put(c.effect["reserved"], "model_calls", 1),
          Map.put(c.effect["reserved"], "other", 1),
          Map.put(c.effect["reserved"], "cost_nanos", 9_007_199_254_740_992)
        ] do
      assert {:error, _} =
               SemanticConsent.authorize(
                 c.pin,
                 c.snapshot,
                 c.context,
                 %{c.effect | "reserved" => reserved},
                 @now
               )
    end
  end

  test "worktree-only grant cannot activate on another reciprocal worktree", c do
    selection =
      put_in(c.selection, ["scope"], %{
        "kind" => "worktree",
        "worktree_id" => c.binding["worktree_id"]
      })

    assert {:ok, policy} = SemanticConsent.prepare(c.binding, c.identity, selection)
    context = put_in(c.context, ["binding", "worktree_id"], hash("another-tree"))
    assert {:error, _} = SemanticConsent.admit(%{c.snapshot | "policy" => policy}, context, @now)
  end

  test "collection namespace is derived from the verified project and operator collection selection",
       c do
    assert {:ok, namespace} = SemanticConsent.namespace(c.binding["project_id"], "notes")
    assert namespace == c.pin["namespace"]
    assert {:ok, other} = SemanticConsent.namespace(c.binding["project_id"], "documents")
    refute other == namespace

    assert {:error, _} =
             SemanticConsent.prepare(c.binding, c.identity, %{
               c.selection
               | "namespace" => hash("caller-chosen")
             })
  end

  test "admission descriptors preserve inactive old Sessions and reconstruct only actual current routes",
       c do
    alias Ipse.Extension.{SemanticAdmission, SemanticRoutes}
    assert {:ok, selectors} = SemanticRoutes.selectors(c.selection["routes"])

    descriptor = %{
      "version" => 1,
      "binding" => c.binding,
      "instance" => "notes",
      "pin" => c.pin,
      "selectors" => selectors,
      "status" => "active"
    }

    config = %{
      provider: :ollama,
      model: "fixture",
      base_url: "http://127.0.0.1:11434",
      extensions: [%{identity: c.identity}],
      approval: :deny,
      approval_origin: :default_headless,
      headless: true,
      semantic_admission: descriptor,
      inference_services: %{"local" => %{"version" => 1, "origins" => ["http://127.0.0.1:11434"]}}
    }

    assert SemanticAdmission.valid?(descriptor, c.context["session_id"])
    assert {:ok, context} = SemanticAdmission.context(config, c.context["session_id"], 4)
    assert context["routes"] == c.context["routes"] and context["source_generation"] == 4

    assert {:ok, inactive} =
             SemanticAdmission.resume(config, "/not-read", c.context["session_id"], nil)

    assert inactive["pin"] == nil and inactive["status"] == "off"
    assert {:ok, ^inactive} = SemanticAdmission.fresh(%{}, "/not-read", c.context["session_id"])

    for changed <- [
          %{descriptor | "version" => 1.0},
          put_in(descriptor, ["binding", "binding_sha256"], hash("wrong")),
          Map.put(descriptor, "extra", true)
        ] do
      refute SemanticAdmission.valid?(changed, c.context["session_id"])
    end

    assert {:error, _} = SemanticAdmission.context(config, String.duplicate("f", 32), 4)

    assert {:error, _} =
             SemanticAdmission.context(%{config | model: "changed"}, c.context["session_id"], 4)
  end

  test "route billing and public fixed query use existing provider registry without leaking credentials",
       c do
    [route] = c.selection["routes"]

    for {provider, endpoint, billing} <- [
          {"demo", "demo://local", "none"},
          {"gemini",
           "https://generativelanguage.googleapis.com/v1beta/models/fixture:streamGenerateContent?alt=sse",
           "api"}
        ] do
      route = %{route | "provider" => provider, "endpoint" => endpoint, "billing_mode" => billing}

      assert {:ok, _} =
               SemanticConsent.prepare(c.binding, c.identity, %{c.selection | "routes" => [route]})

      assert {:error, _} =
               SemanticConsent.prepare(c.binding, c.identity, %{
                 c.selection
                 | "routes" => [%{route | "billing_mode" => "local"}]
               })

      if provider == "gemini" do
        assert {:error, _} =
                 SemanticConsent.prepare(c.binding, c.identity, %{
                   c.selection
                   | "routes" => [%{route | "endpoint" => endpoint <> "&key=private"}]
                 })
      end
    end
  end

  test "local reads use an explicit no-ticket check and only Session read/step/context bounds",
       c do
    mapping = %{
      hd(c.selection["effects"])
      | "class" => "collection.read",
        "operation" => "notes.read"
    }

    selection = %{c.selection | "effects" => [mapping], "limits" => vector(operations: 1)}
    assert {:ok, policy} = SemanticConsent.prepare(c.binding, c.identity, selection)
    snapshot = %{c.snapshot | "policy" => policy}
    assert {:ok, pin} = SemanticConsent.admit(snapshot, c.context, @now)

    effect =
      Map.merge(c.effect, mapping)
      |> Map.put("reserved", Consent.zero())
      |> Map.put("sources", [])

    assert :ok = SemanticConsent.check(pin, snapshot, c.context, effect, @now)

    assert {:error, :semantic_read_requires_check} =
             SemanticConsent.authorize(pin, snapshot, c.context, effect, @now)

    assert {:error, _} = SemanticConsent.check(c.pin, c.snapshot, c.context, c.effect, @now)

    assert {:error, _} =
             SemanticConsent.check(pin, %{snapshot | "epoch" => 3}, c.context, effect, @now)

    assert {:error, _} =
             SemanticConsent.check(
               pin,
               snapshot,
               c.context,
               put_in(effect, ["reserved", "operations"], 1),
               @now
             )
  end

  test "only selected inference can reserve calls and paid calls need a nonzero finite cost allowance",
       c do
    mapping = %{
      (c.selection["effects"]
       |> hd())
      | "class" => "model.complete",
        "inner_op" => "model.complete"
    }

    [route] = c.selection["routes"]

    route = %{
      route
      | "operation" => "model.complete",
        "profile" => "answer",
        "provider" => "openai",
        "endpoint" => "https://api.openai.com/v1/responses",
        "billing_mode" => "api"
    }

    selection = %{
      c.selection
      | "effects" => [mapping],
        "routes" => [hd(c.selection["routes"]), route],
        "limits" => vector(operations: 100, model_calls: 2, input_bytes: 1000, cost_nanos: 100)
    }

    assert {:ok, policy} = SemanticConsent.prepare(c.binding, c.identity, selection)
    snapshot = %{c.snapshot | "policy" => policy}
    context = %{c.context | "routes" => selection["routes"]}
    assert {:ok, pin} = SemanticConsent.admit(snapshot, context, @now)
    effect = Map.merge(c.effect, mapping)
    assert {:error, _} = SemanticConsent.authorize(pin, snapshot, context, effect, @now)
    free = %{effect | "reserved" => vector(operations: 1, model_calls: 1, input_bytes: 100)}
    assert {:error, _} = SemanticConsent.authorize(pin, snapshot, context, free, @now)
    paid = put_in(free, ["reserved", "cost_nanos"], 10)
    assert {:ok, _} = SemanticConsent.authorize(pin, snapshot, context, paid, @now)

    assert {:error, _} =
             SemanticConsent.authorize(
               pin,
               snapshot,
               context,
               %{paid | "class" => "embedding.create", "inner_op" => "embedding.create"},
               @now
             )
  end

  test "operator references require exact current protected policy and cannot be project grants",
       c do
    assert {:ok, selections} = Semantics.selection(c.policy)
    assert Semantics.selected?(selections, "notes", c.policy)
    assert {:ok, pin} = Semantics.admit(selections, c.snapshot, c.context, @now)
    assert pin === c.pin
    assert {:ok, nil} = Semantics.admit(%{}, c.snapshot, c.context, @now)

    assert {:ok, nil} =
             Semantics.admit(
               put_in(selections, ["notes", "enabled"], false),
               c.snapshot,
               c.context,
               @now
             )

    assert {:error, _} = Semantics.admit(%{"notes" => true}, c.snapshot, c.context, @now)

    assert {:ok, ^selections} =
             Semantics.resolve([
               %{scope: "operator", data: %{"semantic_selections" => selections}}
             ])

    for entries <- [selections, %{}] do
      assert {:error, :semantic_configuration_operator_only} =
               Semantics.resolve([
                 %{scope: "project", data: %{"semantic_selections" => entries}}
               ])
    end

    refute Semantics.selected?(put_in(selections, ["notes", "enabled"], false), "notes", c.policy)

    refute Semantics.selected?(
             selections,
             "notes",
             put_in(c.policy, ["limits", "operations"], 101)
           )
  end

  test "closed settings reject unknown fields, invalid endpoints, duplicates and malformed ceilings",
       c do
    for selection <- [
          Map.put(c.selection, "unexpected", true),
          put_in(c.selection, ["retention", "automatic"], 90.0),
          put_in(c.selection, ["sources", "exclusions"], ["../secret"]),
          put_in(c.selection, ["sources", "exclusions"], ["*.env"]),
          put_in(c.selection, ["sources", "exclusions"], ["private//secret"]),
          put_in(c.selection, ["effects"], c.selection["effects"] ++ c.selection["effects"]),
          update_in(c.selection, ["routes"], fn [r] ->
            [%{r | "endpoint" => "http://remote.invalid"}]
          end),
          update_in(c.selection, ["routes"], fn [r] ->
            [%{r | "endpoint" => "https://user:secret@example.invalid"}]
          end),
          update_in(c.selection, ["routes"], fn [r] ->
            [%{r | "endpoint" => "https://example.invalid?token=secret"}]
          end)
        ] do
      assert {:error, _} = SemanticConsent.prepare(c.binding, c.identity, selection)
    end
  end

  test "protected fresh admission pins the actual binding and routes on an admitted filesystem",
       c do
    alias Ipse.Extension.{ProjectIdentity, SemanticAdmission}
    base = Path.join(System.tmp_dir!(), "ipse-semantic-io-" <> Ipse.Usage.id())
    home = Path.join(base, "operator")
    cwd = Path.join(base, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)
    services = %{"local" => %{"version" => 1, "origins" => ["http://127.0.0.1:11434"]}}

    config = %{
      provider: :ollama,
      model: "fixture",
      base_url: "http://127.0.0.1:11434",
      home: home,
      extensions: [%{identity: c.identity}],
      approval: :deny,
      approval_origin: :default_headless,
      headless: true,
      inference_services: services
    }

    case ProjectIdentity.admit(home, cwd, :folder) do
      {:ok, binding} ->
        now = System.system_time(:millisecond)
        {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "notes")
        selection = %{c.selection | "namespace" => namespace, "expires_at_ms" => now + 600_000}
        assert {:ok, policy} = SemanticConsent.prepare(binding, c.identity, selection)
        root = SemanticAdmission.control_root(home)
        assert {:ok, snapshot} = Consent.snapshot(root, binding["project_id"])

        assert {:ok, _} =
                 Consent.replace(root, binding["project_id"], snapshot["epoch"], policy, now)

        assert {:ok, selected} = Semantics.selection(policy)
        config = Map.put(config, :semantic_selections, selected)
        assert {:ok, admission} = SemanticAdmission.fresh(config, cwd, c.context["session_id"])
        assert admission["status"] == "active"
        assert admission["pin"]["session_id"] == c.context["session_id"]
        assert admission["pin"]["namespace"] == namespace
        assert SemanticAdmission.valid?(admission, c.context["session_id"])

        assert {:ok, ^admission} =
                 SemanticAdmission.resume(config, cwd, c.context["session_id"], admission)

        assert {:ok, current} = Consent.snapshot(root, binding["project_id"])
        assert {:ok, _} = Consent.revoke(root, binding["project_id"], current["epoch"])
        assert {:ok, refused} = SemanticAdmission.fresh(config, cwd, String.duplicate("d", 32))
        assert refused["pin"] == nil and refused["status"] == "permission_missing"

        assert {:ok, ^admission} =
                 SemanticAdmission.resume(config, cwd, c.context["session_id"], admission)

        IO.puts("semantic admission IO profile: active branch verified")

      {:error, :project_identity_filesystem_unsupported} ->
        config =
          Map.put(config, :semantic_selections, %{
            "notes" => %{
              "version" => 1,
              "project" => c.binding["project_id"],
              "policy_sha256" => JSON.digest([c.policy]),
              "enabled" => true
            }
          })

        assert {:ok, inactive} = SemanticAdmission.fresh(config, cwd, c.context["session_id"])
        assert inactive["pin"] == nil and inactive["status"] == "identity_unavailable"

        IO.puts(
          "semantic admission IO profile: unsupported branch verified; active grant unverified"
        )

      other ->
        flunk("Unexpected protected identity admission: #{inspect(other)}")
    end
  end

  test "every mixed source row is checked and a strong row never upgrades another", c do
    good = hd(c.effect["sources"])

    for rows <- [
          [],
          List.duplicate(good, 65),
          [good, %{"category" => "assistant_proposal", "path" => nil}],
          [good, %{"category" => "typed_host_outcome", "path" => "private/key"}],
          [Map.put(good, "owner", "operator")]
        ] do
      assert {:error, _} =
               SemanticConsent.authorize(
                 c.pin,
                 c.snapshot,
                 c.context,
                 %{c.effect | "sources" => rows},
                 @now
               )
    end

    assert {:ok, _} =
             SemanticConsent.authorize(
               c.pin,
               c.snapshot,
               c.context,
               %{c.effect | "sources" => List.duplicate(good, 64)},
               @now
             )
  end

  defp hash(s), do: JSON.sha256(s)

  defp vector(values),
    do: Map.merge(Consent.zero(), Map.new(values, fn {k, v} -> {Atom.to_string(k), v} end))
end
