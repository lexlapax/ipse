{:ok, _} = Application.ensure_all_started(:ipse)
for name <- ~w(headless-typed-loopback headless-typed-direct) do
  home = "/tmp/ipse-#{name}-20261029/home"
  [journal] = Path.wildcard(Path.join(home, "sessions/*.jsonl"))
  id = Path.basename(journal, ".jsonl")
  {:ok, events} = Ipse.Journal.load(Path.dirname(journal), id)
  {:ok, saved} = Ipse.Session.Saved.restore(events, id)
  last = Enum.find(Enum.reverse(events), &(&1["type"] == "extension_invocation_intent"))
  {:ok, deps} = Ipse.Session.ManagedLineage.invocation_dependencies(saved.managed_lineage, last["invocation_id"])
  calls = for e <- events, call <- get_in(e, ["message", "tool_calls"]) || [], get_in(call, ["function", "name"]) == "source_list", do: call
  sources = for dep <- deps do
    match = Enum.find(events, fn e -> e["type"] == "managed_read_observed" and dep in e["dependencies"] end)
    action = match && Enum.find(events, &(&1["type"] == "extension_action_result" and &1["operation_id"] == match["operation_id"]))
    %{kind: dep["subject"]["kind"], root: dep["collection"], request: if(action, do: action["request"]), same_parent: action && action["parent_invocation_id"] == last["invocation_id"]}
  end
  call_deps = Enum.map(calls, fn call ->
    {call["id"], Ipse.Session.ManagedLineage.tool_dependencies(saved.managed_lineage, call["id"])}
  end)
  IO.inspect(%{fixture: name, last_parent: last["invocation_id"], dependencies: sources, source_list_calls: calls, source_list_dependencies: call_deps}, limit: :infinity, printable_limit: :infinity)
end
