# Compare only retained synthetic source identities with the fixture's pre-run inventory.
[root] = System.argv()
try do
  true = Regex.match?(~r<\A/dev/shm/ipse-native-recall-[0-9a-f]{32}\z>, root)
  before = root |> Path.join("recall-source-before.json") |> File.read!() |> Jason.decode!()
  true = is_list(before) and length(before) == 33
  true = before |> Enum.map(& &1["id"]) |> Enum.uniq() |> length() == 33
  dir = Path.join(root, "home/sessions")
  identity = fn stat -> [stat.major_device, stat.minor_device, stat.inode, stat.uid] end
  checks = Enum.map(before, fn %{"id" => id} = entry ->
    true = is_binary(id) and Regex.match?(~r<\A[0-9a-f]{32}\z>, id)
    journal = Path.join(dir, id <> ".jsonl")
    lock = Path.join(dir, id <> ".lock")
    with {:ok, journal_stat} <- File.lstat(journal), {:ok, lock_stat} <- File.lstat(lock), {:ok, data} <- File.read(journal) do
      hash = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
      journal_stat.type == :regular and lock_stat.type == :regular and identity.(journal_stat) == entry["journal_identity"] and identity.(lock_stat) == entry["lock_identity"] and hash == entry["journal_sha256"] and match?({:error, :enoent}, File.lstat(journal <> ".held"))
    else
      _ -> false
    end
  end)
  true = Enum.all?(checks)
  IO.puts("synthetic_source_fingerprints=33/33")
rescue
  _ -> IO.puts("synthetic_source_fingerprints=inconclusive"); System.halt(2)
end
