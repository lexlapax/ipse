target = Path.expand("_build/document-inventory-sol-20261029/lib")
Code.prepend_paths(Path.wildcard(Path.join(target, "*/ebin")))
Code.compiler_options(ignore_module_conflict: true)
files = ~w(lib/ipse/extension/collection.ex lib/ipse/extension/collection/document_stage.ex lib/ipse/extension/collection/directory.ex lib/ipse/extension/collection_store.ex)
ebin = Path.join(target, "ipse/ebin")
for file <- files, [_, name] <- Regex.scan(~r/^defmodule ([\w.]+) do/m, File.read!(file)) do
  module = Module.concat([name])
  :code.purge(module)
  :code.delete(module)
  File.rm(Path.join(ebin, "Elixir." <> name <> ".beam"))
end
case Kernel.ParallelCompiler.compile_to_path(files, ebin, warnings_as_errors: true, return_diagnostics: true) do
  {:ok, modules, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("document inventory compile passed: #{length(modules)} modules")
  result -> IO.inspect(result); System.halt(1)
end
