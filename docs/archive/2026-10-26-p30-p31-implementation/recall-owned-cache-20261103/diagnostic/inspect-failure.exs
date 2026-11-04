# Read-only synthetic metadata only; no source or transcript content is printed.
[root] = System.argv()
dir = Path.join(root, "home/sessions")
before = root |> Path.join("recall-source-before.json") |> File.read!() |> :json.decode()
intent = root |> Path.join("recall-one-shot-intent.json") |> File.read!() |> :json.decode()
true = length(before) == 33 and length(Enum.uniq_by(before, & &1["id"])) == 33
true = Enum.sort(Enum.map(before, & &1["id"])) == Enum.sort(intent["source_ids"])
identity = fn stat -> [stat.major_device, stat.minor_device, stat.inode, stat.uid] end
checks = Enum.map(before, fn %{"id" => id} = entry ->
  true = is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
  journal = Path.join(dir, id <> ".jsonl")
  lock = Path.join(dir, id <> ".lock")
  with {:ok, journal_stat} <- File.lstat(journal), {:ok, lock_stat} <- File.lstat(lock), {:ok, data} <- File.read(journal) do
    journal_stat.type == :regular and lock_stat.type == :regular and
      identity.(journal_stat) == entry["journal_identity"] and identity.(lock_stat) == entry["lock_identity"] and
      (:crypto.hash(:sha256, data) |> Base.encode16(case: :lower)) == entry["journal_sha256"] and
      File.lstat(journal <> ".held") == {:error, :enoent}
  else
    _ -> false
  end
end)
IO.inspect(%{source_count: length(before), source_fingerprints_match: Enum.count(checks, & &1), source_fingerprints_mismatch: Enum.count(checks, &(not &1))}, label: "source_restoration")
consumer = intent["session_id"]
true = is_binary(consumer) and Regex.match?(~r/\A[a-f0-9]{32}\z/, consumer)
consumer_path = Path.join(dir, consumer <> ".jsonl")
%File.Stat{type: :regular} = File.lstat!(consumer_path)
events = consumer_path |> File.stream!() |> Enum.map(&:json.decode/1)
for {event, index} <- Enum.with_index(events), event["type"] in ~w(managed_preflight_intent managed_preflight_result inference_dispatch_intent request_measured request_finished turn_finished) do
  fields = Map.take(event, ~w(type status duration_ms))
  IO.inspect(%{index: index, keys: Map.keys(event) |> Enum.sort(), fields: fields}, limit: :infinity)
end
IO.inspect(Enum.frequencies_by(Enum.filter(events, &(&1["type"] == "worker_input_result")), & &1["status"]), label: "worker_input_statuses")
