base = "docs/archive/2026-10-26-p30-p31-implementation/own-root-transition"
root = "_build/own-root-transition-sol-20261029"
hash = fn b -> Base.encode16(:crypto.hash(:sha256, b), case: :lower) end

parse = fn b ->
  b
  |> String.split("\n", trim: true)
  |> Map.new(fn l ->
    [s, p] = String.split(l, "  ", parts: 2)
    {p, s}
  end)
end

manifest = File.read!(base <> "/manifest.sha256")
"899cc69b4eea94b1aa84b7b2a597cc8e7ebe932f686ffcc1caba8907d4da64ca" = hash.(manifest)
rows = parse.(manifest)
Enum.each(rows, fn {p, s} -> ^s = hash.(File.read!(Path.join(base, p))) end)
runtime = parse.(File.read!(base <> "/runtime.sha256"))
Enum.each(runtime, fn {p, s} -> ^s = hash.(File.read!(Path.join(root, p))) end)

parent =
  parse.(
    File.read!(
      "docs/archive/2026-10-26-p30-p31-implementation/managed-source-tool-preflight/runtime-final.sha256"
    )
  )

true = MapSet.new(Map.keys(runtime)) === MapSet.new(Map.keys(parent))

changed =
  Enum.filter(runtime, fn {p, s} -> parent[p] !== s end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

expected =
  Enum.map(
    ~w(ManagedLineage ManagedReference.Plan ManagedReference.State ManagedReference ManagedUse),
    &("_build/dev/lib/ipse/ebin/Elixir.Ipse.Session." <> &1 <> ".beam")
  ) ++ ["_build/dev/lib/ipse/ebin/Elixir.Ipse.Session.beam"]

true = changed === Enum.sort(expected)

for f <- File.ls!(base <> "/beams") do
  b = File.read!(base <> "/beams/" <> f)
  ^b = File.read!(root <> "/_build/dev/lib/ipse/ebin/" <> f)
end

"40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02" =
  hash.(File.read!(root <> "/priv/ipse-runner"))

Code.prepend_paths(Path.wildcard(root <> "/_build/dev/lib/*/ebin"))
digest = &Ipse.JSON.digest/1

events =
  File.read!(base <> "/journals/model-final.jsonl")
  |> String.split("\n", trim: true)
  |> Enum.map(&Jason.decode!/1)

1 = Enum.count(events, &(&1["type"] == "input_received"))
4 = Enum.count(events, &(&1["type"] == "managed_source_lookup_prepared"))
true = Enum.any?(events, &(&1["type"] == "turn_finished" and &1["status"] == "ok"))
false = Enum.any?(events, &(&1["type"] == "managed_preflight_refused"))

[transition] =
  Enum.filter(
    events,
    &(&1["type"] == "managed_preflight_result" and
        get_in(&1, ["projection", "type"]) == "managed_root_transition")
  )

p = transition["projection"]
1 = p["version"]
[old] = p["old_dependencies"]
0 = old["collection"]["generation"]
"absent" = old["collection"]["root_state"]
fresh = p["fresh_dependency"]
1 = fresh["collection"]["generation"]
"present" = fresh["collection"]["root_state"]
true = p["old_dependencies_sha256"] === digest.(p["old_dependencies"])

[action] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and &1["operation_id"] == p["operation_id"])
  )

"ok" = action["outcome"]["status"]
true = p["own_action_sha256"] === digest.([action])
receipt = action["outcome"]["value"]["receipt"]
true = p["receipt_sha256"] === digest.([receipt])
true = p["inspection"]["operation"] === receipt
true = p["inspection"]["floor_anchor"] === p["operation_id"]
true = fresh["collection"]["floor_anchor"] === p["operation_id"]
true = p["fresh_observation"]["value"] === Map.delete(p["inspection"], "operation")
1 = receipt["generation"]
reads = Enum.filter(events, &(&1["type"] == "managed_read_observed"))
3 = length(reads)

true =
  Enum.all?(reads, fn r ->
    Enum.all?(r["dependencies"], &(&1["collection"] === old["collection"]))
  end)

log = File.read!(base <> "/logs/ipse-own-root-model-v3-20261029.log")
true = String.contains?(log, "HEADLESS_DONE :ok")
true = String.contains?(log, "HEADLESS_SOURCE_PREVIEWS_STATUS_ONLY")
lines = String.split(log, "\n")

tagged = fn tag ->
  lines
  |> Enum.find(&String.starts_with?(&1, tag))
  |> String.replace_prefix(tag, "")
  |> String.trim()
  |> Jason.decode!()
end

consent = tagged.("HEADLESS_CONSENT ")
operation = consent["operations"][p["operation_id"]]
"settled" = operation["status"]
true = operation["receipt"] === action["outcome"]
root_value = tagged.("HEADLESS_ROOT ")
1 = root_value["snapshot"]["generation"]
true = root_value["snapshot"]["floor_anchor"] === p["operation_id"]
release = :json.decode(File.read!(base <> "/journals/model-final.release.json"))
"unlocked_exit_0" = release["body"]["native_outcome"]

IO.puts(
  "#{map_size(rows)} frozen entries, #{map_size(runtime)} runtime hashes and exact six-BEAM delta verified; helper unchanged"
)

IO.puts(
  "Final #{length(events)}-event journal: authentic absent0→present1 transition binds own action/receipt/fresh observation; three old root reads, four source lookups, one input, settled exact Consent/native floor and final turn ok; no refused preflight"
)
