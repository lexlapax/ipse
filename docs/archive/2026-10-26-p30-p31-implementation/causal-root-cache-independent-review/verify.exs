base = "docs/archive/2026-10-26-p30-p31-implementation/causal-root-cache"
sha = fn bytes -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) end
manifest = File.read!(base <> "/manifest.sha256")
"8f1274b8270451c71840dd51fa4b4658e333433993be118d444307d274becaf7" = sha.(manifest)

parse = fn text ->
  text
  |> String.split("\n", trim: true)
  |> Map.new(fn line ->
    [digest, path] = String.split(line, "  ", parts: 2)
    {path, digest}
  end)
end

entries = parse.(manifest)
Enum.each(entries, fn {path, digest} -> ^digest = sha.(File.read!(Path.join(base, path))) end)
runtime = parse.(File.read!(base <> "/runtime.sha256"))
root = "_build/notes-root-cache-sol-20261029"
Enum.each(runtime, fn {path, digest} -> ^digest = sha.(File.read!(Path.join(root, path))) end)

previous =
  parse.(
    File.read!(
      "docs/archive/2026-10-26-p30-p31-implementation/remember-publication-absence-integration/runtime.sha256"
    )
  )

true = Map.keys(runtime) |> MapSet.new() |> MapSet.equal?(MapSet.new(Map.keys(previous)))

changed =
  Enum.filter(runtime, fn {path, digest} -> previous[path] != digest end)
  |> Enum.map(&elem(&1, 0))
  |> Enum.sort()

expected =
  Enum.map(
    ~w(ManagedLineage ManagedReads ManagedToolUse),
    &("_build/dev/lib/ipse/ebin/Elixir.Ipse.Session." <> &1 <> ".beam")
  )
  |> Enum.sort()

^expected = changed

for name <- ~w(ManagedLineage ManagedReads ManagedToolUse) do
  bytes = File.read!(base <> "/beams/Elixir.Ipse.Session." <> name <> ".beam")
  ^bytes = File.read!(root <> "/_build/dev/lib/ipse/ebin/Elixir.Ipse.Session." <> name <> ".beam")
end

events =
  File.read!(base <> "/session.jsonl")
  |> String.split("\n", trim: true)
  |> Enum.map(&:json.decode/1)

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

for name <- ~w(write shell) do
  call =
    for(
      e <- events,
      c <- get_in(e, ["message", "tool_calls"]) || [],
      get_in(c, ["function", "name"]) == name,
      do: c
    )
    |> hd()

  [message] = Enum.filter(events, &(get_in(&1, ["message", "tool_call_id"]) == call["id"]))
  "denied" = get_in(message, ["message", "ipse_tool_outcome", "status"])
end

false =
  Enum.any?(events, fn event ->
    Enum.any?(
      get_in(event, ["message", "tool_calls"]) || [],
      &(get_in(&1, ["function", "name"]) in ~w(source_list source_read source_quote))
    )
  end)

IO.puts(
  "#{map_size(entries)} frozen entries and #{map_size(runtime)} runtime hashes verified; exactly three named BEAM changes"
)

IO.puts(
  "Retained #{length(events)}-event direct-client journal: one known headless managed result; write/shell denied; no model source-tool call"
)

lines =
  File.read!(base <> "/logs/ipse-headless-typed-root-cache-20261029.log") |> String.split("\n")

tagged = fn tag ->
  lines
  |> Enum.find(&String.starts_with?(&1, tag))
  |> String.replace_prefix(tag, "")
  |> String.trim()
  |> :json.decode()
end

consent = tagged.("HEADLESS_CONSENT ")
root_value = tagged.("HEADLESS_ROOT ")
operation = consent["operations"][intent["operation_id"]]
true = operation["receipt"] === result["outcome"]
"settled" = operation["status"]
true = operation["headless"]

%{"operations" => 1, "input_bytes" => 4801, "output_bytes" => 16384, "model_calls" => 0} =
  operation["actual"]

1 = root_value["snapshot"]["generation"]
true = root_value["snapshot"]["floor_anchor"] === intent["operation_id"]
[record] = root_value["page"]["records"]
[proof] = record["value"]["evidence"]["sources"]
"typed_host_outcome" = proof["origin"]
"tool.outcome" = proof["kind"]

IO.puts(
  "Retained native/Consent readback: settled exact receipt; generation-1 floor anchor; typed host-outcome proof; 4801/16384 bytes, zero effect model calls"
)
