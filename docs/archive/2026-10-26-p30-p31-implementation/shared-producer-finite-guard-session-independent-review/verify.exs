base = "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-finite-guard-session"
sha = fn b -> Base.encode16(:crypto.hash(:sha256, b), case: :lower) end
bytes = File.read!(base <> "/manifest.json")
"7b9d0f704b7a13cdd9ffc97b8c82ab2d93bc713e80aa33a1feacbf594e920b7f" = sha.(bytes)
m = :json.decode(bytes)

collect = fn recur, v ->
  cond do
    is_map(v) and is_binary(v["path"]) and (is_binary(v["sha256"]) or v["type"] == "symlink") ->
      [v]

    is_map(v) ->
      Enum.flat_map(Map.values(v), &recur.(recur, &1))

    is_list(v) ->
      Enum.flat_map(v, &recur.(recur, &1))

    true ->
      []
  end
end

rows = collect.(collect, m)

Enum.each(rows, fn r ->
  s = File.lstat!(r["path"])

  if r["type"] == "symlink" do
    true = s.type == :symlink and File.read_link!(r["path"]) === r["target"]
  else
    true = s.type == :regular and s.size === r["bytes"]
    true = sha.(File.read!(r["path"])) === r["sha256"]
  end
end)

parent = :json.decode(File.read!(m["ancestor"]["path"]))
true = m["exact_parent_runtime"] === Enum.at(parent["graphs"], 1)
true = m["exact_parent_artifact"] === parent["artifact"]

events =
  File.read!(base <> "/evidence/finite-positive/synthetic-session.jsonl")
  |> String.split("\n", trim: true)
  |> Enum.map(&:json.decode/1)

963 = length(events)
facts = :json.decode(File.read!(base <> "/evidence/finite-positive/facts.json"))
output = :json.decode(File.read!(base <> "/evidence/finite-positive/output.json"))
deadline = 1_793_322_447_085
^deadline = facts["original_finite_expiry"]
true = facts["finished_at_ms"] < deadline
35 = facts["ready"]["revision"]
"ready" = facts["ready"]["value"]["status"]
true = Enum.all?(facts["ready"]["value"]["source_bindings"], &(&1["expires_at_ms"] === deadline))

puts =
  Enum.filter(
    events,
    &(&1["type"] == "extension_invocation_intent" and
        get_in(&1, ["payload", "arguments", "action"]) == "put")
  )

4 = length(puts)

true =
  Enum.all?(puts, &(get_in(&1, ["payload", "arguments", "args", "expires_at_ms"]) === deadline))

embeddings =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "embedding.create")
  )

4 = length(embeddings)
[0, 1, 2, 3] = Enum.map(embeddings, & &1["request"]["source_guard"]["batch_index"])
true = Enum.all?(embeddings, &(&1["outcome"]["status"] == "ok"))
4 = length(output["wires"])
8 = output["store"]

true =
  Enum.map(embeddings, & &1["request"]["inputs"]) === Enum.map(output["wires"], & &1["inputs"])

:null = facts["old_selection"]
IO.puts("#{length(rows)} exact rows; runtime/artifact structurally identical to accepted parent")

IO.puts(
  "963-event journal: four original Source puts and ready bindings preserve expiry #{deadline}; four matching guarded bodies/known results; ready35, completion before expiry, selected absence unchanged"
)
