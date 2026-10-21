Code.require_file("../dev/evaluation/dataset.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationDatasetTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Evaluation.Dataset

  test "as-of population selects observation-eligible generations before lifecycle exclusion" do
    row = fn id, generation, observed, state ->
      %{
        "key" => "#{id}-#{generation}",
        "identity" => %{"project" => "alpha"},
        "source" => %{
          "source_id" => id,
          "generation" => generation,
          "observed_at_ms" => observed,
          "expires_at_ms" => nil
        },
        "state" => state
      }
    end

    old = row.("replacement", 1, 1000, "current")
    live = row.("tombstone", 1, 1000, "current")
    newer = row.("replacement", 2, 3000, "current")
    tombstone = row.("tombstone", 2, 3000, "suppressed")
    rows = [tombstone, newer, live, old]

    assert %{selected: [^old, ^live], eligible: [^old, ^live], excluded: [^tombstone, ^newer]} =
             Dataset.population(rows, 2000)

    assert %{selected: [^newer, ^tombstone], eligible: [^newer]} = Dataset.population(rows, 3000)
    expired = put_in(newer, ["source", "expires_at_ms"], 3000)
    assert %{selected: [^expired], eligible: []} = Dataset.population([old, expired], 3000)
    assert %{selected: [], eligible: []} = Dataset.population(rows, 999)
    suppressed = row.("tombstone", 1, 1000, "suppressed")
    resurrection = row.("tombstone", 2, 2000, "current")

    assert %{observed: [^suppressed, ^resurrection], selected: [^resurrection], eligible: []} =
             Dataset.population([resurrection, suppressed], 3000)
  end

  defp document do
    %{
      "document_id" => "d1",
      "project" => "alpha",
      "source_id" => "source:one",
      "generation" => 1,
      "version" => 1,
      "title" => "Fixture",
      "text" => "A café.",
      "created_at" => "2026-01-01T00:00:00Z",
      "observed_at" => "2026-03-01T00:00:00Z",
      "state" => "current",
      "sha256" => Ipse.JSON.sha256("A café."),
      "byte_length" => byte_size("A café."),
      "media_type" => "text/plain; charset=utf-8"
    }
  end

  defp query do
    %{
      "query_id" => "q1",
      "project" => "alpha",
      "query" => "What is described?",
      "split" => "tuning",
      "expected_class" => "answer",
      "expected_answer" => "A café.",
      "relevance" => [
        %{
          "document_id" => "d1",
          "source_id" => "source:one",
          "generation" => 1,
          "version" => 1,
          "sha256" => document()["sha256"],
          "grade" => 3,
          "start_byte" => 2,
          "end_byte" => 7,
          "quote" => "café"
        }
      ]
    }
  end

  defp queries(rows), do: JSON.encode!(%{"schema_version" => 1, "queries" => rows})
  defp corpus(rows), do: JSON.encode!(%{"schema_version" => 1, "documents" => rows})

  defp sealed_questions(rows \\ [Map.take(query(), ~w(query_id project query))]) do
    JSON.encode!(%{"contract" => "sealed_answers_v1", "split" => "heldout", "queries" => rows})
  end

  defp sealed_answer do
    legacy = query()
    [span] = legacy["relevance"]

    legacy
    |> Map.take(~w(query_id project expected_class expected_answer))
    |> Map.put("expected_refusal", false)
    |> Map.put("relevance", [
      Map.take(span, ~w(grade start_byte end_byte quote))
      |> Map.put("source", Map.take(document(), ~w(project source_id generation version sha256)))
    ])
  end

  defp sealed_answers(rows \\ [sealed_answer()]) do
    JSON.encode!(%{
      "contract" => "sealed_answers_v1",
      "split" => "heldout",
      "commitment_nonce" => String.duplicate("a", 64),
      "answers" => rows
    })
  end

  test "sealed questions reject answer fields and normalize detached answers in question order" do
    second = %{"query_id" => "q2", "project" => "beta", "query" => "Another question?"}

    assert {:ok, questions} =
             Dataset.queries(
               sealed_questions([Map.take(query(), ~w(query_id project query)), second]),
               "heldout"
             )

    assert questions["excluded_fields"] == []
    refute JSON.encode!(questions) =~ "expected_answer"

    other =
      sealed_answer() |> Map.merge(%{"query_id" => "q2", "project" => "beta", "relevance" => []})

    assert {:ok, refs} =
             Dataset.references(sealed_answers([other, sealed_answer()]), "heldout", questions)

    assert Enum.map(refs["labels"]["queries"], & &1["query_id"]) == ~w(q1 q2)
    assert refs["expected_answers"] == %{"q1" => "A café.", "q2" => "A café."}
    refute JSON.encode!(refs["labels"]) =~ "expected_answer"

    assert {:error, :query_shape} =
             Dataset.queries(
               sealed_questions([Map.put(second, "expected_answer", "secret")]),
               "heldout"
             )

    assert {:error, :query_split} = Dataset.queries(sealed_questions(), "tuning")
    assert {:error, :dataset_version} = Dataset.labels(sealed_questions(), "heldout")
    assert {:error, :dataset_version} = Dataset.queries(sealed_answers(), "heldout")
  end

  test "sealed answer joins and typed relevance are closed and never silently drop rows" do
    assert {:ok, questions} = Dataset.queries(sealed_questions(), "heldout")
    answer = sealed_answer()

    for rows <- [
          [],
          [answer, answer],
          [Map.put(answer, "query_id", "foreign")],
          [Map.put(answer, "project", "beta")]
        ] do
      assert {:error, _} = Dataset.references(sealed_answers(rows), "heldout", questions)
    end

    for changed <- [
          Map.put(answer, "query", "duplicated text"),
          Map.delete(answer, "expected_refusal"),
          Map.put(answer, "expected_answer", String.duplicate("x", 8193)),
          Map.update!(answer, "relevance", &(&1 ++ &1)),
          put_in(answer, ["relevance", Access.at(0), "source", "project"], "beta"),
          put_in(answer, ["relevance", Access.at(0), "end_byte"], 6),
          put_in(answer, ["relevance", Access.at(0), "source", "extra"], true)
        ] do
      assert {:error, _} = Dataset.references(sealed_answers([changed]), "heldout", questions)
    end

    assert {:ok, refs} = Dataset.references(sealed_answers(), "heldout", questions)
    assert {:ok, sources} = Ipse.Development.Evaluation.Dataset.sources(corpus([document()]))

    assert Enum.all?(
             Ipse.Development.Evaluation.Dataset.reference_checks(
               refs["labels"]["queries"],
               sources
             ),
             & &1["valid"]
           )

    changed = put_in(answer, ["relevance", Access.at(0), "source", "version"], "1")
    assert {:ok, wrong} = Dataset.references(sealed_answers([changed]), "heldout", questions)

    refute Enum.all?(
             Ipse.Development.Evaluation.Dataset.reference_checks(
               wrong["labels"]["queries"],
               sources
             ),
             & &1["valid"]
           )

    raw = sealed_answers() |> JSON.decode!() |> Map.delete("commitment_nonce") |> JSON.encode!()
    assert {:error, :answer_shape} = Dataset.references(raw, "heldout", questions)
  end

  test "query projection excludes label values even when they change or become invalid" do
    original = query()
    assert {:ok, projected} = Dataset.queries(queries([original]), "tuning")
    assert projected["queries"] == [Map.take(original, ~w(query_id project query))]
    assert projected["excluded_fields"] == ~w(expected_answer expected_class relevance split)

    poisoned =
      Map.merge(original, %{
        "expected_class" => "invalid-label",
        "expected_answer" => "secret-label-marker",
        "relevance" => "secret-relevance-marker",
        "expected_refusal" => true
      })

    assert {:ok, changed} = Dataset.queries(queries([poisoned]), "tuning")
    assert changed["queries"] == projected["queries"]
    refute JSON.encode!(changed) =~ "secret-label-marker"
    refute JSON.encode!(changed) =~ "secret-relevance-marker"
    assert {:error, :label_class} = Dataset.labels(queries([poisoned]), "tuning")
  end

  test "wrong splits, missing query text, duplicate IDs and duplicate JSON keys refuse" do
    assert {:error, :query_split} = Dataset.queries(queries([query()]), "heldout")

    assert {:error, :query_text} =
             Dataset.queries(queries([Map.delete(query(), "query")]), "tuning")

    assert {:error, :duplicate_query} = Dataset.queries(queries([query(), query()]), "tuning")

    raw =
      String.replace(
        queries([query()]),
        "\"query_id\":\"q1\"",
        "\"query_id\":\"q1\",\"query_id\":\"q2\""
      )

    assert {:error, :duplicate_key} = Dataset.queries(raw, "tuning")
    assert {:error, :invalid_json} = Dataset.queries(String.duplicate(" ", 1_048_577), "tuning")
  end

  test "corpus preserves complete source generations and reports excluded metadata" do
    first = Map.put(document(), "curation_note", "never sent to a model")

    second =
      Map.merge(document(), %{"document_id" => "d2", "generation" => 2, "state" => "forgotten"})

    assert {:ok, result} = Dataset.corpus(corpus([first, second]))
    assert length(result["documents"]) == 2
    assert Enum.map(result["documents"], & &1["text"]) == ["A café.", "A café."]
    assert Enum.map(result["documents"], & &1["generation"]) == [1, 2]
    assert List.last(result["documents"])["state"] == "forgotten"
    assert result["excluded_fields"] == ["curation_note"]

    assert {:error, :duplicate_source_generation} =
             Dataset.corpus(corpus([document(), document()]))

    for version <- ["1", 2, "other"] do
      duplicate =
        document() |> Map.put("document_id", "another-id") |> Map.put("version", version)

      assert {:error, :duplicate_source_generation} =
               Dataset.corpus(corpus([document(), duplicate]))
    end

    assert {:ok, _} = Dataset.corpus(corpus([document(), Map.put(document(), "project", "beta")]))
  end

  test "source byte length, hash, observation and field bounds are checked independently" do
    for {field, value, reason} <- [
          {"byte_length", 1, :document_length},
          {"sha256", String.duplicate("0", 64), :document_hash},
          {"observed_at", "invalid", :document_time},
          {"text", String.duplicate("x", 65_537), :document_text},
          {"title", String.duplicate("é", 65), :document_text},
          {"project", "../other", :document_identity}
        ] do
      assert {:error, ^reason} = Dataset.corpus(corpus([Map.put(document(), field, value)]))
    end
  end

  test "labels normalize full source identity and retain byte coordinates only in scoring data" do
    assert {:ok, normalized} = Dataset.labels(queries([query()]), "tuning")
    [row] = normalized["queries"]
    assert row["expected_class"] == "answer"
    assert row["expected_refusal"] == false
    [span] = row["relevance"]
    assert span["source"] == Map.take(document(), ~w(project source_id generation version sha256))
    assert span["start_byte"] == 2 and span["end_byte"] == 7 and span["quote"] == "café"
    refute Map.has_key?(row, "expected_answer")

    wrong_span = put_in(query(), ["relevance", Access.at(0), "end_byte"], 6)
    assert {:error, :relevance_span} = Dataset.labels(queries([wrong_span]), "tuning")
    foreign = put_in(query(), ["relevance", Access.at(0), "project"], "beta")
    assert {:error, :relevance_project} = Dataset.labels(queries([foreign]), "tuning")
  end
end
