Code.prepend_paths(Path.wildcard(Path.join(__DIR__, "lib/*/ebin")))
Code.compiler_options(ignore_module_conflict: true)
case Kernel.ParallelCompiler.compile_to_path(["lib/ipse/session/managed_supersession.ex"],
       Path.join(__DIR__, "lib/ipse/ebin"), warnings_as_errors: true) do
  {:ok, _, []} -> IO.puts("strict incomplete-prefix module compile passed")
  other -> IO.inspect(other); System.halt(1)
end
