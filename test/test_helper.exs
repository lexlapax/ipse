# macOS exposes /var aliases for temporary directories. Keep fixture expectations
# physical, as session workspace metadata intentionally resolves those aliases.
{:ok, temporary_root} = Ipse.WorkspaceContext.canonical_path(System.tmp_dir!())
System.put_env("TMPDIR", temporary_root)

# CLI/default discovery must never inspect the operator's installed skills or
# auth during fixtures. Individual tests may further isolate IPSE_HOME.
operator_home =
  Path.join(temporary_root, "ipse-test-operator-#{System.unique_integer([:positive])}")

File.mkdir_p!(operator_home)
System.put_env("HOME", operator_home)
System.put_env("IPSE_HOME", Path.join(operator_home, ".ipse"))
System.at_exit(fn _ -> File.rm_rf!(operator_home) end)

ExUnit.start(exclude: [:native_sandbox, :macos_sandbox])
