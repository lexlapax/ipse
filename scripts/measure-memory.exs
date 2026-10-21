Code.require_file("../dev/experiments/memory.exs", __DIR__)

report =
  case System.argv() do
    ["--corpus", path] ->
      Ipse.Development.Experiments.Memory.run(path)

    [] ->
      Ipse.Development.Experiments.Memory.run(
        Path.expand("../examples/memory/corpus.json", __DIR__)
      )

    _ ->
      raise("usage: mix run scripts/measure-memory.exs [--corpus PATH]")
  end

IO.puts(Jason.encode!(report))
