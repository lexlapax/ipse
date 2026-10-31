source = "_build/collection-held-read-sol-20261029"
target = "_build/collection-held-read-v2-sol-20261029"
unless File.dir?(target), do: File.cp_r!(source, target)
Path.wildcard(target <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  ["lib/ipse/extension/collection.ex"], target <> "/lib/ipse/ebin", return_diagnostics: true)
IO.puts("Collection token-seal repair compiled with empty warning diagnostics")
