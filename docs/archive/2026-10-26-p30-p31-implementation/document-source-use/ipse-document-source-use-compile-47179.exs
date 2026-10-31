graph = "_build/document-source-use-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
file = "lib/ipse/extension/collection/document_source_use.ex"
File.write!(file, IO.iodata_to_binary(Code.format_file!(file)) <> "\n")
Code.compiler_options(warnings_as_errors: true)
result = Kernel.ParallelCompiler.compile_to_path([file], graph <> "/_build/dev/lib/ipse/ebin", return_diagnostics: true)
IO.inspect(result, label: "strict document source-use compile")
case result do
  {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
  {:ok, _, []} -> :ok
  _ -> System.halt(1)
end
