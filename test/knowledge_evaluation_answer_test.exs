Code.require_file("../examples/knowledge/evaluation_answer.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationAnswerTest do
  use ExUnit.Case, async: true
  alias IpseKnowledgeExample.EvaluationAnswer, as: Answer

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp candidate(id, quote \\ "A release includes its checksums.") do
    %{
      "citation" => %{
        "version" => 1,
        "source_id" => id,
        "source_key" => sha(id),
        "generation" => 1,
        "content_sha256" => sha("prefix" <> quote),
        "chunk_id" => sha("chunk:" <> id),
        "start_byte" => 6,
        "end_byte" => 6 + byte_size(quote),
        "quote" => quote,
        "quote_sha256" => sha(quote),
        "uri" => "fixture:" <> id,
        "observed_at_ms" => 100,
        "event_at_ms" => nil,
        "origin" => %{"kind" => "provided", "ledger_class" => "open"}
      }
    }
  end

  defp response(class \\ "answer", ids \\ ["e1"]) do
    %{
      "classification" => class,
      "answer" => "Include checksums.",
      "claims" => [%{"text" => "Include checksums.", "citations" => ids}]
    }
  end

  test "saved rank and complete citation identity survive deterministic preparation and mapping" do
    evidence = [candidate("second"), candidate("first")]
    assert {:ok, bundle} = Answer.prepare("What belongs in a release?", 1000, evidence)
    assert {:ok, ^bundle} = Answer.prepare("What belongs in a release?", 1000, evidence)
    assert bundle["request"]["profile"] == "p27_answer"
    assert bundle["context_sha256"] == sha(bundle["request"]["input"])
    assert Enum.map(bundle["shown"], & &1["citation"]["source_id"]) == ["second", "first"]
    assert {:ok, decoded} = Answer.decode_answer(JSON.encode!(response()), bundle)
    assert hd(hd(decoded["claims"])["citations"])["citation"] == hd(evidence)["citation"]
    refute Map.has_key?(decoded, "supported")
    assert {:ok, conflict} = Answer.decode_answer(JSON.encode!(response("conflict")), bundle)
    assert conflict["classification"] == "conflict"
  end

  test "UTF8 cropping adjusts coordinates and hashes and omissions preserve saved ranks" do
    quote = String.duplicate("a", 511) <> "é" <> String.duplicate("z", 200)
    evidence = Enum.map(1..10, &candidate("source-#{&1}", quote))
    assert {:ok, bundle} = Answer.prepare("release", 1000, evidence)
    assert byte_size(bundle["request"]["input"]) <= 4096
    assert bundle["coverage"]["omitted_count"] > 0
    assert bundle["coverage"]["shown_count"] + bundle["coverage"]["omitted_count"] == 10

    for item <- bundle["shown"] do
      assert item["cropped"]
      assert String.valid?(item["citation"]["quote"])
      assert byte_size(item["citation"]["quote"]) == 511
      assert item["citation"]["end_byte"] == 517
      assert item["citation"]["quote_sha256"] == sha(item["citation"]["quote"])
      assert item["captured_span"]["end_byte"] == 6 + byte_size(quote)
    end

    assert {:ok, _} = Answer.decode_answer(JSON.encode!(response()), bundle)
    omitted_id = hd(bundle["coverage"]["omitted"])["candidate_id"]

    assert {:error, :unknown_citation} =
             Answer.decode_answer(JSON.encode!(response("answer", [omitted_id])), bundle)
  end

  test "strict answers reject duplicate or unknown references, fenced JSON and duplicate fields" do
    {:ok, bundle} = Answer.prepare("release", 1000, [candidate("a")])

    assert {:error, :duplicate_citation} =
             Answer.decode_answer(JSON.encode!(response("answer", ["e1", "e1"])), bundle)

    assert {:error, :unknown_citation} =
             Answer.decode_answer(JSON.encode!(response("answer", ["e9"])), bundle)

    assert {:error, _} =
             Answer.decode_answer("```json\n" <> JSON.encode!(response()) <> "\n```", bundle)

    assert {:error, :duplicate_json_key} =
             Answer.decode_answer(
               ~s({"classification":"abstain","answer":"","claims":[],"answer":"x"}),
               bundle
             )

    assert {:error, _} = Answer.decode_answer(JSON.encode!(response()) <> "{}", bundle)

    assert {:error, :invalid_answer_shape} =
             Answer.decode_answer(JSON.encode!(response("abstain")), bundle)

    assert {:ok, empty} = Answer.prepare("release", 1000, [])

    assert {:ok, _} =
             Answer.decode_answer(
               ~s({"classification":"abstain","answer":"Insufficient evidence.","claims":[]}),
               empty
             )
  end

  test "tampered bundles and malformed source identity fail without dispatch" do
    {:ok, bundle} = Answer.prepare("release", 1000, [candidate("a")])
    altered = put_in(bundle, ["shown", Access.at(0), "citation", "quote"], "forged")
    assert {:error, :invalid_bundle} = Answer.decode_answer(JSON.encode!(response()), altered)
    bad = put_in(candidate("a"), ["citation", "source_key"], sha("other"))
    assert {:error, :invalid_citation} = Answer.prepare("release", 1000, [bad])

    assert {:error, :too_many_candidates} =
             Answer.prepare("release", 1000, List.duplicate(candidate("a"), 11))

    assert {:error, :invalid_query} = Answer.prepare(" ", 1000, [])
    assert {:error, :invalid_as_of_ms} = Answer.prepare("release", -1, [])
  end
end
