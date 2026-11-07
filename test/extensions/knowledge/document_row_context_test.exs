defmodule Ipse.KnowledgeDocumentRowContextTest do
  use ExUnit.Case, async: false

  test "lexical matches expose bounded same-row cells as attributed context" do
    root = Path.expand("../../..", __DIR__)

    files =
      ~w(evidence documents/zip documents/docx documents/parser_stage documents/pdf documents)

    paths =
      for module <- [Ipse.Extension, Jason, JSONSchex, ExJSONPointer],
          path = module |> :code.which() |> to_string() |> Path.dirname(),
          do: ["-pa", path]

    script = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.{Documents, Evidence}
    locator = fn table, row, cell, paragraph ->
      %{"kind" => "table_cell", "part" => "word/document.xml", "table" => table,
        "row" => row, "cell" => cell, "paragraph" => paragraph}
    end
    build = fn id, rows ->
      segments = Enum.map(rows, fn {text, loc} -> %{"text" => text, "locator" => loc} end)
      document = %{"format" => "docx", "segments" => segments,
        "extraction_version" => Documents.version("docx"), "original_sha256" => Evidence.sha256(id),
        "original_bytes" => 100, "status" => "complete", "warnings" => []}
      {:ok, payload} = Documents.source_payload(document, 65536)
      receipt = Evidence.document_storage_receipt!(payload["document"])
      attrs = %{"source_id" => id, "partition" => "notes", "generation" => 1,
        "title" => id, "text" => payload["text"],
        "uri" => "provided:source.docx", "observed_at_ms" => 10,
        "event_at_ms" => nil, "expires_at_ms" => nil,
        "origin" => %{"kind" => "provided", "store_profile" => "notes",
          "partition_or_scope" => "notes", "receipt" => receipt,
          "historical" => false}}
      attrs = if receipt["version"] == 4, do: Map.put(attrs, "document", payload["document"]), else: attrs
      {:ok, source} = Evidence.source(attrs)
      source
    end
    source = build.("one", [{"Project amber", locator.(1, 1, 1, 1)},
      {"same cell extra paragraph", locator.(1, 1, 1, 2)},
      {"7391", locator.(1, 1, 2, 3)}, {"other row", locator.(1, 2, 1, 4)},
      {"8888", locator.(2, 1, 2, 5)},
      {"different part", locator.(1, 1, 2, 1) |> Map.put("part", "word/header1.xml") |> Map.put("region", "header")}])
    other = build.("two", [{"9999", locator.(1, 1, 2, 1)}])
    {:ok, result} = Evidence.rank_lexical_with_table_context([source, other], "Project amber", 10, 20)
    [hit, context] = result["evidence"]
    assert hit["method"] == "bm25"
    assert context["method"] == "table_context" and context["score"] == 0.0
    assert context["citation"]["quote"] == "7391"
    assert Evidence.valid_span?(source, context["citation"])
    assert context["citation"]["document"]["locator"] == locator.(1, 1, 2, 3)
    assert {:ok, [%{"label" => "open", "uncertainty" => "semantic_support_unassessed"}] = claims} =
      Evidence.classify(result["evidence"], [], "Project amber")
    assert [%{"evidence_indexes" => [0, 1]}] = Evidence.public_claims(result["evidence"], claims)
    assert result["coverage"]["table_context"] == %{"scope" => "single_block_cell_chunks",
      "returned" => 1, "truncated" => false, "multi_block_chunks_expanded" => false}
    {:ok, limited} = Evidence.rank_lexical_with_table_context([source, other], "Project amber", 1, 20)
    assert length(limited["evidence"]) == 1
    assert hd(limited["evidence"])["method"] == "bm25"
    assert limited["coverage"]["table_context"]["truncated"]
    {:ok, unmatched} = Evidence.rank_lexical_with_table_context([source, other], "unmatched", 10, 20)
    assert unmatched["evidence"] == []
    assert unmatched["coverage"]["table_context"]["returned"] == 0
    refute unmatched["coverage"]["table_context"]["truncated"]
    paragraph = build.("paragraph", [{"Project amber in a paragraph",
      %{"kind" => "paragraph", "part" => "word/document.xml", "paragraph" => 1}}])
    {:ok, plain_rank} = Evidence.rank_lexical([paragraph], "Project amber", 10, 20)
    {:ok, plain_context} = Evidence.rank_lexical_with_table_context([paragraph], "Project amber", 10, 20)
    assert Map.drop(plain_context, ["coverage"]) == Map.drop(plain_rank, ["coverage"])
    assert Map.delete(plain_context["coverage"], "table_context") == plain_rank["coverage"]
    assert plain_context["coverage"]["table_context"]["returned"] == 0
    refute plain_context["coverage"]["table_context"]["truncated"]
    signal = build.("three", [{"Project amber elsewhere", locator.(4, 1, 1, 1)}])
    {:ok, competing} = Evidence.rank_lexical_with_table_context([source, signal], "Project amber", 2, 20)
    assert length(competing["evidence"]) == 2
    assert Enum.all?(competing["evidence"], &(&1["method"] == "bm25" and &1["score"] > 0))
    previous = Map.put(source, "generation", 2)
    assert Evidence.valid_source?(previous)
    assert {:error, :invalid_sources} =
      Evidence.rank_lexical_with_table_context([source, previous], "Project amber", 10, 20)
    expired = Map.put(source, "expires_at_ms", 19)
    assert Evidence.valid_source?(expired)
    {:ok, stale} = Evidence.rank_lexical_with_table_context([expired, other], "Project amber", 10, 20)
    assert stale["evidence"] == []
    assert Enum.any?(stale["gaps"], &(&1["code"] == "stale_source"))
    # Reconstruct the same indexed row from the public lexical run. The indexed
    # path hydrates this source only after finding the positive lexical hit.
    {:ok, run} = Evidence.lexical_run(source)
    {:ok, terms} = Evidence.lexical_query_terms("Project amber")
    chunks = run["chunks"]
    n = length(chunks)
    total = Enum.sum(Enum.map(chunks, &Enum.at(&1, 3)))
    postings = Map.new(run["terms"], fn [term, rows] -> {term, rows} end)
    dfs = Map.new(terms, fn term -> {term, length(Map.get(postings, term, []))} end)
    frequencies = Map.new(terms, fn term ->
      pair = Enum.find(Map.get(postings, term, []), &(hd(&1) == 0))
      {term, if(pair, do: Enum.at(pair, 1), else: 0)}
    end)
    len = Enum.at(hd(chunks), 3)
    average = max(total / n, 1.0)
    score = Enum.reduce(terms, 0.0, fn term, sum ->
      tf = frequencies[term]
      sum + :math.log(1.0 + (n - dfs[term] + 0.5) / (dfs[term] + 0.5)) * tf * 2.2 /
        (tf + 1.2 * (0.25 + 0.75 * len / average))
    end)
    row = %{summary: [source["source_key"], source["source_id"], source["generation"], source["content_sha256"]],
      chunk: 0, length: len, terms: frequencies, score: score}
    stats = %{"chunks" => n, "tokens" => total, "dfs" => dfs}
    {:ok, indexed} = Evidence.rank_indexed([source], [row], "Project amber", stats, 10, 20)
    {:ok, selected} = Evidence.rank_lexical_with_table_context([source], "Project amber", 10, 20)
    assert indexed["evidence"] == selected["evidence"]
    {:ok, indexed_with_other} = Evidence.rank_indexed([source, other], [row], "Project amber", stats, 10, 20)
    assert indexed_with_other["evidence"] == indexed["evidence"]
    assert indexed["coverage"]["table_context"] == selected["coverage"]["table_context"]
    assert Evidence.valid_span?(source, List.last(indexed["evidence"])["citation"])
    {:ok, indexed_limited} = Evidence.rank_indexed([source], [row], "Project amber", stats, 1, 20)
    assert length(indexed_limited["evidence"]) == 1
    assert indexed_limited["coverage"]["table_context"]["truncated"]
    {:ok, empty} = Evidence.rank_indexed([], [], "unmatched", %{"chunks" => n, "tokens" => total,
      "dfs" => %{"unmatched" => 0}}, 10, 20)
    assert empty["evidence"] == [] and empty["coverage"]["table_context"]["returned"] == 0
    assert {:error, :invalid_index_selection} =
      Evidence.rank_indexed([source], [Map.put(row, :score, score + 1)], "Project amber", stats, 10, 20)
    zero = %{row | terms: %{"unmatched" => 0}, score: 0.0}
    assert {:error, :invalid_index_selection} =
      Evidence.rank_indexed([source], [zero], "unmatched", %{"chunks" => n, "tokens" => total,
        "dfs" => %{"unmatched" => 0}}, 10, 20)
    assert {:error, :invalid_index_selection} =
      Evidence.rank_indexed([expired], [row], "Project amber", stats, 10, 20)
    IO.puts("ROW_CONTEXT_PASS")
    '''

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        List.flatten(paths) ++
          Enum.flat_map(files, &["-r", Path.join(root, "extensions/knowledge/src/#{&1}.ex")]) ++
          ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
    assert output =~ "ROW_CONTEXT_PASS"
  end
end
