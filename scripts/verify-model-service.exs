unless match?({:unix, :linux}, :os.type()),
  do: raise("model-service synthetic verification requires Linux")

arguments =
  case System.argv() do
    ["--" | rest] -> rest
    rest -> rest
  end

[fixture, root | selected] = arguments
Code.require_file("../examples/knowledge/evaluation_model_service.exs", __DIR__)
Code.require_file("../test/support/model_service_verification.exs", __DIR__)
File.mkdir!(root)
File.chmod!(root, 0o700)
cases = if selected == [], do: ModelServiceVerification.cases(), else: selected

unless Enum.all?(cases, &(&1 in ModelServiceVerification.cases())),
  do: raise("unknown verification case")

results = Enum.map(cases, &ModelServiceVerification.verify_case(&1, fixture, Path.join(root, &1)))
IO.puts(JSON.encode!(%{"synthetic" => true, "cases" => results}))
