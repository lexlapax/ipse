[root, runtime] = System.argv()
for path <- Path.wildcard(Path.join(runtime, "*/ebin")), do: Code.prepend_path(path)
:ok = Application.load(:ipse)
false = Enum.any?(Application.started_applications(), fn {name, _, _} -> name == :ipse end)
input = root |> Path.join("simultaneous-input.json") |> File.read!() |> Jason.decode!()
consumer_ids = Map.new(~w(first second), fn child ->
  ready = root |> Path.join(child <> "/barrier.json") |> File.read!() |> Jason.decode!()
  {child, ready["session_id"]}
end)
source_ids = Map.new(input["consumers"], fn {child, source} -> {child, source["source_session_id"]} end)
true = MapSet.disjoint?(MapSet.new(Map.values(source_ids)), MapSet.new(Map.values(consumer_ids)))
originals = for {child, original} <- input["consumers"] do
  {:ok, events} = Ipse.Journal.load(Path.join(root, "sessions"), original["source_session_id"])
  changes = for event <- events, event["type"] == "extension_action_result" and get_in(event, ["request", "op"]) == "collection.managed" and get_in(event, ["outcome", "status"]) == "ok", change <- get_in(event, ["request", "request", "changes"]), change["key"] == original["key"], do: change["value"]
  [proposal] = changes
  proofs = get_in(proposal, ["evidence", "sources"])
  true = is_list(proofs) and proofs != []
  true = Enum.all?(proofs, &(&1["session_id"] == original["source_session_id"]))
  true = Enum.any?(events, &(&1["type"] == "session_release_intent"))
  {child, proofs}
end
proof_owners = for {child, proofs} <- originals, proof <- proofs, into: %{}, do: {{proof["occurrence_id"], proof["version_id"]}, child}
for child <- ~w(first second) do
  ready = root |> Path.join(child <> "/barrier.json") |> File.read!() |> Jason.decode!()
  {:ok, events} = Ipse.Journal.load(Path.join(root, "sessions"), ready["session_id"])
  [{intent, index}] = events |> Enum.with_index() |> Enum.filter(fn {event, _} -> event["type"] == "managed_preflight_intent" and event["request_id"] == ready["operation_id"] end)
  prefix = Enum.take(events, index + 1)
  {:ok, saved} = Ipse.Session.Saved.restore(prefix, ready["session_id"])
  {:ok, dependencies} = Ipse.Session.ManagedLineage.preflight_dependencies(saved.managed_lineage, "decision.create", saved.messages)
  true = Ipse.JSON.digest(dependencies) == intent["dependencies_sha256"]
  versioned = for dep <- dependencies, dep["version"] in [4,5,6,7], row <- get_in(dep, ["subject", "validity", "source_versions"]) || [], do: Map.fetch!(proof_owners, {row["id"], row["version"]})
  [^child] = Enum.uniq(versioned)
  IO.puts(Jason.encode!(%{child: child, consumer_is_fresh_not_either_original: true, complete_preflight_dependency_digest_matches: true, dependency_versions: Enum.frequencies_by(dependencies, & &1["version"]), referenced_original_owners: Enum.uniq(versioned), references_other_active_consumer: false, referenced_originals_have_durable_release_intent: true}))
end
false = Enum.any?(Application.started_applications(), fn {name, _, _} -> name == :ipse end)
