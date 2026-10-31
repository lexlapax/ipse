{:ok, _} = Application.ensure_all_started(:ipse)
root = "/tmp/ipse-remember-terminal-publication-20261029"
home = Path.join(root, "home")
[filename] = Path.wildcard(Path.join(home, "sessions/*.jsonl"))
id = Path.basename(filename, ".jsonl")
{:ok, events} = Ipse.Journal.load(Path.join(home, "sessions"), id)
header = hd(events)
admission = header["metadata"]["semantic_admission"]
intent = Enum.find(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
result = Enum.find(events, &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"]))
{:ok, snapshot} = Ipse.Extension.Collection.execute(Ipse.Extension.SemanticAdmission.collection_root(home), admission["pin"]["namespace"], %{"op" => "snapshot"}, Ipse.Usage.id())
{:ok, consent} = Ipse.Extension.Consent.snapshot(Ipse.Extension.SemanticAdmission.control_root(home), admission["pin"]["project_id"])
IO.inspect(%{assertions: Enum.count(events, &(&1["type"] == "operator_assertion")), action: result["outcome"]["status"], generation: snapshot["generation"], settled: consent["operations"][intent["operation_id"]]["status"], saved_restore: elem(Ipse.Session.Saved.restore(events,id),0), close_receipt: Enum.any?(events,&(&1["type"] == "session_release_intent"))})
