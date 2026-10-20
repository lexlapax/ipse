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
      "claims" => [%{"text" => "Include checksums.", "citations" => ids}]
    }
  end

  @tag :answer_contract
  test "one ordered cited body supplies the material answer independently of its classification" do
    {:ok, bundle} = Answer.prepare("release", 1000, [candidate("a")])
    texts = ["  Preserve café and é.\nA quoted \"line\".  ", "Path \\release requires checksums."]
    claims = Enum.map(texts, &%{"text" => &1, "citations" => ["e1"]})

    for class <- ~w(answer conflict open) do
      wire = %{"classification" => class, "claims" => claims}
      assert {:ok, decoded} = Answer.decode_answer(JSON.encode!(wire), bundle)
      assert decoded["classification"] == class
      assert decoded["answer"] == Enum.join(texts, "\n")
      assert Enum.map(decoded["claims"], & &1["text"]) == texts
      assert Enum.all?(decoded["claims"], &(Enum.sort(Map.keys(&1)) == ~w(citations text)))

      for legacy_answer <- [nil, "A separate contradictory answer."] do
        assert {:error, :invalid_answer_shape} =
                 Answer.decode_answer(
                   JSON.encode!(Map.put(wire, "answer", legacy_answer)),
                   bundle
                 )
      end
    end
  end

  test "empty decisions preserve the difference between shown, omitted and absent evidence" do
    {:ok, shown} = Answer.prepare("release", 1000, [candidate("a")])
    {:ok, absent} = Answer.prepare("release", 1000, [])

    {:ok, omitted} =
      Answer.prepare("release", 1000, [candidate("a", String.duplicate(<<0>>, 1024))])

    assert absent["coverage"]["candidate_count"] == 0
    assert omitted["coverage"]["candidate_count"] == 1

    for bundle <- [shown, absent, omitted], class <- ~w(answer conflict open abstain) do
      wire = JSON.encode!(%{"classification" => class, "claims" => []})

      if class == "abstain" or (class == "open" and bundle == shown) do
        assert {:ok, decoded} = Answer.decode_answer(wire, bundle)

        assert decoded["answer"] ==
                 if(class == "abstain",
                   do: "I cannot answer from the shown evidence.",
                   else: "The shown evidence leaves this question unresolved."
                 )

        assert decoded["claims"] == []
        refute Map.has_key?(decoded, "supported")
      else
        assert {:error, :invalid_answer_shape} = Answer.decode_answer(wire, bundle)
      end
    end
  end

  test "decoded text and serialized output retain their existing separate byte limits" do
    {:ok, bundle} = Answer.prepare("release", 1000, [candidate("a")])
    assert byte_size(bundle["request"]["instruction"]) <= 2048
    assert bundle["request"]["max_output_bytes"] == 8192
    assert bundle["request"]["timeout_ms"] == 120_000

    for text <- [String.duplicate("é", 512), String.duplicate(<<0>>, 1024)] do
      wire = put_in(response(), ["claims", Access.at(0), "text"], text) |> JSON.encode!()
      padded = wire <> String.duplicate(" ", 8192 - byte_size(wire))
      assert {:ok, decoded} = Answer.decode_answer(padded, bundle)
      assert decoded["answer"] == text
      assert hd(decoded["claims"])["text"] == text
      assert {:error, :answer_too_large} = Answer.decode_answer(padded <> " ", bundle)

      oversized = put_in(response(), ["claims", Access.at(0), "text"], text <> "x")
      assert {:error, :invalid_claim} = Answer.decode_answer(JSON.encode!(oversized), bundle)
    end

    eight = Map.put(response(), "claims", List.duplicate(hd(response()["claims"]), 8))
    assert {:ok, decoded} = Answer.decode_answer(JSON.encode!(eight), bundle)
    assert length(decoded["claims"]) == 8
    assert decoded["answer"] == Enum.map_join(eight["claims"], "\n", & &1["text"])
    nine = Map.update!(eight, "claims", &(&1 ++ [hd(&1)]))
    assert {:error, :invalid_answer_shape} = Answer.decode_answer(JSON.encode!(nine), bundle)
  end

  test "each claim keeps its complete citation associations without text deduplication" do
    evidence = [candidate("a"), candidate("b")]
    {:ok, bundle} = Answer.prepare("release", 1000, evidence)
    repeated = %{"text" => "Include checksums.", "citations" => ["e1", "e2"]}
    wire = %{"classification" => "conflict", "claims" => [repeated, repeated]}
    assert {:ok, decoded} = Answer.decode_answer(JSON.encode!(wire), bundle)
    assert decoded["answer"] == "Include checksums.\nInclude checksums."
    assert length(decoded["claims"]) == 2

    for claim <- decoded["claims"] do
      assert Enum.map(claim["citations"], & &1["candidate_id"]) == ~w(e1 e2)

      assert Enum.map(claim["citations"], & &1["citation"]) ==
               Enum.map(evidence, & &1["citation"])
    end
  end

  test "invalid wire values refuse the whole answer without repairing a decision" do
    {:ok, bundle} = Answer.prepare("release", 1000, [candidate("a")])

    for value <- [
          nil,
          [],
          "answer",
          %{},
          %{"classification" => "unknown", "claims" => []},
          Map.put(response(), "claims", nil),
          Map.put(response(), "extra", true),
          put_in(response(), ["claims", Access.at(0), "text"], " \n"),
          put_in(response(), ["claims", Access.at(0), "citations"], []),
          put_in(response(), ["claims", Access.at(0), "citations"], [1]),
          put_in(response(), ["claims", Access.at(0), "extra"], true)
        ] do
      assert {:error, _} = Answer.decode_answer(JSON.encode!(value), bundle)
    end

    assert {:error, :duplicate_json_key} =
             Answer.decode_answer(
               ~s({"classification":"answer","claims":[{"text":"a","text":"b","citations":["e1"]}]}),
               bundle
             )

    assert {:error, _} =
             Answer.decode_answer(
               ~s({"classification":"answer","claims":[{"text":") <>
                 <<255>> <>
                 ~s(","citations":["e1"]}]}),
               bundle
             )
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

  test "an admitted citation retains a complete qualification after byte 512" do
    quote = String.duplicate("A", 520) <> ". The trial does not establish production safety."
    evidence = [candidate("trial", quote)]

    assert {:ok, bundle} =
             Answer.prepare("Does the trial establish production safety?", 1000, evidence)

    assert [shown] = bundle["shown"]
    assert shown["citation"] == hd(evidence)["citation"]
    assert hd(bundle["context"]["candidates"])["quote"] == quote
    assert bundle["coverage"]["cropped"] == []
  end

  test "whole UTF8 citations retain coordinates and hashes while omissions preserve saved ranks" do
    quote = String.duplicate("a", 511) <> "é" <> String.duplicate("z", 200)
    evidence = Enum.map(1..10, &candidate("source-#{&1}", quote))
    assert {:ok, bundle} = Answer.prepare("release", 1000, evidence)
    assert byte_size(bundle["request"]["input"]) <= 4096
    assert bundle["coverage"]["omitted_count"] > 0
    assert bundle["coverage"]["shown_count"] + bundle["coverage"]["omitted_count"] == 10

    for item <- bundle["shown"] do
      refute item["cropped"]
      assert String.valid?(item["citation"]["quote"])
      assert item["citation"]["quote"] == quote
      assert item["citation"]["end_byte"] == 6 + byte_size(quote)
      assert item["citation"]["quote_sha256"] == sha(item["citation"]["quote"])
      assert item["captured_span"]["end_byte"] == 6 + byte_size(quote)
    end

    assert {:ok, _} = Answer.decode_answer(JSON.encode!(response()), bundle)
    omitted_id = hd(bundle["coverage"]["omitted"])["candidate_id"]

    assert {:error, :unknown_citation} =
             Answer.decode_answer(JSON.encode!(response("answer", [omitted_id])), bundle)
  end

  test "prefix packing records an omitted contradiction and later short candidate without claiming completeness" do
    long = String.duplicate("a", 1000)
    contradiction = "The policy does not permit release. " <> String.duplicate("b", 960)

    evidence =
      Enum.map(1..3, &candidate("source-#{&1}", long)) ++
        [candidate("contradiction", contradiction), candidate("short", "A short statement.")]

    assert {:ok, bundle} = Answer.prepare("release", 1000, evidence)
    assert bundle["coverage"]["shown_ids"] == ~w(e1 e2 e3)
    assert Enum.map(bundle["coverage"]["omitted"], & &1["candidate_id"]) == ~w(e4 e5)
    assert bundle["coverage"]["cropped"] == []
    refute bundle["request"]["input"] =~ "does not permit"

    assert {:error, :unknown_citation} =
             Answer.decode_answer(JSON.encode!(response("conflict", ["e4"])), bundle)
  end

  test "escaped text that cannot fit is omitted whole and remains distinct from empty retrieval" do
    evidence = [candidate("escaped", String.duplicate(<<0>>, 1024))]
    assert {:ok, bundle} = Answer.prepare("release", 1000, evidence)
    assert bundle["coverage"]["candidate_count"] == 1
    assert bundle["coverage"]["shown_count"] == 0
    assert bundle["coverage"]["omitted_count"] == 1
    assert bundle["shown"] == [] and bundle["coverage"]["cropped"] == []
    assert byte_size(bundle["request"]["input"]) <= 4096
    assert {:ok, empty} = Answer.prepare("release", 1000, [])
    assert empty["coverage"]["candidate_count"] == 0
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
               ~s({"classification":"abstain","claims":[]}),
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
