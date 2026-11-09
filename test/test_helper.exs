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

unless System.get_env("IPSE_KEEP_TEST_OPERATOR_HOME") == "1" do
  System.at_exit(fn _ -> File.rm_rf!(operator_home) end)
end

# Protected native storage admits only reviewed kernel and filesystem profiles
# (native/ipse-storage-profile.rs) and refuses everywhere else by design. Ask the
# pinned helper whether the test temporary directory qualifies; tests tagged
# :native_storage need it and are excluded on other hosts instead of failing on
# the intended refusal. IPSE_TEST_NATIVE_STORAGE=1 makes a refusal fatal, for
# runs that must cover native storage. Any other probe result is fatal.
native_storage =
  Task.async(fn ->
    probe = Path.join(temporary_root, "ipse-test-storage-#{System.unique_integer([:positive])}")
    File.mkdir!(probe)
    File.chmod!(probe, 0o700)

    try do
      Ipse.Session.Resources.file_effect(fn ->
        with {:ok, cap} <- Ipse.Runner.Transaction.acquire(Path.join(probe, ".lock")) do
          result = Ipse.Runner.Transaction.quota(cap, :flat, 65_536)
          :ok = Ipse.Runner.Transaction.release(cap)
          result
        end
      end)
    after
      File.rm_rf!(probe)
    end
  end)
  |> Task.await(30_000)
  |> case do
    :ok ->
      :supported

    {:error, :transaction_filesystem_unsupported} ->
      if System.get_env("IPSE_TEST_NATIVE_STORAGE") == "1",
        do: raise("IPSE_TEST_NATIVE_STORAGE=1 but #{temporary_root} is not a reviewed profile")

      IO.puts(
        "Excluding :native_storage tests: #{temporary_root} is not a reviewed native storage profile on this host."
      )

      :unsupported

    other ->
      raise "native storage probe failed: #{inspect(other)}"
  end

ExUnit.start(
  exclude:
    if(native_storage == :unsupported, do: [:native_storage], else: []) ++
      [
        :native_sandbox,
        :macos_sandbox,
        :macos_filesystem,
        :memory_scope,
        :workspace_word_native,
        :controlled_tty_bridge,
        :controlled_tty_loss
      ]
)

Code.require_file("support/resume_assertions.exs", __DIR__)
Code.require_file("support/witnessed_draft.exs", __DIR__)

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
