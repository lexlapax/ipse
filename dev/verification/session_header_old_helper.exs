# The isolated runtime must pin an earlier helper without --session-header-v1.
{:ok, _} = Application.ensure_all_started(:ipse)
root = Path.join(System.tmp_dir!(), "ipse-header-old-helper-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
dir = Path.join(root, "state")
File.mkdir!(dir)
File.chmod!(dir, 0o700)
parent = self()

try do
  spawn(fn ->
    Process.flag(:trap_exit, true)

    send(
      parent,
      {:startup,
       Ipse.Session.start_link(
         config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
         cwd: root,
         state_dir: dir,
         subscriber: parent
       )}
    )
  end)

  receive do
    {:startup, {:error, _}} -> :ok
    {:startup, other} -> raise "old helper unexpectedly started: #{inspect(other)}"
  after
    10_000 -> raise "startup did not finish"
  end

  [] = File.ls!(dir)
  IO.puts("OLD_HELPER_FRESH_SESSION_REFUSED_NO_LOCK_NO_JOURNAL_NO_FALLBACK")
after
  File.rm_rf!(root)
end
