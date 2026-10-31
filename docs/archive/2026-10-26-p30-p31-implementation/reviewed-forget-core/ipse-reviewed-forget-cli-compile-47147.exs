source = "_build/reviewed-forget-core-sol-20261029"
target = "_build/reviewed-forget-cli-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
Path.wildcard(target <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} =
  Kernel.ParallelCompiler.compile_to_path(
    ["lib/ipse/cli/knowledge.ex", "lib/ipse/cli/errors.ex"],
    target <> "/lib/ipse/ebin",
    return_diagnostics: true
  )
IO.puts("Current CLI diagnostic overlays compile with empty diagnostics")
