graph = "_build/retention-deadline-sol-20261028"
File.mkdir_p!(graph <> "/project/lib/ipse")
File.mkdir_p!(graph <> "/build")
{:ok, _} = File.cp_r("/tmp/document-store-host-20261028/_build/test/lib", graph <> "/build/lib")
{:ok, _} = File.cp_r("/tmp/document-store-host-20261028/priv", graph <> "/project/priv")
{:ok, _} = File.cp_r("native", graph <> "/project/native")
File.cp!("lib/ipse/runner.ex", graph <> "/project/lib/ipse/runner.ex")
File.rm!(graph <> "/build/lib/ipse/priv")
:ok = File.ln_s("../../../project/priv", graph <> "/build/lib/ipse/priv")
{output, status} = System.cmd("rustc", ["--edition=2021", "-D", "warnings", "-C", "opt-level=z",
  "-C", "strip=symbols", "-C", "panic=abort", graph <> "/project/native/ipse-runner.rs",
  "-o", graph <> "/project/priv/ipse-runner"], stderr_to_stdout: true)
File.write!(graph <> "/helper-build.log", output)
if status != 0, do: raise(output)
Code.prepend_paths(Path.wildcard(graph <> "/build/lib/*/ebin"))
Mix.start()
Code.compiler_options(ignore_module_conflict: true)
sources = [graph <> "/project/lib/ipse/runner.ex", "lib/ipse/runner/transaction.ex",
  "lib/ipse/extension/collection.ex", "lib/ipse/extension/collection/normalizer_v3.ex"]
{:ok, _, []} = Kernel.ParallelCompiler.compile_to_path(sources, graph <> "/build/lib/ipse/ebin",
  warnings_as_errors: true)
{output, status} = System.cmd("rustc", ["--edition=2021", "-D", "warnings", "--test",
  graph <> "/project/native/ipse-runner.rs", "-o", graph <> "/native-tests"], stderr_to_stdout: true)
File.write!(graph <> "/native-build.log", output)
if status != 0, do: raise(output)
IO.puts("RETENTION_DEADLINE_ISOLATED_GRAPH_READY")
