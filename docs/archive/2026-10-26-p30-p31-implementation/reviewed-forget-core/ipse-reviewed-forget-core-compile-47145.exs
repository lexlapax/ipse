source = "_build/management-review-input-sol-20261029"
target = "_build/reviewed-forget-core-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
Path.wildcard(target <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} =
  Kernel.ParallelCompiler.compile_to_path(
    ["lib/ipse/extension/collection.ex"],
    target <> "/lib/ipse/ebin",
    return_diagnostics: true
  )
File.cp!("lib/ipse/extension/collection.ex", "/tmp/ipse-reviewed-forget-core-47145.ex")
IO.puts("Forget-only Collection gate compile has empty diagnostics")
