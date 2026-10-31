graph = "_build/document-source-use-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
files = ~w(lib/ipse/extension/collection/document_source_use.ex test/ipse/extension/collection_document_source_use_test.exs)
Enum.each(files, fn file -> File.write!(file, IO.iodata_to_binary(Code.format_file!(file)) <> "\n") end)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(
  [hd(files)], graph <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.puts("Production source relation compiled with empty diagnostics")
ExUnit.start(autorun: false, seed: 20261029)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile([List.last(files)], return_diagnostics: true)
IO.puts("Focused test source compiled with empty diagnostics")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
