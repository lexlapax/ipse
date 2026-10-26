defmodule Ipse.KnowledgeDocumentsTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  defp pure(body) do
    files = ~w(documents/zip documents/docx documents/pdf documents)
    args = Enum.flat_map(files, &["-r", Path.join(@root, "extensions/knowledge/src/#{&1}.ex")])

    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.Documents, as: D
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    xml = fn body -> "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>" end
    paragraph = fn text -> "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" end
    zip = fn entries ->
      {:ok,{_,bytes}}=:zip.create(~c"development.docx",Enum.map(entries,fn {name,value}->{String.to_charlist(name),value} end),[:memory])
      bytes
    end
    doc = fn body -> zip.([{"word/document.xml",xml.(body)}]) end
    '''

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["-e", bootstrap <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
  end

  test "text and Markdown retain exact Unicode line offsets and original hash" do
    pure(~S'''
    bytes="# Café\r\n保持 exact\n"
    {:ok,result}=D.extract(bytes,"guide.MD")
    assert result["status"]=="complete"
    assert result["format"]=="markdown"
    assert result["original_sha256"]==Base.encode16(:crypto.hash(:sha256,bytes),case: :lower)
    assert result["extraction_version"]==D.version()
    assert Enum.map(result["segments"],& &1["text"])==["# Café\r","保持 exact",""]
    for segment <- result["segments"] do
      l=segment["locator"]
      assert binary_part(bytes,l["start_byte"],l["end_byte"]-l["start_byte"])==segment["text"]
    end
    assert {:error,:invalid_utf8}=D.extract(<<255>>,"a.txt")
    assert {:error,:binary_input}=D.extract(<<0,1,2>>,"a.txt")
    assert {:error,:unsupported_format}=D.extract("text","a.exe")
    assert {:error,:legacy_word_unsupported}=D.extract("text","a.doc")
    assert {:error,:pdf_experimental_unavailable}=D.extract("%PDF-1.7","a.pdf")
    assert {:error,:format_mismatch}=D.extract("%PDF-1.7","renamed.txt")
    assert {:ok,%{"format"=>"text"}}=D.extract("FROM selected-base\n","Dockerfile")
    ''')
  end

  test "all published ceilings may only be reduced and oversized text is refused" do
    pure(~S'''
    for options <- [[max_input_bytes: D.limits().max_input_bytes+1],[unknown: 1],[max_text_bytes: 0],[timeout_ms: -1],[max_entries: 1,max_entries: 2]] do
      assert {:error,:invalid_limits}=D.extract("text","a.txt",options)
    end
    assert {:error,:invalid_or_oversized_input}=D.extract("hello","a.txt",max_input_bytes: 4)
    assert {:error,:text_limit}=D.extract("hello","a.txt",max_text_bytes: 4)
    assert {:error,:segment_limit}=D.extract("a\nb","a.txt",max_segments: 1)
    ''')
  end

  test "DOCX preserves headings, Unicode, table cells and final visible tracked revisions" do
    pure(~S'''
    body="<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Résumé 好</w:t></w:r></w:p>" <>
      "<w:p><w:r><w:t>before </w:t></w:r><w:del><w:r><w:delText>removed</w:delText><w:t>also removed</w:t></w:r></w:del><w:ins><w:r><w:t>inserted</w:t></w:r></w:ins><w:moveFrom>" <> paragraph.("old") <> "</w:moveFrom></w:p>"
    # Real OOXML moveFrom paragraphs are siblings, not nested in a paragraph.
    body=String.replace(body,"<w:moveFrom>"<>paragraph.("old")<>"</w:moveFrom>","<w:moveFrom><w:r><w:t>old</w:t></w:r></w:moveFrom>")
    table="<w:tbl><w:tr><w:tc>"<>paragraph.("left")<>"</w:tc><w:tc>"<>paragraph.("right &amp; true")<>"</w:tc></w:tr></w:tbl>"
    {:ok,result}=D.extract(doc.(body<>table),"development.docx")
    assert result["status"]=="complete"
    assert result["revision_policy"]=="final_visible_insertions_included_deletions_excluded"
    [heading,revision,left,right]=result["segments"]
    assert heading["text"]=="Résumé 好" and heading["style"]=="Heading1"
    assert revision["text"]=="before inserted"
    assert left["locator"]==%{"kind"=>"table_cell","part"=>"word/document.xml","paragraph"=>3,"table"=>1,"row"=>1,"cell"=>1}
    assert right["text"]=="right & true" and right["locator"]["cell"]==2
    ''')
  end

  test "notes and comments stay labelled, external relationships are inert and omissions are partial" do
    pure(~S'''
    entries=[{"word/document.xml",xml.(paragraph.("main"))},
      {"word/footnotes.xml","<w:footnotes xmlns:w=\"#{word}\"><w:footnote w:id=\"7\">#{paragraph.("footnote")}</w:footnote></w:footnotes>"},
      {"word/comments.xml","<w:comments xmlns:w=\"#{word}\"><w:comment w:id=\"4\">#{paragraph.("comment")}</w:comment></w:comments>"},
      {"word/_rels/document.xml.rels","<Relationships><Relationship Target=\"https://invalid.example/private\" TargetMode=\"External\"/></Relationships>"},
      {"word/header1.xml","omitted header"}]
    {:ok,result}=D.extract(zip.(entries),"a.docx")
    assert result["status"]=="partial"
    assert result["warnings"]==[%{"code"=>"part_not_extracted","part"=>"word/header1.xml"}]
    [main,footnote,comment]=result["segments"]
    assert main["text"]=="main"
    assert footnote["locator"]["part"]=="word/footnotes.xml" and footnote["locator"]["annotation_id"]=="7"
    assert comment["locator"]["part"]=="word/comments.xml" and comment["locator"]["annotation_id"]=="4"
    ''')
  end

  test "archive metadata and actual expanded data have independent bounds" do
    pure(~S'''
    bytes=doc.(paragraph.(String.duplicate("a",100_000)))
    assert {:error,:expansion_limit}=D.extract(bytes,"a.docx",max_expanded_bytes: 1000)
    assert {:error,:text_limit}=D.extract(bytes,"a.docx",max_text_bytes: 1000)
    assert {:error,:zip_entry_limit}=D.extract(zip.([{"word/document.xml",xml.(paragraph.("ok"))},{"extra","x"}]),"a.docx",max_entries: 1)
    # Forge both advertised expanded sizes below the actual deflate expansion.
    [{local,_}]=:binary.matches(bytes,<<80,75,3,4>>)
    [{central,_}]=:binary.matches(bytes,<<80,75,1,2>>)
    replace=fn b,offset,value -> binary_part(b,0,offset)<>value<>binary_part(b,offset+4,byte_size(b)-offset-4) end
    forged=bytes|>replace.(local+22,<<100::little-32>>)|>replace.(central+24,<<100::little-32>>)
    assert {:error,:expansion_limit}=D.extract(forged,"a.docx",max_expanded_bytes: 1000)
    ''')
  end

  test "ZIP traversal, duplicates, encryption and embedded objects refuse explicitly" do
    pure(~S'''
    for name <- ["../outside","word/../outside","C:/outside","word\\outside"] do
      assert {:error,:unsafe_zip_entry}=D.extract(zip.([{"word/document.xml",xml.(paragraph.("ok"))},{name,"bad"}]),"a.docx")
    end
    absolute=zip.([{"word/document.xml",xml.(paragraph.("ok"))},{"xabsolute","bad"}])|>:binary.replace("xabsolute","/absolute",[:global])
    assert {:error,:unsafe_zip_entry}=D.extract(absolute,"a.docx")
    assert {:error,:duplicate_zip_entry}=D.extract(zip.([{"word/document.xml",xml.(paragraph.("first"))},{"word/document.xml",xml.(paragraph.("second"))}]),"a.docx")
    for name <- ["word/embeddings/object.bin","word/vbaProject.bin"] do
      assert {:error,:embedded_objects_unsupported}=D.extract(zip.([{"word/document.xml",xml.(paragraph.("ok"))},{name,"bad"}]),"a.docx")
    end
    assert {:error,:encrypted_document}=D.extract(zip.([{"EncryptionInfo","x"},{"EncryptedPackage","x"}]),"a.docx")
    bytes=doc.(paragraph.("ok"))
    <<prefix::binary-size(6),flags::little-16,rest::binary>>=bytes
    assert {:error,:encrypted_document}=D.extract(prefix<><<Bitwise.bor(flags,1)::little-16>><>rest,"a.docx")
    ''')
  end

  test "malformed packages, entity declarations, XML nesting and output limits fail closed" do
    pure(~S'''
    assert {:error,:malformed_zip}=D.extract("not zip","a.docx")
    assert {:error,:not_word_document}=D.extract(zip.([{"other.xml","x"}]),"a.docx")
    for declaration <- ["<!DOCTYPE w:document SYSTEM \"file:///etc/passwd\">","<!DOCTYPE w:document [<!ENTITY attack SYSTEM \"https://invalid.example\">]>"] do
      assert {:error,:xml_entities_unsupported}=D.extract(zip.([{"word/document.xml",declaration<>xml.(paragraph.("&attack;"))}]),"a.docx")
    end
    assert {:error,:malformed_xml}=D.extract(zip.([{"word/document.xml",xml.("<broken>")}]),"a.docx")
    assert {:error,:xml_structure_limit}=D.extract(doc.(String.duplicate("<w:r>",70)<>String.duplicate("</w:r>",70)),"a.docx")
    assert {:error,:segment_limit}=D.extract(doc.(paragraph.("one")<>paragraph.("two")),"a.docx",max_segments: 1)
    assert {:error,:text_limit}=D.extract(doc.(paragraph.("hello")),"a.docx",max_text_bytes: 4)
    assert {:error,:invalid_word_namespace}=D.extract(zip.([{"word/document.xml","<document><p>hello</p></document>"}]),"a.docx")
    ''')
  end

  test "stored entries and strict OOXML namespaces extract without a deflate assumption" do
    pure(~S'''
    strict=String.replace(xml.(paragraph.("strict")),word,"http://purl.oclc.org/ooxml/wordprocessingml/main")
    {:ok,{_,bytes}}=:zip.create(~c"stored.docx",[{~c"word/document.xml",strict}],[:memory,{:uncompress,:all}])
    assert {:ok,%{"segments"=>[%{"text"=>"strict"}]}}=D.extract(bytes,"a.docx")
    ''')
  end

  test "owned parser work times out and stops when its caller is killed" do
    pure(~S'''
    large=String.duplicate("line\n",200_000)
    assert {:error,:extraction_timeout}=D.extract(large,"large.txt",timeout_ms: 1)
    labels=fn -> Enum.filter(Process.list(),fn pid -> :proc_lib.get_label(pid) in [{D,:worker},{D,:guardian}] end) end
    wait=fn wait,remaining ->
      if labels.()!=[] and remaining>0 do Process.sleep(5); wait.(wait,remaining-1) else labels.() end
    end
    assert wait.(wait,100)==[]
    caller=spawn(fn -> D.extract(large,"large.txt") end)
    find=fn find,remaining ->
      workers=Enum.filter(labels.(),fn pid -> :proc_lib.get_label(pid)=={D,:worker} end)
      cond do workers != [] -> hd(workers); remaining>0 -> Process.sleep(1); find.(find,remaining-1); true -> flunk("worker did not start") end
    end
    worker=find.(find,100)
    monitor=Process.monitor(worker)
    Process.exit(caller,:kill)
    receive do {:DOWN,^monitor,:process,^worker,_} -> :ok after 1000 -> flunk("parser survived caller") end
    assert wait.(wait,100)==[]
    ''')
  end
end
