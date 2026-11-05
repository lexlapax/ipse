defmodule Ipse.KnowledgeDocumentParagraphPackingTest do
  use ExUnit.Case, async: false

  test "many short Unicode paragraphs keep exact locators within bounded chunks and manifests" do
    root = Path.expand("../../..", __DIR__)

    files =
      ~w(evidence documents/zip documents/docx documents/parser_stage documents/pdf documents)

    paths =
      :code.get_path() |> Enum.reject(&(&1 == ~c".")) |> Enum.flat_map(&["-pa", to_string(&1)])

    script = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.{Documents, Evidence}
    segments = for i <- 0..328 do
      locator = %{"kind" => "paragraph", "part" => "word/document.xml", "paragraph" => i * 2 + 1}
      locator = if i >= 17, do: Map.merge(locator, %{"kind" => "table_cell", "table" => 1, "row" => i + 1, "cell" => 2}), else: locator
      %{"text" => "Line #{i} café 好", "locator" => locator}
    end
    document = %{"format" => "docx", "segments" => segments,
      "extraction_version" => Documents.version("docx"), "original_sha256" => Evidence.sha256("original"),
      "original_bytes" => 16079, "status" => "complete", "warnings" => []}
    {:ok, payload} = Documents.source_payload(document, 65536)
    assert payload["text"] == Enum.map_join(segments, "\n", & &1["text"])
    assert length(payload["document"]["segments"]) <= 32
    assert byte_size(IO.iodata_to_binary(JSON.encode!(payload["document"]))) <= 16384
    assert Evidence.valid_document?(payload["document"], payload["text"])
    legacy=put_in(document,["extraction_version"],"ipse-documents-v14")
    {:ok,legacy_payload}=Documents.source_payload(legacy,65536)
    assert legacy_payload["document"]["extraction_version"]=="ipse-documents-v14"
    assert Evidence.valid_document?(legacy_payload["document"],legacy_payload["text"])
    legacy15=put_in(document,["extraction_version"],"ipse-documents-v15")
    {:ok,legacy15_payload}=Documents.source_payload(legacy15,65536)
    assert legacy15_payload["document"]["extraction_version"]=="ipse-documents-v15"
    assert Evidence.valid_document?(legacy15_payload["document"],legacy15_payload["text"])
    legacy16=put_in(document,["extraction_version"],"ipse-documents-v16")
    {:ok,legacy16_payload}=Documents.source_payload(legacy16,65536)
    assert Evidence.valid_document?(legacy16_payload["document"],legacy16_payload["text"])
    legacy17=put_in(document,["extraction_version"],"ipse-documents-v17")
    {:ok,legacy17_payload}=Documents.source_payload(legacy17,65536)
    assert legacy17_payload["document"]["extraction_version"]=="ipse-documents-v17"
    assert Evidence.valid_document?(legacy17_payload["document"],legacy17_payload["text"])
    receipt = Evidence.document_storage_receipt!(payload["document"])
    assert receipt["version"] == 4
    attrs = %{"source_id" => "packing:unicode", "partition" => "notes", "generation" => 1,
      "title" => "Paragraph packing", "text" => payload["text"], "document" => payload["document"],
      "uri" => "provided:source.docx", "observed_at_ms" => 10, "event_at_ms" => nil, "expires_at_ms" => nil,
      "origin" => %{"kind" => "provided", "store_profile" => "notes", "partition_or_scope" => "notes",
        "receipt" => receipt, "historical" => false}}
    {:ok, source} = Evidence.source(attrs)
    {:ok, chunks} = Evidence.chunks(source)
    assert length(chunks) <= 32 and length(chunks) < length(segments)
    assert Enum.all?(chunks, &(byte_size(&1["text"]) <= 2048))
    quote = Enum.at(segments, 128)["text"]
    {start, count} = :binary.match(payload["text"], quote)
    chunk = Enum.find(chunks, &(start >= &1["start_byte"] and start + count <= &1["end_byte"]))
    {:ok, citation} = Evidence.citation(source, chunk, start, start + count)
    assert citation["quote"] == quote
    assert citation["document"]["locator"]["paragraph"] == 257
    assert citation["document"]["locator"]["kind"] == "table_cell"
    assert citation["document"]["locator"]["row"] == 129
    assert citation["document"]["locator"]["cell"] == 2
    assert citation["document"]["start_byte"] == 0
    assert Evidence.valid_span?(source, citation)
    refute Evidence.valid_span?(source, put_in(citation, ["document", "locator", "paragraph"], 256))
    first = hd(chunks)
    {:ok, crossing} = Evidence.citation(source, first, 0, 80)
    assert crossing["document"]["version"] == 2
    assert length(crossing["document"]["spans"]) > 1
    assert Evidence.valid_span?(source, crossing)
    for {version, old_payload} <- [{"ipse-documents-v14",legacy_payload},{"ipse-documents-v15",legacy15_payload},{"ipse-documents-v16",legacy16_payload},{"ipse-documents-v17",legacy17_payload}] do
      legacy_attrs=attrs |> Map.put("document",old_payload["document"])
        |> put_in(["origin","receipt"],Evidence.document_storage_receipt!(old_payload["document"]))
      {:ok,legacy_source}=Evidence.source(legacy_attrs)
      {:ok,[legacy_first|_]}=Evidence.chunks(legacy_source)
      {:ok,legacy_crossing}=Evidence.citation(legacy_source,legacy_first,0,80)
      assert legacy_crossing["document"]["extraction_version"]==version
      assert Enum.all?(legacy_crossing["document"]["spans"], &(length(&1)==if(version in ~w(ipse-documents-v16 ipse-documents-v17),do: 9,else: 5)))
      assert Evidence.valid_span?(legacy_source,legacy_crossing)
    end
    refute Evidence.valid_document?(put_in(payload["document"],["extraction_version"],"ipse-documents-v19"),payload["text"])
    refute Evidence.valid_span?(source, put_in(crossing, ["document", "spans", Access.at(0), Access.at(0)], 2))
    {mixed_start, _} = :binary.match(payload["text"], Enum.at(segments, 16)["text"])
    {:ok, mixed} = Evidence.citation(source, first, mixed_start, mixed_start + 80)
    assert Enum.all?(mixed["document"]["spans"], &(length(&1) == 9))
    assert Enum.any?(mixed["document"]["spans"], &(Enum.slice(&1,5,4) == [nil,nil,nil,nil]))
    assert Enum.any?(mixed["document"]["spans"], &(Enum.at(&1,5) == 1 and Enum.at(&1,8) == nil))
    assert Evidence.valid_span?(source, mixed)
    refute Evidence.valid_span?(source, update_in(mixed, ["document", "spans"], fn rows -> Enum.map(rows, fn row -> if Enum.at(row,5) == 1, do: List.replace_at(row, 6, 999), else: row end) end))
    bad = put_in(payload, ["document", "segments", Access.at(0), "locator", "blocks", Access.at(0), Access.at(1)], 1)
    refute Evidence.valid_document?(bad["document"], bad["text"])
    shifted = update_in(payload["document"], ["segments", Access.at(0), "locator", "blocks"], fn [a,b|rest] ->
      [List.update_at(a,1,&(&1+1)),List.update_at(b,1,&(&1-1))|rest] end)
    refute Evidence.valid_document?(shifted, payload["text"])
    refute Evidence.valid_document?(put_in(payload["document"], ["extraction_version"], "ipse-documents-v13"), payload["text"])
    IO.puts("PARAGRAPH_PACKING_PASS")
    '''

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths ++
          Enum.flat_map(files, &["-r", Path.join(root, "extensions/knowledge/src/#{&1}.ex")]) ++
          ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
    assert output =~ "PARAGRAPH_PACKING_PASS"
  end
end
