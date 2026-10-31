{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.Extension.{Collection, CollectionStore, ProjectIdentity}
alias Ipse.Extension.Collection.DocumentStage
alias Ipse.JSON, as: J
base = "_build/shared-producer-guard-session-20261029/evidence"

reports =
  for kind <- ~w(positive expiry) do
    saved = Path.join([base, kind, "synthetic-session.jsonl"])
    events = File.stream!(saved) |> Enum.map(&Jason.decode!/1)
    id = hd(events)["session_id"]

    locator =
      Path.wildcard(base <> "/attempt-journals/*-home.json")
      |> Enum.map(&Jason.decode!(File.read!(&1)))
      |> Enum.find(&File.exists?(Path.join([&1["home"], "sessions", id <> ".jsonl"])))

    true =
      File.read!(saved) === File.read!(Path.join([locator["home"], "sessions", id <> ".jsonl"]))

    actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    embeddings = Enum.filter(actions, &(&1["request"]["op"] == "embedding.create"))
    first = hd(embeddings)
    parent = first["parent_invocation_id"]
    guard = first["request"]["source_guard"]
    own = Enum.filter(actions, &(&1["parent_invocation_id"] == parent))

    prepare =
      Enum.find(
        own,
        &(&1["request"]["request"]["op"] == "value.prepare_inline" and
            &1["request"]["request"]["key"] == "genproducer.notes")
      )

    ref = Map.take(prepare["outcome"]["value"]["result"]["stage"], ~w(slot epoch))

    claim_commit =
      Enum.find(
        own,
        &(&1["request"]["request"]["op"] == "commit" and
            &1["request"]["request"]["stages"] === [ref])
      )

    true = claim_commit["outcome"]["status"] == "ok"
    true = claim_commit["outcome"]["value"]["result"]["generation"] === guard["claim_revision"]
    true = prepare["request"]["request"]["sha256"] === guard["claim_sha256"]
    {:ok, original_claim} = J.decode_unique(prepare["request"]["request"]["data"])
    true = original_claim["status"] == "pending"

    true =
      Enum.all?(
        embeddings,
        &(&1["request"]["expected_selection_sha256"] ===
            original_claim["vector_selection"]["selection_sha256"])
      )

    true =
      Enum.all?(
        embeddings,
        &(&1["effect_binding"]["version"] === 2 and
            &1["effect_binding"]["source_binding"]["session_id"] === id and
            &1["effect_binding"]["source_binding"]["operator_binding"]["source_use"] ==
              "shared_producer_v1")
      )

    {:ok, project} = ProjectIdentity.existing(locator["home"], locator["cwd"])
    ns = CollectionStore.namespace(project["project_id"])

    {:ok, native} =
      ProjectIdentity.with_existing_binding(locator["home"], locator["cwd"], project, fn _ ->
        Collection.with_document_read(CollectionStore.root(locator["home"]), ns, fn _, read ->
          {:ok, nil} = DocumentStage.read_value(read, "generation.notes")
          {:ok, row} = DocumentStage.read_value(read, "genproducer.notes")

          if kind == "positive" do
            true = row["value"]["status"] == "ready"
            page_ref = row["value"]["page"]
            {:ok, page} = DocumentStage.read_value(read, page_ref["key"])
            true = page["sha256"] === page_ref["sha256"] and page["byte_count"] === 45_064
            true = page["value"]["kind"] == "shared_vectors" and page["value"]["ordinal"] === 0
            true = page["value"]["source_set_sha256"] === original_claim["source_set_sha256"]
            true = length(page["value"]["rows"]) === 8
            bytes = for _ <- 1..1024, into: <<>>, do: <<1.0::float-little-32>>

            Enum.zip(page["value"]["rows"], original_claim["inputs"])
            |> Enum.each(fn {[si, ci, input_sha, vector_sha, pieces], input} ->
              true = [si, ci] === Enum.take(input, 2)
              true = input_sha === Enum.at(input, 3)
              true = vector_sha === J.sha256(bytes)
              true = Enum.map(pieces, &Base.decode64!/1) |> IO.iodata_to_binary() === bytes
            end)

            final = Enum.find(own, &(&1["operation_id"] === row["operation_id"]))

            true =
              final["request"]["request"]["op"] == "commit" and
                length(final["request"]["request"]["stages"]) === 2

            true = final["outcome"]["value"]["result"]["generation"] === row["revision"]

            {:ok,
             %{
               status: "ready",
               revision: row["revision"],
               final_operation_id: row["operation_id"],
               page_sha256: page["sha256"],
               page_bytes: page["byte_count"],
               exact_fixture_vectors: true
             }}
          else
            true = row["value"]["status"] == "pending"
            true = row["operation_id"] === claim_commit["operation_id"]

            {:ok,
             %{status: "pending", revision: row["revision"], operation_id: row["operation_id"]}}
          end
        end)
      end)

    if kind == "positive" do
      true = length(embeddings) === 4
      true = Enum.map(embeddings, & &1["request"]["source_guard"]["batch_index"]) === [0, 1, 2, 3]
      true = Enum.all?(embeddings, &(&1["outcome"]["status"] == "ok"))
    else
      true = length(embeddings) === 1
      true = hd(embeddings)["outcome"]["status"] == "failed"
    end

    %{
      kind: kind,
      journal_bytes: File.stat!(saved).size,
      journal_sha256: J.sha256(File.read!(saved)),
      events: length(events),
      original_journal_exact: true,
      guard_actions: length(embeddings),
      claim_operation_id: claim_commit["operation_id"],
      claim_revision: guard["claim_revision"],
      own_prepare_commit: true,
      native: native,
      selected_root_still_absent: true,
      actual_read_only_inspection: true
    }
  end

IO.puts(Jason.encode!(%{reports: reports, mutation_or_model_replay: false}, pretty: true))
