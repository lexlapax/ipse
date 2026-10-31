target = "_build/collection-held-read-sol-20261029"
Path.wildcard(target <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, []} = Kernel.ParallelCompiler.compile_to_path(["lib/ipse/extension/collection.ex"], target <> "/lib/ipse/ebin", return_diagnostics: true)
IO.puts("Collection strict compile passed without warnings")
