source = "_build/notes-publication-admission-sol-20261029"
target = "_build/notes-absence-publication-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
files = ~w(lib/ipse/session/managed_reads.ex lib/ipse/session/managed_tool_use.ex)
Enum.each(files, &File.cp!(&1, target <> "/" <> &1))
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  Enum.map(files, &(target <> "/" <> &1)), target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.puts("Own root/absence prerequisite owners compile with empty diagnostics")
