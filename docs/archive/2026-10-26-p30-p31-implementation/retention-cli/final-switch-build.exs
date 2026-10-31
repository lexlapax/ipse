root = Path.expand("_build/retention-cli-final-switch-20261028")
unless File.exists?(root) do
  File.mkdir_p!(root)
  source = Path.expand("_build/retention-deadline-sol-20261028")
  File.cp_r!(Path.join(source, "build/lib"), Path.join(root, "lib"))
  File.cp_r!(Path.join(source, "project/priv"), Path.join(root, "priv"))
  priv_link = Path.join(root, "lib/ipse/priv")
  assertion = File.lstat!(priv_link)
  true = assertion.type == :symlink
  File.rm!(priv_link)
  File.ln_s!(Path.join(root, "priv"), priv_link)
end
:ok = :code.add_paths(Path.wildcard(root <> "/lib/*/ebin") |> Enum.map(&String.to_charlist/1))
Code.compiler_options(ignore_module_conflict: true)
sources = ~w(lib/ipse/extension/consent.ex lib/ipse/cli.ex lib/ipse/cli/knowledge.ex lib/ipse/cli/knowledge/management.ex lib/ipse/cli/terminal.ex)
{:ok, modules, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(sources, Path.join(root, "lib/ipse/ebin"), return_diagnostics: true)
helper = File.read!(Path.join(root, "priv/ipse-runner"))
"113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550" = Base.encode16(:crypto.hash(:sha256, helper), case: :lower)
IO.puts("Built isolated new-helper retention CLI graph; #{length(modules)} root modules compiled without warnings")
