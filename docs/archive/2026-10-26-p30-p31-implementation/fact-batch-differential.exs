import ExUnit.Assertions

[old_evidence_path, old_projection_path] = System.argv()
Code.compiler_options(no_warn_undefined: :all)
Code.compile_file("extensions/knowledge/src/evidence.ex")
Code.compile_file("extensions/knowledge/src/store/collection/projection.ex")

old_evidence =
  File.read!(old_evidence_path)
  |> String.replace("defmodule IpseKnowledge.Evidence do", "defmodule FactBaseline.Evidence do", global: false)

old_projection =
  File.read!(old_projection_path)
  |> String.replace("defmodule IpseKnowledge.Store.Collection.Projection do", "defmodule FactBaseline.Projection do", global: false)
  |> String.replace("alias IpseKnowledge.Evidence, as: E", "alias FactBaseline.Evidence, as: E", global: false)

Code.compile_string(old_evidence, old_evidence_path)
Code.compile_string(old_projection, old_projection_path)

alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection.Projection, as: P
alias FactBaseline.Evidence, as: OldE
alias FactBaseline.Projection, as: OldP

attrs = %{
  "source_id" => "differential:synthetic", "partition" => "notes", "generation" => 1,
  "title" => "Synthetic differential", "text" => String.duplicate("café alpha β ", 600),
  "uri" => "local:synthetic", "observed_at_ms" => 10, "event_at_ms" => nil,
  "expires_at_ms" => nil,
  "origin" => %{"kind" => "provided", "store_profile" => "local",
                "partition_or_scope" => "notes", "receipt" => nil, "historical" => false}
}

{:ok, legacy} = E.source(attrs)
{:ok, collection} = E.collection_source(attrs)
selection = %{"kind" => "explicit", "profile" => nil, "version" => 1}

counts =
  for source <- [legacy, collection] do
    {:ok, chunks} = E.chunks(source)
    chunk = hd(chunks)
    forged = Map.put(chunk, "chunk_id", String.duplicate("0", 64))
    span_cases =
      for candidate <- [chunk, forged, Map.put(chunk, "extra", true), nil],
          start <- [-1, 0, 1, 3, 4, 5, 6, 100, nil],
          finish <- [-1, 0, 1, 4, 5, 6, 12, 1025, nil],
          do: {candidate, start, finish}

    for {candidate, start, finish} <- span_cases do
      assert E.citation(source, candidate, start, finish) ===
               OldE.citation(source, candidate, start, finish)
    end

    good_spans = Enum.take(for({c, s, e} <- span_cases, match?({:ok, _}, OldE.citation(source, c, s, e)), do: {c, s, e}), 8)
    assert good_spans != []
    expected = Enum.map(good_spans, fn {c, s, e} -> {:ok, value} = OldE.citation(source, c, s, e); value end)
    assert {:ok, ^expected} = E.citations(source, good_spans)
    assert {:error, :invalid_span} = E.citations(source, good_spans ++ [{forged, 0, 1}])

    {:ok, citation} = E.citation(source, chunk, 0, 5)
    {:ok, fact} = E.fact(%{"subject" => "synthetic", "predicate" => "quotes", "object" => "café",
      "polarity" => "positive", "inferred" => false, "valid_from_ms" => nil, "valid_to_ms" => nil,
      "extraction" => selection, "citations" => [citation]})
    {:ok, pages} = P.pack_facts(source, [fact], selection)
    [page] = pages
    [row] = page["rows"]
    [span] = row["citations"]
    mutants = [
      pages,
      [Map.put(page, "ordinal", 1)],
      [Map.put(page, "source_bundle_sha256", String.duplicate("0", 64))],
      [Map.put(page, "extra", true)],
      [Map.put(page, "rows", [])],
      [Map.put(page, "rows", [row, row])],
      [put_in(page, ["rows", Access.at(0), "citations", Access.at(0)], List.replace_at(span, 3, String.duplicate("0", 64)))],
      [put_in(page, ["rows", Access.at(0), "citations", Access.at(0)], List.replace_at(span, 0, 99))],
      [put_in(page, ["rows", Access.at(0), "subject"], 999)],
      [put_in(page, ["rows", Access.at(0), "fact", "polarity"], "unknown")]
    ]

    for candidate <- mutants do
      assert P.unpack_facts(source, candidate, selection) === OldP.unpack_facts(source, candidate, selection)
    end
    %{span_cases: length(span_cases), page_cases: length(mutants)}
  end

IO.puts(Jason.encode!(%{"source_formats" => length(counts),
  "span_cases" => Enum.sum(Enum.map(counts, & &1.span_cases)),
  "page_cases" => Enum.sum(Enum.map(counts, & &1.page_cases))}))
