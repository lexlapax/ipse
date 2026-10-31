graph = "_build/document-embedding-admission-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
file = "test/ipse/session/document_embedding_test.exs"
File.write!(file, IO.iodata_to_binary(Code.format_file!(file)))
ExUnit.start(autorun: false, seed: 20261029)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile([file], return_diagnostics: true)
IO.puts("Focused document embedding shape/live-state tests compile without diagnostics")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
