[root, "save_managed_approval_cross_session_selection_assessment"] = System.argv()
helper = Path.dirname(Path.dirname(__ENV__.file))

for module <- [Ipse.Test.ProviderFixture, Ipse.Test.SelectionAssessmentPhased] do
  {:module, ^module} = Code.ensure_loaded(module)
  expected = Path.join([helper, "helper-ebin", Atom.to_string(module) <> ".beam"])
  ^expected = :code.which(module) |> to_string()
end

ExUnit.start(autorun: false)
{:ok, _} = Application.ensure_all_started(:ipse)
Ipse.Test.SelectionAssessmentPhased.run(root, "assessment")
IO.puts("ASSESSMENT_ONLY_CONTINUATION_PASSED")
