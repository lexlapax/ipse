base = "docs/archive/2026-10-26-p30-p31-implementation"
public = base <> "/management-forget-public"
qualification = base <> "/management-forget-qualification"
effect = base <> "/management-forget-effect"
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
parse = fn p ->
  for line <- String.split(File.read!(p), "\n", trim: true) do
    [h, f] = String.split(line, "  ", parts: 2)
    {f, h}
  end
end
manifests = for {root, expected} <- [{public, "6870b0db5ae508f5d2fd31c0f981f1db93555ccbd0930ee846d99f96b5b3c56d"}, {qualification, "ebc41315849b658e13ce75b229c5790312f7aca108380fe2c7f8f827c1b8bffd"}] do
  p = root <> "/manifest.sha256"
  true = sha.(File.read!(p)) == expected
  rows = parse.(p)
  Enum.each(rows, fn {p, h} -> true = sha.(File.read!(Path.join(root, p))) == h end)
  {Path.basename(root), length(rows)}
end
tar = fn p ->
  {:ok, rows} = :erl_tar.extract(String.to_charlist(p), [:memory])
  Map.new(rows, fn {p, b} -> {List.to_string(p), b} end)
end
sources = tar.(public <> "/source.tar")
fixtures = tar.(qualification <> "/fixture-source.tar")
prior_sources = tar.(effect <> "/source.tar")
management = "lib/ipse/cli/knowledge/management.ex"
old = "  def forget(_config, _cwd, _key),\n    do: apply(__MODULE__, :reviewed_publication_admission, [])"
new = "  def forget(config, cwd, key) do\n    case full_facts_forget_candidate(\n           config,\n           cwd,\n           key,\n           \"Operator requested forgetting this selected literal\"\n         ) do\n      {:closed, result} -> result\n      result -> result\n    end\n  end"
true = sources[management] == prior_sources[management]
  |> String.replace(old, new)
  |> String.replace("              try do\n                with {:ok, {handle, prepared}} <-", "              try do\n                with :ok <- Ipse.CLI.Terminal.puts(\"Management journal: \#{owned.id}\"),\n                     {:ok, {handle, prepared}} <-")
for name <- ~w(knowledge errors) do
  true = sources["lib/ipse/cli/#{name}.ex"] == File.read!(base <> "/reviewed-forget-core/lib__ipse__cli__#{name}.ex.txt")
end
instrumented = File.read!(public <> "/instrumentation/management-cleanup-unknown-instrumented.ex")
true = instrumented == String.replace(sources[management], "if Writer.close(writer) == :ok,", "if Ipse.Test.ManagementDisplayProbe.close_unknown(writer) == :ok,")
walk = fn f, p ->
  case File.lstat!(p).type do
    :regular -> [Path.expand(p)]
    :symlink -> []
    :directory -> Enum.flat_map(File.ls!(p), &f.(f, Path.join(p, &1)))
  end
end
verify_graph = fn inventory, graph ->
  rows = parse.(inventory)
  for {p, h} <- rows, do: true = sha.(File.read!(Path.join(graph, p))) == h
  true = Enum.sort(Enum.map(rows, fn {p, _} -> Path.expand(Path.join(graph, p)) end)) == Enum.sort(walk.(walk, graph))
  Map.new(rows)
end
prior = verify_graph.(effect <> "/runtime.sha256", "_build/management-forget-effect-sol-20261029/lib")
qualified = verify_graph.(qualification <> "/runtime.sha256", "_build/management-forget-qualification-sol-20261029/lib")
true = prior == qualified
recipe = verify_graph.(qualification <> "/runtime-recipe-after.sha256", "_build/management-forget-recipe-v3-sol-20261029/lib")
final = verify_graph.(public <> "/runtime.sha256", "_build/management-forget-public-sol-20261029/lib")
true = Enum.sort(Map.keys(prior)) == Enum.sort(Map.keys(final))
delta = for {p, h} <- final, prior[p] != h, do: p
true = Enum.sort(delta) == ["./ipse/ebin/Elixir.Ipse.CLI.Knowledge.Management.beam", "./ipse/ebin/Elixir.Ipse.CLI.Knowledge.beam", "./ipse/ebin/Elixir.Ipse.CLI.beam"]
for p <- Path.wildcard(public <> "/beams/*.beam") do
  true = File.read!(p) == File.read!("_build/management-forget-public-sol-20261029/lib/ipse/ebin/" <> Path.basename(p))
end
added = Map.keys(recipe) -- Map.keys(prior)
changed = for {p, h} <- prior, recipe[p] != h, do: p
true = changed == ["./ipse/priv/extension-bundles/catalog.json"] and length(added) == 10
artifact = tar.(qualification <> "/alternate-artifact.tar")
catalog = :json.decode(File.read!(qualification <> "/alternate-catalog.json"))
[entry] = catalog["artifacts"]
manifest_bytes = artifact["alternate-knowledge/extension.json"]
true = sha.(manifest_bytes) == entry["manifest_sha256"]
am = :json.decode(manifest_bytes)
for r <- am["files"] do
  b = artifact["alternate-knowledge/" <> r["path"]]
  true = byte_size(b) == r["bytes"] and sha.(b) == r["sha256"]
end
true = map_size(artifact) == length(am["files"]) + 1
journals = for root <- [public, qualification], p <- Path.wildcard(root <> "/journals/*.jsonl") do
  events = File.stream!(p) |> Enum.map(&:json.decode/1)
  [%{"type" => "session", "metadata" => %{"kind" => "knowledge_management"}} | rest] = events
  intents = Enum.filter(rest, &(&1["type"] == "managed_lifecycle_intent"))
  results = Enum.filter(rest, &(&1["type"] == "managed_lifecycle_result"))
  true = length(intents) <= 1 and length(results) <= 1 and length(rest) == length(intents) + length(results)
  if intents != [] and results != [], do: true = hd(intents)["operation_id"] == hd(results)["operation_id"]
  {Path.basename(p), length(intents), Enum.map(results, & &1["status"])}
end
IO.inspect(%{manifests: manifests, public_sources: map_size(sources), qualification_fixtures: map_size(fixtures), regular_runtime_files: [map_size(prior), map_size(qualified), map_size(recipe), map_size(final)], public_delta: Enum.sort(delta), recipe_added_files: length(added), alternate_artifact_files: map_size(artifact), journals: journals, repeated_tests: 0}, label: "MANAGEMENT_FORGET_PUBLIC_REVIEW_OK")
