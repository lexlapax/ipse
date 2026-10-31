{:ok, _} = Application.ensure_all_started(:ipse)
for name <- ~w(headless-typed-loopback headless-typed-direct headless-typed-diagnostic) do
  home = "/tmp/ipse-#{name}-20261029/home"
  [journal] = Path.wildcard(Path.join(home, "sessions/*.jsonl"))
  id = Path.basename(journal, ".jsonl")
  {:ok, events} = Ipse.Journal.load(Path.dirname(journal), id)
  admission = hd(events)["metadata"]["semantic_admission"]
  {:ok, snapshot} = Ipse.Extension.Collection.execute(Ipse.Extension.SemanticAdmission.collection_root(home), admission["pin"]["namespace"], %{"op" => "snapshot"}, Ipse.Usage.id())
  {:ok, consent} = Ipse.Extension.Consent.snapshot(Ipse.Extension.SemanticAdmission.control_root(home), admission["pin"]["project_id"])
  {:ok, saved} = Ipse.Session.Saved.restore(events, id)
  parents = Enum.filter(events, &(&1["type"] == "extension_invocation_intent"))
  last = List.last(parents)
  input = case saved.managed_lineage.invocations[last["invocation_id"]] do
    %{input: value} -> value
    _ -> nil
  end
  IO.inspect(%{fixture: name, root_generation: snapshot["generation"], consent_sequence: consent["sequence"], managed_intents: Enum.count(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed")), lifecycle_outcomes: Enum.count(events, &(&1["type"] == "lifecycle_tool_outcome")), last_invocation_input: input, saved_restore: :ok})
end
