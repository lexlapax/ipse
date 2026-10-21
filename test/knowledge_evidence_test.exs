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

  test "public open claims resolve against final order and retain unreturned provenance" do
    pure(~S'''
    one=source.("first passage",%{}); two=source.("second passage",%{"source_id"=>"second"})
    c1=cite.(one,"first passage"); c2=cite.(two,"second passage")
    evidence=Enum.map([c1,c2], &%{"citation"=>&1,"score"=>1.0,"method"=>"bm25"})
    {:ok,[claim]}=E.classify(evidence,[],"passage")
    [public]=E.public_claims(Enum.reverse(evidence),[claim])
    assert public["evidence_indexes"]==[1,0]
    refute Map.has_key?(public,"basis")
    assert Enum.map(public["evidence_indexes"], &Enum.at(Enum.reverse(evidence),&1)["citation"])==claim["basis"]
    assert E.public_claims(Enum.take(evidence,1),[claim])==[claim]
    attributed=%{"label"=>"supported","basis"=>[c1]}
    assert E.public_claims(evidence,[attributed])==[attributed]
    {:ok,[empty]}=E.classify([],[],"passage")
    assert hd(E.public_claims([],[empty]))["evidence_indexes"]==[]
    ''')
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

  test "portable source, citation, fact and query identities stop at the safe integer boundary" do
    pure(~S'''
    max=E.safe_integer_max()
    for n <- [0,1,max], do: assert(E.safe_uint?(n))
    for n <- [-1,max+1,1.0,nil,"1",true], do: refute(E.safe_uint?(n))
    for n <- [1,max], do: assert(E.safe_positive?(n))
    refute E.safe_positive?(0)
    s=source.("Release requires lock.",%{})
    attrs=Map.drop(s,~w(version source_key content_sha256))
    for field <- ~w(generation observed_at_ms event_at_ms expires_at_ms) do
      assert {:ok,good}=E.source(Map.put(attrs,field,max))
      assert E.valid_source?(good)
      assert {:error,:invalid_source}=E.source(Map.put(attrs,field,max+1))
      refute E.valid_source?(Map.put(good,field,max+1))
    end
    c=cite.(s,s["text"])
    for field <- ~w(generation observed_at_ms event_at_ms) do
      refute E.valid_span?(s,Map.put(c,field,max+1))
      unsafe=Map.put(c,field,max+1)
      assert {:error,_}=E.fact(%{"subject"=>"Release","predicate"=>"requires","object"=>"lock",
        "polarity"=>"positive","inferred"=>false,"valid_from_ms"=>nil,"valid_to_ms"=>nil,
        "extraction"=>%{"kind"=>"explicit","profile"=>nil,"version"=>1},"citations"=>[unsafe]})
    end
    max_source=source.(s["text"],%{"generation"=>max,"observed_at_ms"=>max,"event_at_ms"=>max})
    max_citation=cite.(max_source,s["text"])
    assert E.valid_span?(max_source,max_citation)
    assert E.valid_fact?(fact.("Release","lock",max_citation))
    f=fact.("Release","lock",c)
    attrs=Map.drop(f,~w(version fact_id))
    for {from,to} <- [{max,max},{nil,max},{max,nil}] do
      assert {:ok,valid}=E.fact(Map.merge(attrs,%{"valid_from_ms"=>from,"valid_to_ms"=>to}))
      assert E.valid_fact?(valid)
    end
    for field <- ~w(valid_from_ms valid_to_ms) do
      assert {:error,_}=E.fact(Map.put(attrs,field,max+1))
      refute E.valid_fact?(Map.put(f,field,max+1))
    end
    assert E.current?(s,max)
    refute E.current?(s,max+1)
    assert {:ok,_}=E.rank_lexical([s],"Release",1,max)
    assert {:error,_}=E.rank_lexical([s],"Release",1,max+1)
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
    attrs=%{"chunk_id"=>c["chunk_id"],"selection_sha256"=>E.sha256("selected encoder"),"input_sha256"=>E.sha256("opaque host input"),"profile"=>"encoder","model"=>"model-a","dimensions"=>4096,"values"=>[1.0|List.duplicate(0.0,4095)]}
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
    assert v["version"] === 2
    refute E.compatible_vectors?(v,Map.put(v,"selection_sha256",E.sha256("other encoder")))
    assert {:error,:incompatible_vector}=E.rank_cosine([put_in(candidate,["vector","selection_sha256"],E.sha256("other encoder"))],v,5)
    legacy=v |> Map.delete("selection_sha256") |> Map.put("version",1)
    assert E.valid_vector?(legacy)
    refute E.current_vector?(legacy)
    refute E.compatible_vectors?(v,legacy)
    assert {:error,:invalid_vector}=E.rank_cosine([],legacy,5)
    assert {:error,:incompatible_vector}=E.rank_cosine([Map.put(candidate,"vector",legacy)],v,5)
    assert {:error,:invalid_vector}=E.vector(Map.delete(attrs,"selection_sha256"))
    refute E.valid_vector?(Map.delete(v,"selection_sha256"))
    refute E.valid_vector?(Map.put(legacy,"selection_sha256",E.sha256("invented")))
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
    assert {:ok,[^cb,^ca]}=E.apply_rerank([ca,cb],[E.candidate_id(cb)])
    assert {:error,:invalid_rerank}=E.apply_rerank([ca,cb],["invented"])
    assert {:error,:invalid_rerank}=E.apply_rerank([ca,cb],[E.candidate_id(ca),E.candidate_id(ca)])
    assert {:error,:invalid_ranks}=E.fuse([[Map.put(ca,"destination","attacker")]],5,60)
    ''')
  end

  test "fusion reinforces chunk overlap and keeps the best ranked exact span" do
    pure(~S'''
    s=source.("alpha beta gamma",%{})
    a=%{"citation"=>cite.(s,"alpha"),"score"=>2.0,"method"=>"bm25"}
    b=%{"citation"=>cite.(s,"beta"),"score"=>1.0,"method"=>"cosine"}
    {:ok,r}=E.fuse([[a,a,b],[b]],10,60)
    assert [hit]=r["evidence"]
    assert hit["score"]==2/61
    assert hit["citation"]==a["citation"]
    assert E.candidate_id(hit)==E.candidate_id(a)
    other=source.("other",%{"source_id"=>"other"})
    c=%{"citation"=>cite.(other,"other"),"score"=>1.0,"method"=>"bm25"}
    {:ok,r}=E.fuse([[c,a],[b]],10,60)
    assert hd(r["evidence"])["citation"]==b["citation"]
    assert {:ok,[^a,^b]}=E.apply_rerank([a,b],[E.candidate_id(a),E.candidate_id(b)])
    partitioned=put_in(Map.put(s,"partition","elsewhere"),["origin","partition_or_scope"],"elsewhere")
    p=%{"citation"=>cite.(partitioned,"alpha"),"score"=>1.0,"method"=>"bm25"}
    newer=source.(s["text"],%{"generation"=>2})
    n=%{"citation"=>cite.(newer,"alpha"),"score"=>1.0,"method"=>"bm25"}
    changed=source.("alpha changed",%{})
    d=%{"citation"=>cite.(changed,"alpha"),"score"=>1.0,"method"=>"bm25"}
    {:ok,r}=E.fuse([[a],[p],[n],[d]],10,60)
    assert length(r["evidence"])==4
    ''')
  end

  test "depth exhaustion reports remaining graph work without marking leaves or closed cycles partial" do
    pure(~S'''
    s=source.("A requires B. B requires C. B requires A.",%{})
    ab=fact.("A","B",cite.(s,"A requires B."))
    bc=fact.("B","C",cite.(s,"B requires C."))
    ba=fact.("B","A",cite.(s,"B requires A."))
    limits=%{"depth"=>1,"max_nodes"=>8,"max_edges"=>8,"top_k"=>5}
    for {facts,depth,complete,edges} <- [
      {[],0,true,0},{[ab],0,false,0},{[ab],1,true,1},
      {[ab,bc],1,false,1},{[ab,bc],2,true,2},
      {[ab,ba],1,false,1},{[ab,ba],2,true,2},{[ab,ba],4,true,2}
    ] do
      {:ok,rank}=E.traverse([s],facts,"A",Map.put(limits,"depth",depth),20)
      result=E.query_scope(rank,[s],[],20)
      assert result["coverage"]["complete"]==complete
      assert result["coverage"]["edges"]==edges
      expected_status=cond do
        not complete -> "partial"
        edges==0 -> "abstain"
        true -> "ok"
      end
      assert result["status"]==expected_status
      assert Enum.all?(result["evidence"], &E.valid_span?(s,&1["citation"]))
    end
    ''')
  end

  test "graph seeds use eligible facts and complete longest entity names" do
    pure(~S'''
    s=source.("Release requires lock. Release train requires approval.",%{})
    release=fact.("Release","lock",cite.(s,"Release requires lock."))
    train=fact.("Release train","approval",cite.(s,"Release train requires approval."))
    lease=fact.("Lease","rent",cite.(s,"Release requires lock."))
    a=fact.("A","old",cite.(s,"Release requires lock."))
    {:ok,expired}=E.fact(a |> Map.drop(~w(version fact_id)) |> Map.put("valid_to_ms",20))
    {:ok,future}=E.fact(a |> Map.drop(~w(version fact_id)) |> Map.put("valid_from_ms",21))
    for facts <- [[release,train,lease,expired],[future,lease,train,release]] do
      assert {:ok,"Release train"}=E.graph_seed([s],facts,"A RELEASE train",20)
      assert {:ok,"Release"}=E.graph_seed([s],facts,"A Release",20)
      assert {:ok,"unmatched"}=E.graph_seed([s],facts,"unmatched",20)
    end
    for extra <- [%{"expires_at_ms"=>20},%{"observed_at_ms"=>21},%{"origin"=>Map.put(s["origin"],"historical",true)}] do
      stale=source.("A requires old.",Map.put(extra,"source_id","stale"))
      old=fact.("A","old",cite.(stale,"A requires old."))
      assert {:ok,"Release"}=E.graph_seed([stale,s],[old,release],"A Release",20)
    end
    forged=put_in(release,["citations",Access.at(0),"quote"],"forged")
    assert {:error,:invalid_fact}=E.graph_seed([s],[forged],"Release",20)
    ''')
  end

  test "shared excerpts retain actors and conditions and prefer a compact term cluster" do
    pure(~S'''
    text="Ada owns the migration. It proceeds only after audit. Unrelated appendix."
    s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
    for query <- ["migration","audit"] do
      assert {:ok,c}=E.excerpt(s,chunk,query)
      assert String.contains?(c["quote"],"Ada owns the migration.")
      assert String.contains?(c["quote"],"It proceeds only after audit.")
      assert E.valid_span?(s,c)
    end
    s=source.("alpha. "<>String.duplicate("unrelated ",110)<>". alpha beta.",%{})
    {:ok,[chunk]}=E.chunks(s)
    assert {:ok,c}=E.excerpt(s,chunk,"alpha beta")
    assert c["quote"]=="alpha beta."
    assert c["end_byte"]==byte_size(s["text"])
    assert E.valid_span?(s,c)
    ''')
  end

  test "normalized lexical matches keep original UTF8 byte offsets" do
    pure(~S'''
    text=String.duplicate("x ",600)<>"İstanbul"
    s=source.(text,%{})
    for query <- ["İstanbul","i","stanbul"] do
      {:ok,r}=E.rank_lexical([s],query,5,20)
      [hit]=r["evidence"]
      assert hit["citation"]["start_byte"]<=1200
      assert hit["citation"]["end_byte"]>=1200+byte_size("İstanbul")
      assert String.ends_with?(hit["citation"]["quote"],"İstanbul")
      assert E.valid_span?(s,hit["citation"])
    end
    later=source.(String.duplicate("é ",700)<>"İstanbul",%{})
    {:ok,r}=E.rank_lexical([later],"stanbul",5,20)
    [hit]=r["evidence"]
    assert hit["citation"]["start_byte"]<=2100
    assert hit["citation"]["end_byte"]==byte_size(later["text"])
    assert String.ends_with?(hit["citation"]["quote"],"İstanbul")
    assert E.valid_span?(later,hit["citation"])
    ''')
  end

  test "complete short chunks and bounded long context expose their omissions" do
    pure(~S'''
    long="Migration "<>String.duplicate("x",850)<>" only after the audit completes."
    s=source.(long,%{}); {:ok,[chunk]}=E.chunks(s)
    assert byte_size(long)>512 and byte_size(long)<=1024
    assert {:ok,%{"quote"=>^long}}=E.excerpt(s,chunk,"migration")
    text="Owner Ada. Migration proceeds. Administrative note. Only after audit."
    s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
    assert {:ok,c}=E.excerpt(s,chunk,"migration")
    assert c["quote"]==text
    text="Owner Ada. Migration proceeds. "<>String.duplicate("Administrative note. ",60)<>"Only after audit."
    s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
    assert {:ok,c}=E.excerpt(s,chunk,"migration")
    assert String.starts_with?(c["quote"],"Owner Ada. Migration proceeds. ")
    refute String.contains?(c["quote"],"Only after audit")
    text="Owner Ada "<>String.duplicate("x",1050)<>". Migration proceeds. Only after audit."
    s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
    assert {:ok,c}=E.excerpt(s,chunk,"migration")
    assert c["quote"]=="Migration proceeds. Only after audit."
    refute String.contains?(c["quote"],"Owner Ada")
    text="Migration "<>String.duplicate("x",1200)<>" only after audit."
    s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
    assert {:ok,c}=E.excerpt(s,chunk,"migration")
    assert byte_size(c["quote"])==1024
    assert String.starts_with?(c["quote"],"Migration ")
    refute String.contains?(c["quote"],"only after audit")
    assert E.valid_span?(s,c)
    ''')
  end

  test "mechanical boundaries and unmatched prefixes retain literal original bytes" do
    pure(~S'''
    for text <- ["Dr. Rowan owns version 3.14.\r\nRelease requires review!\nNext step? Done.",
                 "Owner says \"ready.\" Release proceeds only after audit.",
                 String.duplicate("é ",600)<>"release"] do
      s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
      assert {:ok,c}=E.excerpt(s,chunk,"release")
      assert E.valid_span?(s,c)
      assert c["quote"]==binary_part(text,c["start_byte"],c["end_byte"]-c["start_byte"])
      assert String.contains?(String.downcase(c["quote"]),"release")
    end
    for {count,kept} <- [{200,200},{400,341}], query <- ["absent","?!",""] do
      s=source.(String.duplicate("A. ",count),%{}); {:ok,[chunk]}=E.chunks(s)
      assert {:ok,c}=E.excerpt(s,chunk,query)
      assert c["quote"]==String.duplicate("A. ",kept)
      assert c["start_byte"]==0 and c["end_byte"]==3*kept
    end
    s=source.("A.",%{}); {:ok,[chunk]}=E.chunks(s)
    assert {:error,:invalid_query}=E.excerpt(s,chunk,String.duplicate("x",1025))
    assert {:error,:invalid_query}=E.rank_remote([],[],nil,1,20)
    assert {:error,:invalid_span}=E.excerpt(s,Map.put(chunk,"chunk_id",E.sha256("forged")),"a")
    ''')
  end

  test "coverage core agrees with exhaustive bounded windows on varied long lines" do
    pure(~S'''
    for seed <- 1..40 do
      :rand.seed(:exsss,{seed,seed+1,seed+2})
      words=Enum.map(1..35, fn _ ->
        Enum.at(~w(alpha beta gamma unrelated),:rand.uniform(4)-1)<>
          String.duplicate(" ",:rand.uniform(22))
      end)
      text=String.duplicate("x",520)<>" "<>Enum.join(words)<>String.duplicate("y",520)
      assert byte_size(text)>1024 and byte_size(text)<=2048
      hits=Regex.scan(~r/alpha|beta|gamma/,text,return: :index)
        |> Enum.map(fn [{start,size}] -> {start,start+size,binary_part(text,start,size)} end)
      trials=for {start,_,_}<-hits, {_,finish,_}<-hits, finish>start,
        finish-start<=1024 do
        covered=hits |> Enum.filter(fn {a,b,_}-> a>=start and b<=finish end)
          |> Enum.map(&elem(&1,2)) |> Enum.uniq() |> length()
        {-covered,finish-start,start,finish}
      end
      {_,size,start,finish}=Enum.min(trials)
      target=1024
      left=max(0,start-div(target-size,2))
      right=min(byte_size(text),left+target)
      left=max(0,right-target)
      s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
      assert {:ok,c}=E.excerpt(s,chunk,"alpha beta gamma")
      assert {c["start_byte"],c["end_byte"]}=={left,right}
      assert c["start_byte"]<=start and c["end_byte"]>=finish
      assert E.valid_span?(s,c)
    end
    ''')
  end

  test "huge original tokens and combining graphemes never invent normalized byte spans" do
    pure(~S'''
    for text <- [String.duplicate("İ",520)<>" owner i",
                 "a"<>String.duplicate(<<0x0301::utf8>>,600),
                 String.duplicate("😀",180)<>" migration "<>String.duplicate("😀",180)] do
      s=source.(text,%{}); {:ok,[chunk]}=E.chunks(s)
      assert {:ok,c}=E.excerpt(s,chunk,"i migration")
      assert E.valid_span?(s,c)
      assert String.valid?(c["quote"]) and byte_size(c["quote"])<=1024
      assert c["quote"]==binary_part(text,c["start_byte"],c["end_byte"]-c["start_byte"])
      if String.starts_with?(text,"İ"), do: assert(String.ends_with?(c["quote"],"owner i"))
    end
    ''')
  end

  test "selected whole excerpts expose the exact answer packing tradeoff" do
    pure(~S'''
    Code.require_file("dev/evaluation/answer.exs")
    alias Ipse.Development.Evaluation.Answer, as: Answer
    query="release "<>String.duplicate("z",56)
    assert byte_size(query)==64
    candidates=fn size, filler ->
      quote="Release "<>String.duplicate(filler,size-byte_size("Release  only after audit."))<>" only after audit."
      assert byte_size(quote)==size
      Enum.map(1..6,fn n ->
        s=source.("Preface "<>String.duplicate("x",900)<>". "<>quote,
          %{"source_id"=>String.pad_leading(Integer.to_string(n),16,"s"),"observed_at_ms"=>1700000000000})
        {:ok,[chunk]}=E.chunks(s)
        assert {:ok,c}=E.excerpt(s,chunk,query)
        assert c["quote"]==quote and E.valid_span?(s,c)
        %{"citation"=>c}
      end)
    end
    short=candidates.(480,"x")
    assert {:ok,compact}=Answer.prepare(query,1700000020000,short)
    assert length(compact["shown"])==6
    assert byte_size(compact["request"]["input"])<=4096
    long=candidates.(900,"x")
    assert {:ok,whole}=Answer.prepare(query,1700000020000,long)
    assert length(whole["shown"])==3
    assert byte_size(whole["request"]["input"])<=4096
    original=JSON.decode!(whole["request"]["input"])
    fourth=hd(Enum.drop(long,3))["citation"] |> Map.take(~w(source_id generation observed_at_ms event_at_ms quote))
      |> Map.put("id","e4")
    assert byte_size(JSON.encode!(Map.update!(original,"candidates",&(&1++[fourth]))))>4096
    assert Enum.map(whole["shown"],& &1["citation"])==Enum.take(long,3)|>Enum.map(& &1["citation"])
    assert Enum.all?(whole["shown"],&String.ends_with?(&1["citation"]["quote"],"only after audit."))
    assert length(whole["coverage"]["omitted"])==3
    assert {:ok,escaped}=Answer.prepare(query,1700000020000,candidates.(480,"\""))
    assert length(escaped["shown"])<6
    assert Enum.all?(escaped["shown"],&(&1["cropped"]==false))
    assert byte_size(escaped["request"]["input"])<=4096
    ''')
  end

  test "negative context remains attributable without reaching its object" do
    pure(~S'''
    s=source.("Release does not require lock. Lock requires exit.",%{})
    negative=fact.("Release","lock",cite.(s,"Release does not require lock."))
    {:ok,negative}=E.fact(negative |> Map.drop(~w(version fact_id)) |> Map.put("polarity","negative"))
    descendant=fact.("lock","exit",cite.(s,"Lock requires exit."))
    limits=%{"depth"=>2,"max_nodes"=>8,"max_edges"=>8,"top_k"=>1}
    {:ok,rank}=E.traverse([s],[negative,descendant],"Release",limits,20)
    result=E.query_scope(rank,[s],[],20)
    assert result["status"]=="ok" and result["coverage"]["complete"]
    assert result["coverage"]["edges"]==0 and result["coverage"]["nodes"]==1
    assert result["coverage"]["seed"]=="Release"
    assert result["coverage"]["negative_context"]==1
    assert Enum.map(result["claims"],& &1["fact_id"])==[negative["fact_id"]]
    assert hd(result["claims"])["basis"]==negative["citations"]
    ''')
  end

  test "every graph support is checked through suppression replacement and polarity" do
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
    forged=put_in(first,["citations",Access.at(0),"quote"],"forged")
    assert {:error,:invalid_fact}=E.validate_facts([s],[forged],20)
    {:ok,negative}=E.fact(first |> Map.drop(~w(version fact_id)) |> Map.put("polarity","negative"))
    {:ok,no_path}=E.traverse([s],[negative,second],"Release",limits,20)
    assert Enum.map(no_path["claims"],& &1["fact_id"])==[negative["fact_id"]]
    assert no_path["coverage"]["edges"]==0
    ''')
  end

  test "positive relationships can retain several compatible requirements" do
    pure(~S'''
    s=source.("Release requires quiescence. Release requires tests.",%{})
    first=fact.("Release","quiescence",cite.(s,"Release requires quiescence."))
    second=fact.("Release","tests",cite.(s,"Release requires tests."))
    limits=%{"depth"=>2,"max_nodes"=>8,"max_edges"=>8,"top_k"=>10}
    for facts <- [[first,second],[second,first]] do
      {:ok,claims}=E.classify([],facts,"Release")
      assert Enum.all?(claims,&(&1["label"]=="supported"))
      {:ok,result}=E.traverse([s],facts,"Release",limits,20)
      assert result["coverage"]["complete"] and result["coverage"]["edges"]==2
      assert result["coverage"]["context_facts"]==2 and result["coverage"]["counterassertions"]==0
      assert Enum.all?(result["claims"],&(&1["label"]=="supported"))
      assert Map.new(result["claims"],&{&1["fact_id"],&1["basis"]})==Map.new(facts,&{&1["fact_id"],&1["citations"]})
    end
    ''')
  end

  test "graph conflict context preserves opposing polarity and every basis beyond top k" do
    pure(~S'''
    s=source.("Release requires lock. Release does not require lock.",%{})
    positive=fact.("Release","lock",cite.(s,"Release requires lock."))
    {:ok,negative}=E.fact(positive |> Map.drop(~w(version fact_id)) |> Map.merge(%{"polarity"=>"negative","citations"=>[cite.(s,"Release does not require lock.")]}))
    limits=%{"depth"=>2,"max_nodes"=>128,"max_edges"=>256,"top_k"=>1}
    {:ok,result}=E.traverse([s],[negative,positive,negative],"Release",limits,20)
    assert result["coverage"]["complete"]
    assert result["coverage"]["edges"]==1 and result["coverage"]["nodes"]==2
    assert result["coverage"]["context_facts"]==2 and result["coverage"]["counterassertions"]==1
    assert length(result["evidence"])==1
    assert Enum.map(result["claims"],& &1["fact_id"])==[positive["fact_id"],negative["fact_id"]]
    assert Enum.map(result["claims"],& &1["polarity"])==["positive","negative"]
    assert Enum.all?(result["claims"],&(&1["label"]=="conflict"))
    assert Enum.map(result["claims"],& &1["basis"])==[positive["citations"],negative["citations"]]
    assert E.public_claims(result["evidence"],result["claims"])==result["claims"]
    assert hd(result["evidence"])["citation"]==hd(positive["citations"])
    {:ok,no_path}=E.traverse([s],[negative],"Release",limits,20)
    assert hd(no_path["claims"])["polarity"]=="negative"
    assert hd(no_path["claims"])["basis"]==negative["citations"]
    assert no_path["coverage"]["edges"]==0 and no_path["coverage"]["nodes"]==1
    assert no_path["coverage"]["context_facts"]==1 and no_path["coverage"]["counterassertions"]==0
    ''')
  end

  test "graph conflict identity ignores object case while preserving exact fact attribution" do
    pure(~S'''
    s=source.("Release requires lock. RELEASE does not require LOCK. Release requires LOCK.",%{})
    positive=fact.("Release","lock",cite.(s,"Release requires lock."))
    {:ok,negative}=E.fact(positive |> Map.drop(~w(version fact_id)) |> Map.merge(%{"subject"=>"RELEASE","predicate"=>"REQUIRES","object"=>"LOCK","polarity"=>"negative","citations"=>[cite.(s,"RELEASE does not require LOCK.")]}))
    equivalent=fact.("RELEASE","LOCK",cite.(s,"Release requires LOCK."))
    limits=%{"depth"=>1,"max_nodes"=>2,"max_edges"=>2,"top_k"=>1}
    for facts <- [[positive,negative],[negative,positive],[positive,equivalent],[equivalent,positive]] do
      expected=if Enum.any?(facts,&(&1["polarity"]=="negative")),do: "conflict",else: "supported"
      {:ok,direct}=E.classify([],facts,"release")
      assert Enum.all?(direct,&(&1["label"]==expected))
      {:ok,result}=E.traverse([s],facts,"release",limits,20)
      assert result["coverage"]["complete"]
      assert result["coverage"]["nodes"]==2 and result["coverage"]["context_facts"]==2
      assert result["coverage"]["edges"]==if(expected=="conflict",do: 1,else: 2)
      assert result["coverage"]["counterassertions"]==if(expected=="conflict",do: 1,else: 0)
      assert length(result["evidence"])==1
      assert Enum.all?(result["claims"],&(&1["label"]==expected))
      assert Map.new(result["claims"],&{&1["fact_id"],Map.take(&1,~w(subject predicate object polarity))})==
        Map.new(facts,&{&1["fact_id"],Map.take(&1,~w(subject predicate object polarity))})
      assert Map.new(result["claims"],&{&1["fact_id"],&1["basis"]})==Map.new(facts,&{&1["fact_id"],&1["citations"]})
      assert E.public_claims(result["evidence"],result["claims"])==result["claims"]
    end
    ''')
  end

  test "graph counterassertions exclude unrelated inactive and replaced assertions" do
    pure(~S'''
    s=source.("Release requires lock. Release does not require lock.",%{})
    positive=fact.("Release","lock",cite.(s,"Release requires lock."))
    attrs=positive |> Map.drop(~w(version fact_id)) |> Map.merge(%{"polarity"=>"negative","citations"=>[cite.(s,"Release does not require lock.")]})
    {:ok,unrelated}=E.fact(Map.put(attrs,"subject","Other"))
    {:ok,other_predicate}=E.fact(Map.put(attrs,"predicate","owns"))
    {:ok,other_object}=E.fact(Map.put(attrs,"object","other"))
    {:ok,expired}=E.fact(Map.put(attrs,"valid_to_ms",20))
    {:ok,future}=E.fact(Map.put(attrs,"valid_from_ms",21))
    old=source.(s["text"],%{"source_id"=>"old"})
    {:ok,replaced}=E.fact(Map.put(attrs,"citations",[cite.(old,"Release does not require lock.")]))
    limits=%{"depth"=>2,"max_nodes"=>128,"max_edges"=>256,"top_k"=>10}
    for negative <- [unrelated,expired,future,replaced] do
      {:ok,result}=E.traverse([s,Map.put(old,"generation",2)],[positive,negative],"Release",limits,20)
      assert [%{"label"=>"supported","polarity"=>"positive","basis"=>basis}]=result["claims"]
      assert basis==positive["citations"]
      assert result["coverage"]["context_facts"]==1 and result["coverage"]["counterassertions"]==0
    end
    for negative <- [other_predicate,other_object] do
      {:ok,result}=E.traverse([s],[positive,negative],"Release",limits,20)
      assert Enum.map(result["claims"],& &1["fact_id"])==[positive["fact_id"],negative["fact_id"]]
      assert Enum.all?(result["claims"],&(&1["label"]=="supported"))
      assert result["coverage"]["context_facts"]==2 and result["coverage"]["counterassertions"]==0
      assert result["coverage"]["negative_context"]==1
    end
    ''')
  end

  test "a cut positive alternative stays outside conflict context and leaves coverage partial" do
    pure(~S'''
    s=source.("Release requires lock. Release requires quiescence. Lock requires exit. Quiescence requires exit.",%{})
    first=fact.("Release","lock",cite.(s,"Release requires lock."))
    second=fact.("Release","quiescence",cite.(s,"Release requires quiescence."))
    descendants=[fact.("lock","exit",cite.(s,"Lock requires exit.")),fact.("quiescence","exit",cite.(s,"Quiescence requires exit."))]
    selected=Enum.min_by([first,second],& &1["fact_id"])
    limits=%{"depth"=>3,"max_nodes"=>128,"max_edges"=>1,"top_k"=>1}
    {:ok,result}=E.traverse([s],descendants++[second,first],"Release",limits,20)
    refute result["coverage"]["complete"]
    assert result["coverage"]["edges"]==1 and result["coverage"]["nodes"]==2
    assert result["coverage"]["context_facts"]==1 and result["coverage"]["counterassertions"]==0
    assert Enum.map(result["claims"],& &1["fact_id"])==[selected["fact_id"]]
    assert Enum.all?(result["claims"],&(&1["label"]=="supported" and &1["polarity"]=="positive"))
    assert Enum.map(result["claims"],& &1["basis"])==[selected["citations"]]
    assert length(result["evidence"])==1
    assert E.query_scope(result,[s],[],20)["status"]=="partial"
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
    {:ok,r}=E.rank_remote([s],[ref], "release", 5, 20)
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
    assert {:ok,[^hit]}=E.apply_rerank(r["evidence"],[E.candidate_id(hit)])
    ''')
  end

  test "remote score order is preserved with deterministic ties and exact reference identity" do
    pure(~S'''
    a=source.("alpha",%{}); b=source.("beta",%{"source_id"=>"second"})
    refs=Enum.map([a,b],fn s -> {:ok,[c]}=E.chunks(s);Map.take(s,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>c["chunk_id"],"score"=>1.0}) end)
    {:ok,ties}=E.rank_remote([a,b],refs, "release", 5, 20)
    assert {:ok,^ties}=E.rank_remote([a,b],Enum.reverse(refs), "release", 5, 20)
    ranked=[Map.put(hd(refs),"score",-3),Map.put(List.last(refs),"score",0)]
    {:ok,result}=E.rank_remote([a,b],ranked, "release", 5, 20)
    assert Enum.map(result["evidence"],& &1["score"])==[0,-3]
    assert hd(result["evidence"])["citation"]["source_id"]=="second"
    assert {:error,:invalid_remote_refs}=E.rank_remote([a,b],[hd(refs),hd(refs)], "release", 5, 20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([a,b],List.duplicate(hd(refs),11), "release", 10, 20)
    assert {:error,:invalid_sources}=E.rank_remote([a,b],refs, "release", 0, 20)
    ''')
  end

  test "forged remote selection metadata cannot select different content or partitions" do
    pure(~S'''
    s=source.("captured evidence",%{});{:ok,[chunk]}=E.chunks(s)
    ref=Map.take(s,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>chunk["chunk_id"],"score"=>1.0})
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"source_id","other")], "release", 5, 20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"partition","other")], "release", 5, 20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"score",:nan)], "release", 5, 20)
    assert {:error,:invalid_remote_refs}=E.rank_remote([s],[Map.put(ref,"generation",0)], "release", 5, 20)
    for field<-~w(content_sha256 chunk_id) do
      assert {:error,:invalid_remote_selection}=E.rank_remote([s],[Map.put(ref,field,String.duplicate("0",64))], "release", 5, 20)
    end
    assert {:error,:invalid_remote_selection}=E.rank_remote([s],[Map.put(ref,"generation",2)], "release", 5, 20)
    assert {:error,:invalid_remote_selection}=E.rank_remote([], [ref], "release", 5, 20)
    other=source.("foreign",%{"source_id"=>"second","partition"=>"other"})
    assert {:error,:invalid_remote_selection}=E.rank_remote([s,other],[ref], "release", 5, 20)
    assert {:error,:invalid_sources}=E.rank_remote([Map.put(s,"text","tampered")],[ref], "release", 5, 20)
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
      assert {:error,:invalid_remote_selection}=E.rank_remote([stale],[ref], "release", 5, 20)
    end
    live=source.("live",%{"source_id"=>"second"});{:ok,[c]}=E.chunks(live)
    live_ref=Map.take(live,~w(source_id source_key generation content_sha256))|>Map.merge(%{"chunk_id"=>c["chunk_id"],"score"=>2.0})
    assert {:error,:invalid_remote_selection}=E.rank_remote([live],[live_ref,ref], "release", 5, 20)
    {:ok,empty}=E.rank_remote([],[], "release", 5, 20)
    assert empty["evidence"]==[] and empty["claims"]==[] and empty["gaps"]==[]
    assert empty["coverage"]["sources"]==0 and empty["coverage"]["chunks"]==0
    assert empty["coverage"]["score_provenance"]=="server_asserted"
    ''')
  end
end
