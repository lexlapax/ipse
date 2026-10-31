base = "docs/archive/2026-10-26-p30-p31-implementation"
gap = base <> "/document-producer-source-egress-gap"
worker = base <> "/shared-producer-worker-policy-repair"
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
verify_lines = fn data, load ->
  lines = String.split(data, "\n", trim: true)
  for line <- lines do
    [expected, path] = String.split(line, "  ", parts: 2)
    true = sha.(load.(path)) == expected
    path
  end
end
manifest = File.read!(gap <> "/manifest.sha256")
true = sha.(manifest) == "1baa506e5b88280923b2ed0251ad529d9be2370e4230e706a9a86fe51807966c"
verify_lines.(manifest, &File.read!(Path.join(gap, &1)))
{:ok, contents} = :erl_tar.extract(String.to_charlist(gap <> "/source.tar"), [:memory])
files = Map.new(contents, fn {p, b} -> {List.to_string(p), b} end)
paths = verify_lines.(File.read!(gap <> "/source.sha256"), &Map.fetch!(files, &1))
true = length(paths) == 28 and Enum.sort(paths) == Enum.sort(Map.keys(files))
bytes = File.read!(worker <> "/manifest.json")
true = sha.(bytes) == "7f880bd4bc594fea9dfb8026c1aaa530e98b958ddf8f568bcb758b88225b9ad7"
m = :json.decode(bytes)
check = fn r ->
  true = File.lstat!(r["path"]).type == :regular
  b = File.read!(r["path"])
  true = byte_size(b) == r["bytes"] and sha.(b) == r["sha256"]
end
for k <- ~w(source logs artifact_files), r <- m[k], do: check.(r)
check.(m["ancestor"])
walk = fn f, p ->
  case File.lstat!(p).type do
    :regular -> [p]
    :directory -> Enum.flat_map(File.ls!(p), &f.(f, Path.join(p, &1)))
  end
end
true = Enum.sort(walk.(walk, "_build/shared-producer-policy-corpus-20261029")) ==
  Enum.sort(Enum.map(m["artifact_files"], & &1["path"]))
producer = "extensions/knowledge/src/store/collection/producer.ex"
producer_row = Enum.find(m["source"], &(&1["original"] == producer))
true = File.read!(producer_row["path"]) == files[producer]
IO.inspect(%{source_only_tar_files: map_size(files), worker_sources_and_freezer: length(m["source"]), retained_logs: length(m["logs"]), candidate_artifact_files: length(m["artifact_files"]), producer_snapshots_identical: true, executed_tests: 0}, label: "SOURCE_EGRESS_REVIEW_OK")
