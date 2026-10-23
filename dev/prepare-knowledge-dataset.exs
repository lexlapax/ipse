Code.require_file("evaluation/dataset.exs", __DIR__)

result =
  try do
    args =
      case System.argv() do
        ["--" | rest] -> rest
        rest -> rest
      end

    {options, [], []} =
      OptionParser.parse(args,
        strict: [
          corpus: :string,
          queries: :string,
          answers: :string,
          as_of_ms: :integer,
          output: :string
        ]
      )

    true = Enum.sort(Keyword.keys(options)) == ~w(answers as_of_ms corpus output queries)a
    true = options[:as_of_ms] in 0..9_007_199_254_740_991
    output = Path.expand(options[:output])
    root = Path.dirname(output)
    true = Path.expand(options[:corpus]) == Path.join(root, "corpus.json")
    true = Path.expand(options[:queries]) == Path.join(root, "queries.json")

    true =
      Path.expand(options[:answers]) not in [
        output,
        Path.join(root, "corpus.json"),
        Path.join(root, "queries.json")
      ]

    read = fn path ->
      %{type: :regular, size: size} = File.lstat!(path)
      true = size <= 1_048_576
      {:ok, bytes} = File.open(path, [:read, :binary], &IO.binread(&1, 1_048_577))
      true = is_binary(bytes) and byte_size(bytes) <= 1_048_576
      bytes
    end

    corpus = read.(options[:corpus])
    queries = read.(options[:queries])
    answers = read.(options[:answers])
    {:ok, questions} = Ipse.Development.Evaluation.Dataset.queries(queries, "heldout")
    true = questions["contract"] == "sealed_answers_v1"
    true = length(questions["queries"]) == 50
    projects = questions["queries"] |> Enum.map(& &1["project"]) |> Enum.uniq()
    true = length(projects) == 2

    {:ok, reference} =
      Ipse.Development.Evaluation.Dataset.references(answers, "heldout", questions)

    {:ok, sources} = Ipse.Development.Evaluation.Dataset.sources(corpus)

    true =
      Enum.all?(
        Ipse.Development.Evaluation.Dataset.reference_checks(
          reference["labels"]["queries"],
          sources
        ),
        & &1["valid"]
      )

    sha = &Ipse.JSON.sha256/1

    manifest = %{
      "contract" => "sealed_answers_v1",
      "as_of_ms" => options[:as_of_ms],
      "inputs" => %{
        "corpus" => %{"path" => "corpus.json", "sha256" => sha.(corpus)},
        "queries" => %{"path" => "queries.json", "sha256" => sha.(queries)}
      },
      "answers_sha256" => sha.(answers)
    }

    bytes = JSON.encode!(manifest) <> "\n"
    {:ok, file} = File.open(output, [:write, :binary, :exclusive])

    try do
      :ok = File.chmod(output, 0o600)
      :ok = IO.binwrite(file, bytes)
      :ok = :file.sync(file)
    after
      File.close(file)
    end

    {:ok,
     %{
       "manifest_sha256" => sha.(bytes),
       "answers_sha256" => sha.(answers),
       "query_count" => 50,
       "project_count" => 2
     }}
  rescue
    _ -> {:error, "invalid_dataset_or_output"}
  end

case result do
  {:ok, metadata} ->
    IO.puts(JSON.encode!(%{"status" => "ok", "result" => metadata}))

  {:error, code} ->
    IO.puts(JSON.encode!(%{"status" => "failed", "code" => code}))
    System.halt(1)
end
