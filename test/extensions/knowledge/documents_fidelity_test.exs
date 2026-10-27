defmodule Ipse.KnowledgeDocumentsFidelityTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  defp pure(body) do
    files = ~w(documents/zip documents/docx documents/parser_stage documents/pdf documents)

    arguments =
      Enum.flat_map(files, &["-r", Path.join(@root, "extensions/knowledge/src/#{&1}.ex")])

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
        parts=Enum.filter(~w(styles footnotes endnotes comments), &("word/#{&1}.xml" in names))
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
      System.cmd(System.find_executable("elixir"), arguments ++ ["-e", bootstrap <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
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
      assert result["extraction_version"]=="ipse-documents-v3"
    end
    for value <- ["false","0","off"] do
      {:ok,result}=D.extract(doc.("<w:p><w:r><w:rPr><w:vanish w:val=\"#{value}\"/></w:rPr><w:t>visible</w:t></w:r></w:p>"),"a.docx")
      assert [%{"text"=>"visible"}]=result["segments"]
    end
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

  test "custom header and footer references and inherited styles disclose omitted coverage" do
    pure(~S'''
    main=xml.("<w:p>"<>run.("body")<>"</w:p><w:sectPr><w:headerReference w:type=\"default\" r:id=\"custom\"/><w:footerReference w:type=\"default\" r:id=\"missing\"/></w:sectPr>")
    relationships="<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"custom\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"custom-header.xml\"/><Relationship Id=\"styles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
    header="<w:hdr xmlns:w=\"#{word}\"><w:p>"<>run.("omitted header")<>"</w:p></w:hdr>"
    styles="<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"character\" w:styleId=\"hidden\"><w:rPr><w:vanish/></w:rPr></w:style></w:styles>"
    {:ok,result}=D.extract(zip.([{"word/document.xml",main},{"word/custom-header.xml",header},{"word/_rels/document.xml.rels",relationships},{"word/styles.xml",styles}]),"a.docx")
    assert result["status"]=="partial"
    assert [%{"text"=>"body"}]=result["segments"]
    assert "referenced_part_not_extracted" in codes.(result)
    refute "styles_not_applied" in codes.(result)
    assert Enum.count(result["warnings"],&(&1["code"]=="referenced_part_not_extracted"))==2
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
    assert {:error,:unsupported_docx_style_visibility}=D.extract(doc.(p),"missing.docx")
    for body <- [
      "<w:p>"<>run.("already emitted")<>"<w:pPr><w:pStyle w:val=\"a\"/></w:pPr></w:p>",
      "<w:p><w:pPr><w:pStyle w:val=\"a\"/><w:pStyle w:val=\"a\"/></w:pPr>"<>run.("duplicate")<>"</w:p>",
      "<w:p><w:r><w:t>already emitted</w:t><w:rPr><w:rStyle w:val=\"b\"/></w:rPr></w:r></w:p>",
      "<w:p><w:pPr><w:numPr/></w:pPr>"<>run.("numbered")<>"</w:p>"
    ] do
      assert {:error,:unsupported_docx_style_visibility}=extract.(style.("paragraph","a","")<>style.("character","b",""),body)
    end
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
