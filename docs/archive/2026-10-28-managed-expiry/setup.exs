graph = "_build/managed-expiry-sol-20261028"
base = "_build/retention-deadline-sol-20261028"
File.mkdir_p!(graph <> "/build")
File.mkdir_p!(graph <> "/project")
{:ok, _} = File.cp_r(base <> "/build/lib", graph <> "/build/lib")
{:ok, _} = File.cp_r(base <> "/project/priv", graph <> "/project/priv")
Code.prepend_paths(Path.wildcard(graph <> "/build/lib/*/ebin"))
Mix.start()
Code.compiler_options(ignore_module_conflict: true)
IO.inspect(Kernel.ParallelCompiler.compile_to_path(~w(lib/ipse/extension/collection/managed_retention.ex
  lib/ipse/extension/collection/normalizer_v3.ex lib/ipse/session/managed_lifecycle.ex),
  graph <> "/build/lib/ipse/ebin", warnings_as_errors: true, return_diagnostics: true))
