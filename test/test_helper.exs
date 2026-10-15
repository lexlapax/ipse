# macOS exposes /var aliases for temporary directories. Keep fixture expectations
# physical, as session workspace metadata intentionally resolves those aliases.
{:ok, temporary_root} = Ipse.WorkspaceContext.canonical_path(System.tmp_dir!())
System.put_env("TMPDIR", temporary_root)

ExUnit.start(exclude: [:native_sandbox])
