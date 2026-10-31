source = "_build/reviewed-forget-cli-sol-20261029"
target = "_build/embedding-selection-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
Path.wildcard(target <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
files = ~w(lib/ipse/extension/inference.ex lib/ipse/extension/actions.ex lib/ipse/extension/host.ex lib/ipse/session/invocation.ex)
{:ok, modules, %{compile_warnings: [], runtime_warnings: []}} =
  Kernel.ParallelCompiler.compile_to_path(files, target <> "/lib/ipse/ebin", return_diagnostics: true)
IO.inspect(modules, label: "Compiled selection owners with empty diagnostics")
