source = "_build/document-embedding-sdk-sol-20261029"
target = "_build/document-embedding-admission-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
files = (Path.wildcard("lib/**/*.ex") ++ Path.wildcard("extensions/bundled/**/*.ex")) |> Enum.sort()
hash = fn p -> :crypto.hash(:sha256, File.read!(p)) |> Base.encode16(case: :lower) end
before = Map.new(files, &{&1, hash.(&1)})
Enum.each(files, fn file ->
  dest = target <> "/" <> file
  File.mkdir_p!(Path.dirname(dest))
  File.cp!(file, dest)
end)
true = before === Map.new(files, &{&1, hash.(&1)})
true = before === Map.new(files, &{&1, hash.(target <> "/" <> &1)})
File.write!(target <> "/admission-source.sha256", Enum.map(files, fn file -> before[file] <> "  " <> file <> "\n" end))
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
result = Kernel.ParallelCompiler.compile_to_path(Enum.map(files, &(target <> "/" <> &1)),
  target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.inspect(result, label: "Current complete host source snapshot compile", limit: 8)
case result do
  {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("All #{length(files)} host source inputs compile without diagnostics")
  _ -> System.halt(1)
end
