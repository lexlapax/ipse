Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Extension.ActivationTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Activation
  alias Ipse.Test.ManagedPolicy, as: F
  @base %{"instances" => [], "trust" => []}

  test "pure overlay adds exact operator data without preparing identity or mutating base configuration" do
    policy = F.policy()
    assert :ok = Activation.validate(F.activation())
    assert {:ok, result} = Activation.derive(policy, @base)
    [instance] = result.catalog["instances"]
    [trust] = result.catalog["trust"]
    assert instance["scope"] == "operator"
    assert instance["source"] == result.source
    assert instance["options"] == F.activation()["options"]
    assert trust["allow_children"] == false
    assert trust["allow_project"] == false
    refute Map.has_key?(instance, "identity")
    refute Map.has_key?(result, :identity)
    assert @base == %{"instances" => [], "trust" => []}
    altered_epoch = Map.put(policy, "untrusted_epoch", 99)
    assert {:error, _} = Activation.derive(altered_epoch, @base)
  end

  test "saved activation derives independently of current enable or revocation" do
    saved = F.policy()
    current = put_in(saved, ["settings", "activation"], nil)
    assert {:ok, old} = Activation.derive(saved, @base)
    assert {:error, _} = Activation.derive(current, @base)
    assert {:ok, ^old} = Activation.derive(saved, @base)

    assert {:error, _} =
             Activation.derive(
               Map.put(
                 saved,
                 "settings",
                 Map.drop(saved["settings"], ~w(constraints recipes activation))
               ),
               @base
             )
  end

  test "collisions, definition injection, child widening and mixed service refs refuse" do
    a = F.activation()

    for invalid <- [
          Map.put(a, "provider", "fallback"),
          Map.put(a, "allow_children", true),
          Map.put(a, "lifetime", "persistent"),
          Map.put(a, "artifact", "builtin:any:1"),
          Map.put(a, "options", %{"value" => String.duplicate("x", 1025)}),
          Map.put(a, "service_refs", [
            %{
              "operation" => "main",
              "service_id" => "fixture",
              "profile" => nil,
              "endpoint" => "https://other"
            }
          ]),
          Map.put(a, "capabilities", Enum.reverse(a["capabilities"]))
        ],
        do: assert({:error, _} = Activation.validate(invalid))

    policy = F.policy()

    for base <- [
          %{@base | "instances" => [%{"instance" => "knowledge"}]},
          %{@base | "trust" => [%{"artifact" => a["artifact"]}]}
        ],
        do: assert({:error, _} = Activation.derive(policy, base))

    changed =
      put_in(
        policy,
        ["settings", "activation", "service_refs", Access.at(0), "service_id"],
        "other"
      )

    refute Ipse.Extension.SemanticConsent.policy?(changed)
    assert {:error, _} = Activation.derive(changed, @base)
  end
end
