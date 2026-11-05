[root, scenario] = System.argv()
base = Path.dirname(__ENV__.file)
descriptor = System.fetch_env!("IPSE_PAIRED_DESCRIPTOR") |> File.read!() |> Jason.decode!()
true = descriptor["reviewed"] === true and root === descriptor["actor_root"]
phase = String.replace_prefix(scenario, "save_managed_approval_cross_session_paired_", "")
true = phase in ~w(setup read baseline selection candidate)
for module <- [Ipse.Test.ProviderFixture, Ipse.Test.ResumeAssertions,
  Ipse.Development.Evaluation.ProtectedAnswer, Ipse.Test.PairedProtectedAnswerSession] do
  {:module, ^module} = Code.ensure_loaded(module)
  expected = Path.join([base, "helper-ebin", Atom.to_string(module) <> ".beam"])
  ^expected = to_string(:code.which(module))
end
:non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
ExUnit.start(autorun: false)
{:ok, _} = Application.ensure_all_started(:ipse)
Ipse.Test.PairedProtectedAnswerSession.run(root, phase, descriptor["helper_artifact"], descriptor["commitments"])
IO.puts("PAIRED_PROTECTED_ANSWER_PHASE_PASSED " <> phase)
