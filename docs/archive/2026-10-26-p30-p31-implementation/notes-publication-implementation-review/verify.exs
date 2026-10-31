base = "docs/archive/2026-10-26-p30-p31-implementation"
review = base <> "/notes-publication-implementation-review"
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
check = fn r ->
  case r["type"] do
    "regular" ->
      true = File.lstat!(r["path"]).type == :regular
      b = File.read!(r["path"])
      true = byte_size(b) == r["bytes"] and sha.(b) == r["sha256"]
    "symlink" ->
      true = File.lstat!(r["path"]).type == :symlink
      true = File.read_link!(r["path"]) == r["target"]
  end
end
parse = fn p ->
  for line <- String.split(File.read!(p), "\n", trim: true), into: %{} do
    [h, f] = String.split(line, "  ", parts: 2)
    {f, h}
  end
end
walk = fn f, p ->
  case File.lstat!(p).type do
    t when t in [:regular, :symlink] -> [Path.expand(p)]
    :directory -> Enum.flat_map(File.ls!(p), &f.(f, Path.join(p, &1)))
  end
end
records = for {name, expected} <- [{"notes-publication-admission", "af4274dbf884df9c4912d564ad0307559f526e58fa3dcc3b78f9844546b7ed59"}, {"notes-publication-prerequisites", "ae6c379a3e297ee63ea6dda1e50ea82ec2bd22d6b962ba90ae4e66cf834edf5b"}] do
  b = File.read!(base <> "/" <> name <> "/manifest.json")
  true = sha.(b) == expected
  m = :json.decode(b)
  check.(m["ancestor"])
  for k <- ~w(sources retained), r <- m[k], do: check.(r)
  for r <- m["sources"], do: true = sha.(File.read!(r["source"])) == r["sha256"]
  graphs = for g <- m["graphs"] do
    check.(g["inventory"])
    rows = :json.decode(File.read!(g["inventory"]["path"]))
    Enum.each(rows, check)
    true = length(rows) == g["files"]
    physical = walk.(walk, g["graph"] <> "/_build/dev/lib") ++ walk.(walk, g["graph"] <> "/priv")
    true = Enum.sort(physical) == Enum.sort(Enum.map(rows, &Path.expand(&1["path"])))
    {g["graph"], Map.new(rows, fn r -> {Path.relative_to(r["path"], g["graph"]), Map.drop(r, ["path"])} end)}
  end
  [{_, prior}, {_, final}] = graphs
  true = Enum.sort(Map.keys(prior)) == Enum.sort(Map.keys(final))
  delta = for {p, r} <- final, prior[p] != r, do: p
  {name, m, graphs, Enum.sort(delta)}
end
[{_, admission, _, admission_delta}, {_, prerequisites, [{_, _}, {_, last_graph}], prerequisite_delta}] = records
true = admission_delta == ["_build/dev/lib/ipse/ebin/Elixir.Ipse.Extension.Collection.DocumentStage.beam", "_build/dev/lib/ipse/ebin/Elixir.Ipse.Extension.Collection.beam", "_build/dev/lib/ipse/ebin/Elixir.Ipse.Extension.ManagedCollectionCall.beam", "_build/dev/lib/ipse/ebin/Elixir.Ipse.Session.Invocation.beam"]
true = prerequisite_delta == ["_build/dev/lib/ipse/ebin/Elixir.Ipse.Session.ManagedReads.beam", "_build/dev/lib/ipse/ebin/Elixir.Ipse.Session.ManagedToolUse.beam"]
positive = base <> "/remember-publication-absence-integration"
true = sha.(File.read!(positive <> "/manifest.sha256")) == "71b910e85daa9a4dd2c667f8af2e4a8d77095347c635d821005c3427cb004637"
positive_rows = parse.(positive <> "/manifest.sha256")
for {p, h} <- positive_rows, do: true = sha.(File.read!(Path.join(positive, p))) == h
{:ok, members} = :erl_tar.extract(String.to_charlist(positive <> "/overlay-source.tar"), [:memory])
sources = Map.new(members, fn {p, b} -> {List.to_string(p), b} end)
true = map_size(sources) == 7
for {p, b} <- sources, do: true = File.read!(p) == b
graph = "_build/remember-absence-integration-sol-20261029"
for {p, r} <- last_graph, do: check.(Map.put(r, "path", Path.join(graph, p)))
positive_runtime = parse.(positive <> "/runtime.sha256")
for {p, h} <- positive_runtime, do: true = last_graph[p]["sha256"] == h
old_runtime = parse.(base <> "/remember-publication-first-control/runtime.sha256")
true = Enum.sort(Map.keys(old_runtime)) == Enum.sort(Map.keys(positive_runtime))
true = Enum.sort(for {p, h} <- positive_runtime, old_runtime[p] != h, do: p) == prerequisite_delta
for p <- Path.wildcard(positive <> "/beams/*.beam"), do: true = File.read!(p) == File.read!(graph <> "/_build/dev/lib/ipse/ebin/" <> Path.basename(p))
true = sha.(File.read!(graph <> "/priv/ipse-runner")) == "40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02"
catalog = :json.decode(File.read!(graph <> "/priv/extension-bundles/catalog.json"))
[entry] = catalog["artifacts"]
true = entry["manifest_sha256"] == "578cd2ade037601ee7f17a2b69f901d116efc664369459e53d9be566cdf317fc"
events = File.stream!(positive <> "/session.jsonl") |> Enum.map(&:json.decode/1)
[assertion] = Enum.filter(events, &(&1["type"] == "operator_assertion"))
[intent] = Enum.filter(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
[result] = Enum.filter(events, &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"]))
true = Enum.find_index(events, &(&1 == assertion)) < Enum.find_index(events, &(&1 == intent))
true = result["outcome"]["status"] == "ok"
normalization = result["outcome"]["value"]["normalization"]
true = normalization["valid_until_ms"] - normalization["first_admitted_ms"] == 90 * 86_400_000
false = Enum.any?(events, &(&1["type"] in ~w(request_admitted inference_dispatch_intent)))
tests = for m <- [admission, prerequisites], r <- m["sources"], String.starts_with?(r["source"], "test/") and Path.basename(r["source"]) in ~w(notes_publication_admission_test.exs managed_collection_call_test.exs managed_tool_use_test.exs), into: %{}, do: {r["source"], File.read!(r["path"])}
all = Map.merge(sources, tests)
File.write!(review <> "/source.sha256", Enum.map(Enum.sort(all), fn {p, b} -> "#{sha.(b)}  #{p}\n" end))
IO.inspect(%{admission_sources: length(admission["sources"]), admission_retained: length(admission["retained"]), prerequisite_sources: length(prerequisites["sources"]), prerequisite_retained: length(prerequisites["retained"]), graph_regular_and_symlink: Enum.frequencies_by(Map.values(last_graph), & &1["type"]), admission_delta: admission_delta, prerequisite_delta: prerequisite_delta, positive_manifest_entries: map_size(positive_rows), positive_source_owners: map_size(sources), source_hashes_recorded: map_size(all), actual_journal_managed_intents: 1, original_ordinary_age_ms: normalization["valid_until_ms"] - normalization["first_admitted_ms"], repeated_tests_effects: 0}, label: "NOTES_PUBLICATION_IMPLEMENTATION_VERIFIED")
