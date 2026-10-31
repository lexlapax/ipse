source = "_build/document-source-use-sol-20261029"
target = "_build/document-embedding-sdk-sol-20261029"
false = File.exists?(target)
File.cp_r!(source, target)
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
files = ~w(lib/ipse/extension/collection_store.ex lib/ipse/extension/inference.ex lib/ipse/extension/actions.ex)
Enum.each(files, fn path ->
  File.write!(path, IO.iodata_to_binary(Code.format_file!(path)))
  File.cp!(path, target <> "/" <> path)
end)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  Enum.map(files, &(target <> "/" <> &1)), target <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.puts("Guarded SDK surface compiled with empty diagnostics; NOT a Session admission runtime")
