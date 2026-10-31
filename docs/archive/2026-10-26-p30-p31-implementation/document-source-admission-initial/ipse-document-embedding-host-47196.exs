Mix.start()
Mix.env(:dev)
target = "_build/document-embedding-admission-sol-20261029"
files = File.read!(target <> "/admission-source.sha256") |> String.split("\n", trim: true)
  |> Enum.map(fn row -> [hash, file] = String.split(row, "  ", parts: 2); {hash, file} end)
Enum.each(files, fn {expected, file} ->
  actual = :crypto.hash(:sha256, File.read!(target <> "/" <> file)) |> Base.encode16(case: :lower)
  true = actual === expected
end)
ebin = target <> "/_build/dev/lib/ipse/ebin"
beams = Path.wildcard(ebin <> "/*.beam")
Enum.each(beams, &File.rm!/1)
IO.puts("Removed #{length(beams)} inherited host BEAMs from isolated candidate before source compilation")
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
result = Kernel.ParallelCompiler.compile_to_path(Enum.map(files, fn {_, file} -> target <> "/" <> file end),
  ebin, return_diagnostics: true)
IO.inspect(result, label: "Complete host source without stale struct metadata", limit: 8)
case result do
  {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("All #{length(files)} host source inputs compile without diagnostics")
  _ -> System.halt(1)
end
