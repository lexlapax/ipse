defmodule Ipse.KnowledgeDocumentsFidelityTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  defp pure(body) do
    files =
      ~w(evidence documents/zip documents/docx documents/parser_stage documents/pdf documents)

    arguments =
      Enum.flat_map(files, &["-r", Path.join(@root, "extensions/knowledge/src/#{&1}.ex")])

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", to_string(&1)])

    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.Documents, as: D
    word="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    xml=fn body -> "<w:document xmlns:w=\"#{word}\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\"><w:body>#{body}</w:body></w:document>" end
    raw_zip=fn entries ->
      {:ok,{_,bytes}}=:zip.create(~c"fidelity.docx",Enum.map(entries,fn {name,text}->{String.to_charlist(name),text} end),[:memory])
      bytes
    end
    package=fn entries ->
      names=Enum.map(entries,&elem(&1,0))
      if "word/document.xml" in names do
        relationships="http://schemas.openxmlformats.org/package/2006/relationships"
        prefix="http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        parts=Enum.filter(~w(styles footnotes endnotes comments numbering), &("word/#{&1}.xml" in names))
        entries=if "word/_rels/document.xml.rels" not in names and parts != [], do: entries++[{"word/_rels/document.xml.rels","<Relationships xmlns=\"#{relationships}\">"<>Enum.map_join(parts,fn kind -> "<Relationship Id=\"#{kind}\" Type=\"#{prefix}#{kind}\" Target=\"#{kind}.xml\"/>" end)<>"</Relationships>"}], else: entries
        entries=if "_rels/.rels" not in names, do: entries++[{"_rels/.rels","<Relationships xmlns=\"#{relationships}\"><Relationship Id=\"main\" Type=\"#{prefix}officeDocument\" Target=\"word/document.xml\"/></Relationships>"}], else: entries
        kinds=[{"word/document.xml","document.main"}|Enum.map(parts,&{"word/#{&1}.xml",&1})]
        if "[Content_Types].xml" not in names, do: entries++[{"[Content_Types].xml","<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"<>Enum.map_join(kinds,fn {path,kind} -> "<Override PartName=\"/#{path}\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.#{kind}+xml\"/>" end)<>"</Types>"}], else: entries
      else
        entries
      end
    end
    zip=fn entries -> raw_zip.(package.(entries)) end
    doc=fn body -> zip.([{"word/document.xml",xml.(body)}]) end
    run=fn text -> "<w:r><w:t>#{text}</w:t></w:r>" end
    codes=fn result -> Enum.map(result["warnings"],& &1["code"]) end
    '''

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths ++ arguments ++ ["-e", bootstrap <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
  end

  test "a freshly built corpus artifact contains the current DOCX extraction recipe" do
    root = Path.join(System.tmp_dir!(), "ipse-docx-artifact-" <> Ipse.Usage.id())
    artifact = Path.join(root, "corpus")
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          Path.join(@root, "extensions/knowledge/build.exs"),
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          artifact,
          "--package",
          "corpus",
          "--preset",
          "state-lexical"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    {probe, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "-pa",
          Path.join(artifact, "ebin"),
          Path.join(@root, "test/support/docx_artifact_probe.exs")
        ],
        stderr_to_stdout: true
      )

    assert status == 0, probe
    assert probe =~ "ARTIFACT_DOCX_PROBE_PASSED " <> Path.join(artifact, "ebin")
  end

  test "direct hidden runs are excluded without hiding following visible runs" do
    pure(~S'''
    for value <- ["", " w:val=\"true\"", " w:val=\"1\"", " w:val=\"on\""] do
      hidden="<w:r><w:rPr><w:vanish#{value}/></w:rPr><w:t>hidden</w:t><w:tab/><w:t>also hidden</w:t></w:r>"
      {:ok,result}=D.extract(doc.("<w:p>"<>run.("before ")<>hidden<>run.("after")<>"</w:p>"),"a.docx")
      assert [%{"text"=>"before after"}]=result["segments"]
      assert result["status"]=="complete" and result["warnings"]==[]
      assert result["revision_policy"]=="insertions_included_deletions_excluded"
      assert result["visibility_policy"]=="bounded_style_and_direct_hidden_excluded"
      assert result["extraction_version"]=="ipse-documents-v18"
    end
    for value <- ["false","0","off"] do
      {:ok,result}=D.extract(doc.("<w:p><w:r><w:rPr><w:vanish w:val=\"#{value}\"/></w:rPr><w:t>visible</w:t></w:r></w:p>"),"a.docx")
      assert [%{"text"=>"visible"}]=result["segments"]
    end
    ''')
  end

  test "conflicting strict and transitional visibility attributes are refused" do
    pure(~S'''
    strict="http://purl.oclc.org/ooxml/wordprocessingml/main"
    for attrs <- ["w:val=\"false\" s:val=\"true\"", "s:val=\"true\" w:val=\"false\"", "w:val=\"true\" s:val=\"true\""] do
      main="<w:document xmlns:w=\"#{word}\" xmlns:s=\"#{strict}\"><w:body><w:p><w:r><w:rPr><w:vanish #{attrs}/></w:rPr><w:t>ambiguous hidden text</w:t></w:r></w:p></w:body></w:document>"
      assert {:error,:invalid_word_namespace}=D.extract(zip.([{"word/document.xml",main}]),"ambiguous.docx")
      styles="<w:styles xmlns:w=\"#{word}\" xmlns:s=\"#{strict}\"><w:docDefaults><w:rPrDefault><w:rPr><w:vanish #{attrs}/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>"
      assert {:error,:unsupported_docx_style_visibility}=D.extract(zip.([{"word/styles.xml",styles},{"word/document.xml",xml.("<w:p>"<>run.("ambiguous hidden text")<>"</w:p>")}]),"ambiguous.docx")
    end
    strict_main="<s:document xmlns:s=\"#{strict}\"><s:body><s:p><s:r><s:rPr><s:vanish s:val=\"true\"/></s:rPr><s:t>hidden</s:t></s:r><s:r><s:t>visible</s:t></s:r></s:p></s:body></s:document>"
    assert {:ok,%{"segments"=>[%{"text"=>"visible"}]}}=D.extract(zip.([{"word/document.xml",strict_main}]),"strict.docx")
    ''')
  end

  test "text and control elements outside a Word run cannot claim complete extraction" do
    pure(~S'''
    for content <- ["<w:t>misplaced text</w:t>", "<w:tab/>", "<w:br/>", "<w:cr/>", "<w:noBreakHyphen/>", "<w:softHyphen/>"] do
      assert {:error,:unsupported_docx_text_structure}=D.extract(doc.("<w:p>"<>content<>"</w:p>"),"a.docx")
    end
    ''')
  end

  test "run text nested in paragraph properties cannot become document content" do
    pure(~S'''
    for property <- ["pPr", "tblPr", "trPr", "tcPr", "sectPr", "tblGrid"] do
      body="<w:p><w:#{property}><w:ins>"<>run.("metadata text")<>"</w:ins></w:#{property}>"<>run.("visible")<>"</w:p>"
      assert {:error,:unsupported_docx_text_structure}=D.extract(doc.(body),"a.docx")
    end
    {:ok,result}=D.extract(doc.("<w:p><w:ins>"<>run.("inserted")<>"</w:ins>"<>run.(" visible")<>"</w:p>"),"a.docx")
    assert [%{"text"=>"inserted visible"}]=result["segments"]
    assert result["status"]=="complete"
    ''')
  end

  test "paragraph tab stops do not become document text" do
    pure(~S'''
    body="<w:p><w:pPr><w:tabs><w:tab w:val=\"left\" w:pos=\"720\"/></w:tabs></w:pPr>"<>run.("actual")<>"</w:p>"
    {:ok,result}=D.extract(doc.(body),"a.docx")
    assert [%{"text"=>"actual"}]=result["segments"]
    assert result["status"]=="partial" and "unsupported_word_content" in codes.(result)
    {:ok,inline}=D.extract(doc.("<w:p><w:r><w:t>before</w:t><w:tab/><w:t>after</w:t></w:r></w:p>"),"a.docx")
    assert [%{"text"=>"before\tafter"}]=inline["segments"]
    assert inline["status"]=="complete"
    ''')
  end

  test "late, duplicated, unknown and nested run properties refuse ambiguous visibility" do
    pure(~S'''
    for body <- [
      "<w:r><w:t>already emitted</w:t><w:rPr><w:vanish/></w:rPr></w:r>",
      "<w:r><w:rPr><w:vanish/><w:vanish w:val=\"false\"/></w:rPr><w:t>ambiguous</w:t></w:r>",
      "<w:r><w:rPr><w:vanish w:val=\"unknown\"/></w:rPr><w:t>ambiguous</w:t></w:r>"
    ] do
      assert {:error,:unsupported_docx_run_properties}=D.extract(doc.("<w:p>"<>body<>"</w:p>"),"a.docx")
    end
    assert {:error,:unsupported_nested_run}=D.extract(doc.("<w:p><w:r>"<>run.("nested")<>"</w:r></w:p>"),"a.docx")
    ''')
  end

  test "unsupported symbols, equations, fields and foreign text cannot claim complete coverage" do
    pure(~S'''
    for {body,code} <- [
      {"<w:r><w:sym w:font=\"Wingdings\" w:char=\"F0FC\"/></w:r>","unsupported_content"},
      {"<m:oMath><m:r><m:t>x+y=7</m:t></m:r></m:oMath>","unsupported_namespace_content"},
      {"<w:fldSimple w:instr=\"DATE\">"<>run.("cached date")<>"</w:fldSimple>","fields_not_recalculated"},
      {"<w:r><w:instrText>DATE</w:instrText></w:r>","fields_not_recalculated"},
      {"<w:unexpected>unrepresented text</w:unexpected>","unsupported_word_content"}
    ] do
      {:ok,result}=D.extract(doc.("<w:p>"<>run.("visible")<>body<>"</w:p>"),"a.docx")
      assert result["status"]=="partial"
      assert code in codes.(result)
      assert hd(result["segments"])["text"]=~"visible"
    end
    many=String.duplicate("<w:r><w:sym w:char=\"F0FC\"/></w:r>",1000)
    {:ok,result}=D.extract(doc.("<w:p>"<>run.("visible")<>many<>"</w:p>"),"a.docx")
    assert [%{"code"=>"unsupported_content","element"=>"sym"}]=result["warnings"]
    {:ok,result}=D.extract(doc.(run.("outside paragraph")),"a.docx")
    assert result["status"]=="partial" and result["segments"]==[]
    assert "unsupported_text_location" in codes.(result)
    ''')
  end

  test "missing referenced footer is refused even with a present custom header and styles" do
    pure(~S'''
    main=xml.("<w:p>"<>run.("body")<>"</w:p><w:sectPr><w:headerReference w:type=\"default\" r:id=\"custom\"/><w:footerReference w:type=\"default\" r:id=\"missing\"/></w:sectPr>")
    relationships="<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"custom\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"custom-header.xml\"/><Relationship Id=\"styles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
    header="<w:hdr xmlns:w=\"#{word}\"><w:p>"<>run.("omitted header")<>"</w:p></w:hdr>"
    styles="<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"character\" w:styleId=\"hidden\"><w:rPr><w:vanish/></w:rPr></w:style></w:styles>"
    assert {:error,:unsupported_docx_part_relationship}=D.extract(zip.([{"word/document.xml",main},{"word/custom-header.xml",header},{"word/_rels/document.xml.rels",relationships},{"word/styles.xml",styles}]),"a.docx")
    ''')
  end

  test "old tracked formatting does not hide current runs and omitted visibility stays partial" do
    pure(~S'''
    body="<w:p><w:r><w:rPr><w:rPrChange><w:rPr><w:vanish/></w:rPr></w:rPrChange></w:rPr><w:t>current visible</w:t></w:r></w:p>"
    {:ok,result}=D.extract(doc.(body),"a.docx")
    assert [%{"text"=>"current visible"}]=result["segments"]
    assert result["status"]=="partial"
    assert "unsupported_visibility_property" in codes.(result)
    assert {:error,:unsupported_docx_style_visibility}=D.extract(doc.("<w:p><w:r><w:rPr><w:webHidden/></w:rPr><w:t>view dependent</w:t></w:r></w:p>"),"a.docx")
    ''')
  end

  test "supported explicit hyphens retain text and compound Word containers refuse honestly" do
    pure(~S'''
    {:ok,result}=D.extract(doc.("<w:p><w:r><w:t>a</w:t><w:noBreakHyphen/><w:t>b</w:t><w:softHyphen/><w:t>c</w:t></w:r></w:p>"),"a.docx")
    assert [%{"text"=>"a\u2011b\u00adc"}]=result["segments"]
    compound=<<0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1,0::size(504*8)>>
    assert {:error,:compound_word_container_unsupported}=D.extract(compound,"encrypted.docx")
    assert {:error,:legacy_word_unsupported}=D.extract(compound,"legacy.doc")
    ''')
  end

  @tag :docx_numbering
  test "single-level decimal lists retain derived labels separately from cited source text" do
    pure(~S'''
    alias IpseKnowledge.Evidence, as: E
    numbering="<w:numbering xmlns:w=\"#{word}\"><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"3\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/><w:suff w:val=\"space\"/></w:lvl></w:abstractNum><w:num w:numId=\"7\"><w:abstractNumId w:val=\"1\"/></w:num><w:num w:numId=\"8\"><w:abstractNumId w:val=\"1\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"10\"/></w:lvlOverride></w:num></w:numbering>"
    list=fn id,text -> "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"#{id}\"/></w:numPr></w:pPr>"<>run.(text)<>"</w:p>" end
    body=list.(7,"First α")<>"<w:p>"<>run.("interlude")<>"</w:p>"<>list.(7,"Second β")<>list.(8,"Restart γ")<>list.(7,"Third δ")
    bytes=zip.([{"word/document.xml",xml.(body)},{"word/numbering.xml",numbering}])
    {:ok,result}=D.extract(bytes,"numbered.docx")
    assert result["extraction_version"]=="ipse-documents-v18"
    assert result["status"]=="partial"
    assert Enum.map(result["segments"],& &1["text"])==["First α","interlude","Second β","Restart γ","Third δ"]
    [first,plain,second,restart,third]=result["segments"]
    assert first["locator"]["numbering"]["label"]=="3."
    assert first["locator"]["numbering"]["suffix"]=="space"
    assert plain["locator"]["numbering"]==nil
    assert second["locator"]["numbering"]["ordinal"]==4
    assert restart["locator"]["numbering"]["ordinal"]==10
    assert third["locator"]["numbering"]["ordinal"]==5
    {:ok,payload}=D.source_payload(result,65536)
    assert payload["text"]=="First α\ninterlude\nSecond β\nRestart γ\nThird δ"
    assert E.valid_document?(payload["document"],payload["text"])
    for old <- ["ipse-documents-v14","ipse-documents-v15"] do
      refute E.valid_document?(Map.put(payload["document"],"extraction_version",old),payload["text"])
    end
    receipt=E.document_storage_receipt!(payload["document"])
    attrs=%{"source_id"=>"numbered:source","partition"=>"notes","generation"=>1,
      "title"=>"Numbered list","text"=>payload["text"],"uri"=>"provided:numbered.docx",
      "observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil,
      "origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"notes",
        "receipt"=>receipt,"historical"=>false}}
    attrs=if receipt["version"]==4, do: Map.put(attrs,"document",payload["document"]), else: attrs
    {:ok,source}=E.source(attrs)
    {:ok,chunks}=E.chunks(source)
    {start,count}=:binary.match(payload["text"],"Second β")
    chunk=Enum.find(chunks,&(start>=&1["start_byte"] and start+count<=&1["end_byte"]))
    {:ok,citation}=E.citation(source,chunk,start,start+count)
    assert citation["quote"]=="Second β"
    assert citation["document"]["locator"]["numbering"]["label"]=="4."
    assert E.valid_span?(source,citation)
    refute E.valid_span?(source,put_in(citation,["document","locator","numbering","label"],"5."))

    many=Enum.map_join(1..40,&list.(7,"Line #{&1} café"))
    {:ok,long}=D.extract(zip.([{"word/document.xml",xml.(many)},{"word/numbering.xml",numbering}]),"long-numbered.docx")
    {:ok,packed}=D.source_payload(long,65536)
    assert length(packed["document"]["segments"])<40
    assert E.valid_document?(packed["document"],packed["text"])
    packed_receipt=E.document_storage_receipt!(packed["document"])
    packed_attrs=attrs |> Map.put("text",packed["text"]) |> put_in(["origin","receipt"],packed_receipt)
    packed_attrs=if packed_receipt["version"]==4, do: Map.put(packed_attrs,"document",packed["document"]), else: Map.delete(packed_attrs,"document")
    {:ok,packed_source}=E.source(packed_attrs)
    {:ok,packed_chunks}=E.chunks(packed_source)
    {start,count}=:binary.match(packed["text"],"Line 17 café")
    chunk=Enum.find(packed_chunks,&(start>=&1["start_byte"] and start+count<=&1["end_byte"]))
    {:ok,citation}=E.citation(packed_source,chunk,start,start+count)
    assert citation["quote"]=="Line 17 café"
    assert citation["document"]["locator"]["numbering"]["ordinal"]==19
    assert E.valid_span?(packed_source,citation)
    first=hd(packed_chunks)
    crossing_text="Line 1 café\nLine 2 café"
    {:ok,crossing}=E.citation(packed_source,first,0,byte_size(crossing_text))
    assert crossing["quote"]==crossing_text and crossing["document"]["version"]==2
    assert List.last(crossing["document"]["span_fields"])=="numbering"
    assert Enum.map(crossing["document"]["spans"],&(List.last(&1)["ordinal"]))==[3,4]
    assert E.valid_span?(packed_source,crossing)
    changed=put_in(crossing,["document","spans",Access.at(0),Access.at(8),"label"],"4.")
    refute E.valid_span?(packed_source,changed)

    for legacy_recipe <- ~w(ipse-documents-v16 ipse-documents-v17) do
    legacy=put_in(packed,["document","extraction_version"],legacy_recipe)
    assert E.valid_document?(legacy["document"],legacy["text"])
    legacy_receipt=E.document_storage_receipt!(legacy["document"])
    legacy_attrs=packed_attrs |> put_in(["origin","receipt"],legacy_receipt)
    legacy_attrs=if legacy_receipt["version"]==4, do: Map.put(legacy_attrs,"document",legacy["document"]), else: Map.delete(legacy_attrs,"document")
    {:ok,legacy_source}=E.source(legacy_attrs)
    {:ok,[legacy_chunk|_]}=E.chunks(legacy_source)
    {:ok,legacy_crossing}=E.citation(legacy_source,legacy_chunk,0,byte_size(crossing_text))
    assert legacy_crossing["document"]["extraction_version"]==legacy_recipe
    assert List.last(legacy_crossing["document"]["span_fields"])=="numbering"
    assert E.valid_span?(legacy_source,legacy_crossing)
    refute E.valid_span?(legacy_source,put_in(legacy_crossing,["document","spans",Access.at(0),Access.at(8),"label"],"9."))
    end

    table=fn content -> "<w:tbl><w:tr><w:tc>"<>content<>"</w:tc></w:tr></w:tbl>" end
    mixed_body="<w:p>"<>run.("Plain")<>"</w:p>"<>list.(7,"Numbered")<>
      table.("<w:p>"<>run.("Table plain")<>"</w:p>"<>list.(7,"Table numbered"))<>
      Enum.map_join(1..36,&("<w:p>"<>run.("Filler #{&1}")<>"</w:p>"))
    {:ok,mixed_document}=D.extract(zip.([{"word/document.xml",xml.(mixed_body)},{"word/numbering.xml",numbering}]),"mixed.docx")
    {:ok,mixed_payload}=D.source_payload(mixed_document,65536)
    mixed_receipt=E.document_storage_receipt!(mixed_payload["document"])
    mixed_attrs=attrs |> Map.put("text",mixed_payload["text"]) |> put_in(["origin","receipt"],mixed_receipt)
    mixed_attrs=if mixed_receipt["version"]==4, do: Map.put(mixed_attrs,"document",mixed_payload["document"]), else: Map.delete(mixed_attrs,"document")
    {:ok,mixed_source}=E.source(mixed_attrs)
    {:ok,[mixed_chunk|_]}=E.chunks(mixed_source)
    mixed_quote="Plain\nNumbered\nTable plain\nTable numbered"
    {:ok,mixed_citation}=E.citation(mixed_source,mixed_chunk,0,byte_size(mixed_quote))
    assert mixed_citation["quote"]==mixed_quote
    fields=mixed_citation["document"]["span_fields"]
    rows=mixed_citation["document"]["spans"]
    assert Enum.all?(rows,&(length(&1)==length(fields)))
    [plain,numbered,cell,numbered_cell]=Enum.map(rows,&Map.new(Enum.zip(fields,&1)))
    assert {plain["table"],plain["numbering"]}=={nil,nil}
    assert numbered["table"]==nil and numbered["numbering"]["label"]=="3."
    assert {cell["table"],cell["row"],cell["cell"],cell["numbering"]}=={1,1,1,nil}
    assert {numbered_cell["table"],numbered_cell["row"],numbered_cell["cell"]}=={1,1,1}
    assert numbered_cell["numbering"]["label"]=="4."
    assert E.valid_span?(mixed_source,mixed_citation)
    refute E.valid_span?(mixed_source,update_in(mixed_citation,["document","spans",Access.at(1)],&List.delete_at(&1,5)))
    ''')
  end

  @tag :docx_numbering
  test "numbering refuses mixed WordprocessingML dialects" do
    pure(~S'''
    strict="http://purl.oclc.org/ooxml/wordprocessingml/main"
    number="<w:numbering xmlns:w=\"#{word}\"><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/></w:lvl></w:abstractNum><w:num w:numId=\"7\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>"
    props="<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"7\"/></w:numPr>"
    body=fn p -> "<w:p><w:pPr>"<>p<>"</w:pPr>"<>run.("item")<>"</w:p>" end
    with_s=fn doc -> String.replace(doc,"xmlns:w=\"#{word}\"","xmlns:w=\"#{word}\" xmlns:s=\"#{strict}\"") end
    for p <- [String.replace(props,"w:","s:"),String.replace(props,"w:val=\"7\"","s:val=\"7\"")] do
      assert {:error,:invalid_word_namespace}=D.extract(zip.([{"word/document.xml",with_s.(xml.(body.(p)))},{"word/numbering.xml",number}]),"mixed-body.docx")
    end
    for n <- [String.replace(number,"<w:numFmt","<s:numFmt"),String.replace(number,"w:val=\"decimal\"","s:val=\"decimal\"")] do
      assert {:error,:unsupported_docx_numbering}=D.extract(zip.([{"word/document.xml",xml.(body.(props))},{"word/numbering.xml",with_s.(n)}]),"mixed-numbering.docx")
    end
    styles="<w:styles xmlns:w=\"#{word}\" xmlns:s=\"#{strict}\"><w:docDefaults><w:rPrDefault><w:rPr><s:vanish/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>"
    assert {:error,:unsupported_docx_style_visibility}=D.extract(zip.([{"word/document.xml",xml.(body.(props))},{"word/numbering.xml",number},{"word/styles.xml",styles}]),"mixed-styles.docx")
    strict_body=String.replace(xml.(body.(props)),word,strict)
    strict_number=String.replace(number,word,strict)
    assert {:error,:unsupported_docx_numbering}=D.extract(zip.([{"word/document.xml",xml.(body.(props))},{"word/numbering.xml",strict_number}]),"mixed-parts.docx")
    assert {:error,:unsupported_docx_numbering}=D.extract(zip.([{"word/document.xml",strict_body},{"word/numbering.xml",number}]),"mixed-parts.docx")
    strict_styles="<w:styles xmlns:w=\"#{strict}\"/>"
    assert {:error,:unsupported_docx_numbering}=D.extract(zip.([{"word/document.xml",xml.(body.(props))},{"word/numbering.xml",number},{"word/styles.xml",strict_styles}]),"mixed-styles-part.docx")
    strict_styles=String.replace(strict_styles,strict,word)
    assert {:error,:unsupported_docx_numbering}=D.extract(zip.([{"word/document.xml",strict_body},{"word/numbering.xml",strict_number},{"word/styles.xml",strict_styles}]),"mixed-styles-part.docx")
    assert {:ok,%{"segments"=>[%{"locator"=>%{"numbering"=>%{"label"=>"1."}}}]}}=
      D.extract(zip.([{"word/document.xml",strict_body},{"word/numbering.xml",strict_number}]),"strict-list.docx")
    ''')
  end

  @tag :docx_numbering
  test "ambiguous, unsupported or revision-affected numbering refuses instead of guessing" do
    pure(~S'''
    valid="<w:numbering xmlns:w=\"#{word}\"><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/></w:lvl></w:abstractNum><w:num w:numId=\"7\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>"
    num="<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"7\"/></w:numPr>"
    docx=fn number,body -> zip.([{"word/document.xml",xml.(body)},{"word/numbering.xml",number}]) end
    item=fn props,text -> "<w:p><w:pPr>#{props}</w:pPr>"<>run.(text)<>"</w:p>" end
    for number <- [String.replace(valid,"singleLevel","multilevel"),String.replace(valid,"decimal","upperRoman"),
      String.replace(valid,"%1.","%2."),String.replace(valid,"w:ilvl=\"0\"","w:ilvl=\"1\""),
      String.replace(valid,"</w:num>","<w:lvlOverride w:ilvl=\"0\"><w:lvl w:ilvl=\"0\"/></w:lvlOverride></w:num>"),
      String.replace(valid,"<w:num w:numId=\"7\">","<w:num w:numId=\"7\"><w:abstractNumId w:val=\"1\"/></w:num><w:num w:numId=\"7\">")] do
      assert {:error,:unsupported_docx_numbering}=D.extract(docx.(number,item.(num,"content")),"bad.docx")
    end
    for props <- [String.replace(num,"w:val=\"7\"","w:val=\"8\""),String.replace(num,"w:val=\"0\"","w:val=\"1\""),
      String.replace(num,"</w:numPr>","<w:numId w:val=\"7\"/></w:numPr>"),
      String.replace(num,"<w:numId w:val=\"7\"/>","<w:numId w:val=\"7\"><w:unexpected/></w:numId>"),
      String.replace(num,"<w:numId w:val=\"7\"/>","<w:numId w:val=\"7\">unexpected</w:numId>"),
      "<w:rPr><w:vanish/></w:rPr>"<>num] do
      assert {:error,:unsupported_docx_numbering}=D.extract(docx.(valid,item.(props,"content")),"bad.docx")
    end
    for body <- [item.(num,""),"<w:p><w:pPr>#{num}</w:pPr><w:ins>"<>run.("changed")<>"</w:ins></w:p>",
      "<w:p><w:pPr>#{num}</w:pPr><w:r><w:rPr><w:vanish/></w:rPr><w:t>hidden</w:t></w:r></w:p>",
      item.("<w:rPr><w:del/></w:rPr>"<>num,"changed")] do
      assert {:error,:unsupported_docx_numbering}=D.extract(docx.(valid,body),"bad.docx")
    end
    removed="<w:del>"<>item.(num,"removed")<>"</w:del>"
    {:ok,visible}=D.extract(docx.(valid,item.(num,"first")<>removed<>item.(num,"second")),"deleted.docx")
    assert Enum.map(visible["segments"],& &1["text"])==["first","second"]
    assert Enum.map(visible["segments"],& &1["locator"]["numbering"]["ordinal"])==[1,2]
    ''')
  end

  test "document defaults and paragraph or character inheritance suppress hidden text" do
    pure(~S'''
    extract=fn style_body,body ->
      styles="<w:styles xmlns:w=\"#{word}\">#{style_body}</w:styles>"
      D.extract(zip.([{"word/styles.xml",styles},{"word/document.xml",xml.(body)}]),"styles.docx")
    end
    style=fn type,id,body -> "<w:style w:type=\"#{type}\" w:styleId=\"#{id}\">#{body}</w:style>" end
    hidden="<w:rPr><w:vanish/></w:rPr>"
    visible="<w:r><w:rPr><w:vanish w:val=\"false\"/></w:rPr><w:t>visible</w:t></w:r>"
    defaults="<w:docDefaults><w:rPrDefault>#{hidden}</w:rPrDefault></w:docDefaults>"
    {:ok,result}=extract.(defaults,"<w:p>"<>run.("hidden")<>visible<>"</w:p>")
    assert [%{"text"=>"visible"}]=result["segments"]
    assert result["status"]=="complete"
    styles=style.("paragraph","base",hidden)<>style.("paragraph","child","<w:basedOn w:val=\"base\"/>")
    {:ok,result}=extract.(styles,"<w:p><w:pPr><w:pStyle w:val=\"child\"/></w:pPr>"<>run.("hidden")<>visible<>"</w:p>")
    assert [%{"text"=>"visible","style"=>"child"}]=result["segments"]
    styles=style.("character","base",hidden)<>style.("character","child","<w:basedOn w:val=\"base\"/>")
    body="<w:p>"<>run.("before ")<>"<w:r><w:rPr><w:rStyle w:val=\"child\"/></w:rPr><w:t>hidden</w:t></w:r>"<>visible<>"</w:p>"
    {:ok,result}=extract.(styles,body)
    assert [%{"text"=>"before visible"}]=result["segments"]
    styles="<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"normal\">#{hidden}</w:style>"
    {:ok,result}=extract.(styles,"<w:p>"<>run.("hidden")<>visible<>"</w:p>")
    assert [%{"text"=>"visible"}]=result["segments"]
    # Metadata and font/spacing alone do not create missing-content warnings.
    styles=style.("paragraph","normal","<w:name w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"100\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Arial\"/></w:rPr>")
    {:ok,result}=extract.(styles,"<w:p><w:pPr><w:pStyle w:val=\"normal\"/></w:pPr>"<>run.("ordinary")<>"</w:p>")
    assert result["status"]=="complete" and result["warnings"]==[]
    ''')
  end

  test "undefined selected paragraph and character styles preserve Unicode and exact citations" do
    pure(~S'''
    alias IpseKnowledge.Evidence, as: E
    body="<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"MissingChar\"/></w:rPr><w:t>Résumé 雪 evidence.</w:t></w:r></w:p>"
    bytes=doc.(body)
    {:ok,result}=D.extract(bytes,"undefined.docx")
    assert result["extraction_version"]=="ipse-documents-v18"
    assert result["status"]=="complete" and result["warnings"]==[]
    assert [%{"text"=>"Résumé 雪 evidence.","style"=>"Heading1"}]=result["segments"]
    {:ok,payload}=D.source_payload(result)
    {:ok,source}=E.source(%{"source_id"=>"undefined:styles","partition"=>"notes","generation"=>1,
      "title"=>"Undefined references","text"=>payload["text"],"uri"=>"provided:undefined.docx",
      "observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil,
      "origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"notes",
        "receipt"=>E.document_storage_receipt!(payload["document"]),"historical"=>false}})
    {:ok,[chunk]}=E.chunks(source)
    {start,length}=:binary.match(payload["text"],"雪 evidence.")
    {:ok,citation}=E.citation(source,chunk,start,start+length)
    assert citation["quote"]=="雪 evidence."
    assert citation["document"]["original_sha256"]==E.sha256(bytes)
    assert citation["document"]["start_byte"]==byte_size("Résumé ")
    assert citation["document"]["extraction_version"]=="ipse-documents-v18"
    assert E.valid_span?(source,citation)
    refute E.valid_span?(source,put_in(citation,["document","start_byte"],start+1))
    ''')
  end

  test "undefined style references cannot reveal hidden defaults, paragraph styles or direct properties" do
    pure(~S'''
    style=fn type,id,body -> "<w:style w:type=\"#{type}\" w:styleId=\"#{id}\">#{body}</w:style>" end
    hidden="<w:rPr><w:vanish/></w:rPr>"
    unknown_run="<w:r><w:rPr><w:rStyle w:val=\"MissingChar\"/></w:rPr><w:t>secret</w:t></w:r>"
    visible="<w:r><w:rPr><w:rStyle w:val=\"MissingChar\"/><w:vanish w:val=\"false\"/></w:rPr><w:t>visible café 雪</w:t></w:r>"
    extract=fn styles,pstyle,runs ->
      D.extract(zip.([{"word/styles.xml","<w:styles xmlns:w=\"#{word}\">#{styles}</w:styles>"},{"word/document.xml",xml.("<w:p><w:pPr><w:pStyle w:val=\"#{pstyle}\"/></w:pPr>"<>runs<>"</w:p>")}]),"hidden-undefined.docx")
    end
    defaults="<w:docDefaults><w:rPrDefault>#{hidden}</w:rPrDefault></w:docDefaults>"
    for {styles,pstyle} <- [{defaults,"MissingParagraph"},{style.("paragraph","hidden",hidden),"hidden"}] do
      {:ok,result}=extract.(styles,pstyle,unknown_run<>visible)
      assert [%{"text"=>"visible café 雪"}]=result["segments"]
      refute result["segments"] |> Enum.any?(&String.contains?(&1["text"],"secret"))
    end
    runs="<w:r><w:rPr><w:rStyle w:val=\"hidden\"/></w:rPr><w:t>secret</w:t></w:r>"<>run.("visible café 雪")
    {:ok,result}=extract.(style.("character","hidden",hidden),"MissingParagraph",runs)
    assert [%{"text"=>"visible café 雪"}]=result["segments"]
    direct="<w:r><w:rPr><w:rStyle w:val=\"MissingChar\"/><w:vanish/></w:rPr><w:t>secret</w:t></w:r>"<>run.("visible café 雪")
    {:ok,result}=extract.("","MissingParagraph",direct)
    assert [%{"text"=>"visible café 雪"}]=result["segments"]
    for value <- ["true","false"] do
      default="<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"normal\"><w:rPr><w:vanish w:val=\"#{value}\"/></w:rPr></w:style>"
      assert {:error,:unsupported_docx_style_visibility}=extract.(default,"MissingParagraph",visible)
    end
    harmless="<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"normal\"><w:name w:val=\"Normal\"/></w:style>"
    assert {:ok,%{"segments"=>[%{"text"=>"visible café 雪"}]}}=extract.(harmless,"MissingParagraph",visible)
    ''')
  end

  test "ignoring undefined selections never repairs malformed graphs or wrong style types" do
    pure(~S'''
    style=fn type,id,body -> "<w:style w:type=\"#{type}\" w:styleId=\"#{id}\">#{body}</w:style>" end
    extract=fn styles,pstyle,rstyle ->
      D.extract(zip.([{"word/styles.xml","<w:styles xmlns:w=\"#{word}\">#{styles}</w:styles>"},{"word/document.xml",xml.("<w:p><w:pPr><w:pStyle w:val=\"#{pstyle}\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"#{rstyle}\"/></w:rPr><w:t>must not leak</w:t></w:r></w:p>")}]),"invalid-undefined.docx")
    end
    for styles <- [style.("paragraph","unused","<w:basedOn w:val=\"missing\"/>"),
      style.("paragraph","unused","<w:basedOn w:val=\"unused\"/>"),
      style.("paragraph","unused","<w:basedOn w:val=\"b\"/>")<>style.("character","b",""),
      style.("paragraph","unused","")<>style.("paragraph","unused","")] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(styles,"MissingParagraph","MissingChar")
    end
    assert {:error,:unsupported_docx_style_visibility}=extract.(style.("character","known",""),"known","MissingChar")
    assert {:error,:unsupported_docx_style_visibility}=extract.(style.("paragraph","known",""),"MissingParagraph","known")
    linked=style.("paragraph","known","<w:link w:val=\"linked\"/>")<>style.("character","linked","")
    assert {:error,:unsupported_docx_style_visibility}=extract.(linked,"known","MissingChar")
    table="<w:tbl><w:tblPr><w:tblStyle w:val=\"MissingTable\"/></w:tblPr><w:tr><w:tc><w:p>"<>run.("table")<>"</w:p></w:tc></w:tr></w:tbl>"
    assert {:error,:unsupported_docx_style_visibility}=D.extract(doc.(table),"unknown-table.docx")
    ''')
  end

  @tag :docx_table_style
  test "nonhidden table styles retain visible Unicode cells and independent table locators" do
    pure(~S'''
    styles="<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"table\" w:styleId=\"base\"/><w:style w:type=\"table\" w:styleId=\"grid\"><w:basedOn w:val=\"base\"/><w:tblPr><w:shd w:fill=\"eeeeee\"/></w:tblPr></w:style></w:styles>"
    table=fn text -> "<w:tbl><w:tblPr><w:tblStyle w:val=\"grid\"/></w:tblPr><w:tr><w:tc><w:p>"<>run.(text)<>"<w:r><w:rPr><w:vanish/></w:rPr><w:t>hidden cell text</w:t></w:r></w:p></w:tc></w:tr></w:tbl>" end
    body="<w:p>"<>run.("before")<>"</w:p>"<>table.("café α")<>"<w:p>"<>run.("between")<>"</w:p>"<>table.("雪")
    {:ok,result}=D.extract(zip.([{"word/styles.xml",styles},{"word/document.xml",xml.(body)}]),"styled-tables.docx")
    assert Enum.map(result["segments"],& &1["text"])==["before","café α","between","雪"]
    [_,first,_,second]=result["segments"]
    assert Map.take(first["locator"],~w(kind table row cell))==%{"kind"=>"table_cell","table"=>1,"row"=>1,"cell"=>1}
    assert Map.take(second["locator"],~w(kind table row cell))==%{"kind"=>"table_cell","table"=>2,"row"=>1,"cell"=>1}
    assert result["status"]=="complete" and result["warnings"]==[]
    assert result["extraction_version"]=="ipse-documents-v18"
    ''')
  end

  @tag :docx_table_style
  test "table styles cannot bypass hidden inheritance or ambiguous reference placement" do
    pure(~S'''
    style=fn type,id,body -> "<w:style w:type=\"#{type}\" w:styleId=\"#{id}\">#{body}</w:style>" end
    row="<w:tr><w:tc><w:p>"<>run.("never published on refusal")<>"</w:p></w:tc></w:tr>"
    reference="<w:tblStyle w:val=\"grid\"/>"
    properties="<w:tblPr>#{reference}</w:tblPr>"
    extract=fn styles,body -> D.extract(zip.([{"word/styles.xml","<w:styles xmlns:w=\"#{word}\">#{styles}</w:styles>"},{"word/document.xml",xml.(body)}]),"styles.docx") end
    for styles <- [
      style.("table","grid","<w:rPr><w:vanish/></w:rPr>"),
      style.("table","grid","<w:tblStylePr w:type=\"firstRow\"><w:rPr><w:vanish/></w:rPr></w:tblStylePr>"),
      style.("table","grid","<w:basedOn w:val=\"hidden\"/>")<>style.("table","hidden","<w:rPr><w:vanish/></w:rPr>"),
      style.("paragraph","grid",""),
      style.("table","different","")
    ] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(styles,"<w:tbl>"<>properties<>row<>"</w:tbl>")
    end
    for body <- [
      "<w:tbl>"<>row<>properties<>"</w:tbl>",
      "<w:tbl><w:tblPr>"<>reference<>reference<>"</w:tblPr>"<>row<>"</w:tbl>",
      "<w:p><w:pPr>"<>reference<>"</w:pPr>"<>run.("wrong owner")<>"</w:p>"
    ] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(style.("table","grid",""),body)
    end
    ''')
  end

  test "style graph ambiguity, unsupported visibility and late references refuse every segment" do
    pure(~S'''
    extract=fn styles,body -> D.extract(zip.([{"word/styles.xml","<w:styles xmlns:w=\"#{word}\">#{styles}</w:styles>"},{"word/document.xml",xml.(body)}]),"styles.docx") end
    style=fn type,id,body -> "<w:style w:type=\"#{type}\" w:styleId=\"#{id}\">#{body}</w:style>" end
    hidden="<w:rPr><w:vanish/></w:rPr>"
    p="<w:p><w:pPr><w:pStyle w:val=\"a\"/></w:pPr>"<>run.("never eligible")<>"</w:p>"
    for styles <- [
      style.("paragraph","a","<w:basedOn w:val=\"missing\"/>"),
      style.("paragraph","a","<w:basedOn w:val=\"a\"/>"),
      style.("paragraph","a","<w:basedOn w:val=\"b\"/>")<>style.("paragraph","b","<w:basedOn w:val=\"a\"/>"),
      style.("paragraph","a","")<>style.("paragraph","a",hidden),
      style.("paragraph","a","<w:basedOn w:val=\"b\"/>")<>style.("character","b",hidden),
      style.("paragraph","a","<w:basedOn w:val=\"b\"/>"<>hidden)<>style.("paragraph","b",hidden),
      "<w:docDefaults><w:rPrDefault>#{hidden}</w:rPrDefault></w:docDefaults>"<>style.("paragraph","a",hidden),
      style.("paragraph","a","<w:link w:val=\"b\"/>")<>style.("character","b",hidden),
      style.("paragraph","a","<w:rPr><w:vanish/><w:vanish/></w:rPr>"),
      style.("paragraph","a","<w:rPr><w:webHidden/></w:rPr>"),
      "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"a\"/><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"b\"/>"
    ] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(styles,p)
    end
    assert {:ok,%{"segments"=>[%{"text"=>"never eligible","style"=>"a"}]}}=D.extract(doc.(p),"missing.docx")
    for body <- [
      "<w:p>"<>run.("already emitted")<>"<w:pPr><w:pStyle w:val=\"a\"/></w:pPr></w:p>",
      "<w:p><w:pPr><w:pStyle w:val=\"a\"/><w:pStyle w:val=\"a\"/></w:pPr>"<>run.("duplicate")<>"</w:p>",
      "<w:p><w:r><w:t>already emitted</w:t><w:rPr><w:rStyle w:val=\"b\"/></w:rPr></w:r></w:p>"
    ] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(style.("paragraph","a","")<>style.("character","b",""),body)
    end
    assert {:error,:unsupported_docx_numbering}=extract.(style.("paragraph","a",""),"<w:p><w:pPr><w:numPr/></w:pPr>"<>run.("numbered")<>"</w:p>")
    for styles <- [String.duplicate(style.("paragraph","a",""),513),
      "<w:docDefaults/><w:docDefaults/>",
      "<w:docDefaults><w:rPrDefault><w:rPr><w:vanish w:val=\"bad\"/></w:rPr></w:rPrDefault></w:docDefaults>"] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(styles,"<w:p>"<>run.("no")<>"</w:p>")
    end
    ''')
  end

  test "style count, inheritance depth and shared expansion budgets have exact boundaries" do
    pure(~S'''
    extract=fn styles,options ->
      D.extract(zip.([{"word/styles.xml","<w:styles xmlns:w=\"#{word}\">#{styles}</w:styles>"},{"word/document.xml",xml.("<w:p><w:pPr><w:pStyle w:val=\"s0\"/></w:pPr>"<>run.("bounded")<>"</w:p>")}]),"styles.docx",options)
    end
    many=fn count -> Enum.map_join(0..(count-1),fn i -> "<w:style w:type=\"paragraph\" w:styleId=\"s#{i}\"/>" end) end
    assert {:ok,%{"segments"=>[%{"text"=>"bounded"}]}}=extract.(many.(512),[])
    assert {:error,:unsupported_docx_style_visibility}=extract.(many.(513),[])
    chain=fn count -> Enum.map_join(0..(count-1),fn i ->
      parent=if i+1<count,do: "<w:basedOn w:val=\"s#{i+1}\"/>",else: ""
      "<w:style w:type=\"paragraph\" w:styleId=\"s#{i}\">#{parent}</w:style>"
    end) end
    assert {:ok,_}=extract.(chain.(64),[])
    assert {:error,:unsupported_docx_style_visibility}=extract.(chain.(65),[])
    style="<w:styles xmlns:w=\"#{word}\">#{many.(1)}</w:styles>"
    main=xml.("<w:p><w:pPr><w:pStyle w:val=\"s0\"/></w:pPr>"<>run.("bounded")<>"</w:p>")
    bytes=zip.([{"word/styles.xml",style},{"word/document.xml",main}])
    expanded=package.([{"word/styles.xml",style},{"word/document.xml",main}])|>Enum.reduce(0,fn {_,body},sum -> sum+byte_size(body) end)
    assert {:ok,_}=D.extract(bytes,"styles.docx",max_expanded_bytes: expanded)
    assert {:error,:expansion_limit}=D.extract(bytes,"styles.docx",max_expanded_bytes: expanded-1)
    ''')
  end

  @tag :docx_matching_effects
  test "matching primary and effects style graphs preserve visible text and exclude hidden runs" do
    pure(~S'''
    styles="<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"character\" w:styleId=\"hidden\"><w:rPr><w:vanish/></w:rPr></w:style></w:styles>"
    effects=String.replace(styles,"<w:rPr>","<w:name w:val=\"Different presentation name\"/><w:rPr>")
    main=xml.("<w:p>"<>run.("visible λ")<>"<w:r><w:rPr><w:rStyle w:val=\"hidden\"/></w:rPr><w:t>hidden literal</w:t></w:r></w:p>")
    rels="<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"e\" Type=\"http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects\" Target=\"stylesWithEffects.xml\"/></Relationships>"
    entries=package.([{"word/document.xml",main},{"word/styles.xml",styles},{"word/stylesWithEffects.xml",effects},{"word/_rels/document.xml.rels",rels}])
    entries=Enum.map(entries,fn
      {"[Content_Types].xml",types} -> {"[Content_Types].xml",String.replace(types,"</Types>","<Override PartName=\"/word/stylesWithEffects.xml\" ContentType=\"application/vnd.ms-word.stylesWithEffects+xml\"/></Types>")}
      entry -> entry
    end)
    {:ok,result}=D.extract(raw_zip.(entries),"effects.docx")
    assert [%{"text"=>"visible λ","locator"=>%{"kind"=>"paragraph","part"=>"word/document.xml","paragraph"=>1}}]=result["segments"]
    assert result["status"]=="complete" and result["warnings"]==[]
    ''')
  end

  test "alternate, missing and external style relationships refuse before publishing body text" do
    pure(~S'''
    styles="<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"paragraph\" w:styleId=\"a\"><w:rPr><w:vanish/></w:rPr></w:style></w:styles>"
    main=xml.("<w:p><w:pPr><w:pStyle w:val=\"a\"/></w:pPr>"<>run.("hidden body")<>"</w:p>")
    relation=fn target,mode -> "<Relationship Id=\"s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"#{target}\"#{mode}/>" end
    rels=fn body -> "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">#{body}</Relationships>" end
    for target <- ["custom-styles.xml","../other/styles.xml","https://invalid.example/styles.xml"] do
      bytes=zip.([{"word/document.xml",main},{"word/styles.xml",styles},{"word/custom-styles.xml",styles},{"word/_rels/document.xml.rels",rels.(relation.(target,""))}])
      assert {:error,:unsupported_docx_style_relationship}=D.extract(bytes,"styles.docx")
    end
    for {body,parts} <- [
      {relation.("styles.xml"," TargetMode=\"External\""),[{"word/styles.xml",styles}]},
      {relation.("styles.xml",""),[]},
      {relation.("styles.xml","")<>relation.("styles.xml",""),[{"word/styles.xml",styles}]}
    ] do
      assert {:error,:unsupported_docx_style_relationship}=D.extract(zip.([{"word/document.xml",main},{"word/_rels/document.xml.rels",rels.(body)}]++parts),"styles.docx")
    end
    for target <- ["styles.xml","/word/styles.xml"] do
      {:ok,result}=D.extract(zip.([{"word/document.xml",main},{"word/styles.xml",styles},{"word/_rels/document.xml.rels",rels.(relation.(target,""))}]),"styles.docx")
      assert result["segments"]==[]
    end
    effects="<Relationship Id=\"e\" Type=\"http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects\" Target=\"stylesWithEffects.xml\"/>"
    assert {:error,:unsupported_docx_style_relationship}=D.extract(zip.([{"word/document.xml",main},{"word/styles.xml",styles},{"word/_rels/document.xml.rels",rels.(effects)}]),"styles.docx")
    ''')
  end

  @tag :docx_matching_effects
  test "effects styles require exact authority and matching bounded visibility graphs" do
    pure(~S'''
    styles="<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"a\"><w:rPr><w:vanish w:val=\"false\"/></w:rPr></w:style></w:styles>"
    main=xml.("<w:p>"<>run.("do not disclose on ambiguity")<>"</w:p>")
    primary="<Relationship Id=\"s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
    effect="<Relationship Id=\"e\" Type=\"http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects\" Target=\"stylesWithEffects.xml\"/>"
    rels=fn links -> "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">#{links}</Relationships>" end
    make=fn alternate,links,extras ->
      entries=package.([{"word/document.xml",main},{"word/styles.xml",styles},{"word/stylesWithEffects.xml",alternate},{"word/_rels/document.xml.rels",rels.(links)}])
      Enum.map(entries,fn
        {"[Content_Types].xml",types} -> {"[Content_Types].xml",String.replace(types,"</Types>","<Override PartName=\"/word/stylesWithEffects.xml\" ContentType=\"application/vnd.ms-word.stylesWithEffects+xml\"/></Types>")}
        entry -> entry
      end) |> extras.() |> raw_zip.()
    end
    unchanged=fn entries -> entries end
    for alternate <- [
      String.replace(styles,"w:val=\"false\"","w:val=\"true\""),
      String.replace(styles," w:default=\"1\"",""),
      String.replace(styles,"w:type=\"paragraph\"","w:type=\"character\""),
      String.replace(styles,"w:styleId=\"a\"","w:styleId=\"b\""),
      String.replace(styles,"</w:styles>","<w:style w:type=\"paragraph\" w:styleId=\"b\"/></w:styles>"),
      String.replace(styles,"</w:style>","<w:link w:val=\"a\"/></w:style>")
    ] do
      assert {:error,:unsupported_docx_style_visibility}=D.extract(make.(alternate,primary<>effect,unchanged),"mismatch.docx")
    end
    for invalid <- [
      String.replace(effect,"stylesWithEffects.xml","alternate.xml"),
      String.replace(effect," Target="," TargetMode=\"External\" Target="),
      String.replace(effect,"schemas.microsoft.com/office/2007","invalid.example"),
      effect<>String.replace(effect,"Id=\"e\"","Id=\"duplicate\"")
    ] do
      assert {:error,:unsupported_docx_style_relationship}=D.extract(make.(styles,primary<>invalid,unchanged),"relationship.docx")
    end
    assert {:error,:unsupported_docx_part_relationship}=D.extract(make.(styles,primary,unchanged),"unlinked.docx")
    assert {:error,:unsupported_docx_style_relationship}=D.extract(make.(styles,primary<>effect,fn entries -> Enum.reject(entries,&(elem(&1,0)=="word/stylesWithEffects.xml")) end),"missing.docx")
    assert {:error,:unsupported_docx_style_visibility}=D.extract(make.(styles,effect,fn entries -> Enum.reject(entries,&(elem(&1,0)=="word/styles.xml")) end),"effects-only.docx")
    assert {:error,:unsupported_docx_content_types}=D.extract(make.(styles,primary<>effect,fn entries -> Enum.map(entries,fn {name,bytes}->{name,String.replace(bytes,"application/vnd.ms-word.stylesWithEffects+xml","application/xml")} end) end),"content-type.docx")
    assert {:error,:xml_entities_unsupported}=D.extract(make.("<!DOCTYPE styles [<!ENTITY x 'no'>]>"<>styles,primary<>effect,unchanged),"entity.docx")
    assert {:error,:unsupported_docx_style_visibility}=D.extract(make.(String.replace(styles,"<w:rPr>","<w:rPr><x:effect xmlns:x=\"urn:unsupported\"/>"),primary<>effect,unchanged),"unknown-effects.docx")
    good=make.(styles,primary<>effect,unchanged)
    {:ok,result}=D.extract(good,"effects.docx")
    assert [%{"text"=>"do not disclose on ambiguity"}]=result["segments"]
    {:ok,parts}=:zip.extract(good,[:memory])
    expanded=Enum.sum(Enum.map(parts,fn {_,bytes}->byte_size(bytes) end))
    assert {:ok,_}=D.extract(good,"effects.docx",max_expanded_bytes: expanded)
    assert {:error,:expansion_limit}=D.extract(good,"effects.docx",max_expanded_bytes: expanded-1)
    ''')
  end

  test "visibility-bearing default character styles refuse instead of guessing implicit application" do
    pure(~S'''
    extract=fn styles -> D.extract(zip.([{"word/styles.xml","<w:styles xmlns:w=\"#{word}\">#{styles}</w:styles>"},{"word/document.xml",xml.("<w:p>"<>run.("potentially hidden")<>"</w:p>")}]),"default-character.docx") end
    default=fn body -> "<w:style w:type=\"character\" w:default=\"1\" w:styleId=\"DefaultParagraphFont\">#{body}</w:style>" end
    for value <- ["true","false"] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(default.("<w:rPr><w:vanish w:val=\"#{value}\"/></w:rPr>"))
    end
    base="<w:style w:type=\"character\" w:styleId=\"base\"><w:rPr><w:vanish/></w:rPr></w:style>"
    assert {:error,:unsupported_docx_style_visibility}=extract.(base<>default.("<w:basedOn w:val=\"base\"/>"))
    assert {:ok,%{"segments"=>[%{"text"=>"potentially hidden"}]}}=extract.(default.("<w:name w:val=\"Default Paragraph Font\"/>"))
    ''')
  end

  test "package root authority and content types exclude orphan or non-Word main stories" do
    pure(~S'''
    entries=package.([{"word/document.xml",xml.("<w:p>"<>run.("orphan must not publish")<>"</w:p>")}])
    replace=fn name,body -> List.keystore(entries,name,0,{name,body}) end
    relationship=fn target,mode -> "<Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"#{target}\"#{mode}/>" end
    rels=fn body -> "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">#{body}</Relationships>" end
    for root <- [rels.(""),rels.(relationship.("main.xml","")),rels.(relationship.("word/actual.xml","")),
      rels.(relationship.("word/document.xml"," TargetMode=\"External\"")),
      rels.(relationship.("word/document.xml","")<>String.replace(relationship.("word/document.xml",""),"Id=\"main\"","Id=\"second\""))] do
      bytes=raw_zip.(replace.("_rels/.rels",root)++[{"main.xml",xml.("<w:p>"<>run.("actual")<>"</w:p>")},{"word/actual.xml",xml.("<w:p>"<>run.("actual")<>"</w:p>")}])
      assert {:error,:unsupported_docx_package_authority}=D.extract(bytes,"orphan.docx")
    end
    for missing <- ["_rels/.rels","[Content_Types].xml"] do
      assert {:error,:unsupported_docx_package_authority}=D.extract(raw_zip.(List.keydelete(entries,missing,0)),"missing.docx")
    end
    content=fn body -> "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">#{body}</Types>" end
    override=fn type -> "<Override PartName=\"/word/document.xml\" ContentType=\"#{type}\"/>" end
    for types <- [content.(""),content.(override.("application/xml")),content.(override.("application/vnd.ms-word.document.macroEnabled.main+xml")),
      content.(override.("application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml")<>override.("application/xml"))] do
      assert {:error,:unsupported_docx_content_types}=D.extract(raw_zip.(replace.("[Content_Types].xml",types)),"types.docx")
    end
    for target <- ["word/document.xml","/word/document.xml"] do
      assert {:ok,_}=D.extract(raw_zip.(replace.("_rels/.rels",rels.(relationship.(target,"")))),"canonical.docx")
    end
    ''')
  end

  @tag :annotation_completeness
  test "fully linked footnote and endnote paragraphs resolve their annotation coverage" do
    pure(~S'''
    for {part,item,ref} <- [{"footnotes","footnote","footnoteReference"},{"endnotes","endnote","endnoteReference"}] do
      body="<w:p>"<>run.("café")<>"<w:r><w:#{ref} w:id=\"7\"/></w:r>"<>run.(" end")<>"</w:p>"
      annotation="<w:#{part} xmlns:w=\"#{word}\"><w:#{item} w:id=\"+07\"><w:p>"<>run.("first α")<>"</w:p><w:p>"<>run.("second β")<>"</w:p></w:#{item}></w:#{part}>"
      {:ok,result}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/#{part}.xml",annotation}]),"resolved.docx")
      assert result["status"]=="complete" and result["warnings"]==[]
      assert Enum.map(result["segments"],& &1["text"])==["café end","first α","second β"]
      for segment <- tl(result["segments"]) do
        assert segment["locator"]["reference_site"]["byte_offset"]==5
        assert segment["locator"]["annotation_id"]=="+07"
      end
      alias IpseKnowledge.Evidence, as: E
      {:ok,payload}=D.source_payload(result)
      assert E.valid_document?(payload["document"],payload["text"])
      receipt=E.document_storage_receipt!(payload["document"])
      assert receipt["version"]==3
      attrs=%{"source_id"=>"annotation:"<>part,"partition"=>"notes","generation"=>1,
        "title"=>"Linked notes","text"=>payload["text"],
        "uri"=>"provided:resolved.docx","observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil,
        "origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"notes",
          "receipt"=>receipt,"historical"=>false}}
      assert {:error,:invalid_source}=E.source(Map.put(attrs,"document",payload["document"]))
      {:ok,source}=E.source(attrs)
      {:ok,chunks}=E.chunks(source)
      quote="first α"
      {start,count}=:binary.match(payload["text"],quote)
      chunk=Enum.find(chunks,&(start >= &1["start_byte"] and start+count <= &1["end_byte"]))
      {:ok,citation}=E.citation(source,chunk,start,start+count)
      assert citation["document"]["extraction_version"]=="ipse-documents-v18"
      assert citation["document"]["locator"]["reference_site"]["byte_offset"]==5
      assert E.valid_span?(source,citation)
      refute E.valid_span?(source,put_in(citation,["document","locator","reference_site","byte_offset"],4))
    end
    ''')
  end

  @tag :annotation_completeness
  test "fully linked point and same-paragraph range comments resolve annotation coverage" do
    pure(~S'''
    note="<w:comments xmlns:w=\"#{word}\"><w:comment w:id=\"7\"><w:p>"<>run.("review")<>"</w:p></w:comment></w:comments>"
    reference="<w:r><w:commentReference w:id=\"07\"/></w:r>"
    for range <- [false,true] do
      start=if range, do: "<w:commentRangeStart w:id=\"+7\"/>", else: ""
      finish=if range, do: "<w:commentRangeEnd w:id=\"7\"/>", else: ""
      body="<w:p>"<>run.("α")<>start<>run.("café")<>finish<>reference<>"</w:p>"
      {:ok,result}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/comments.xml",note}]),"comments.docx")
      assert result["status"]=="complete" and result["warnings"]==[]
      locator=List.last(result["segments"])["locator"]
      assert locator["reference_site"]["byte_offset"]==7
      if range, do: assert(locator["reference_range"]["start_byte"]==2 and locator["reference_range"]["end_byte"]==7)
    end
    ''')
  end

  @tag :annotation_completeness
  test "annotation completeness requires every body reference and every annotation identity" do
    pure(~S'''
    reference=fn id -> "<w:r><w:footnoteReference w:id=\"#{id}\"/></w:r>" end
    note=fn id,text -> "<w:footnote w:id=\"#{id}\"><w:p>"<>run.(text)<>"</w:p></w:footnote>" end
    for {refs,notes} <- [
      {reference.("7"),note.("7","linked")<>note.("8","orphan")},
      {reference.("7")<>reference.("8"),note.("7","linked")},
      {reference.("7")<>reference.("+07"),note.("7","ambiguous")},
      {reference.("7"),note.("7","")},
      {"<w:r><w:rPr><w:vanish/></w:rPr><w:footnoteReference w:id=\"7\"/></w:r>",note.("7","hidden anchor")}
    ] do
      body="<w:p>"<>run.("body")<>refs<>"</w:p>"
      annotation="<w:footnotes xmlns:w=\"#{word}\">"<>notes<>"</w:footnotes>"
      {:ok,result}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/footnotes.xml",annotation}]),"incomplete.docx")
      assert result["status"]=="partial"
      assert "annotation_anchors_unresolved" in codes.(result)
    end
    ''')
  end

  @tag :annotation_completeness
  test "resolved annotation anchors do not hide unsupported annotation rendering" do
    pure(~S'''
    body="<w:p>"<>run.("body")<>"<w:r><w:footnoteReference w:id=\"7\"/></w:r></w:p>"
    notes="<w:footnotes xmlns:w=\"#{word}\"><w:footnote w:id=\"7\"><w:p><w:r><w:footnoteRef/></w:r>"<>run.("note")<>"</w:p></w:footnote></w:footnotes>"
    {:ok,result}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/footnotes.xml",notes}]),"numbered-note.docx")
    assert result["status"]=="partial"
    assert "unsupported_word_content" in codes.(result)
    assert Enum.at(result["segments"],1)["locator"]["reference_site"]["byte_offset"]==4
    refute "annotation_anchors_unresolved" in codes.(result)
    ''')
  end

  test "visible body annotation references carry a point in extracted text" do
    pure(~S'''
    make_note=fn id,text -> "<w:footnote w:id=\"#{id}\"><w:p>"<>run.(text)<>"</w:p></w:footnote>" end
    main="<w:p>"<>run.("café")<>"<w:r><w:footnoteReference w:id=\"7\"/></w:r>"<>run.(" end")<>"</w:p>"
    notes="<w:footnotes xmlns:w=\"#{word}\">"<>make_note.("07","anchored")<>make_note.("8","orphan")<>"</w:footnotes>"
    {:ok,result}=D.extract(zip.([{"word/document.xml",xml.(main)},{"word/footnotes.xml",notes}]),"linked.docx")
    [body,anchored,orphan]=result["segments"]
    assert body["text"]=="café end"
    assert anchored["locator"]["reference_site"]==%{"part"=>"word/document.xml","kind"=>"paragraph","paragraph"=>1,"byte_offset"=>5}
    refute Map.has_key?(orphan["locator"],"reference_site")
    assert result["status"]=="partial"
    hidden="<w:r><w:rPr><w:vanish/></w:rPr><w:footnoteReference w:id=\"7\"/></w:r>"
    {:ok,hidden_result}=D.extract(zip.([{"word/document.xml",xml.("<w:p>"<>run.("visible")<>hidden<>"</w:p>")},{"word/footnotes.xml",notes}]),"hidden.docx")
    refute Map.has_key?(Enum.at(hidden_result["segments"],1)["locator"],"reference_site")
    marker_only="<w:p><w:r><w:footnoteReference w:id=\"7\"/></w:r></w:p>"
    {:ok,empty_body}=D.extract(zip.([{"word/document.xml",xml.(marker_only)},{"word/footnotes.xml",notes}]),"empty-body.docx")
    refute Map.has_key?(hd(empty_body["segments"])["locator"],"reference_site")
    duplicate="<w:p>"<>run.("a")<>"<w:r><w:footnoteReference w:id=\"7\"/></w:r>"<>run.("b")<>"<w:r><w:footnoteReference w:id=\"07\"/></w:r></w:p>"
    {:ok,duplicate_result}=D.extract(zip.([{"word/document.xml",xml.(duplicate)},{"word/footnotes.xml",notes}]),"duplicate.docx")
    refute Map.has_key?(Enum.at(duplicate_result["segments"],1)["locator"],"reference_site")
    for {part,item,ref} <- [{"endnotes","endnote","endnoteReference"},{"comments","comment","commentReference"}] do
      body="<w:p>"<>run.("λ")<>"<w:r><w:#{ref} w:id=\"5\"/></w:r></w:p>"
      annotations="<w:#{part} xmlns:w=\"#{word}\"><w:#{item} w:id=\"5\"><w:p>"<>run.("annotation")<>"</w:p></w:#{item}></w:#{part}>"
      {:ok,linked}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/#{part}.xml",annotations}]),"linked.docx")
      assert Enum.at(linked["segments"],1)["locator"]["reference_site"]["byte_offset"]==2
    end
    {:ok,missing}=D.extract(doc.("<w:p>"<>run.("text")<>"<w:r><w:footnoteReference w:id=\"99\"/></w:r></w:p>"),"missing.docx")
    assert missing["status"]=="partial"
    assert %{"code"=>"annotation_anchors_unresolved","part"=>"word/document.xml"} in missing["warnings"]
    cell="<w:tbl><w:tr><w:tc><w:p>"<>run.("α")<>"<w:r><w:footnoteReference w:id=\"7\"/></w:r></w:p></w:tc></w:tr></w:tbl>"
    {:ok,table_result}=D.extract(zip.([{"word/document.xml",xml.(cell)},{"word/footnotes.xml",notes}]),"table.docx")
    assert Enum.at(table_result["segments"],1)["locator"]["reference_site"]==%{"part"=>"word/document.xml","kind"=>"table_cell","paragraph"=>1,"table"=>1,"row"=>1,"cell"=>1,"byte_offset"=>2}
    ''')
  end

  test "a unique same-paragraph comment range maps to visible UTF-8 byte offsets" do
    pure(~S'''
    comment="<w:comments xmlns:w=\"#{word}\"><w:comment w:id=\"7\"><w:p>"<>run.("review")<>"</w:p></w:comment></w:comments>"
    start="<w:commentRangeStart w:id=\"7\"/>"
    finish="<w:commentRangeEnd w:id=\"07\"/>"
    ref="<w:r><w:commentReference w:id=\"+7\"/></w:r>"
    extract=fn body ->
      {:ok,result}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/comments.xml",comment}]),"range.docx")
      result
    end
    result=extract.("<w:p>"<>run.("α")<>start<>run.("café")<>finish<>ref<>run.("!")<>"</w:p>")
    assert result["status"]=="complete" and result["warnings"]==[]
    [body,note]=result["segments"]
    assert body["text"]=="αcafé!"
    assert note["locator"]["reference_range"]==%{"part"=>"word/document.xml","kind"=>"paragraph","paragraph"=>1,"start_byte"=>2,"end_byte"=>7}
    for body <- [
      "<w:p>"<>start<>run.("a")<>start<>run.("b")<>finish<>ref<>"</w:p>",
      "<w:p>"<>finish<>run.("a")<>start<>ref<>"</w:p>",
      "<w:p>"<>start<>run.("a")<>"</w:p><w:p>"<>run.("b")<>finish<>ref<>"</w:p>",
      "<w:p>"<>start<>finish<>ref<>"</w:p>",
      "<w:p>"<>ref<>start<>run.("a")<>finish<>"</w:p>",
      "<w:p><w:del>"<>start<>"</w:del>"<>start<>run.("a")<>finish<>ref<>"</w:p>",
      "<w:p>"<>start<>run.("a")<>finish<>ref<>ref<>"</w:p>"
    ] do
      result=extract.(body)
      assert result["status"]=="partial"
      note=result["segments"] |> List.last()
      refute Map.has_key?(note["locator"],"reference_range")
    end
    table="<w:tbl><w:tr><w:tc><w:p>"<>run.("α")<>start<>run.("β")<>finish<>ref<>"</w:p></w:tc></w:tr></w:tbl>"
    table_note=extract.(table)["segments"] |> List.last()
    assert table_note["locator"]["reference_range"]==%{"part"=>"word/document.xml","kind"=>"table_cell","paragraph"=>1,"table"=>1,"row"=>1,"cell"=>1,"start_byte"=>2,"end_byte"=>4}
    hidden="<w:r><w:rPr><w:vanish/></w:rPr><w:t>hidden</w:t></w:r>"
    visible=extract.("<w:p>"<>start<>run.("a")<>hidden<>"<w:del>"<>run.("deleted")<>"</w:del>"<>run.("b")<>finish<>ref<>"</w:p>")
    assert hd(visible["segments"])["text"]=="ab"
    assert List.last(visible["segments"])["locator"]["reference_range"]["end_byte"]==2
    {:ok,dangling}=D.extract(doc.("<w:p>"<>start<>run.("text")<>finish<>"</w:p>"),"dangling.docx")
    assert dangling["status"]=="partial"
    assert %{"code"=>"annotation_anchors_unresolved","part"=>"word/document.xml"} in dangling["warnings"]
    ''')
  end

  @tag :annotation_layout
  test "reserved footnote and endnote layout types omit content while retaining paragraph ordinals" do
    pure(~S'''
    for {part,item,reference} <- [{"footnotes","footnote","footnoteReference"},{"endnotes","endnote","endnoteReference"}] do
      entry=fn id,type,content -> "<w:#{item} w:id=\"#{id}\" w:type=\"#{type}\"><w:p>#{content}</w:p></w:#{item}>" end
      notes="<w:#{part} xmlns:w=\"#{word}\">"<>
        entry.("-1","separator",run.("not merely a dash")<>"<w:r><w:separator/></w:r>")<>
        entry.("0","continuationSeparator",run.("ordinary-looking text")<>"<w:r><w:continuationSeparator/></w:r>")<>
        entry.("3","continuationNotice",run.("layout continuation notice"))<>
        entry.("7","normal",run.("ordinary-looking text"))<>"</w:#{part}>"
      body="<w:p>"<>run.("bodyé")<>"<w:r><w:#{reference} w:id=\"7\"/></w:r></w:p>"
      {:ok,result}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/#{part}.xml",notes}]),"layout.docx")
      assert result["extraction_version"]=="ipse-documents-v18"
      assert result["status"]=="complete" and result["warnings"]==[]
      assert [%{"text"=>"bodyé"},%{"text"=>"ordinary-looking text","locator"=>locator}]=result["segments"]
      assert locator["annotation_id"]=="7" and locator["paragraph"]==4
      assert locator["reference_site"]["byte_offset"]==byte_size("bodyé")
      for {maximum,chunking} <- [{8192,1},{65536,2}] do
        {:ok,payload}=D.source_payload(result,maximum,chunking)
        assert payload["text"]=="bodyé\nordinary-looking text"
        assert List.last(payload["document"]["segments"])["locator"]==locator
      end
    end
    ''')
  end

  @tag :annotation_layout
  test "ordinary negative and unreferenced annotations remain evidence even when their text resembles layout" do
    pure(~S'''
    for {part,item} <- [{"footnotes","footnote"},{"endnotes","endnote"}] do
      entry=fn attrs,text -> "<w:#{item}#{attrs}><w:p>"<>run.(text)<>"</w:p></w:#{item}>" end
      notes="<w:#{part} xmlns:w=\"#{word}\">"<>
        entry.(" w:id=\"99\" w:type=\"separator\"","layout content")<>
        entry.(" w:id=\"-1\" w:type=\"normal\"","—")<>
        entry.(" w:id=\"0\"","unreferenced ordinary")<>
        entry.(" w:id=\"8\" xmlns:x=\"urn:foreign\" x:type=\"separator\"","foreign type remains ordinary")<>"</w:#{part}>"
      {:ok,result}=D.extract(zip.([{"word/document.xml",xml.("<w:p>"<>run.("body")<>"</w:p>")},{"word/#{part}.xml",notes}]),"ordinary.docx")
      assert Enum.map(tl(result["segments"]),& &1["text"])==["—","unreferenced ordinary","foreign type remains ordinary"]
      assert Enum.map(tl(result["segments"]),& &1["locator"]["annotation_id"])==["-1","0","8"]
      assert Enum.map(tl(result["segments"]),& &1["locator"]["paragraph"])==[2,3,4]
      assert result["status"]=="partial"
      assert %{"code"=>"annotation_anchors_unresolved","part"=>"word/#{part}.xml"} in result["warnings"]
    end
    ''')
  end

  @tag :annotation_layout
  test "unknown annotation types and duplicate layout identities refuse instead of hiding evidence" do
    pure(~S'''
    for {part,item} <- [{"footnotes","footnote"},{"endnotes","endnote"}] do
      entry=fn id,type -> "<w:#{item} w:id=\"#{id}\" w:type=\"#{type}\"><w:p>"<>run.("text")<>"</w:p></w:#{item}>" end
      for content <- [entry.("7","unknown"),entry.("7","Separator"),entry.("7",""),entry.("7","separator")<>entry.("+07","normal"),entry.("-1","separator")<>entry.("-01","continuationSeparator")] do
        assert {:error,:unsupported_docx_annotation}=D.extract(zip.([{"word/document.xml",xml.("<w:p>"<>run.("body")<>"</w:p>")},{"word/#{part}.xml","<w:#{part} xmlns:w=\"#{word}\">"<>content<>"</w:#{part}>"}]),"invalid.docx")
      end
    end
    comments="<w:comments xmlns:w=\"#{word}\"><w:comment w:id=\"7\" w:type=\"separator\"><w:p>"<>run.("must not become comment layout")<>"</w:p></w:comment></w:comments>"
    assert {:error,:unsupported_docx_annotation}=D.extract(zip.([{"word/document.xml",xml.("<w:p>"<>run.("body")<>"</w:p>")},{"word/comments.xml",comments}]),"comment.docx")
    ordinary="<w:footnotes xmlns:w=\"#{word}\"><w:footnote w:id=\"7\"><w:p>"<>run.("ordinary")<>"<w:r><w:separator/></w:r></w:p></w:footnote></w:footnotes>"
    {:ok,unsupported}=D.extract(zip.([{"word/document.xml",xml.("<w:p>"<>run.("body")<>"</w:p>")},{"word/footnotes.xml",ordinary}]),"marker.docx")
    assert List.last(unsupported["segments"])["text"]=="ordinary"
    assert %{"code"=>"unsupported_word_content","part"=>"word/footnotes.xml"} in unsupported["warnings"]
    layout="<w:footnotes xmlns:w=\"#{word}\"><w:footnote w:id=\"7\" w:type=\"separator\"><w:p>"<>run.("layout")<>"</w:p></w:footnote></w:footnotes>"
    body="<w:p>"<>run.("body")<>"<w:r><w:footnoteReference w:id=\"7\"/></w:r></w:p>"
    {:ok,dangling}=D.extract(zip.([{"word/document.xml",xml.(body)},{"word/footnotes.xml",layout}]),"layout-reference.docx")
    assert [%{"text"=>"body"}]=dangling["segments"]
    assert %{"code"=>"annotation_anchors_unresolved","part"=>"word/document.xml"} in dangling["warnings"]
    ''')
  end

  test "annotation citations require distinct, correctly placed numeric identities" do
    pure(~S'''
    for {part,root,item} <- [{"footnotes","footnotes","footnote"},{"endnotes","endnotes","endnote"},{"comments","comments","comment"}] do
      paragraph="<w:p>"<>run.("annotation text")<>"</w:p>"
      entry=fn attrs -> "<w:#{item}#{attrs}>#{paragraph}</w:#{item}>" end
      make=fn body -> zip.([{"word/document.xml",xml.("<w:p>"<>run.("body")<>"</w:p>")},{"word/#{part}.xml","<w:#{root} xmlns:w=\"#{word}\">#{body}</w:#{root}>"}]) end
      for body <- [entry.(""),entry.(" w:id=\"not-a-number\""),entry.(" w:id=\""<>String.duplicate("9",129)<>"\""),entry.(" w:id=\"7\"")<>entry.(" w:id=\"+07\""),paragraph,"<w:wrapper>"<>entry.(" w:id=\"4\"")<>"</w:wrapper>"] do
        assert {:error,:unsupported_docx_annotation}=D.extract(make.(body),"invalid.docx")
      end
      assert {:ok,result}=D.extract(make.(entry.(" w:id=\"-1\"")<>entry.(" w:id=\"7\"")),"valid.docx")
      assert Enum.map(tl(result["segments"]),& &1["locator"]["annotation_id"])==["-1","7"]
      assert result["status"]=="partial"
      assert %{"code"=>"annotation_anchors_unresolved","part"=>"word/#{part}.xml"} in result["warnings"]
    end
    assert {:error,:unsupported_docx_annotation}=D.extract(doc.("<w:footnote w:id=\"1\"><w:p>"<>run.("wrong part")<>"</w:p></w:footnote>"),"wrong.docx")
    ''')
  end

  test "unreferenced optional Word parts cannot publish text or set visibility by filename" do
    pure(~S'''
    for {name,body} <- [
      {"word/styles.xml","<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"hidden\"><w:rPr><w:vanish/></w:rPr></w:style></w:styles>"},
      {"word/footnotes.xml","<w:footnotes xmlns:w=\"#{word}\"><w:footnote w:id=\"1\"><w:p>"<>run.("orphan note")<>"</w:p></w:footnote></w:footnotes>"}
    ] do
      entries=package.([{"word/document.xml",xml.("<w:p>"<>run.("body")<>"</w:p>")},{name,body}])
      entries=List.keystore(entries,"word/_rels/document.xml.rels",0,{"word/_rels/document.xml.rels","<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"/>"})
      assert {:error,:unsupported_docx_part_relationship}=D.extract(raw_zip.(entries),"orphan-part.docx")
    end
    ''')
  end
end
