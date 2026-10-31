defmodule Ipse.KnowledgeCollectionChunkingTest do
  use ExUnit.Case, async: false
  @tag :collection_chunking
  test "explicit Collection recipe preserves legacy spans and fits the unchanged byte/chunk targets" do
    root = Path.expand("../../..", __DIR__)

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    files =
      ~w(evidence documents/zip documents/docx documents/parser_stage documents/pdf documents)

    script = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.{Evidence,Documents}
    package=fn texts ->
      word="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      body=Enum.map_join(texts,&("<w:p><w:r><w:t>"<>&1<>"</w:t></w:r></w:p>"))
      rel="http://schemas.openxmlformats.org/package/2006/relationships"
      root="<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"
      types="<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"
      {:ok,{_,bytes}}=:zip.create(~c"source.docx",[{~c"_rels/.rels",root},{~c"[Content_Types].xml",types},{~c"word/document.xml","<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}],[:memory])
      bytes
    end
    attrs=fn payload,id ->
      receipt=Evidence.document_storage_receipt!(payload["document"])
      source=%{"source_id"=>id,"partition"=>"notes","generation"=>1,"title"=>"Chunk recipe fixture",
        "text"=>payload["text"],"uri"=>"provided:source.docx","observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil,
        "origin"=>%{"kind"=>"provided","store_profile"=>"documents","partition_or_scope"=>"notes","receipt"=>receipt,"historical"=>false}}
      if receipt["version"]==4,do: Map.put(source,"document",payload["document"]),else: source
    end
    cases=Enum.map([2097,2096],fn size ->
      bytes=package.(List.duplicate(String.duplicate("a",size),10))
      {:ok,document}=Documents.extract(bytes,"source.docx")
      {:ok,oldpayload}=Documents.source_payload(document,65536)
      {:ok,payload}=Documents.source_payload(document,65536,2)
      assert oldpayload === payload
      input=attrs.(payload,"fixture:#{size}")
      {:ok,legacy}=Evidence.source(input)
      {:ok,oldchunks}=Evidence.chunks(legacy)
      assert length(oldchunks)==20
      first=hd(oldchunks)
      assert first["version"]==1
      assert first["chunk_id"]==Evidence.id("chunk",[legacy["source_key"],1,legacy["content_sha256"],1,0,2048])
      {:ok,oldcitation}=Evidence.citation(legacy,first,0,40)
      {:ok,current}=Evidence.collection_source(input)
      assert current["version"]==3
      assert current["chunking"]==%{"version"=>2,"max_bytes"=>4096}
      assert current["text"]==legacy["text"]
      {:ok,chunks}=Evidence.chunks(current)
      assert length(chunks)==10
      assert Enum.all?(chunks,&(&1["version"]==2))
      assert hd(chunks)["chunk_id"] != first["chunk_id"]
      assert {:ok,^oldchunks}=Evidence.chunks(legacy)
      assert Evidence.valid_span?(legacy,oldcitation)
      refute Evidence.valid_span?(current,oldcitation)
      assert Enum.all?(chunks,fn chunk -> Enum.any?(payload["document"]["segments"],fn segment ->
        chunk["start_byte"]>=segment["start_byte"] and chunk["end_byte"]<=segment["end_byte"] end) end)
      {:ok,citation}=Evidence.citation(current,hd(chunks),2040,2090)
      assert citation["version"]==3
      assert citation["chunking"]==current["chunking"]
      assert citation["document"]["locator"]["paragraph"]==1
      assert citation["document"]["start_byte"]==2040
      assert citation["document"]["end_byte"]==2090
      assert citation["document"]["original_sha256"]==Evidence.sha256(bytes)
      assert Evidence.valid_span?(current,citation)
      {:ok,run}=Evidence.lexical_run(current)
      assert run["version"]==2 and run["chunking"]==current["chunking"]
      assert Evidence.valid_lexical_run?(run)
      {:ok,oldrun}=Evidence.lexical_run(legacy)
      assert oldrun["version"]==1 and not Map.has_key?(oldrun,"chunking")
      assert Evidence.valid_lexical_run?(oldrun)
      refute Evidence.valid_source?(put_in(current,["chunking","max_bytes"],8192))
      refute Evidence.valid_lexical_run?(put_in(run,["chunking","max_bytes"],8192))
      {byte_size(current["text"]),length(chunks)}
    end)
    [{large,10},{small,10}]=cases
    assert large==20979 and small==20969
    assert 252*large+748*small==20*1024*1024
    assert (252+748)*10==10000
    assert 10000*2048 < 20*1024*1024
    assert 20*1024*1024-10000*2048==491520
    bytes=package.([String.duplicate("好",21845)])
    {:ok,document}=Documents.extract(bytes,"source.docx")
    assert {:error,:document_source_limit}=Documents.source_payload(document,65536)
    {:ok,payload}=Documents.source_payload(document,65536,2)
    {:ok,source}=Evidence.collection_source(attrs.(payload,"fixture:unicode"))
    {:ok,chunks}=Evidence.chunks(source)
    assert length(chunks)==17
    assert Enum.all?(chunks,&String.valid?(&1["text"]))
    assert Enum.map_join(chunks,& &1["text"])==payload["text"]
    IO.puts("COLLECTION_CHUNK_GEOMETRY_PASS bytes20971520 chunks10000 legacygap491520; arithmetic, not populated capacity")
    '''

    args =
      paths ++
        Enum.flat_map(files, &["-r", Path.join(root, "extensions/knowledge/src/#{&1}.ex")]) ++
        ["-e", script]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    refute output =~ "warning:"
    assert output =~ "COLLECTION_CHUNK_GEOMETRY_PASS"
    IO.write(output)
  end
end
