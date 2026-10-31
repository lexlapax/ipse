Mix.start()
Mix.env(:dev)
target = "_build/document-embedding-admission-sol-20261029"
files = File.read!(target <> "/admission-source.sha256") |> String.split("\n", trim: true)
  |> Enum.map(fn row -> [hash, file] = String.split(row, "  ", parts: 2); {hash, file} end)
Enum.each(files, fn {expected, file} ->
  actual = :crypto.hash(:sha256, File.read!(target <> "/" <> file)) |> Base.encode16(case: :lower)
  true = actual === expected
end)
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
result = Kernel.ParallelCompiler.compile_to_path(Enum.map(files, fn {_, file} -> target <> "/" <> file end),
  target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.inspect(result, label: "Same complete host source snapshot with initialized Mix", limit: 8)
case result do
  {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("All #{length(files)} host source inputs compile without diagnostics")
  _ -> System.halt(1)
end
