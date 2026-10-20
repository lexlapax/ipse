Code.require_file("../examples/knowledge/evaluation_plan.exs", __DIR__)

result =
  try do
    args =
      case System.argv() do
        ["--" | rest] -> rest
        rest -> rest
      end

    {options, [], []} =
      OptionParser.parse(args, strict: [spec: :string, output: :string, new_blind_seed: :boolean])

    true =
      Enum.sort(Keyword.keys(options)) in [[:output, :spec], [:new_blind_seed, :output, :spec]]

    path = Path.expand(Keyword.fetch!(options, :spec))
    %{type: :regular, size: size} = File.lstat!(path)
    true = size <= 1_048_576
    {:ok, spec} = Ipse.JSON.decode_bounded(File.read!(path), 1_048_576)

    spec =
      if options[:new_blind_seed] do
        true = spec["blind_seed"] == nil
        Map.put(spec, "blind_seed", Ipse.Usage.id() <> Ipse.Usage.id())
      else
        spec
      end

    spec =
      Map.update!(spec, "artifacts", fn artifacts ->
        Map.new(artifacts, fn {name, artifact} ->
          {name, Path.expand(artifact, Path.dirname(path))}
        end)
      end)

    {:ok, plan} = IpseKnowledgeExample.EvaluationPlan.build(spec)
    bytes = JSON.encode!(plan) <> "\n"
    true = byte_size(bytes) <= 1_048_576
    output = Path.expand(Keyword.fetch!(options, :output))
    {:ok, file} = File.open(output, [:write, :binary, :exclusive])

    try do
      File.chmod!(output, 0o600)
      :ok = IO.binwrite(file, bytes)
      :ok = :file.sync(file)
    after
      File.close(file)
    end

    {:ok,
     %{
       "path" => output,
       "sha256" => Ipse.JSON.sha256(bytes),
       "variants" => length(plan["variants"])
     }}
  rescue
    _ -> {:error, "invalid_spec_or_output"}
  end

case result do
  {:ok, report} ->
    IO.puts(JSON.encode!(%{"status" => "ok", "result" => report}))

  {:error, code} ->
    IO.puts(JSON.encode!(%{"status" => "failed", "code" => code}))
    System.halt(1)
end
