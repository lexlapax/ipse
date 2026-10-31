# Isolated graph with the earlier native helper that does not implement export.
{:ok, _} = Application.ensure_all_started(:ipse)
root = Path.join(System.tmp_dir!(), "ipse-genuine-export-unavailable-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
state_dir = Path.join(root, "state")
File.mkdir!(state_dir)
File.chmod!(state_dir, 0o700)

opts = [
  config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
  cwd: root,
  state_dir: state_dir,
  subscriber: self()
]

try do
  parent = self()

  spawn(fn ->
    Process.flag(:trap_exit, true)
    send(parent, {:candidate_result, Ipse.Session.start_export_candidate_link(opts)})
  end)

  receive do
    {:candidate_result, {:error, _}} -> :ok
    {:candidate_result, other} -> raise "candidate unexpectedly started: #{inspect(other)}"
  after
    5_000 -> raise "candidate startup did not finish"
  end

  [] = Path.wildcard(Path.join(state_dir, "*.lock"))
  [] = Path.wildcard(Path.join(state_dir, "*.jsonl"))
  {:ok, legacy} = Ipse.Session.start_link(opts)
  :ok = Ipse.Session.close_confirmed(legacy)
  IO.puts("GENUINE_SESSION_EXPORT_UNAVAILABLE_NO_FALLBACK_NO_ORPHAN_JOURNAL")
after
  File.rm_rf!(root)
end
