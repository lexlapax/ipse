Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.ManagedReadsTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Session.{ManagedReads, ManagedReference}
  alias Ipse.Test.ManagedPolicy, as: F
  @error {:error, :managed_read_refused}

  test "only absence keeps legacy layout; an explicit null or unknown marker refuses" do
    assert {:ok, nil} = ManagedReads.marker(%{})
    layout = ManagedReads.layout()
    assert {:ok, ^layout} = ManagedReads.marker(%{"managed_read_layout" => layout})

    for value <- [nil, false, 1, "unknown", %{}] do
      assert @error = ManagedReads.marker(%{"managed_read_layout" => value})
    end
  end

  setup do
    id = Usage.id()

    pin =
      Map.new(
        ~w(project_id worktree_id binding_sha256 policy_sha256 identity_sha256 routes_sha256 source_sha256),
        &{&1, JSON.sha256(&1)}
      )
      |> Map.merge(%{
        "version" => 1,
        "session_id" => id,
        "epoch" => 4,
        "namespace" => JSON.sha256("collection")
      })

    parent = %{
      "invocation_id" => Usage.id(),
      "descriptor" => %{"stage" => "invoke.tool", "id" => "inspect"}
    }

    policy = F.policy()

    mapping = %{
      "class" => "collection.read",
      "operation" => "notes.read",
      "inner_op" => "collection.call",
      "outer_sha256" => JSON.digest([parent["descriptor"]]),
      "managed_read" => Enum.sort(Map.keys(policy["settings"]["recipes"]))
    }

    admission = %{"policy" => put_in(policy, ["settings", "effects"], [mapping])}
    config = %{managed_read_layout: ManagedReads.layout(), semantic_admission: admission}

    intent = %{
      "type" => "extension_action_intent",
      "version" => 2,
      "operation_id" => Usage.id(),
      "parent_invocation_id" => parent["invocation_id"],
      "request" => %{"op" => "collection.call", "request" => %{"op" => "get", "key" => "missing"}},
      "effect_binding" => %{"pin" => pin}
    }

    intent = Map.put(intent, "request_sha256", JSON.digest([intent["request"]]))

    value = %{
      "version" => 3,
      "project" => pin["namespace"],
      "generation" => 0,
      "floor" => 0,
      "floor_anchor" => nil,
      "record" => nil
    }

    dependency = %{
      "version" => 3,
      "project_id" => pin["project_id"],
      "namespace" => pin["namespace"],
      "pin_sha256" => JSON.digest([pin]),
      "policy_generation" => pin["epoch"],
      "collection" => %{
        "project" => pin["namespace"],
        "generation" => 0,
        "floor" => 0,
        "floor_anchor" => nil,
        "root_state" => "absent",
        "root_sha256" => nil,
        "manifest_sha256" => nil
      },
      "subject" => %{
        "kind" => "root_observation",
        "request_sha256" => JSON.digest([intent["request"]["request"]]),
        "result_sha256" => JSON.digest([value])
      }
    }

    assert ManagedReference.dependency?(dependency)

    %{
      id: id,
      pin: pin,
      parent: parent,
      config: config,
      intent: intent,
      value: value,
      dependency: dependency
    }
  end

  defp result(c, status \\ "ok", value \\ nil) do
    c.intent
    |> Map.put("type", "extension_action_result")
    |> Map.put("outcome", %{"status" => status, "value" => value || c.value})
  end

  test "exact receipt binds Session, action, request, result, policy and root", c do
    assert {:ok, receipt} = ManagedReads.prepare(c.id, c.intent, c.value, [c.dependency])
    assert ManagedReads.valid?(receipt, c.id, c.intent, c.value)

    assert ManagedReads.covered?(c.config.semantic_admission, c.parent, c.intent, c.value, [
             c.dependency
           ])

    assert {:ok, ^receipt, [dependency]} =
             ManagedReads.bind_result(c.id, c.config, c.parent, receipt, [], result(c))

    assert dependency == c.dependency

    for changed <- [
          Map.put(receipt, "session_id", Usage.id()),
          Map.put(receipt, "operation_id", Usage.id()),
          Map.put(receipt, "result_sha256", JSON.sha256("changed")),
          Map.put(receipt, "extra", true)
        ] do
      refute ManagedReads.valid?(changed, c.id, c.intent, c.value)
    end

    refute ManagedReads.valid?(receipt, c.id, c.intent, %{c.value | "generation" => 1})

    for dependency <- [
          Map.put(c.dependency, "pin_sha256", JSON.sha256("foreign")),
          Map.put(c.dependency, "policy_generation", 5),
          put_in(c.dependency, ["collection", "generation"], 1)
        ] do
      assert @error = ManagedReads.prepare(c.id, c.intent, c.value, [dependency])
    end
  end

  test "accepted records cannot become root-only reads when their recipe is absent", c do
    recipes = c.config.semantic_admission["policy"]["settings"]["recipes"]

    proposal =
      Enum.find_value(recipes, fn {sha, recipe} -> if recipe["kind"] == "proposal", do: sha end)

    admission =
      put_in(
        c.config.semantic_admission,
        ["policy", "settings", "effects", Access.at(0), "managed_read"],
        [proposal]
      )

    for kind <- ~w(accepted_decision candidate_acceptance_link) do
      record = %{"key" => "note." <> JSON.sha256(kind), "value" => %{"kind" => kind}}
      value = Map.put(c.value, "record", record)

      refute ManagedReads.covered?(admission, c.parent, c.intent, value, [c.dependency])
    end

    ordinary = %{"key" => "other", "value" => %{"kind" => "ordinary"}}

    assert ManagedReads.covered?(
             admission,
             c.parent,
             c.intent,
             Map.put(c.value, "record", ordinary),
             [c.dependency]
           )
  end

  test "new layout requires a prepared observation before a successful managed read", c do
    assert @error = ManagedReads.bind_result(c.id, c.config, c.parent, nil, [], result(c))

    assert {:ok, nil, []} =
             ManagedReads.bind_result(
               c.id,
               %{c.config | managed_read_layout: nil},
               c.parent,
               nil,
               [],
               result(c)
             )

    assert {:ok, nil, []} =
             ManagedReads.bind_result(
               c.id,
               c.config,
               c.parent,
               nil,
               [],
               result(c, "failed", %{"code" => "collection_source_refused"})
             )

    assert @error = ManagedReads.prepare(c.id, c.intent, c.value, [])
  end

  test "canonical complete read union retains every successful observation", c do
    assert {:ok, receipt} = ManagedReads.prepare(c.id, c.intent, c.value, [c.dependency])
    old = put_in(c.dependency, ["subject", "request_sha256"], JSON.sha256("prior request"))

    assert {:ok, ^receipt, union} =
             ManagedReads.bind_result(c.id, c.config, c.parent, receipt, [old], result(c))

    assert Enum.sort(union) == Enum.sort([old, c.dependency])

    assert {:ok, ^receipt, ^union} =
             ManagedReads.bind_result(c.id, c.config, c.parent, receipt, union, result(c))
  end

  test "a literal result needs its own recipe and exact source versions, not only a root", c do
    # A trusted-function fixture; native endorsement is covered by the CLI suite.
    proof = F.proof()
    assert {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(proof)

    value = %{
      "lineage" => lineage,
      "text" => proof["quote"],
      "category" => "ordinary",
      "evidence" => %{"sources" => [proof]}
    }

    bytes = Ipse.Extension.Collection.Migration.encode(value)

    record = %{
      "key" => "note." <> lineage,
      "revision" => 1,
      "operation_id" => Usage.id(),
      "value" => value,
      "bytes" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes)
    }

    result_value = %{c.value | "record" => record, "generation" => 1}
    intent = put_in(c.intent, ["request", "request", "key"], record["key"])
    intent = Map.put(intent, "request_sha256", JSON.digest([intent["request"]]))

    recipe =
      c.config.semantic_admission["policy"]["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    dependency =
      c.dependency
      |> Map.put("version", 4)
      |> Map.put(
        "collection",
        Map.merge(c.dependency["collection"], %{
          "generation" => 1,
          "root_state" => "present",
          "root_sha256" => JSON.sha256("root"),
          "manifest_sha256" => JSON.sha256("manifest")
        })
      )
      |> Map.put("subject", %{
        "kind" => "record_observation",
        "key" => record["key"],
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => record["key"]}]),
        "result_sha256" => JSON.digest([%{"record" => record}]),
        "publication_policy_sha256" => JSON.sha256("publication"),
        "record" => %{"key" => record["key"], "revision" => 1, "value_sha256" => record["sha256"]},
        "validity" => %{
          "recipe_sha256" => JSON.digest([recipe]),
          "lineage" => lineage,
          "status" => "eligible",
          "valid_until_ms" => 1_000_000,
          "source_versions" => [
            %{"id" => proof["occurrence_id"], "version" => proof["version_id"]}
          ],
          "dependencies" => []
        }
      })

    assert ManagedReference.dependency?(dependency)
    assert {:ok, _} = ManagedReads.prepare(c.id, intent, result_value, [dependency])

    assert ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [
             dependency
           ])

    refute ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [])

    changed =
      put_in(dependency, ["subject", "validity", "source_versions"], [
        %{"id" => proof["occurrence_id"], "version" => Usage.id()}
      ])

    refute ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [
             changed
           ])

    refute ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [
             c.dependency
           ])
  end

  test "an accepted read binds its decision, immutable link, original source and deadline", c do
    proof = F.proof()
    lineage = JSON.sha256("accepted lineage")
    candidate = JSON.sha256("candidate")
    event_sha = JSON.sha256("native acceptance event")
    link_sha = JSON.sha256("immutable acceptance link")

    recipe =
      c.config.semantic_admission["policy"]["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    value = %{
      "kind" => "accepted_decision",
      "candidate_id" => candidate,
      "lineage" => lineage,
      "source_proof" => proof,
      "acceptance_event_sha256" => event_sha,
      "acceptance_link_sha256" => link_sha,
      "valid_until_ms" => 1_000_000
    }

    bytes = Ipse.Extension.Collection.Migration.encode(value)

    record = %{
      "key" => "note." <> lineage,
      "revision" => 1,
      "operation_id" => Usage.id(),
      "value" => value,
      "bytes" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes)
    }

    result_value = %{c.value | "record" => record, "generation" => 1}
    intent = put_in(c.intent, ["request", "request", "key"], record["key"])
    intent = Map.put(intent, "request_sha256", JSON.digest([intent["request"]]))
    link = %{"key" => "accept." <> candidate, "revision" => 1, "value_sha256" => link_sha}

    dependency =
      c.dependency
      |> Map.put("version", 6)
      |> Map.put(
        "collection",
        Map.merge(c.dependency["collection"], %{
          "generation" => 1,
          "root_state" => "present",
          "root_sha256" => JSON.sha256("root"),
          "manifest_sha256" => JSON.sha256("manifest")
        })
      )
      |> Map.put("subject", %{
        "kind" => "accepted_decision_observation",
        "key" => record["key"],
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => record["key"]}]),
        "result_sha256" => JSON.digest([%{"record" => record}]),
        "publication_policy_sha256" => JSON.sha256("publication policy"),
        "record" => %{"key" => record["key"], "revision" => 1, "value_sha256" => record["sha256"]},
        "validity" => %{
          "recipe_sha256" => JSON.digest([recipe]),
          "lineage" => lineage,
          "status" => "eligible",
          "valid_until_ms" => value["valid_until_ms"],
          "source_versions" => [
            %{"id" => proof["occurrence_id"], "version" => proof["version_id"]}
          ],
          "dependencies" => [link]
        },
        "acceptance" => %{
          "journal_id" => Usage.id(),
          "journal_kind" => "knowledge_management",
          "event_sha256" => event_sha,
          "link" => link
        }
      })

    # Receipt consistency alone grants no current source or native acceptance authority.
    assert ManagedReference.dependency?(dependency)
    assert {:ok, _} = ManagedReads.prepare(c.id, intent, result_value, [dependency])

    retained =
      dependency
      |> put_in(["subject", "validity", "valid_until_ms"], nil)
      |> put_in(["subject", "acceptance", "retention"], %{
        "version" => 1,
        "kind" => "native_retention_choice",
        "choice_sha256" => JSON.sha256("synthetic authenticated-choice commitment"),
        "policy" => %{"kind" => "pin"},
        "observed_at_ms" => 1000
      })

    assert ManagedReference.dependency?(retained)
    assert {:ok, _} = ManagedReads.prepare(c.id, intent, result_value, [retained])

    assert ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [
             retained
           ])

    for invalid <- [
          put_in(retained, ["subject", "acceptance", "retention", "choice_sha256"], "unverified"),
          put_in(retained, ["subject", "acceptance", "retention", "policy"], %{
            "kind" => "session"
          }),
          put_in(retained, ["subject", "validity", "valid_until_ms"], 999_999)
        ] do
      refute ManagedReference.dependency?(invalid)

      refute ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [
               invalid
             ])
    end

    assert ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [
             dependency
           ])

    for changed <- [
          put_in(
            dependency,
            ["subject", "acceptance", "event_sha256"],
            JSON.sha256("another event")
          ),
          put_in(dependency, ["subject", "validity", "valid_until_ms"], 999_999),
          put_in(
            dependency,
            ["subject", "validity", "source_versions", Access.at(0), "version"],
            Usage.id()
          ),
          c.dependency
        ] do
      refute ManagedReads.covered?(c.config.semantic_admission, c.parent, intent, result_value, [
               changed
             ])
    end
  end
end
