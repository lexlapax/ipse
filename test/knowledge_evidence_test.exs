defmodule Ipse.KnowledgeEvidenceTest do
  use ExUnit.Case, async: false
  @root Path.expand("..", __DIR__)

  # Domain modules run in their own VM, as they do in SDK artifacts.
  defp pure(body) do
    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.Evidence, as: E
    source = fn text, extra ->
      attrs = %{"source_id"=>"manual:one","partition"=>"notes","generation"=>1,"title"=>"Manual","text"=>text,"uri"=>"local:manual","observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"project","receipt"=>nil,"historical"=>false}}
      {:ok,s} = E.source(Map.merge(attrs,extra)); s
    end
    cite = fn s, quote ->
      {:ok,chunks}=E.chunks(s); {start,len}=:binary.match(s["text"],quote)
      chunk=Enum.find(chunks,&(&1["start_byte"]<=start and &1["end_byte"]>=start+len))
      {:ok,c}=E.citation(s,chunk,start,start+len); c
    end
    fact = fn subject, object, citation ->
      {:ok,f}=E.fact(%{"subject"=>subject,"predicate"=>"requires","object"=>object,"polarity"=>"positive","inferred"=>false,"valid_from_ms"=>nil,"valid_to_ms"=>nil,"extraction"=>%{"kind"=>"explicit","profile"=>nil,"version"=>1},"citations"=>[citation]}); f
    end
    '''

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["-r", Path.join(@root, "extensions/knowledge/src/evidence.ex"), "-e", bootstrap <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "source identity and exact byte citations refuse forged attribution and boundary splits" do
    pure(~S'''
    s=source.("Le café reste ouvert. The café closes at 17:00 UTC.",%{})
    c=cite.(s,"The café closes at 17:00 UTC.")
    assert E.valid_span?(s,c)
    assert c["start_byte"] == byte_size("Le café reste ouvert. ")
    refute E.valid_span?(s,Map.put(c,"chunk_id",String.duplicate("0",64)))
    refute E.valid_span?(s,Map.put(c,"quote","not captured"))
    refute E.valid_span?(s,put_in(c,["origin","historical"],true))
    refute E.valid_span?(Map.put(s,"generation",2),c)
    refute E.valid_source?(Map.put(s,"text",s["text"]<>"changed"))
    refute E.valid_source?(Map.put(s,"partition","../other"))
    refute E.valid_source?(Map.put(s,"extra",true))
    assert {:error,:invalid_source}=E.source(%{})
    bad=source.("café",%{})
    {:ok,[chunk]}=E.chunks(bad)
    assert {:error,:invalid_span}=E.citation(bad,chunk,4,5)
    assert {:error,:invalid_span}=E.citation(bad,chunk,0,4)
    ''')
  end

  test "64 KiB sources are contiguous and UTF8 chunk cuts never lose bytes" do
    pure(~S'''
    s=source.(String.duplicate("a",65536),%{})
    {:ok,chunks}=E.chunks(s)
    assert length(chunks)==32
    assert Enum.map_join(chunks,& &1["text"])==s["text"]
    assert Enum.reduce(chunks,0,fn c,offset -> assert c["start_byte"]==offset; assert c["end_byte"]-offset==byte_size(c["text"]); c["end_byte"] end)==65536
    utf=source.(String.duplicate("a",2047)<>"é"<>String.duplicate("x",3000),%{})
    {:ok,cs}=E.chunks(utf)
    assert Enum.all?(cs,&(String.valid?(&1["text"]) and byte_size(&1["text"])<=2048))
    assert Enum.map_join(cs,& &1["text"])==utf["text"]
    refute E.valid_source?(Map.put(s,"text",String.duplicate("x",65537)))
    ''')
  end

  test "lexical ranking excludes stale and historical sources and never invents absent evidence" do
    pure(~S'''
    live=source.("Releasing the OS lock preserves inode identity.",%{})
    expired=source.("inode inode inode",%{"source_id"=>"expired","expires_at_ms"=>20})
    future=source.("inode",%{"source_id"=>"future","observed_at_ms"=>21})
    historical=put_in(source.("inode",%{"source_id"=>"import"}),["origin","historical"],true)
    {:ok,r}=E.rank_lexical([expired,future,historical,live],"inode lock",5,20)
    assert length(r["evidence"])==1
    assert hd(r["evidence"])["citation"]["source_id"]=="manual:one"
    assert length(r["gaps"])==3
    assert E.valid_span?(live,hd(r["evidence"])["citation"])
    {:ok,empty}=E.rank_lexical([live],"arbitrary absent mineral",5,20)
    assert empty["evidence"]==[]
    assert {:ok,[%{"label"=>"open"}]}=E.classify([],[],"absent")
    {:ok,a}=E.rank_lexical([live],"inode",5,20)
    assert {:ok,^a}=E.rank_lexical([live],"inode",5,20)
    ''')
  end

  test "full4096 vectors preserve canonical values and reject hash or profile substitutions" do
    pure(~S'''
    s=source.("the evidence",%{}); c=cite.(s,"the evidence")
    attrs=%{"chunk_id"=>c["chunk_id"],"input_sha256"=>E.sha256("opaque host input"),"profile"=>"encoder","model"=>"model-a","dimensions"=>4096,"values"=>[1.0|List.duplicate(0.0,4095)]}
    {:ok,v}=E.vector(attrs)
    assert E.valid_vector?(v)
    assert length(v["values"])==4096
    assert v["vector_sha256"]==E.sha256(<<1.0::little-float-size(32),0::size(4095*32)>>)
    candidate=%{"citation"=>c,"score"=>0.0,"method"=>"bm25","vector"=>v}
    {:ok,r}=E.rank_cosine([candidate],v,5)
    assert hd(r["evidence"])["score"]==1.0
    refute Map.has_key?(hd(r["evidence"]),"vector")
    assert {:error,:incompatible_vector}=E.rank_cosine([put_in(candidate,["vector","model"],"model-b")],v,5)
    refute E.valid_vector?(Map.put(v,"vector_sha256",String.duplicate("0",64)))
    assert {:error,:invalid_vector}=E.vector(Map.put(attrs,"values",List.duplicate(0.0,4096)))
    assert {:error,:invalid_vector}=E.vector(Map.merge(attrs,%{"dimensions"=>1,"values"=>[1.0e-100]}))
    assert {:error,:invalid_vector}=E.vector(Map.merge(attrs,%{"dimensions"=>1,"values"=>[1.0e100]}))
    ''')
  end

  test "fusion and reranking preserve citation authority and refuse fabricated candidates" do
    pure(~S'''
    a=source.("alpha",%{});b=source.("beta",%{"source_id"=>"second"})
    ca=%{"citation"=>cite.(a,"alpha"),"score"=>2.0,"method"=>"bm25"}
    cb=%{"citation"=>cite.(b,"beta"),"score"=>1.0,"method"=>"bm25"}
    {:ok,r}=E.fuse([[ca,cb],[cb]],5,60)
    assert hd(r["evidence"])["citation"]==cb["citation"]
    assert {:ok,[^cb,^ca]}=E.apply_rerank([ca,cb],[cb["citation"]["chunk_id"]])
    assert {:error,:invalid_rerank}=E.apply_rerank([ca,cb],["invented"])
    assert {:error,:invalid_rerank}=E.apply_rerank([ca,cb],[ca["citation"]["chunk_id"],ca["citation"]["chunk_id"]])
    assert {:error,:invalid_ranks}=E.fuse([[Map.put(ca,"destination","attacker")]],5,60)
    ''')
  end

  test "every graph support is checked through suppression replacement and conflicts" do
    pure(~S'''
    s=source.("Release requires quiescence. Quiescence requires worker exit.",%{})
    first=fact.("Release","quiescence",cite.(s,"Release requires quiescence."))
    second=fact.("quiescence","worker exit",cite.(s,"Quiescence requires worker exit."))
    limits=%{"depth"=>2,"max_nodes"=>128,"max_edges"=>256,"top_k"=>10}
    {:ok,r}=E.traverse([s],[first,second],"Release",limits,20)
    assert r["coverage"]["edges"]==2
    {:ok,gone}=E.traverse([],[first,second],"Release",limits,20)
    assert gone["evidence"]==[]
    {:ok,stale}=E.traverse([Map.put(s,"generation",2)],[first,second],"Release",limits,20)
    assert stale["evidence"]==[]
    {:ok,bounded}=E.traverse([s],[first,second],"Release",Map.put(limits,"depth",1),20)
    assert bounded["coverage"]["edges"]==1
    contradictory=fact.("Release","other",cite.(s,"Release requires quiescence."))
    {:ok,claims}=E.classify([],[first,contradictory],"Release")
    assert Enum.all?(claims,&(&1["label"]=="conflict"))
    forged=put_in(first,["citations",Access.at(0),"quote"],"forged")
    assert {:error,:invalid_fact}=E.validate_facts([s],[forged],20)
    {:ok,negative}=E.fact(first |> Map.drop(~w(version fact_id)) |> Map.put("polarity","negative"))
    {:ok,no_path}=E.traverse([s],[negative,second],"Release",limits,20)
    assert no_path["evidence"]==[]
    ''')
  end

  test "fact policy exclusions remain distinct from missing or replaced provenance" do
    pure(~S'''
    s=source.("Release requires quiescence.",%{})
    original=fact.("Release","quiescence",cite.(s,"Release requires quiescence."))
    {:ok,expires}=E.fact(original |> Map.drop(~w(version fact_id)) |> Map.put("valid_to_ms",20))
    {:ok,future}=E.fact(original |> Map.drop(~w(version fact_id)) |> Map.put("valid_from_ms",21))
    limits=%{"depth"=>2,"max_nodes"=>16,"max_edges"=>16,"top_k"=>10}
    {:ok,before}=E.traverse([s],[expires],"Release",limits,19)
    assert E.query_scope(before,[s],[],19)["status"]=="ok"
    for {sources,facts} <- [{[s],[expires]},{[s],[future]},{[Map.put(s,"expires_at_ms",20)],[original]}] do
      {:ok,rank}=E.traverse(sources,facts,"Release",limits,20)
      result=E.query_scope(rank,sources,[],20)
      assert result["status"]=="abstain" and result["coverage"]["complete"]
      assert Enum.any?(result["gaps"],&(&1["code"]=="excluded_fact"))
      assert result["evidence"]==[]
    end
    for sources <- [[],[Map.put(s,"generation",2)]] do
      {:ok,rank}=E.traverse(sources,[expires],"Release",limits,20)
      result=E.query_scope(rank,sources,[],20)
      assert result["status"]=="partial" and not result["coverage"]["complete"]
      assert Enum.any?(result["gaps"],&(&1["code"]=="stale_fact"))
    end
    citation=hd(expires["citations"])
    forged=Map.put(citation,"chunk_id",String.duplicate("0",64))
    {:ok,forged_fact}=E.fact(expires |> Map.drop(~w(version fact_id)) |> Map.put("citations",[forged]))
    assert {:error,:invalid_span}=E.validate_facts([s],[forged_fact],20)
    ''')
  end

  test "frozen development source bytes and span annotations stay independent of rank output" do
    fixture = Path.join(@root, "extensions/knowledge/fixtures")

    pure(
      "fixture=" <>
        inspect(fixture) <>
        "\n" <>
        ~S'''
        corpus=JSON.decode!(File.read!(Path.join(fixture,"development-corpus.json")))
        queries=JSON.decode!(File.read!(Path.join(fixture,"development-queries.json")))
        manifest=JSON.decode!(File.read!(Path.join(fixture,"development-manifest.json")))
        Enum.each(corpus["sources"],fn row ->
          expected=Enum.find(manifest["sources"],&(&1["source_id"]==row["source_id"]))
          assert expected["generation"]==row["generation"]
          assert expected["bytes"]==byte_size(row["text"])
          assert expected["content_sha256"]==Base.encode16(:crypto.hash(:sha256,row["text"]),case: :lower)
        end)
        assert corpus["split"]=="development" and length(corpus["sources"])==10
        sources=Enum.map(corpus["sources"],fn row -> source.(row["text"],%{"source_id"=>row["source_id"],"generation"=>row["generation"],"expires_at_ms"=>row["expires_at_ms"]}) end)
        Enum.each(queries["queries"],fn q ->
          if q["quote"] do
            s=Enum.find(sources,&(&1["source_id"] in q["sources"]))
            assert E.valid_span?(s,cite.(s,q["quote"]))
          end
        end)
        assert Enum.any?(sources,&(&1["source_id"]=="dev:chair" and &1["generation"]==2 and not String.contains?(&1["text"],"Ada")))
        '''
    )
  end

  test "remote references become exact bounded citations with asserted score provenance" do
    pure(~S'''
    s=source.(String.duplicate("x",2047)<>"é"<>String.duplicate("y",1300),%{})
    {:ok,chunks}=E.chunks(s); selected=Enum.at(chunks,1)
    ref=Map.take(s,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>selected["chunk_id"],"score"=>2.75})
    {:ok,r}=E.rank_remote([s],[ref],5,20)
    [hit]=r["evidence"]
    assert hit["method"]=="mcp_query" and hit["score"]==2.75
    assert hit["citation"]["chunk_id"]==selected["chunk_id"]
    assert hit["citation"]["start_byte"]==selected["start_byte"]
    assert byte_size(hit["citation"]["quote"])<=1024
    assert String.starts_with?(hit["citation"]["quote"],"é")
    assert E.valid_span?(s,hit["citation"])
    assert r["coverage"]==%{"method"=>"mcp_query","score_provenance"=>"server_asserted","as_of_ms"=>20,"sources"=>1,"chunks"=>1,"complete"=>true}
    {:ok,fused}=E.fuse([r["evidence"]],5,60)
    assert hd(fused["evidence"])["citation"]==hit["citation"]
    assert {:ok,[^hit]}=E.apply_rerank(r["evidence"],[selected["chunk_id"]])
    ''')
  end

  test "remote score order is preserved with deterministic ties and exact reference identity" do
    pure(~S'''
    a=source.("alpha",%{}); b=source.("beta",%{"source_id"=>"second"})
    refs=Enum.map([a,b],fn s -> {:ok,[c]}=E.chunks(s);Map.take(s,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>c["chunk_id"],"score"=>1.0}) end)
    {:ok,ties}=E.rank_remote([a,b],refs,5,20)
    assert {:ok,^ties}=E.rank_remote([a,b],Enum.reverse(refs),5,20)
    ranked=[Map.put(hd(refs),"score",-3),Map.put(List.last(refs),"score",0)]
    {:ok,result}=E.rank_remote([a,b],ranked,5,20)
    assert Enum.map(result["evidence"],& &1["score"])==[0,-3]
    assert hd(result["evidence"])["citation"]["source_id"]=="second"
    assert {:error,:invalid_remote_refs}=E.rank_remote([a,b],[hd(refs),hd(refs)],5,20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([a,b],List.duplicate(hd(refs),11),10,20)
    assert {:error,:invalid_sources}=E.rank_remote([a,b],refs,0,20)
    ''')
  end

  test "forged remote selection metadata cannot select different content or partitions" do
    pure(~S'''
    s=source.("captured evidence",%{});{:ok,[chunk]}=E.chunks(s)
    ref=Map.take(s,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>chunk["chunk_id"],"score"=>1.0})
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"source_id","other")],5,20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"partition","other")],5,20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"score",:nan)],5,20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"generation",0)],5,20)
    for field<-~w(content_sha256 chunk_id) do
      assert {:error,:invalid_remote_selection}=E.rank_remote([s],[Map.put(ref,field,String.duplicate("0",64))],5,20)
    end
    assert {:error,:invalid_remote_selection}=E.rank_remote([s],[Map.put(ref,"generation",2)],5,20)
    assert {:error,:invalid_remote_selection}=E.rank_remote([], [ref],5,20)
    other=source.("foreign",%{"source_id"=>"second","partition"=>"other"})
    assert {:error,:invalid_remote_selection}=E.rank_remote([s,other],[ref],5,20)
    assert {:error,:invalid_sources}=E.rank_remote([Map.put(s,"text","tampered")],[ref],5,20)
    ''')
  end

  test "remote stale or suppressed selection refuses all evidence and empty refs stay empty" do
    pure(~S'''
    s=source.("captured evidence",%{});{:ok,[chunk]}=E.chunks(s)
    ref=Map.take(s,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>chunk["chunk_id"],"score"=>1.0})
    expired=Map.put(s,"expires_at_ms",20)
    future=Map.put(s,"observed_at_ms",21)
    historical=put_in(s,["origin","historical"],true)
    for stale<-[expired,future,historical] do
      assert {:error,:invalid_remote_selection}=E.rank_remote([stale],[ref],5,20)
    end
    live=source.("live",%{"source_id"=>"second"});{:ok,[c]}=E.chunks(live)
    live_ref=Map.take(live,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>c["chunk_id"],"score"=>2.0})
    assert {:error,:invalid_remote_selection}=E.rank_remote([live],[live_ref,ref],5,20)
    {:ok,empty}=E.rank_remote([],[],5,20)
    assert empty["evidence"]==[] and empty["claims"]==[] and empty["gaps"]==[]
    assert empty["coverage"]["sources"]==0 and empty["coverage"]["chunks"]==0
    assert empty["coverage"]["score_provenance"]=="server_asserted"
    ''')
  end
end
