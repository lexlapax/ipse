Code.require_file("../dev/evaluation/review.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationReviewTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Evaluation.Review, as: Review
  @seed String.duplicate("b", 64)
  @body "α café Ω"
  @variants ~w(secret-lexical-engine secret-graph-engine)

  defp sha(b), do: Base.encode16(:crypto.hash(:sha256, b), case: :lower)

  defp identity(generation \\ 1, version \\ 1, project \\ "p"),
    do: %{
      "project" => project,
      "source_id" => "source",
      "generation" => generation,
      "version" => version,
      "sha256" => sha(@body)
    }

  defp prediction(variant, generation, version) do
    source = identity(generation, version)

    %{
      "version" => 2,
      "prediction_id" => "p-" <> sha(variant),
      "variant" => variant,
      "query_id" => "q",
      "project" => "p",
      "attempt" => 1,
      "status" => "ok",
      "top_k" => 10,
      "predicted_class" => "answer",
      "response_kind" => "answer",
      "answer" => "The moon is cheese.",
      "claims" => [%{"claim_id" => "claim", "text" => "The moon is cheese."}],
      "evidence" => [
        %{
          "span_id" => "r1",
          "source" => source,
          "start_byte" => 0,
          "end_byte" => byte_size(@body),
          "quote" => @body
        }
      ],
      "context_evidence" => [
        %{
          "span_id" => "a1",
          "source" => source,
          "start_byte" => 3,
          "end_byte" => 8,
          "quote" => "café"
        }
      ],
      "citations" => [%{"citation_id" => "pair", "claim_id" => "claim", "span_id" => "a1"}]
    }
  end

  defp rows, do: [prediction(hd(@variants), 1, 1), prediction(List.last(@variants), 2, "1")]

  defp inputs(rows \\ rows()) do
    bytes = Enum.map_join(rows, "\n", &JSON.encode!/1) <> "\n"

    freeze = %{
      "version" => 2,
      "context_sha256" => sha("synthetic review context"),
      "metric_version" => 1,
      "variants" => @variants,
      "baseline" => hd(@variants),
      "queries" => [%{"query_id" => "q", "project" => "p"}],
      "files" => [%{"id" => "predictions", "sha256" => sha(bytes)}],
      "classification_map" => Map.new(~w(answer conflict open abstain), &{&1, &1})
    }

    {freeze, %{"predictions" => bytes}}
  end

  defp context do
    documents =
      for {g, v, p} <- [{1, 1, "p"}, {2, "1", "p"}, {1, 1, "foreign"}] do
        identity(g, v, p)
        |> Map.merge(%{
          "document_id" => p <> to_string(g),
          "title" => "Example",
          "text" => @body,
          "created_at" => "2026-01-01T00:00:00Z",
          "observed_at" => "2026-02-01T00:00:00Z",
          "state" => "current",
          "byte_length" => byte_size(@body),
          "media_type" => "text/plain"
        })
      end

    relevance =
      identity()
      |> Map.merge(%{"grade" => 1, "start_byte" => 3, "end_byte" => 8, "quote" => "café"})

    query = %{
      "query_id" => "q",
      "project" => "p",
      "query" => "What does this passage say?",
      "split" => "fixture",
      "expected_class" => "answer",
      "expected_answer" => "A café.",
      "relevance" => [relevance]
    }

    %{
      "corpus" => JSON.encode!(%{"schema_version" => 1, "documents" => documents}),
      "queries" => JSON.encode!(%{"schema_version" => 1, "queries" => [query]}),
      "split" => "fixture",
      "as_of_ms" => 1_800_000_000_000
    }
  end

  test "hashes, closed rows, opaque identity and complete grid precede any label access" do
    {freeze, blobs} = inputs()

    loader = fn ->
      send(self(), :opened_labels)
      {:ok, context()}
    end

    assert {:error, :prediction_hash_mismatch} =
             Review.prepare(freeze, %{"predictions" => "{}\n"}, loader, @seed)

    refute_received :opened_labels
    {partial, partial_blobs} = inputs([hd(rows())])

    assert {:error, :incomplete_prediction_grid} =
             Review.prepare(partial, partial_blobs, loader, @seed)

    refute_received :opened_labels
    named = List.update_at(rows(), 0, &Map.put(&1, "prediction_id", "secret-lexical-engine"))
    {f, b} = inputs(named)
    assert {:error, :nonopaque_prediction_id} = Review.prepare(f, b, loader, @seed)
    refute_received :opened_labels

    bytes =
      String.replace(blobs["predictions"], "\"attempt\":1", "\"attempt\":1,\"attempt\":1",
        global: false
      )

    altered = put_in(freeze, ["files", Access.at(0), "sha256"], sha(bytes))

    assert {:error, :duplicate_prediction_key} =
             Review.prepare(altered, %{"predictions" => bytes}, loader, @seed)

    refute_received :opened_labels
  end

  defp sealed_context do
    legacy = context()
    [row] = JSON.decode!(legacy["queries"])["queries"]
    [span] = row["relevance"]

    answer =
      row
      |> Map.take(~w(query_id project expected_class expected_answer))
      |> Map.put("expected_refusal", false)
      |> Map.put("relevance", [
        Map.take(span, ~w(grade start_byte end_byte quote))
        |> Map.put("source", Map.take(span, ~w(project source_id generation version sha256)))
      ])

    legacy
    |> Map.put("split", "heldout")
    |> Map.put(
      "queries",
      JSON.encode!(%{
        "contract" => "sealed_answers_v1",
        "split" => "heldout",
        "queries" => [Map.take(row, ~w(query_id project query))]
      })
    )
    |> Map.put(
      "answers",
      JSON.encode!(%{
        "contract" => "sealed_answers_v1",
        "split" => "heldout",
        "commitment_nonce" => String.duplicate("a", 64),
        "answers" => [answer]
      })
    )
  end

  test "sealed review joins separate references and refuses invalid typed source spans" do
    {freeze, blobs} = inputs()
    context = sealed_context()
    assert {:ok, packet} = Review.prepare(freeze, blobs, fn -> {:ok, context} end, @seed)
    assert packet["summary"]["queries_sha256"] == sha(context["queries"])
    assert packet["summary"]["answers_sha256"] == sha(context["answers"])
    refute Map.has_key?(packet["summary"], "query_labels_sha256")
    [query] = JSON.decode!(packet["files"]["queries.json"])["queries"]
    assert query["expected_answer"] == "A café."
    refute packet["files"]["queries.json"] =~ "commitment_nonce"

    bad =
      context["answers"]
      |> JSON.decode!()
      |> put_in(["answers", Access.at(0), "relevance", Access.at(0), "source", "version"], "1")
      |> JSON.encode!()

    assert {:error, :invalid_reference_integrity} =
             Review.prepare(
               freeze,
               blobs,
               fn -> {:ok, Map.put(context, "answers", bad)} end,
               @seed
             )

    assert {:error, :invalid_context} =
             Review.prepare(freeze, blobs, fn -> {:ok, Map.delete(context, "answers")} end, @seed)

    changed = put_in(freeze, ["queries", Access.at(0), "project"], "foreign")

    loader = fn ->
      send(self(), :opened_answers)
      {:ok, context}
    end

    assert {:error, _} = Review.prepare(changed, blobs, loader, @seed)
    refute_received :opened_answers
  end

  test "literal UTF8 matches do not independently support a false semantic claim" do
    {freeze, blobs} = inputs()
    assert {:ok, packet} = Review.prepare(freeze, blobs, fn -> {:ok, context()} end, @seed)
    assert {:ok, ^packet} = Review.prepare(freeze, blobs, fn -> {:ok, context()} end, @seed)
    files = packet["files"]
    cases = files["cases.jsonl"] |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

    assert Enum.sort(Enum.map(cases, & &1["prediction_id"])) ==
             Enum.sort(Enum.map(rows(), & &1["prediction_id"]))

    assert Enum.all?(
             cases,
             &(not Map.has_key?(&1, "variant") and &1["answer"] == "The moon is cheese.")
           )

    for label <- @variants ++ [@seed], do: refute(JSON.encode!(files) =~ label)
    review = JSON.decode!(files["reviews-template.json"])
    assert review["version"] == 2
    assert {:ok, verified} = Ipse.Development.Evaluation.Score.verified_predictions(freeze, blobs)
    assert review["review_binding_sha256"] == verified["review_binding_sha256"]
    assert packet["summary"]["review_binding_sha256"] == verified["review_binding_sha256"]
    assert packet["summary"]["protocol"] == "independent-knowledge-review-v2"

    assert Enum.all?(
             review["semantic"],
             &(&1["verdict"] == "unmeasured" and not &1["independent"])
           )

    assert Enum.all?(
             review["integrity"],
             &(&1["verdict"] == "valid" and &1["reviewer_id"] == "source-bytes-v1")
           )

    assert length(review["integrity"]) == 4
    assert packet["summary"]["literal_invalid"] == 0
    assert packet["summary"]["reference_integrity_complete"]
    manifest = JSON.decode!(files["manifest.json"])
    for {name, hash} <- manifest["files"], do: assert(sha(files[name]) == hash)

    assert JSON.decode!(files["queries.json"])["queries"] |> hd() |> Map.fetch!("expected_answer") ==
             "A café."
  end

  test "template and integrity lists cannot retain the private execution order" do
    {freeze, blobs} = inputs()
    original = Enum.map(rows(), & &1["prediction_id"])

    selected =
      Enum.find_value(1..8, fn i ->
        {:ok, packet} =
          Review.prepare(freeze, blobs, fn -> {:ok, context()} end, sha("order-#{i}"))

        ids =
          packet["files"]["cases.jsonl"]
          |> String.split("\n", trim: true)
          |> Enum.map(&JSON.decode!(&1)["prediction_id"])

        if ids != original, do: {packet, ids}
      end)

    assert {packet, ids} = selected
    review = JSON.decode!(packet["files"]["reviews-template.json"])
    assert Enum.map(review["semantic"], & &1["prediction_id"]) == ids
    assert Enum.map(review["integrity"], & &1["prediction_id"]) |> Enum.uniq() == ids
  end

  test "same-body typed identities and foreign-project passages cannot forge literal integrity" do
    for forged <- [
          identity(2, 1),
          identity(3, "1"),
          identity(1, 1, "foreign"),
          Map.put(identity(), "sha256", String.duplicate("0", 64))
        ] do
      changed =
        List.update_at(rows(), 0, fn row ->
          row
          |> Map.update!("evidence", &Enum.map(&1, fn span -> %{span | "source" => forged} end))
          |> Map.update!(
            "context_evidence",
            &Enum.map(&1, fn span -> %{span | "source" => forged} end)
          )
        end)

      {freeze, blobs} = inputs(changed)
      assert {:ok, packet} = Review.prepare(freeze, blobs, fn -> {:ok, context()} end, @seed)
      assert packet["summary"]["literal_invalid"] == 2

      assert Enum.all?(
               JSON.decode!(packet["files"]["reviews-template.json"])["semantic"],
               &(&1["verdict"] == "unmeasured")
             )
    end
  end

  test "a structurally valid wrong reference span stays visible and incomplete" do
    c = context()
    query = JSON.decode!(c["queries"])

    query =
      update_in(
        query,
        ["queries", Access.at(0), "relevance", Access.at(0)],
        &%{&1 | "start_byte" => 0, "end_byte" => 5}
      )

    c = %{c | "queries" => JSON.encode!(query)}
    {freeze, blobs} = inputs()
    assert {:ok, packet} = Review.prepare(freeze, blobs, fn -> {:ok, c} end, @seed)
    refute packet["summary"]["reference_integrity_complete"]

    assert [%{"valid" => false}] =
             JSON.decode!(packet["files"]["reference-integrity.json"])["references"]
  end
end
