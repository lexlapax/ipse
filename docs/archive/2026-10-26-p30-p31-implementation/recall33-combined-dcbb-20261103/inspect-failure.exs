root = "/dev/shm/ipse-native-recall-872f65241b8c07911d1b5f817ac41184"
dir = Path.join(root, "home/sessions")
{:ok, before} = root |> Path.join("recall-source-before.json") |> File.read!() |> Jason.decode()
identity = fn stat -> [stat.major_device, stat.minor_device, stat.inode, stat.uid] end
checks = Enum.map(before, fn %{"id" => id} = entry ->
  journal = Path.join(dir, id <> ".jsonl")
  lock = Path.join(dir, id <> ".lock")
  with {:ok, journal_stat} <- File.stat(journal), {:ok, lock_stat} <- File.stat(lock), {:ok, data} <- File.read(journal) do
    hash = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
    identity.(journal_stat) == entry["journal_identity"] and identity.(lock_stat) == entry["lock_identity"] and hash == entry["journal_sha256"] and not File.exists?(journal <> ".held")
  else
    _ -> false
  end
end)
IO.inspect(%{source_count: length(before), source_fingerprints_match: Enum.count(checks, & &1), source_fingerprints_mismatch: Enum.count(checks, &(not &1))}, label: "source_restoration")
files = Path.wildcard(Path.join(dir, "*.jsonl"))
read_events = fn file -> file |> File.stream!() |> Enum.map(&Jason.decode!/1) end
matched = Enum.filter(files, fn file -> Enum.any?(read_events.(file), &(&1["type"] == "inference_dispatch_intent")) end)
IO.puts("journals_with_dispatch_intent=#{length(matched)}")
for file <- matched do
  events = read_events.(file)
  IO.puts("synthetic_consumer=" <> Path.basename(file))
  for {event, index} <- Enum.with_index(events), event["type"] in ~w(managed_preflight_intent managed_preflight_result inference_dispatch_intent request_measured request_finished turn_finished) do
    IO.inspect(%{index: index, keys: Map.keys(event) |> Enum.sort(), fields: Map.take(event, ~w(type status reason error timestamp at elapsed_ms duration_ms latency_ms))}, limit: :infinity)
  end
end
