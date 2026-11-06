# Explicit synthetic test entry. Normal native approval and the saved one-call
# experiment remain necessary; this file supplies no permission or policy.
ExUnit.start(autorun: false)
Code.require_file("provider_fixture.ex", __DIR__)
Code.require_file("../../dev/evaluation/candidate_assessment_recipe.exs", __DIR__)

[recipe, output, "save_managed_approval_candidate_evaluation"] = System.argv()
:ok = Ipse.Development.Evaluation.CandidateAssessmentRecipe.run(recipe, output)
IO.puts("CANDIDATE_ASSESSMENT_PROTOCOL_PASSED")
