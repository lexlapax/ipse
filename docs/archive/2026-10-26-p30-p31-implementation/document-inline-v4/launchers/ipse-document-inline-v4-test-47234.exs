graph = "_build/document-inline-v4-complete-sol-20261029"
Path.wildcard(graph <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
ExUnit.start(autorun: false, seed: 20261029)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} =
  Kernel.ParallelCompiler.compile(["test/ipse/session/document_embedding_test.exs"], return_diagnostics: true)
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
