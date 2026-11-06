[root, phase] = System.argv()
base = Path.dirname(__ENV__.file)
descriptor = System.fetch_env!("IPSE_PAIRED_DESCRIPTOR")
bytes = File.read!(descriptor)
true = Ipse.JSON.sha256(bytes) === System.fetch_env!("IPSE_PAIRED_DESCRIPTOR_SHA256")
d = Jason.decode!(bytes)
true = d["reviewed"] === true and d["execution_enabled"] === true and d["prepared"] === true
true = root === d["storage"] <> "/actor"
true = phase in ~w(setup read baseline selection candidate)
System.argv([descriptor, Ipse.JSON.sha256(bytes)])
Code.eval_file(Path.join(base, "guard.exs"))
true = Code.prepend_path(Path.join([base, "prepared-current-02", "helper-ebin"]))

for module <- [
      Ipse.Test.ProviderFixture,
      Ipse.Test.ResumeAssertions,
      Ipse.Development.Evaluation.Metrics,
      Ipse.Development.Evaluation.DecisionMetrics,
      Ipse.Development.Evaluation.SelectionExperiment,
      Ipse.Development.Evaluation.ProtectedAnswer,
      Ipse.Test.PairedProtectedAnswerSession
    ] do
  {:module, ^module} = Code.ensure_loaded(module)

  true =
    to_string(:code.which(module)) ===
      Path.join([base, "prepared-current-02", "helper-ebin", Atom.to_string(module) <> ".beam"])
end

:non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
reference_bytes = File.read!(d["references"])

{:ok, reference_sha} =
  Ipse.Development.Evaluation.SelectionExperiment.commit_references(reference_bytes)

true = reference_sha === d["reference_sha256"]
reference_file = Path.join(root, "reference-labels.before-app.json")

if phase === "setup" do
  File.write!(reference_file, reference_bytes, [:exclusive, :sync])
  File.chmod!(reference_file, 0o600)
else
  true = File.read!(reference_file) === reference_bytes
end

true = File.read!(reference_file) === reference_bytes
ExUnit.start(autorun: false)
{:ok, _} = Application.ensure_all_started(:ipse)

commitments = %{
  "source_sha256" => d["source_commitment"],
  "runtime_sha256" => d["archive_sha256"],
  "label_commitment" => reference_sha,
  "reference_path" => reference_file
}

Ipse.Test.PairedProtectedAnswerSession.run(root, phase, d["artifact"], commitments)
IO.puts("PAIRED_PROTECTED_ANSWER_PHASE_PASSED " <> phase)
