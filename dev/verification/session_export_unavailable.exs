# Run only in an isolated graph pinned to a legacy native helper that has no
# --lock-export-v1 mode. This verifies the internal candidate refuses without
# creating or silently acquiring a legacy lock.
{:ok, _} = Application.ensure_all_started(:ipse)
root = Path.join(System.tmp_dir!(), "ipse-export-unavailable-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
path = Path.join(root, String.duplicate("b", 32) <> ".lock")

try do
  {:error, _} = Ipse.Session.Lock.acquire_export_candidate(path)
  false = File.exists?(path)
  {:ok, legacy} = Ipse.Runner.protected_lock(path)
  :ok = Ipse.Runner.unlock(legacy)
  IO.puts("EXPORT_START_UNAVAILABLE_NO_FALLBACK")
after
  File.rm_rf!(root)
end
