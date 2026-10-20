Code.require_file("../examples/knowledge/evaluation_runner.exs", __DIR__)
Code.require_file("../test/support/measured_model_fixture.exs", __DIR__)
Code.require_file("../test/support/measured_knowledge_verification.exs", __DIR__)
Code.require_file("../test/support/measured_scoring_verification.exs", __DIR__)

arguments =
  case System.argv() do
    ["--" | rest] -> rest
    rest -> rest
  end

{paths, contract} =
  case arguments do
    [repository, output] -> {[repository, output], nil}
    [repository, output, "--sealed-answers"] -> {[repository, output], "sealed_answers_v1"}
  end

[repository, output] = Enum.map(paths, &Path.expand/1)

unless :os.type() == {:unix, :linux},
  do: raise("complete measured verification requires the optional Linux backend")

{:ok, _} = Application.ensure_all_started(:ipse)
File.mkdir!(output)
File.chmod!(output, 0o700)

artifacts =
  MeasuredKnowledgeVerification.build_artifacts(Path.join(output, "artifacts"), repository)

MeasuredKnowledgeVerification.save!(Path.join(output, "artifacts.json"), JSON.encode!(artifacts))

run =
  MeasuredKnowledgeVerification.prepare(
    Path.join(output, "source"),
    repository,
    artifacts,
    nil,
    contract
  )

result = MeasuredKnowledgeVerification.verify(run)
scoring = MeasuredScoringVerification.verify(run, result, repository)

IO.puts(
  JSON.encode!(%{
    "synthetic" => true,
    "model_quality_measured" => false,
    "result" => result,
    "scoring" => scoring,
    "evidence" => output
  })
)
