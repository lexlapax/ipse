source = "_build/management-snapshot-read-v2-sol-20261029"
target = "_build/collection-held-read-sol-20261029"
unless File.dir?(target), do: File.cp_r!(source, target)
Path.wildcard(target <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true, warnings_as_errors: true)
{:ok, _, []} = Kernel.ParallelCompiler.compile_to_path(["lib/ipse/extension/collection.ex"], target <> "/lib/ipse/ebin")
IO.puts("Collection strict compile passed")
