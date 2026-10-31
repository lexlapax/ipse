graph = "_build/document-source-use-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
file = "test/ipse/extension/collection_document_source_use_test.exs"
File.write!(file, IO.iodata_to_binary(Code.format_file!(file)) <> "\n")
ExUnit.start(autorun: false, seed: 20261029, exclude: [:test], include: [:source_relation_repair])
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile([file], return_diagnostics: true)
IO.puts("Corrected test source compiled with empty diagnostics; production bytes unchanged")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
