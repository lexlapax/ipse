Code.require_file("../examples/knowledge/evaluation_input.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationInputTest do
  use ExUnit.Case, async: true
  alias IpseKnowledgeExample.EvaluationInput, as: Input

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
      "sha256" => Ipse.Extensions.Manifest.sha256("A café."),
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

  test "query projection excludes label values even when they change or become invalid" do
    original = query()
    assert {:ok, projected} = Input.queries(queries([original]), "tuning")
    assert projected["queries"] == [Map.take(original, ~w(query_id project query))]
    assert projected["excluded_fields"] == ~w(expected_answer expected_class relevance split)

    poisoned =
      Map.merge(original, %{
        "expected_class" => "invalid-label",
        "expected_answer" => "secret-label-marker",
        "relevance" => "secret-relevance-marker",
        "expected_refusal" => true
      })

    assert {:ok, changed} = Input.queries(queries([poisoned]), "tuning")
    assert changed["queries"] == projected["queries"]
    refute JSON.encode!(changed) =~ "secret-label-marker"
    refute JSON.encode!(changed) =~ "secret-relevance-marker"
    assert {:error, :label_class} = Input.labels(queries([poisoned]), "tuning")
  end

  test "wrong splits, missing query text, duplicate IDs and duplicate JSON keys refuse" do
    assert {:error, :query_split} = Input.queries(queries([query()]), "heldout")

    assert {:error, :query_text} =
             Input.queries(queries([Map.delete(query(), "query")]), "tuning")

    assert {:error, :duplicate_query} = Input.queries(queries([query(), query()]), "tuning")

    raw =
      String.replace(
        queries([query()]),
        "\"query_id\":\"q1\"",
        "\"query_id\":\"q1\",\"query_id\":\"q2\""
      )

    assert {:error, :duplicate_key} = Input.queries(raw, "tuning")
    assert {:error, :invalid_json} = Input.queries(String.duplicate(" ", 1_048_577), "tuning")
  end

  test "corpus preserves complete source generations and reports excluded metadata" do
    first = Map.put(document(), "curation_note", "never sent to a model")

    second =
      Map.merge(document(), %{"document_id" => "d2", "generation" => 2, "state" => "forgotten"})

    assert {:ok, result} = Input.corpus(corpus([first, second]))
    assert length(result["documents"]) == 2
    assert Enum.map(result["documents"], & &1["text"]) == ["A café.", "A café."]
    assert Enum.map(result["documents"], & &1["generation"]) == [1, 2]
    assert List.last(result["documents"])["state"] == "forgotten"
    assert result["excluded_fields"] == ["curation_note"]
    assert {:error, :duplicate_source_generation} = Input.corpus(corpus([document(), document()]))

    for version <- ["1", 2, "other"] do
      duplicate =
        document() |> Map.put("document_id", "another-id") |> Map.put("version", version)

      assert {:error, :duplicate_source_generation} =
               Input.corpus(corpus([document(), duplicate]))
    end

    assert {:ok, _} = Input.corpus(corpus([document(), Map.put(document(), "project", "beta")]))
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
      assert {:error, ^reason} = Input.corpus(corpus([Map.put(document(), field, value)]))
    end
  end

  test "labels normalize full source identity and retain byte coordinates only in scoring data" do
    assert {:ok, normalized} = Input.labels(queries([query()]), "tuning")
    [row] = normalized["queries"]
    assert row["expected_class"] == "answer"
    assert row["expected_refusal"] == false
    [span] = row["relevance"]
    assert span["source"] == Map.take(document(), ~w(project source_id generation version sha256))
    assert span["start_byte"] == 2 and span["end_byte"] == 7 and span["quote"] == "café"
    refute Map.has_key?(row, "expected_answer")

    wrong_span = put_in(query(), ["relevance", Access.at(0), "end_byte"], 6)
    assert {:error, :relevance_span} = Input.labels(queries([wrong_span]), "tuning")
    foreign = put_in(query(), ["relevance", Access.at(0), "project"], "beta")
    assert {:error, :relevance_project} = Input.labels(queries([foreign]), "tuning")
  end
end
