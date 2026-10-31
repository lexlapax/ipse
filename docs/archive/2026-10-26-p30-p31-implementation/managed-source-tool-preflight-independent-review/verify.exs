base = "docs/archive/2026-10-26-p30-p31-implementation/managed-source-tool-preflight"
sha = fn bytes -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) end

parse = fn bytes ->
  bytes
  |> String.split("\n", trim: true)
  |> Map.new(fn l ->
    [s, p] = String.split(l, "  ", parts: 2)
    {p, s}
  end)
end

manifest = File.read!(base <> "/manifest.sha256")
"6081e0c06d7d9631c5f09039eda50330f5f336676673b03a6fb403984fa01b0f" = sha.(manifest)
rows = parse.(manifest)
Enum.each(rows, fn {p, s} -> ^s = sha.(File.read!(Path.join(base, p))) end)

inventories =
  Enum.map(
    [
      {"runtime-positive-v3.sha256", "_build/source-tool-preflight-positive-v3-sol-20261029",
       "positive-beams"},
      {"runtime-final.sha256", "_build/source-tool-preflight-sol-20261029", "final-beams"}
    ],
    fn {name, root, beams} ->
      inventory = parse.(File.read!(base <> "/" <> name))
      Enum.each(inventory, fn {p, s} -> ^s = sha.(File.read!(Path.join(root, p))) end)

      for file <- File.ls!(base <> "/" <> beams) do
        retained = File.read!(base <> "/" <> beams <> "/" <> file)
        ^retained = File.read!(root <> "/_build/dev/lib/ipse/ebin/" <> file)
      end

      "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02" =
        sha.(File.read!(root <> "/priv/ipse-runner"))

      IO.puts("#{name}: #{map_size(inventory)} exact runtime hashes; retained BEAMs/helper exact")
      inventory
    end
  )

[positive, final] = inventories
true = MapSet.new(Map.keys(positive)) == MapSet.new(Map.keys(final))

changed =
  Enum.filter(final, fn {p, s} -> positive[p] != s end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

expected =
  Enum.map(
    ~w(ManagedLineage ManagedToolUse),
    &("_build/dev/lib/ipse/ebin/Elixir.Ipse.Session." <> &1 <> ".beam")
  )
  |> Enum.sort()

^expected = changed
IO.puts("#{map_size(rows)} manifest rows verified; exactly two positive→final runtime changes")

sources =
  for name <- ~w(source-positive-v3.tar source-final.tar) do
    {:ok, files} = :erl_tar.extract(String.to_charlist(base <> "/" <> name), [:memory])
    Map.new(files, fn {p, b} -> {List.to_string(p), sha.(b)} end)
  end

[old_sources, new_sources] = sources
10 = map_size(old_sources)
10 = map_size(new_sources)
true = MapSet.new(Map.keys(old_sources)) == MapSet.new(Map.keys(new_sources))

source_changes =
  Enum.filter(new_sources, fn {p, s} -> old_sources[p] != s end)
  |> Enum.map(&elem(&1, 0))
  |> Enum.sort()

["lib/ipse/session/managed_lineage.ex", "lib/ipse/session/managed_tool_use.ex"] = source_changes

IO.puts(
  "Both ten-source tar cohorts verified; exactly ManagedLineage/ManagedToolUse source changes"
)

for {name, count} <- [{"model", 2}, {"quote", 3}] do
  events =
    File.read!(base <> "/journals/" <> name <> ".jsonl")
    |> String.split("\n", trim: true)
    |> Enum.map(&:json.decode/1)

  pre = Enum.filter(events, &(&1["type"] == "managed_source_lookup_prepared"))

  obs =
    Enum.filter(events, &(&1["type"] == "managed_tool_result_observed" and &1["version"] == 2))

  ^count = length(pre)
  ^count = length(obs)

  for p <- pre do
    [o] = Enum.filter(obs, &(&1["call_id"] == p["call_id"]))
    true = o["source_selection_sha256"] === p["selection_sha256"]
    true = o["dependencies_sha256"] === p["dependencies_sha256"]
  end

  [intent] =
    Enum.filter(
      events,
      &(&1["type"] == "extension_action_intent" and
          get_in(&1, ["request", "op"]) == "collection.managed")
    )

  [result] =
    Enum.filter(
      events,
      &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"])
    )

  "ok" = result["outcome"]["status"]
  "saved_consent" = result["approval"]

  true =
    Enum.any?(
      events,
      &(&1["type"] == "managed_output_release_result" and &1["decision"] == "historical_write")
    )

  true = Enum.any?(events, &(&1["type"] == "managed_preflight_refused"))
  log = File.read!(base <> "/logs/" <> if(name == "model", do: "positive.log", else: "quote.log"))
  true = String.contains?(log, "HEADLESS_DONE :error")
  true = String.contains?(log, "HEADLESS_SOURCE_PREVIEWS_STATUS_ONLY")
  lines = String.split(log, "\n")

  tagged = fn tag ->
    lines
    |> Enum.find(&String.starts_with?(&1, tag))
    |> String.replace_prefix(tag, "")
    |> String.trim()
    |> :json.decode()
  end

  consent = tagged.("HEADLESS_CONSENT ")
  operation = consent["operations"][intent["operation_id"]]
  "settled" = operation["status"]
  true = operation["receipt"] === result["outcome"]
  root = tagged.("HEADLESS_ROOT ")
  1 = root["snapshot"]["generation"]
  true = root["snapshot"]["floor_anchor"] === intent["operation_id"]
  [record] = root["page"]["records"]
  [proof] = record["value"]["evidence"]["sources"]
  "typed_host_outcome" = proof["origin"]
  "tool.outcome" = proof["kind"]

  IO.puts(
    "#{name}: #{count} selections/results agree; exact settled receipt and generation-1 floor; final turn error/stale refusal retained"
  )
end

ordinary =
  File.read!(base <> "/journals/ordinary.jsonl")
  |> String.split("\n", trim: true)
  |> Enum.map(&:json.decode/1)

1 = Enum.count(ordinary, &(&1["type"] == "managed_source_lookup_prepared"))
message = Enum.find(ordinary, &(get_in(&1, ["message", "tool_call_id"]) == "ordinary_source"))
[_ | _] = :json.decode(message["message"]["content"])["sources"]
IO.puts("Ordinary journal retains one prepared source call and complete nonempty source result")
