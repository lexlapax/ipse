source = "_build/p30-p31-integrated-source-20261029"
target = "_build/document-held-read-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
File.cp!("lib/ipse/extension/collection.ex", target <> "/lib/ipse/extension/collection.ex")
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  [target <> "/lib/ipse/extension/collection.ex"], target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.puts("Fixed document held-read compile has empty diagnostics")
