Code.require_file("verification/memory.exs", __DIR__)

report =
  case System.argv() do
    ["--corpus", path] ->
      Ipse.Development.Verification.Memory.run(path)

    [] ->
      Ipse.Development.Verification.Memory.run(
        Path.expand("../examples/memory-corpus.json", __DIR__)
      )

    _ ->
      raise("usage: mix run dev/measure-memory.exs [--corpus PATH]")
  end

IO.puts(Jason.encode!(report))
