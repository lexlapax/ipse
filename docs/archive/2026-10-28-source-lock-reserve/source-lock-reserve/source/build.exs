root = Path.expand("_build/source-lock-reserve-20261028")
false = File.exists?(root)
File.mkdir_p!(root)
base = Path.expand("_build/retention-cli-final-switch-20261028")
File.cp_r!(Path.join(base, "lib"), Path.join(root, "lib"))
File.mkdir_p!(Path.join(root, "project"))
File.cp_r!(Path.join(base, "priv"), Path.join(root, "project/priv"))
link = Path.join(root, "lib/ipse/priv")
true = File.lstat!(link).type == :symlink
File.rm!(link)
File.ln_s!(Path.join(root, "project/priv"), link)

for directory <- ~w(lib/ipse/session test/ipse/session test/support), do: File.mkdir_p!(Path.join([root, "project", directory]))
for path <- ~w(lib/ipse/session/resources.ex lib/ipse/session/stored_sources.ex test/ipse/session/source_lock_capacity_test.exs test/support/managed_policy.exs test/test_helper.exs) do
  File.cp!(path, Path.join([root, "project", path]))
end

frozen = File.read!("docs/archive/2026-10-28-retention-publication-deadline/sources/private_runner.ex")
start = "  @doc \"Acquire a persistent advisory lock. Its Port must remain owned by the session.\""
finish = "  @doc \"Release an owned lock Port. The lock file remains to preserve inode identity.\""
[prefix, frozen_rest] = String.split(frozen, start, parts: 2)
[old_block, suffix] = String.split(frozen_rest, finish, parts: 2)
actual = File.read!("lib/ipse/runner.ex")
[_, actual_rest] = String.split(actual, start, parts: 2)
[new_block, _] = String.split(actual_rest, finish, parts: 2)
true = String.contains?(old_block, "owned_port(:lock, helper")
true = String.contains?(new_block, "owned_port(kind, helper") and String.contains?(new_block, "def lock_source(path)")
runner = prefix <> start <> new_block <> finish <> suffix
runner_path = Path.join(root, "project/lib/ipse/runner.ex")
File.write!(runner_path, runner)

:ok = :code.add_paths(Path.wildcard(root <> "/lib/*/ebin") |> Enum.map(&String.to_charlist/1))
Code.compiler_options(ignore_module_conflict: true)
sources = [runner_path, Path.join(root, "project/lib/ipse/session/resources.ex"), Path.join(root, "project/lib/ipse/session/stored_sources.ex")]
{:ok, _, %{compile_warnings: [], runtime_warnings: []}} = Kernel.ParallelCompiler.compile_to_path(sources, Path.join(root, "lib/ipse/ebin"), return_diagnostics: true)
helper = File.read!(Path.join(root, "project/priv/ipse-runner"))
"113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550" = Base.encode16(:crypto.hash(:sha256, helper), case: :lower)
System.delete_env("IPSE_RUNNER_PATH")
Code.require_file(Path.join(root, "project/test/test_helper.exs"))
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.join(root, "project/test/ipse/session/source_lock_capacity_test.exs"))
