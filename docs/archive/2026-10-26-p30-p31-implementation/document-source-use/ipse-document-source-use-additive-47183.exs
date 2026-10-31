graph = "_build/document-source-use-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
{:ok, _} = Application.ensure_all_started(:ipse)
file = "test/ipse/extension/collection_document_source_use_test.exs"
File.write!(file, IO.iodata_to_binary(Code.format_file!(file)) <> "\n")
ExUnit.start(autorun: false, seed: 20261029, exclude: [:test], include: [:source_relation_additive])
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile([file], return_diagnostics: true)
IO.puts("Additive compatibility and native source-relation tests compile with empty diagnostics")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
