Code.require_file("../examples/knowledge/evaluation_runner.exs", __DIR__)
Code.require_file("../test/support/measured_model_fixture.exs", __DIR__)
Code.require_file("../test/support/measured_knowledge_verification.exs", __DIR__)
Code.require_file("../test/support/measured_authority_verification.exs", __DIR__)

arguments =
  case System.argv() do
    ["--" | rest] -> rest
    rest -> rest
  end

[repository, artifact_file, output] = Enum.map(arguments, &Path.expand/1)
artifacts = JSON.decode!(File.read!(artifact_file))
summary = MeasuredAuthorityVerification.verify(repository, artifacts, output)
IO.puts(JSON.encode!(summary))
