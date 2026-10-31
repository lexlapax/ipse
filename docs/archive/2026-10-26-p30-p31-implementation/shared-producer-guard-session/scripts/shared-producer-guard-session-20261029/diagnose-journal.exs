ExUnit.start(autorun: false)
Code.prepend_path(Path.expand("_build/shared-producer-guard-session-20261029/artifact/ebin"))
# The retained general ledger starts at generation 1000. This read-only adapter
# reconstructs an actual empty generation-zero store, whose floor follows its
# mutation generation. No runtime store or historical request is changed.
model_source = File.read!("dev/knowledge/collection_recipe_model.ex")
model_source = String.replace(model_source, "m.generation - 1000", "m.generation")
Code.compile_string(model_source, "diagnostic-generation-zero-collection-model")
alias Ipse.CollectionRecipeModel, as: M
alias Ipse.Extension.Collection.DocumentSourceUse
alias Ipse.Session.DocumentEmbedding
alias Ipse.JSON, as: J

journal =
  "_build/shared-producer-guard-session-20261029/evidence/attempt-journals/b1612de88618dfa391d05b2e6678a04d.jsonl"

events = File.stream!(journal) |> Enum.map(&Jason.decode!/1)

embedding =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "embedding.create")
  )

true = embedding["outcome"]["status"] == "failed"
parent_id = embedding["parent_invocation_id"]

parent =
  Enum.find(
    events,
    &(&1["type"] == "extension_invocation_intent" and &1["invocation_id"] == parent_id)
  )

actions =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.store")
  )

{model, operation_ids, _} =
  Enum.reduce(actions, {M.new(%{}, 0), %{}, nil}, fn event, {model, ids, previous_parent} ->
    true = event["outcome"]["status"] == "ok"
    model = if previous_parent == event["parent_invocation_id"], do: model, else: M.reset(model)
    before = model.records
    {%{"status" => "ok"}, next} = M.host(event["request"], model)

    ids =
      Enum.reduce(next.records, ids, fn {key, row}, ids ->
        if before[key] != row, do: Map.put(ids, key, event["operation_id"]), else: ids
      end)

    {next, ids, event["parent_invocation_id"]}
  end)

read = fn key ->
  case model.records[key] do
    nil ->
      {:ok, nil}

    row ->
      bytes = IO.iodata_to_binary(JSON.encode!(row.value))
      true = byte_size(bytes) <= 6144

      {:ok,
       %{
         "key" => key,
         "revision" => row.revision,
         "operation_id" => operation_ids[key],
         "value" => %{
           "version" => 1,
           "kind" => "document_value",
           "parts" => [bytes],
           "sha256" => J.sha256(bytes),
           "byte_count" => byte_size(bytes)
         }
       }}
  end
end

request = embedding["request"]
execution = embedding["effect_binding"]["execution"]

selection = %{
  "profile" => execution["id"],
  "model" => execution["model"],
  "dimensions" => execution["dimensions"],
  "encoding" => "float32le",
  "selection_sha256" => request["expected_selection_sha256"]
}

facts =
  DocumentSourceUse.authenticate(read, request["source_guard"], request["inputs"], selection)

invocation = %{parent: parent, document_producer: nil}

live =
  actions
  |> Enum.filter(&(&1["parent_invocation_id"] == parent_id))
  |> Enum.reduce(invocation, &DocumentEmbedding.record_action(&2, &1))

claim = model.records[request["source_guard"]["claim_key"]]

IO.puts(
  Jason.encode!(
    %{
      kind: "read_only_actual_journal_reconstruction_NOT_native_current_store",
      journal: journal,
      successful_collection_actions: length(actions),
      logical_records: map_size(model.records),
      generation: model.generation,
      authenticate:
        case facts do
          {:ok, value} ->
            %{
              status: "ok",
              reads: value.reads,
              logical_bytes: value.logical_bytes,
              bundle_bytes: value.bundle_bytes,
              source_count: length(value.sources),
              current_at_diagnostic:
                DocumentSourceUse.current?(value, System.system_time(:millisecond)),
              claim_operation_id: value.claim_operation_id
            }

          refused ->
            %{status: inspect(refused)}
        end,
      claim_revision_matches: claim.revision == request["source_guard"]["claim_revision"],
      selection_matches_claim: selection === claim.value["vector_selection"],
      live_cache_status: live.document_producer && live.document_producer.status,
      live_cache_operation_matches:
        live.document_producer && live.document_producer.claim &&
          live.document_producer.claim.operation_id ===
            operation_ids[request["source_guard"]["claim_key"]],
      allowed: DocumentEmbedding.allowed?(live, request, embedding["effect_binding"]),
      mocked_packed_read: true,
      model_floor_adapter: "generation-zero instead of prior synthetic seed1000",
      native_effects_replayed: false
    },
    pretty: true
  )
)
