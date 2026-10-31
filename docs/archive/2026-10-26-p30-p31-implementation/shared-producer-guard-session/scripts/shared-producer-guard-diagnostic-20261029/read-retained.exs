{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.Extension.{Collection, CollectionStore, ProjectIdentity}
alias Ipse.Extension.Collection.{DocumentSourceUse, DocumentStage}

locator =
  Jason.decode!(
    File.read!(
      "_build/shared-producer-guard-session-20261029/evidence/attempt-journals/ipse-document-guard-session-98c9607b9791d08ff40773020bcb265c-home.json"
    )
  )

[journal] = Path.wildcard(Path.join(locator["home"], "sessions/*.jsonl"))
events = File.stream!(journal) |> Enum.map(&Jason.decode!/1)

embedding =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "embedding.create")
  )

request = embedding["request"]
execution = embedding["effect_binding"]["execution"]

selection = %{
  "profile" => execution["id"],
  "model" => execution["model"],
  "dimensions" => execution["dimensions"],
  "encoding" => "float32le",
  "selection_sha256" => request["expected_selection_sha256"]
}

{:ok, project} = ProjectIdentity.existing(locator["home"], locator["cwd"])
namespace = CollectionStore.namespace(project["project_id"])

{:ok, result} =
  ProjectIdentity.with_existing_binding(locator["home"], locator["cwd"], project, fn _ ->
    Collection.with_document_read(CollectionStore.root(locator["home"]), namespace, fn _, read ->
      {:ok, claim} = DocumentStage.read_value(read, request["source_guard"]["claim_key"])
      {:ok, nil} = DocumentStage.read_value(read, "generation.notes")

      {:ok, facts} =
        DocumentSourceUse.authenticate(
          read,
          request["source_guard"],
          request["inputs"],
          selection
        )

      {:ok,
       %{
         facts: facts,
         claim_operation_id: claim["operation_id"],
         claim_revision: claim["revision"],
         pending: claim["value"]["status"] == "pending",
         old_selected_root_absent: true
       }}
    end)
  end)

prepare =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_result" and
        &1["parent_invocation_id"] == embedding["parent_invocation_id"] and
        &1["request"]["request"]["op"] == "value.prepare_inline" and
        &1["request"]["request"]["key"] == request["source_guard"]["claim_key"])
  )

ref = Map.take(prepare["outcome"]["value"]["result"]["stage"], ~w(slot epoch))

commit =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_result" and
        &1["parent_invocation_id"] == embedding["parent_invocation_id"] and
        &1["request"]["request"]["op"] == "commit" and
        &1["request"]["request"]["stages"] === [ref])
  )

true = commit["operation_id"] === result.claim_operation_id
true = commit["outcome"]["value"]["result"]["generation"] === result.claim_revision
true = prepare["request"]["request"]["sha256"] === request["source_guard"]["claim_sha256"]

IO.puts(
  Jason.encode!(
    %{
      kind: "read_only_retained_native_store_after_failed_diagnostic",
      native_authentication: "ok",
      claim_operation_id: result.claim_operation_id,
      claim_revision: result.claim_revision,
      same_parent_prepare_commit: true,
      exact_known_commit: commit["outcome"]["status"] == "ok",
      pending: result.pending,
      old_selected_root_absent: result.old_selected_root_absent,
      reads: result.facts.reads,
      logical_bytes: result.facts.logical_bytes,
      bundle_bytes: result.facts.bundle_bytes,
      source_count: length(result.facts.sources),
      current: DocumentSourceUse.current?(result.facts, System.system_time(:millisecond)),
      mutation_or_model_replay: false
    }, pretty: true)
)
