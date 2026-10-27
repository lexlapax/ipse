Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Extension.SemanticConsentV2Test do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{SemanticConsent, Consent}
  alias Ipse.Test.ManagedPolicy, as: F

  test "explicit v2 prepare, Session pin and exact managed effect cannot be promoted through v1" do
    policy = F.policy()
    selection = Map.drop(policy["settings"], ~w(instance identity_sha256))

    selection =
      Map.merge(selection, Map.take(policy, ~w(limits period_ms expires_at_ms headless)))

    identity = F.identity()
    assert Ipse.Extension.Registry.valid_identity?(identity)
    assert {:ok, prepared} = SemanticConsent.prepare(F.binding(), identity, selection)
    assert prepared["settings"]["version"] === 2
    assert prepared["settings"]["identity_sha256"] == F.hash(identity)

    assert {:error, _} =
             SemanticConsent.prepare(F.binding(), identity, Map.delete(selection, "version"))

    assert {:error, _} =
             SemanticConsent.prepare(F.binding(), identity, Map.put(selection, "version", 1))

    assert {:ok, mode} =
             Ipse.Extension.Mode.capture(%{
               approval: :deny,
               approval_origin: :default_headless,
               headless: true
             })

    context = %{
      "session_id" => String.duplicate("a", 32),
      "binding" => F.binding(),
      "identity" => identity,
      "namespace" => prepared["settings"]["namespace"],
      "routes" => prepared["settings"]["routes"],
      "mode" => mode,
      "source_generation" => 1
    }

    snapshot = %{"epoch" => 1, "policy" => prepared}
    assert {:ok, pin} = SemanticConsent.admit(snapshot, context, 1000)
    mapping = Enum.find(prepared["settings"]["effects"], &(&1["operation"] == "notes.save"))
    effect = Map.take(mapping, ~w(operation class outer_sha256 inner_op))

    effect =
      Map.merge(effect, %{
        "id" => String.duplicate("b", 32),
        "request_sha256" => F.hash("original request"),
        "source_generation" => 1,
        "sources" => [%{"category" => "interactive_operator", "path" => nil}],
        "reserved" => Map.merge(Consent.zero(), %{"operations" => 1, "input_bytes" => 1000})
      })

    assert {:ok, reservation} = SemanticConsent.authorize(pin, snapshot, context, effect, 1000)
    assert reservation["request_sha256"] == effect["request_sha256"]

    assert {:error, _} =
             SemanticConsent.authorize(
               pin,
               snapshot,
               context,
               Map.put(effect, "recipe_sha256", mapping["recipe_sha256"]),
               1000
             )

    assert {:error, _} =
             SemanticConsent.authorize(pin, %{snapshot | "epoch" => 2}, context, effect, 1000)

    assert {:ok, ^pin} = SemanticConsent.resume(pin, context)
  end

  test "actual native note/proposal schemas and deduplicated mappings fit existing settings limits" do
    policy = F.policy()
    settings = policy["settings"]
    assert SemanticConsent.settings?(settings)
    assert SemanticConsent.policy?(policy)
    assert Consent.valid_policy?(policy)
    assert byte_size(Jason.encode!(settings)) <= 16_384
    assert {:ok, ^settings} = Ipse.JSON.decode_unique(Jason.encode!(settings), 12)
    assert map_size(settings["constraints"]) == 2
    assert map_size(settings["recipes"]) == 2

    for mapping <- settings["effects"] do
      case mapping["class"] do
        "collection.publish" ->
          assert {:ok, constraint} = SemanticConsent.constraints(settings, mapping)
          assert {:ok, recipe} = SemanticConsent.recipe(settings, mapping)
          assert recipe["constraints_sha256"] == F.hash(constraint)

        "collection.read" ->
          assert {:ok, recipes} = SemanticConsent.managed_recipes(settings, mapping)
          assert length(recipes) == 2
      end
    end
  end

  test "missing, aliased, unreferenced, mixed-version and ambiguous registries refuse" do
    settings = F.policy()["settings"]
    [key | _] = Map.keys(settings["constraints"])
    [rkey | _] = Map.keys(settings["recipes"])

    for invalid <- [
          Map.delete(settings, "activation"),
          Map.put(settings, "version", 1),
          put_in(settings, ["constraints"], Map.delete(settings["constraints"], key)),
          put_in(settings, ["constraints", F.hash("alias")], settings["constraints"][key]),
          put_in(settings, ["recipes", rkey, "key_prefix"], "foreign."),
          update_in(settings["effects"], &(&1 ++ [hd(&1)])),
          put_in(settings, ["effects", Access.at(0), "inner_op"], "collection.call"),
          put_in(settings, ["effects", Access.at(0), "constraints"], settings["constraints"][key])
        ],
        do: refute(SemanticConsent.settings?(invalid))

    helper = %{
      "operation" => "arbitrary",
      "class" => "model.complete",
      "outer_sha256" => F.hash("outer"),
      "inner_op" => "model.complete"
    }

    refute SemanticConsent.settings?(Map.put(settings, "effects", [helper]))
  end

  test "managed read refs must be sorted unique and all exact registry members" do
    settings = F.policy()["settings"]
    index = Enum.find_index(settings["effects"], &(&1["class"] == "collection.read"))
    mapping = Enum.at(settings["effects"], index)
    [first | _] = mapping["managed_read"]

    for refs <- [
          [],
          first,
          [first, first],
          Enum.reverse(mapping["managed_read"]),
          [F.hash("missing")]
        ] do
      bad = put_in(settings, ["effects", Access.at(index), "managed_read"], refs)
      refute SemanticConsent.settings?(bad)
      assert {:error, _} = SemanticConsent.managed_recipes(bad, Enum.at(bad["effects"], index))
    end
  end

  test "activation must match exact policy artifact and instance and cannot widen settings size" do
    policy = F.policy()
    refute SemanticConsent.policy?(put_in(policy, ["artifact_sha256"], F.hash("foreign")))

    refute SemanticConsent.policy?(
             put_in(policy, ["settings", "activation", "instance"], "other")
           )

    assert SemanticConsent.policy?(put_in(policy, ["settings", "activation"], nil))

    oversized =
      put_in(
        policy,
        ["settings", "sources", "exclusions"],
        Enum.map(0..63, &("long/" <> String.duplicate("a", 256) <> "/#{&1}"))
      )

    oversized = put_in(oversized, ["source_sha256"], F.hash(oversized["settings"]["sources"]))
    refute SemanticConsent.policy?(oversized)
  end
end
