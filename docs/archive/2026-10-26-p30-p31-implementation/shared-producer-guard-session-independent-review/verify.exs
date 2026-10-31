base = "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session"
hash = fn bytes -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) end
bytes = File.read!(base <> "/manifest.json")
"c191be053710bcc6c291b62edb8f600837477e9ee7c9642d489dfd36d6fe904b" = hash.(bytes)
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

check = fn r ->
  stat = File.lstat!(r["path"])

  if r["type"] == "symlink" do
    true = stat.type == :symlink and File.read_link!(r["path"]) === r["target"]
  else
    true = stat.type == :regular and stat.size === r["bytes"]
    true = hash.(File.read!(r["path"])) === r["sha256"]
  end
end

rows = collect.(collect, m)
Enum.each(rows, check)

index = fn g ->
  Map.new(g["rows"], &{Path.relative_to(&1["path"], g["root"]), Map.delete(&1, "path")})
end

[inventory, actual, _diagnostic] = m["graphs"]
a = index.(inventory)
b = index.(actual)
true = MapSet.new(Map.keys(a)) == MapSet.new(Map.keys(b))

["_build/dev/lib/ipse/ebin/Elixir.Ipse.Session.DocumentEmbedding.beam"] =
  Enum.filter(Map.keys(a), &(a[&1] !== b[&1]))

for graph <- m["graphs"] do
  %{"regular" => 699, "symlink" => 2} = Enum.frequencies_by(graph["rows"], & &1["type"])

  {:ok, [{:application, :ipse, props}]} =
    :file.consult(String.to_charlist(graph["root"] <> "/_build/dev/lib/ipse/ebin/ipse.app"))

  216 = length(props[:modules])
end

{listed, 0} = System.cmd("rg", ["--files", "--hidden", "--no-ignore", m["artifact"]["root"]])

true =
  MapSet.new(String.split(listed, "\n", trim: true)) ==
    MapSet.new(Enum.map(m["artifact"]["rows"], & &1["path"]))

"8de1ae2e139b416b8cdf7c8015f6b2c990e9003bc3f445bd4b2bd7b3a517b229" =
  hash.(File.read!(m["artifact"]["root"] <> "/extension.json"))

production = File.read!(base <> "/production-corpus.ex.txt")

delegated =
  String.replace(
    production,
    "finish(state, refused(:shared_producer_source_dispatch_unavailable))",
    "advance(IpseKnowledge.Store.Collection.Producer.start(state.resolved, profile, Map.delete(args, \"store\")), %{state | phase: :collection_producer, ctx: %{args: args}})",
    global: false
  )

ast = fn text ->
  Code.string_to_quoted!(text)
  |> Macro.prewalk(fn
    {tag, meta, args} when is_list(meta) -> {tag, [], args}
    x -> x
  end)
end

true = ast.(delegated) === ast.(File.read!(base <> "/private-package/src/corpus.ex"))

IO.puts(
  "#{length(rows)} exact rows, three 699+2 inventories/216-module apps; return graph only DocumentEmbedding BEAM delta; exact26 artifact files; sole Corpus page-delegation AST delta"
)

for ancestor <- m["ancestors"] do
  data = :json.decode(File.read!(ancestor["path"]))
  direct = collect.(collect, data)
  Enum.each(direct, check)

  IO.puts(
    "Ancestor #{Path.basename(Path.dirname(ancestor["path"]))}: #{length(direct)} direct rows exact"
  )

  if data["source_tar"] do
    {:ok, files} = :erl_tar.extract(String.to_charlist(data["source_tar"]["path"]), [:memory])
    source = Map.new(files, fn {p, v} -> {List.to_string(p), v} end)
    hashes = File.read!(data["source_hashes"]["path"]) |> String.split("\n", trim: true)
    175 = length(hashes)
    175 = map_size(source)

    Enum.each(hashes, fn line ->
      [sha, path] = String.split(line, "  ", parts: 2)
      ^sha = hash.(Map.fetch!(source, path))
    end)

    IO.puts(
      "Initial Host source tar: all175 exact members; retained prefix excludes later return repair"
    )
  end
end

for {name, expected_count} <- [{"positive", 4}, {"expiry", 1}] do
  events =
    File.read!(base <> "/evidence/" <> name <> "/synthetic-session.jsonl")
    |> String.split("\n", trim: true)
    |> Enum.map(&:json.decode/1)

  actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
  embeddings = Enum.filter(actions, &(&1["request"]["op"] == "embedding.create"))
  ^expected_count = length(embeddings)
  first = hd(embeddings)
  id = first["namespace"]
  guard = first["request"]["source_guard"]
  parent = first["parent_invocation_id"]
  own = Enum.filter(actions, &(&1["parent_invocation_id"] == parent))

  prepare =
    Enum.find(
      own,
      &(get_in(&1, ["request", "request", "op"]) == "value.prepare_inline" and
          get_in(&1, ["request", "request", "key"]) == guard["claim_key"])
    )

  0 = prepare["request"]["request"]["expected_revision"]
  true = prepare["request"]["request"]["sha256"] === guard["claim_sha256"]
  ref = Map.take(prepare["outcome"]["value"]["result"]["stage"], ~w(slot epoch))

  commit =
    Enum.find(
      own,
      &(get_in(&1, ["request", "request", "op"]) == "commit" and
          get_in(&1, ["request", "request", "stages"]) == [ref])
    )

  "ok" = commit["outcome"]["status"]
  true = commit["outcome"]["value"]["result"]["generation"] === guard["claim_revision"]
  claim = :json.decode(prepare["request"]["request"]["data"])
  "pending" = claim["status"]

  for e <- embeddings do
    true = e["effect_binding"]["source_binding"]["session_id"] === id
    "shared_producer_v1" = e["effect_binding"]["source_binding"]["operator_binding"]["source_use"]

    true =
      e["request"]["expected_selection_sha256"] === claim["vector_selection"]["selection_sha256"]
  end

  output = :json.decode(File.read!(base <> "/evidence/" <> name <> "/output.json"))
  facts = :json.decode(File.read!(base <> "/evidence/" <> name <> "/facts.json"))
  :null = facts["old_selection"]

  if name == "positive" do
    [0, 1, 2, 3] = Enum.map(embeddings, & &1["request"]["source_guard"]["batch_index"])
    true = Enum.all?(embeddings, &(&1["outcome"]["status"] == "ok"))
    4 = output["embedding"]
    8 = output["store"]
    4 = length(output["wires"])

    true =
      Enum.map(embeddings, & &1["request"]["inputs"]) ===
        Enum.map(output["wires"], & &1["inputs"])

    true = Enum.all?(claim["source_bindings"], &(&1["expires_at_ms"] == :null))
    "ready" = facts["ready"]["value"]["status"]
  else
    [] = output["wires"]
    "failed" = first["outcome"]["status"]
    "pending" = facts["pending"]["value"]["status"]
    true = facts["pending"]["operation_id"] === commit["operation_id"]
    1 = Enum.count(claim["source_bindings"], &is_integer(&1["expires_at_ms"]))
  end

  IO.puts(
    "#{name}: #{length(events)} events; original same-parent expected0 claim commit #{commit["operation_id"]}; #{expected_count} guarded actions; exact source selection/session binding; retained body/outcome evidence agrees"
  )
end
