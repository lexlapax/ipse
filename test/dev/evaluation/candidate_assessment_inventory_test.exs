Code.require_file("../../support/provider_fixture.ex", __DIR__)
Code.require_file("../../../dev/evaluation/candidate_assessment_recipe.exs", __DIR__)

defmodule Ipse.Development.Evaluation.CandidateAssessmentInventoryTest do
  use ExUnit.Case, async: true

  alias Ipse.Development.Evaluation.CandidateAssessmentRecipe, as: Recipe
  alias Ipse.JSON

  test "the current inventories match both the recipe and frozen declaration" do
    source = %{"script.exs" => JSON.sha256("script")}
    runtime = %{"ebin_files" => %{"Example.beam" => JSON.sha256("beam")}}
    recipe = %{"source_commitment" => source, "runtime_commitment" => runtime}

    declaration = %{
      "spec" => %{
        "source_sha256" => JSON.digest([source]),
        "runtime_sha256" => JSON.digest([runtime])
      }
    }

    assert Recipe.inventory_matches?(declaration, recipe, source, runtime)

    changed_source = Map.put(source, "script.exs", JSON.sha256("changed"))
    changed_runtime = put_in(runtime, ["ebin_files", "Example.beam"], JSON.sha256("changed"))

    refute Recipe.inventory_matches?(declaration, recipe, changed_source, runtime)
    refute Recipe.inventory_matches?(declaration, recipe, source, changed_runtime)
    refute Recipe.inventory_matches?(declaration, recipe, %{}, runtime)
    refute Recipe.inventory_matches?(declaration, recipe, source, %{})

    refute Recipe.inventory_matches?(
             declaration,
             Map.put(recipe, "source_commitment", changed_source),
             changed_source,
             runtime
           )

    refute Recipe.inventory_matches?(
             declaration,
             Map.put(recipe, "runtime_commitment", changed_runtime),
             source,
             changed_runtime
           )

    refute Recipe.inventory_matches?(
             put_in(declaration, ["spec", "source_sha256"], nil),
             recipe,
             source,
             runtime
           )

    refute Recipe.inventory_matches?(nil, recipe, source, runtime)
  end
end
