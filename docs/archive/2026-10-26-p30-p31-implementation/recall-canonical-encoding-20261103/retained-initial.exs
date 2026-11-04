Code.prepend_paths(Path.wildcard("/home/lexlapax/projects/lexlapax/ipse/_build/test/lib/*/ebin"))
alias Ipse.Session.{Saved, SourceWindow, SourceReplayCache}
{:ok, _} = Application.ensure_all_started(:crypto)
archive = "/home/lexlapax/projects/lexlapax/ipse/docs/archive/2026-10-26-p30-p31-implementation"
cases = [
  {"single8", "/dev/shm/ipse-source-phase-controls-f44-20261103-01/single/ipse-native-recall-4b7ee1d5ffe3255896fde1cc3100a8fe", archive <> "/source-owner-phase-20261103/single/phase-before.json"},
  {"split33", "/dev/shm/ipse-native-recall-fa547f3ae898e4bd50df06a2afe015dd", archive <> "/egress-diagnostic-dcbb-20261103/strict-source-before.json"}
]
digest = fn bytes -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) end
measure = fn fun ->
  {us, result} = :timer.tc(fun)
  unless match?({:ok, _}, result), do: raise("synthetic reconstruction refused")
  us
end
for {name, root, manifest} <- cases do
  sources = for row <- Jason.decode!(File.read!(manifest)) do
    id = row["id"]
    path = Path.join([root, "home", "sessions", id <> ".jsonl"])
    before = File.lstat!(path)
    unless before.type == :regular, do: raise("source not regular")
    bytes = File.read!(path)
    unless digest.(bytes) == row["journal_sha256"], do: raise("retained synthetic source hash mismatch")
    events = bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    {id, events, path, before, byte_size(bytes), row["journal_sha256"]}
  end
  {:ok, cache} = SourceReplayCache.start(self())
  misses = for {id, events, _, _, _, _} <- sources, do: measure.(fn -> SourceReplayCache.restore(cache, events, id) end)
  cached = :sys.get_state(cache.pid)
  hits = for _ <- 1..3 do
    for {id, events, _, _, _, _} <- sources, do: measure.(fn -> SourceReplayCache.restore(cache, events, id) end)
  end
  {id, events, _, _, _, _} = hd(sources)
  checks = [
    {:saved, fn -> Saved.restore(events, id) end},
    {:source_window, fn -> SourceWindow.restore(events, id) end},
    {:context, fn -> Saved.context(events) end},
    {:actions, fn -> Ipse.Extension.Actions.restore(events) end},
    {:usage, fn -> Ipse.Usage.restore(events, id) end},
    {:input, fn -> {:ok, Ipse.Session.Input.validate_events(events, id)} end},
    {:assertion, fn -> {:ok, Ipse.Session.OperatorAssertion.validate_events(events, id)} end}
  ]
  components = Map.new(checks, fn {label, fun} -> {label, for(_ <- 1..3, do: measure.(fun))} end)
  IO.puts(inspect(%{case: name, source_count: length(sources), journal_bytes: Enum.map(sources, &elem(&1, 4)), event_counts: Enum.map(sources, &(length(elem(&1, 1)))), cache_entries: map_size(cached.entries), cache_bytes: cached.bytes, miss_us: misses, hit_us: hits, first_source_components_us: components}, charlists: :as_lists, limit: :infinity))
  if name == "split33" do
    :eprof.start()
    :eprof.profile([self()], fn -> Saved.restore(events, id) end)
    :eprof.analyze(:total, filter: [{:time, 100}])
    :eprof.stop()
  end
  for {_, _, path, before, _, sha} <- sources do
    after_stat = File.lstat!(path)
    unless before == after_stat and digest.(File.read!(path)) == sha, do: raise("original synthetic source changed")
  end
  GenServer.stop(cache.pid)
end
IO.puts("RETAINED_SYNTHETIC_SOURCE_PHASE_PASSED")
