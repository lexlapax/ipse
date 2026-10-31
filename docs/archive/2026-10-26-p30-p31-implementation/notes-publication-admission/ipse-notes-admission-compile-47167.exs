source = "_build/remember-intake-sol-20261029"
target = "_build/notes-publication-admission-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
files = ~w(lib/ipse/extension/collection.ex lib/ipse/extension/managed_collection_call.ex lib/ipse/session/invocation.ex lib/ipse/extension/collection/document_stage.ex)
Enum.each(files, &File.cp!(&1, target <> "/" <> &1))
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, modules, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  Enum.map(files, &(target <> "/" <> &1)), target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.inspect(modules, label: "Notes final-admission owners compile with empty diagnostics")
