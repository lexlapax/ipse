{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.Extension.{Collection, CollectionStore, ProjectIdentity}
alias Ipse.Extension.Collection.DocumentStage
base = "_build/shared-producer-finite-guard-session-20261029/evidence"
facts = Jason.decode!(File.read!(base <> "/finite-positive/facts.json"))
deadline = facts["original_finite_expiry"]
true = facts["finished_at_ms"] < deadline
true = Enum.all?(facts["ready"]["value"]["source_bindings"], &(&1["expires_at_ms"] === deadline))
saved = base <> "/finite-positive/synthetic-session.jsonl"
events = File.stream!(saved) |> Enum.map(&Jason.decode!/1)
embeddings = Enum.filter(events, &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "embedding.create"))
4 = length(embeddings)
[0, 1, 2, 3] = Enum.map(embeddings, & &1["request"]["source_guard"]["batch_index"])
true = Enum.all?(embeddings, &(&1["outcome"]["status"] == "ok"))
id = hd(embeddings)["effect_binding"]["source_binding"]["session_id"]
[locator_path] = Path.wildcard(base <> "/attempt-journals/*-home.json")
locator = Jason.decode!(File.read!(locator_path))
true = File.read!(saved) === File.read!(Path.join([locator["home"], "sessions", id <> ".jsonl"]))
{:ok, project} = ProjectIdentity.existing(locator["home"], locator["cwd"])
{:ok, row} = ProjectIdentity.with_existing_binding(locator["home"], locator["cwd"], project, fn _ ->
  Collection.with_document_read(CollectionStore.root(locator["home"]), CollectionStore.namespace(project["project_id"]), fn _, read ->
    {:ok, nil} = DocumentStage.read_value(read, "generation.notes")
    {:ok, row} = DocumentStage.read_value(read, "genproducer.notes")
    true = row === facts["ready"]
    true = row["value"]["status"] == "ready"
    {:ok, page} = DocumentStage.read_value(read, row["value"]["page"]["key"])
    true = page["sha256"] === row["value"]["page"]["sha256"]
    true = length(page["value"]["rows"]) === 8
    {:ok, Map.take(row, ~w(key revision operation_id sha256 byte_count))}
  end)
end)
IO.puts(Jason.encode!(%{actual_native_read_only: true, native_ready: row, original_deadline_ms: deadline, finished_at_ms: facts["finished_at_ms"], unchanged_expiries: true, batches: 4, journal_bytes: File.stat!(saved).size, journal_events: length(events), original_journal_exact: true, no_effect_or_inference_replay: true}, pretty: true))
