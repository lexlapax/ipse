base = Path.expand("_build/managed-audit-repairs-sol-20261029/lib")
target = Path.expand("_build/managed-review-followup-sol-20261029/lib")
File.mkdir_p!(Path.dirname(target))
unless File.dir?(target), do: File.cp_r!(base, target)
Code.prepend_paths(Path.wildcard(Path.join(target, "*/ebin")))
Code.compiler_options(ignore_module_conflict: true)
files = ~w(lib/ipse/session/saved.ex lib/ipse/extension/collection.ex lib/ipse/extension/collection_call.ex lib/ipse/extension/managed_collection_call.ex)
ebin = Path.join(target, "ipse/ebin")
for file <- files, [_, name] <- Regex.scan(~r/^defmodule ([\w.]+) do/m, File.read!(file)) do
  module = Module.concat([name])
  :code.purge(module)
  :code.delete(module)
  File.rm(Path.join(ebin, "Elixir." <> name <> ".beam"))
end
case Kernel.ParallelCompiler.compile_to_path(files, ebin, warnings_as_errors: true, return_diagnostics: true) do
  {:ok, modules, %{compile_warnings: [], runtime_warnings: []}} -> IO.puts("strict managed host/display compile passed: #{length(modules)} modules")
  result -> IO.inspect(result); System.halt(1)
end
