[root] = System.argv()
before = root |> Path.join("recall-source-before.json") |> File.read!() |> :json.decode()
identity = fn stat -> [stat.major_device, stat.minor_device, stat.inode, stat.uid] end
after_rows = Enum.map(before, fn row ->
  id = row["id"]
  true = Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
  journal = Path.join([root, "home/sessions", id <> ".jsonl"])
  lock = Path.join([root, "home/sessions", id <> ".lock"])
  js = File.lstat!(journal)
  ls = File.lstat!(lock)
  true = js.type == :regular and ls.type == :regular
  {:error, :enoent} = File.lstat(journal <> ".held")
  %{"id" => id, "journal_identity" => identity.(js), "lock_identity" => identity.(ls), "journal_sha256" => :crypto.hash(:sha256, File.read!(journal)) |> Base.encode16(case: :lower)}
end)
true = length(before) == 33 and before === after_rows
IO.iodata_to_binary(:json.encode(after_rows)) |> IO.write()
