root = "docs/archive/2026-10-26-p30-p31-implementation/remember-publication-first-control"
sha = fn b -> :crypto.hash(:sha256, b) |> Base.encode16(case: :lower) end
parse = fn path ->
  for line <- String.split(File.read!(path), "\n", trim: true), into: %{} do
    [h, p] = String.split(line, "  ", parts: 2)
    {p, h}
  end
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "389011521b04cbf17dd7c43b05934989782530696bd2a3b7b6138a95b0f55764"
manifest = parse.(root <> "/manifest.sha256")
for {p, h} <- manifest, do: true = sha.(File.read!(Path.join(root, p))) == h
true = File.read!(root <> "/runtime.sha256") == File.read!(root <> "/parent-runtime.sha256")
true = File.read!(root <> "/runtime-difference.log") == ""
runtime = parse.(root <> "/runtime.sha256")
for graph <- ~w(_build/remember-publication-sol-20261029 _build/notes-publication-admission-sol-20261029), {p, h} <- runtime do
  true = sha.(File.read!(Path.join(graph, p))) == h
end
{:ok, members} = :erl_tar.extract(String.to_charlist(root <> "/overlay-source.tar"), [:memory])
sources = Map.new(members, fn {p, b} -> {List.to_string(p), b} end)
true = map_size(sources) == 6
canon = fn f, value ->
  cond do
    is_map(value) -> "{" <> (value |> Enum.sort_by(&elem(&1, 0)) |> Enum.map_join(",", fn {k, v} -> IO.iodata_to_binary(:json.encode(k)) <> ":" <> f.(f, v) end)) <> "}"
    is_list(value) -> "[" <> Enum.map_join(value, ",", &f.(f, &1)) <> "]"
    true -> IO.iodata_to_binary(:json.encode(value))
  end
end
digest = fn v -> sha.(canon.(canon, [v])) end
events = File.stream!(root <> "/session.jsonl") |> Enum.map(&:json.decode/1)
reads = Enum.filter(events, &(&1["type"] == "managed_read_observed"))
true = length(reads) == 2
results = Enum.filter(events, &(&1["type"] == "extension_action_result"))
observations = for read <- reads do
  [result] = Enum.filter(results, &(&1["operation_id"] == read["operation_id"]))
  true = result["parent_invocation_id"] == read["parent_invocation_id"]
  true = result["request"]["op"] == "collection.call" and result["request"]["request"]["op"] == "get"
  true = result["outcome"]["status"] == "ok" and result["outcome"]["value"]["record"] == :null
  [dependency] = read["dependencies"]
  true = dependency["version"] === 3 and dependency["subject"]["kind"] == "root_observation"
  true = dependency["subject"]["request_sha256"] == digest.(result["request"]["request"])
  true = dependency["subject"]["result_sha256"] == digest.(result["outcome"]["value"])
  true = dependency["collection"]["generation"] === 0 and dependency["collection"]["root_state"] == "absent"
  {result["request"]["request"]["key"], dependency}
end
[{_, first}, {_, second}] = observations
true = first["collection"] == second["collection"] and first["pin_sha256"] == second["pin_sha256"] and first["policy_generation"] == second["policy_generation"]
false = Enum.any?(results, &(get_in(&1, ["request", "request", "op"]) == "snapshot"))
false = Enum.any?(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
IO.inspect(%{manifest_entries: map_size(manifest), overlay_sources: map_size(sources), identical_parent_runtime_regular_files: map_size(runtime), root_observations: length(observations), observed_keys: Enum.map(observations, &elem(&1, 0)), full_root: first["collection"], snapshot_results: 0, managed_publication_intents: 0, repeated_tests_or_effects: 0}, label: "REMEMBER_FIRST_CONTROL_VERIFIED")
