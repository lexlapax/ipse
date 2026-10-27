Code.require_file("../../support/managed_policy.exs", __DIR__)

unless Code.ensure_loaded?(IpseKnowledge.Notes),
  do: Code.require_file("../../../extensions/knowledge/src/notes.ex", __DIR__)

unless Code.ensure_loaded?(IpseKnowledge.Knowledge.Records),
  do: Code.require_file("../../../extensions/knowledge/src/knowledge/records.ex", __DIR__)

defmodule Ipse.Extension.ManagedRecipeTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.ManagedRecipe, as: Recipe
  alias Ipse.Test.ManagedPolicy, as: F
  alias IpseKnowledge.Knowledge.{Contracts, Records}

  defp recipe(kind),
    do:
      F.recipe(
        kind,
        Contracts.operator()["publication"][if(kind == "proposal", do: "pending", else: "note")]
      )

  defp value(proof, kind \\ "literal_source", text \\ nil) do
    {:ok, lineage} = Recipe.source_identity(proof)

    %{
      "lineage" => lineage,
      "text" => text || proof["quote"],
      "category" => "ordinary",
      "assigned_category" => "ordinary",
      "evidence" => %{"sources" => [proof]},
      "created_at_ms" => 9_007_199_254_740_991,
      "expires_at_ms" => nil,
      "kind" => kind
    }
  end

  test "fixed identity and proposal hashes match actual capture bytes including Unicode and escaping" do
    for text <- ["café 雪", "quote\" slash\\ newline\n", "separator\u2028text"] do
      proof = F.proof("unattended_input", text)
      assert {:ok, lineage} = Recipe.source_identity(proof)
      assert lineage == Records.lineage(proof)

      attrs = %{
        "text" => text <> " paraphrase",
        "category" => "ordinary",
        "reason" => "fixture",
        "event_at_ms" => nil
      }

      assert {:ok, key, proposal} = Records.capture(attrs, proof, 1000)
      assert {:ok, id} = Recipe.proposal_identity(lineage, attrs["text"])
      assert key == "pending." <> id
      assert proposal["id"] == id
    end
  end

  test "literal source is exact host-supported text and never trusts worker clocks" do
    proof = F.proof()
    r = recipe("literal_source")
    assert Recipe.valid?(r)
    assert {:ok, lineage} = Recipe.source_identity(proof)
    assert {:ok, result} = Recipe.extract(r, "note." <> lineage, value(proof), [proof])
    assert result["eligibility"] == "pending_host"
    assert result["max_age_ms"] == 7_776_000_000
    refute Map.has_key?(result, "created_at_ms")
    refute Map.has_key?(result, "expires_at_ms")

    assert {:error, _} =
             Recipe.extract(r, "note." <> lineage, value(proof, "literal_source", "paraphrase"), [
               proof
             ])

    assert {:error, _} = Recipe.extract(r, "note.foreign", value(proof), [proof])

    assert {:error, _} =
             Recipe.extract(
               r,
               "note." <> lineage,
               Map.put(value(proof), "lineage", F.hash("foreign")),
               [proof]
             )
  end

  test "one unrelated strong proof cannot authenticate another selected receipt" do
    proof = F.proof()
    other = F.proof("native_operator_answer", "different answer")
    {:ok, lineage} = Recipe.source_identity(proof)

    assert {:error, _} =
             Recipe.extract(recipe("literal_source"), "note." <> lineage, value(proof), [other])

    assert {:ok, _} =
             Recipe.extract(recipe("literal_source"), "note." <> lineage, value(proof), [
               other,
               proof
             ])

    altered = Map.put(proof, "origin", "native_operator_answer")
    assert {:error, _} = Recipe.source_identity(altered)
    assert {:error, _} = Recipe.source_identity(Map.put(proof, "path", "workspace/file"))
    assert {:error, _} = Recipe.source_identity(Map.put(proof, "coverage", "unavailable"))
  end

  test "assistant or unattended paraphrases remain pending and expire within seven days" do
    for origin <- ~w(unattended_input assistant_proposal) do
      proof = F.proof(origin)
      {:ok, lineage} = Recipe.source_identity(proof)
      text = "paraphrased candidate"
      {:ok, id} = Recipe.proposal_identity(lineage, text)

      assert {:ok, result} =
               Recipe.extract(
                 recipe("proposal"),
                 "pending." <> id,
                 value(proof, "proposal", text),
                 [proof]
               )

      assert result["eligibility"] == "never_current"

      assert {:error, _} =
               Recipe.extract(
                 recipe("proposal"),
                 "pending." <> lineage,
                 value(proof, "proposal", text),
                 [proof]
               )

      assert {:error, _} =
               Recipe.extract(recipe("literal_source"), "note." <> lineage, value(proof), [proof])
    end

    r = recipe("proposal")
    refute Recipe.valid?(put_in(r, ["rules", Access.at(0), "max_age_ms"], nil))
    refute Recipe.valid?(put_in(r, ["rules", Access.at(0), "max_age_ms"], 604_800_001))
  end

  test "typed outcomes only support ordinary class and native answers never infer operator choices" do
    proof = F.proof("typed_host_outcome")
    {:ok, lineage} = Recipe.source_identity(proof)
    r = recipe("literal_source")
    assert {:ok, _} = Recipe.extract(r, "note." <> lineage, value(proof), [proof])

    refute match?(
             {:ok, _},
             Recipe.extract(
               r,
               "note." <> lineage,
               Map.put(value(proof), "category", "preference"),
               [proof]
             )
           )

    operator = F.proof("native_operator_answer", "2")

    override = %{
      r
      | "kind" => "operator_override",
        "key_prefix" => "override.",
        "text_path" => nil,
        "category_path" => nil,
        "rules" => []
    }

    assert Recipe.valid?(override)

    assert {:error, :managed_recipe_requires_typed_choice} =
             Recipe.extract(override, "override." <> lineage, value(operator), [operator])
  end

  test "recipes close selectors, reserved automatic categories and finite rules" do
    r = recipe("literal_source")
    for key <- Map.keys(r), do: refute(Recipe.valid?(Map.delete(r, key)))

    for invalid <- [
          Map.put(r, "callback", "Domain.authorize"),
          Map.put(r, "evidence_path", ["../file"]),
          Map.put(r, "lineage_path", Enum.map(1..9, fn _ -> "nested" end)),
          Map.put(r, "rules", r["rules"] ++ [hd(r["rules"])]),
          put_in(r, ["rules", Access.at(0), "category"], "pin"),
          put_in(r, ["rules", Access.at(0), "category"], "history"),
          put_in(r, ["rules", Access.at(1), "max_age_ms"], nil),
          put_in(r, ["rules", Access.at(0), "origins"], ["attributed_reference"])
        ],
        do: refute(Recipe.valid?(invalid))
  end
end
