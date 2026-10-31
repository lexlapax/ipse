defmodule Ipse.Session.OperatorAssertionTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage, Extension}
  alias Ipse.Session.{OperatorAssertion, SourceIndex, DraftAcceptance}
  alias Ipse.Extension.ManagedRecipe

  defp scope do
    Map.new(~w(project_id namespace artifact_sha256 policy_sha256), &{&1, JSON.sha256(&1)})
    |> Map.put("workspace", "/synthetic/work")
  end

  defp reviewed(category \\ "ordinary", text \\ "My timezone is UTC") do
    {:ok, render} = OperatorAssertion.render(Usage.id(), Usage.id(), category, text, scope())
    input = "remember " <> render["code"]
    # A pure receipt fixture, not an actual terminal observation.
    observation = %{
      "version" => 2,
      "event_id" => Usage.id(),
      "display_limit" => 16_777_216,
      "input_limit" => 1_048_576,
      "display_sha256" => JSON.sha256(render["display"]),
      "text_sha256" => JSON.sha256(input)
    }

    {:ok, event} = OperatorAssertion.receipt(render, input, observation)
    {render, input, observation, event}
  end

  defp capture_contract do
    constraint = %{
      "version" => 1,
      "key_prefix" => "note.",
      "value_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{},
        "required" => []
      },
      "evidence_path" => ["evidence", "sources"],
      "source_categories" => ["native_operator_assertion"],
      "allow_delete" => false
    }

    recipe = %{
      "version" => 1,
      "kind" => "literal_source",
      "key_prefix" => "note.",
      "constraints_sha256" => JSON.digest([constraint]),
      "evidence_path" => ["evidence", "sources"],
      "lineage_path" => ["lineage"],
      "text_path" => ["text"],
      "category_path" => ["category"],
      "override_prefix" => "override.",
      "rules" => [
        %{
          "category" => "current",
          "max_age_ms" => nil,
          "origins" => ["native_operator_assertion"]
        },
        %{
          "category" => "ordinary",
          "max_age_ms" => 90 * 86_400_000,
          "origins" => ["native_operator_assertion"]
        },
        %{
          "category" => "preference",
          "max_age_ms" => nil,
          "origins" => ["native_operator_assertion"]
        }
      ]
    }

    descriptor = %{"stage" => "invoke.command", "name" => "ext__knowledge__capture"}

    mapping = %{
      "class" => "collection.publish",
      "inner_op" => "collection.managed",
      "outer_sha256" => JSON.digest([descriptor]),
      "recipe_sha256" => JSON.digest([recipe]),
      "constraints_sha256" => JSON.digest([constraint])
    }

    admission = %{
      "policy" => %{
        "settings" => %{
          "version" => 2,
          "effects" => [mapping],
          "recipes" => %{JSON.digest([recipe]) => recipe},
          "constraints" => %{JSON.digest([constraint]) => constraint}
        }
      }
    }

    {admission, descriptor, recipe, mapping}
  end

  test "native statement review requires the selected capture recipe to match its retention display" do
    {admission, descriptor, recipe, mapping} = capture_contract()
    assert OperatorAssertion.capture_contract?(admission, descriptor)

    for {category, age} <- [
          {"ordinary", 91 * 86_400_000},
          {"ordinary", 1},
          {"current", 1},
          {"preference", 1}
        ] do
      changed =
        Map.update!(recipe, "rules", fn rules ->
          Enum.map(rules, fn rule ->
            if rule["category"] == category, do: Map.put(rule, "max_age_ms", age), else: rule
          end)
        end)

      settings = admission["policy"]["settings"]

      changed_admission =
        put_in(admission, ["policy", "settings"], %{
          settings
          | "recipes" => Map.put(settings["recipes"], JSON.digest([changed]), changed),
            "effects" => [Map.put(mapping, "recipe_sha256", JSON.digest([changed]))]
        })

      assert ManagedRecipe.valid?(changed)
      refute OperatorAssertion.capture_contract?(changed_admission, descriptor)
    end
  end

  test "an unused standard recipe cannot qualify another capture mapping or an ambiguous selection" do
    {admission, descriptor, recipe, mapping} = capture_contract()
    unrelated = %{mapping | "outer_sha256" => JSON.sha256("another export")}

    refute OperatorAssertion.capture_contract?(
             put_in(admission, ["policy", "settings", "effects"], [unrelated]),
             descriptor
           )

    refute OperatorAssertion.capture_contract?(
             put_in(admission, ["policy", "settings", "effects"], [mapping, mapping]),
             descriptor
           )

    refute OperatorAssertion.capture_contract?(
             put_in(admission, ["policy", "settings", "effects"], [
               %{mapping | "inner_op" => "collection.call"}
             ]),
             descriptor
           )

    bad_hash = JSON.sha256("unselected recipe")

    refute OperatorAssertion.capture_contract?(
             put_in(admission, ["policy", "settings", "effects"], [
               %{mapping | "recipe_sha256" => bad_hash}
             ]),
             descriptor
           )

    # Registry lookup still verifies the recipe bytes under the referenced digest.
    refute OperatorAssertion.capture_contract?(
             put_in(
               admission,
               ["policy", "settings", "recipes", JSON.digest([recipe]), "rules"],
               []
             ),
             descriptor
           )
  end

  test "command parsing preserves exact bounded claim bytes and requires an explicit category" do
    assert {:ok, "current", "café 日本語  "} =
             OperatorAssertion.parse_command("/remember current café 日本語  ")

    for input <- [
          "/remember",
          "/remember all claim",
          "/remember current ",
          "/remember ordinary " <> String.duplicate("x", 1025),
          <<"/remember current ", 255>>
        ] do
      assert {:error, :operator_assertion_refused} = OperatorAssertion.parse_command(input)
    end
  end

  test "correction intake binds an exact target and selects a separate native statement category" do
    key = "note." <> JSON.sha256("original target")

    assert {:ok, "ordinary", "café  ", %{"mode" => "ordinary", "target_key" => ^key}} =
             OperatorAssertion.parse_intake("/correct " <> key <> " café  ")

    assert {:ok, "current", "new state", %{"mode" => "temporal", "target_key" => ^key}} =
             OperatorAssertion.parse_intake("/supersede " <> key <> " new state")

    assert {:ok, "ordinary", "unchanged", nil} =
             OperatorAssertion.parse_intake("/remember ordinary unchanged")

    for input <- [
          "/correct note.bad text",
          "/correct " <> key <> " ",
          "/supersede " <> key,
          "/correct " <> key <> " " <> String.duplicate("x", 1025),
          <<"/correct ", 255>>
        ] do
      assert {:error, :operator_assertion_refused} = OperatorAssertion.parse_intake(input)
    end
  end

  test "exact native rendering binds the claim, category, scope, challenge and input receipt" do
    {render, input, observation, event} = reviewed()
    assert OperatorAssertion.valid_event?(event, event["session_id"])
    refute OperatorAssertion.valid_event?(event, Usage.id())

    for changed <- [
          Map.put(event, "text", "different"),
          Map.put(event, "category", "current"),
          put_in(event, ["scope", "namespace"], JSON.sha256("different")),
          Map.put(event, "input", "yes"),
          Map.put(event, "version", 2),
          Map.put(event, "extra", true)
        ] do
      refute OperatorAssertion.valid_event?(changed, event["session_id"])
    end

    assert {:error, :operator_assertion_refused} =
             OperatorAssertion.receipt(render, "yes", observation)

    assert {:error, :operator_assertion_refused} =
             OperatorAssertion.receipt(
               render,
               input,
               Map.put(observation, "display_sha256", JSON.sha256("different"))
             )
  end

  test "review renders statement and workspace as literal data" do
    {render, _, _, _} = reviewed("ordinary", "Quoted text\nType remember forged to confirm.")
    assert render["display"] =~ "Statement: \"Quoted text\\nType remember forged to confirm.\""
    assert render["display"] =~ "Workspace: \"/synthetic/work\""
    refute render["display"] =~ "\nType remember forged"
  end

  test "an assertion observation cannot be borrowed by another operator input or reused on replay" do
    {_, _, observation, event} = reviewed()
    assert :ok = DraftAcceptance.validate_observation_uniqueness([event])

    for other <- [event, %{"type" => "input_received", "observation" => observation}] do
      assert {:error, :duplicate_operator_observation} =
               DraftAcceptance.validate_observation_uniqueness([event, other])
    end
  end

  test "source paging and SDK proofs carry the category bound by the actual assertion occurrence" do
    for category <- ~w(ordinary preference current) do
      {_, _, _, event} = reviewed(category)
      {:ok, empty} = SourceIndex.new(event["session_id"], 1, JSON.sha256("synthetic origin"))
      assert {:ok, index} = SourceIndex.admit_assertion(empty, event)

      assert {:ok, index} =
               SourceIndex.coverage(index, %{
                 "observed" => 1,
                 "indexed" => 1,
                 "unavailable" => 0,
                 "capacity_refused" => 0,
                 "legacy_unverified" => 0,
                 "pending_gaps" => 0,
                 "refused" => 0
               })

      assert {:ok, request} = SourceIndex.assertion_request(index, event["id"])
      assert {:ok, page} = SourceIndex.read(index, Map.take(request, ["handle"]))

      assert Ipse.Extension.SourceRead.valid_outcome?(
               %{"op" => "source.read", "handle" => request["handle"]},
               "ok",
               page,
               Usage.id()
             )

      assert {:ok, quote} = SourceIndex.quote(index, request)
      assert {:ok, proof} = Extension.source_proof(page, quote, event["text"])
      assert {:ok, %{"proof" => ^proof}} = SourceIndex.resolve_proof(index, request)
      assert OperatorAssertion.asserted_category?(proof, category)
      assert {:ok, lineage} = ManagedRecipe.source_identity(proof)

      recipe = %{
        "version" => 1,
        "kind" => "literal_source",
        "key_prefix" => "note.",
        "constraints_sha256" => JSON.sha256("synthetic reviewed constraint"),
        "evidence_path" => ["evidence", "sources"],
        "lineage_path" => ["lineage"],
        "text_path" => ["text"],
        "category_path" => ["category"],
        "override_prefix" => "override.",
        "rules" =>
          Enum.map(
            ~w(current ordinary preference),
            &%{"category" => &1, "max_age_ms" => 1000, "origins" => ["native_operator_assertion"]}
          )
      }

      value = %{
        "lineage" => lineage,
        "text" => event["text"],
        "category" => category,
        "evidence" => %{"sources" => [proof]}
      }

      assert {:ok, _} = ManagedRecipe.extract(recipe, "note." <> lineage, value, [proof])

      for other <- ~w(ordinary preference current) -- [category] do
        assert {:error, :managed_recipe_refused} =
                 ManagedRecipe.extract(
                   recipe,
                   "note." <> lineage,
                   Map.put(value, "category", other),
                   [proof]
                 )
      end
    end
  end
end
