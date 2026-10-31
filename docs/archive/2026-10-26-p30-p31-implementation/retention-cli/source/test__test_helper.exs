# macOS exposes /var aliases for temporary directories. Keep fixture expectations
# physical, as session workspace metadata intentionally resolves those aliases.
{:ok, temporary_root} = Ipse.Workspace.canonical_path(System.tmp_dir!())
System.put_env("TMPDIR", temporary_root)

# CLI/default discovery must never inspect the operator's installed skills or
# auth during fixtures. Individual tests may further isolate IPSE_HOME.
operator_home =
  Path.join(temporary_root, "ipse-test-operator-#{System.unique_integer([:positive])}")

File.mkdir_p!(operator_home)

# Rustup resolves its toolchain from HOME unless configured separately. Preserve
# that compiler location before isolating operator discovery; no skills/auth from
# the real home are loaded by this fixture setup.
rustup_home = Path.join(Ipse.Workspace.operator_home(), ".rustup")

if is_nil(System.get_env("RUSTUP_HOME")) and File.dir?(rustup_home),
  do: System.put_env("RUSTUP_HOME", rustup_home)

System.put_env("HOME", operator_home)
System.put_env("IPSE_HOME", Path.join(operator_home, ".ipse"))
System.at_exit(fn _ -> File.rm_rf!(operator_home) end)

ExUnit.start(exclude: [:native_sandbox, :macos_sandbox, :macos_filesystem, :memory_scope])

defmodule Ipse.Test.FileEffectProbe do
  def fifo!(path) do
    probe = path <> ".probe"

    try do
      {_, 0} =
        System.cmd("rustc", ["--edition=2021", "test/support/file_effect_probe.rs", "-o", probe],
          stderr_to_stdout: true
        )

      {_, 0} = System.cmd(probe, ["--fifo-only", path])
      :ok
    after
      File.rm(probe)
    end
  end
end
