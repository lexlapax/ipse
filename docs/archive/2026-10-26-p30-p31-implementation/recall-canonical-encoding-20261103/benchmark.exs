Code.prepend_paths(Path.wildcard("/home/lexlapax/projects/lexlapax/ipse/_build/test/lib/*/ebin"))
alias Ipse.Session.{Input, Saved, SourceWindow, SourceReplayCache}
{:ok, _} = Application.ensure_all_started(:crypto)
IO.puts("RUNTIME_BEGIN")
for module <- [Input, Saved, SourceWindow, SourceReplayCache] do
  {^module, beam, path} = :code.get_object_code(module)
  {:ok, {^module, [{:compile_info, info}]}} = :beam_lib.chunks(beam, [:compile_info])
  IO.puts(inspect(%{module: module, beam_path: List.to_string(path), beam_sha256: Base.encode16(:crypto.hash(:sha256, beam), case: :lower), compiled_source: info[:source]}))
end
IO.puts("RUNTIME_END")
id = String.duplicate("a", 32)
header = %{"type" => "session", "metadata" => %{"source_layout" => SourceWindow.layout()}}
measure = fn fun ->
  :erlang.garbage_collect()
  {:reductions, before_r} = Process.info(self(), :reductions)
  {us, result} = :timer.tc(fun)
  {:reductions, after_r} = Process.info(self(), :reductions)
  unless match?({:ok, _}, result), do: raise("synthetic reconstruction refused")
  {us, after_r - before_r}
end
for bytes <- [5, 1_024], n <- [1, 8, 32, 128] do
  text = String.duplicate("x", bytes)
  events = [header | Enum.flat_map(1..n, fn _ -> [Input.received(id, Ipse.Usage.id(), text, text, nil), %{"type" => "message", "message" => %{"role" => "user", "content" => text}}] end)]
  {:ok, cache} = SourceReplayCache.start(self())
  miss = measure.(fn -> SourceReplayCache.restore(cache, events, id) end)
  state = :sys.get_state(cache.pid)
  unless map_size(state.entries) == 1, do: raise("cache did not retain synthetic index")
  hits = for _ <- 1..7, do: measure.(fn -> SourceReplayCache.restore(cache, events, id) end)
  restores = for _ <- 1..7, do: measure.(fn -> Saved.restore(events, id) end)
  windows = for _ <- 1..7, do: measure.(fn -> SourceWindow.restore(events, id) end)
  lookup = for _ <- 1..7 do
    {us, _} = :timer.tc(fn -> {:erlang.external_size(events), :crypto.hash(:sha256, :erlang.term_to_binary(events, [:deterministic]))} end)
    us
  end
  entry = state.entries |> Map.values() |> hd()
  summary = fn rows -> %{us: Enum.map(rows, &elem(&1, 0)), caller_reductions: Enum.map(rows, &elem(&1, 1))} end
  IO.puts(inspect(%{notes: n, text_bytes: bytes, events: length(events), event_external_bytes: :erlang.external_size(events), retained_index_bytes: entry.bytes, miss: miss, hits: summary.(hits), saved: summary.(restores), window: summary.(windows), lookup_us: lookup}, limit: :infinity, printable_limit: :infinity))
  GenServer.stop(cache.pid)
end
IO.puts("SYNTHETIC_CACHE_PHASE_PASSED")
