source = "_build/document-layout-inventory-sol-20261029"
graph = "_build/generation-progress-sol-20261029"
unless File.dir?(graph), do: File.cp_r!(source, graph)
output = "_build/generation-progress-corpus-sol-20261029"
{message, 0} = System.cmd("elixir", ["--erl", "+S 2:2", "extensions/knowledge/build.exs",
  "--sdk", Path.expand(graph <> "/lib/ipse/ebin"), "--output", output,
  "--package", "corpus", "--preset", "collection-documents"], stderr_to_stdout: true)
IO.write(message)
