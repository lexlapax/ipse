Path.wildcard("_build/notes-absence-publication-sol-20261029/_build/dev/lib/*/ebin")
|> Enum.each(&Code.prepend_path/1)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.compiler_options(ignore_module_conflict: true)
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} =
  Kernel.ParallelCompiler.compile(["lib/ipse/cli/terminal.ex"], return_diagnostics: true)
Ipse.CLI.Terminal.help()
