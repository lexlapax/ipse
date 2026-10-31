base = Path.expand("_build/strict-deadline-gate-sol-20261029/lib")
target = Path.expand("_build/strict-lifetime-followup-sol-20261029/lib")
File.mkdir_p!(Path.dirname(target))
unless File.dir?(target), do: File.cp_r!(base, target)
Code.prepend_paths(Path.wildcard(Path.join(target, "*/ebin")))
Code.compiler_options(ignore_module_conflict: true)
files = ~w(lib/ipse/extension/state.ex lib/ipse/extension/collection.ex lib/ipse/cli/knowledge/management.ex lib/ipse/cli/knowledge.ex lib/ipse/cli/errors.ex lib/ipse/session/invocation.ex lib/ipse/cli/terminal.ex)
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
