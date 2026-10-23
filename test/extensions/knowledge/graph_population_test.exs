defmodule Ipse.KnowledgeGraphPopulationTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)
  @suite ~S"""
  ExUnit.start(autorun: false)
  for file <- ~w(evidence profiles store/state store/mcp_cas store adapters graph) do
    Code.require_file("extensions/knowledge/src/" <> file <> ".ex")
  end
  corpus=File.read!("extensions/knowledge/src/corpus.ex")
    |>String.replace(~s(@preset "state-lexical"),~s(@preset "state-dense"))
  Code.compile_string(corpus,"extensions/knowledge/src/corpus.ex")
  Code.require_file("dev/verification/scenarios.exs")
  Code.require_file("dev/verification/runtime.exs")
  Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)

  defmodule PopulationDriver do
    import ExUnit.Assertions
    alias IpseKnowledge.{Evidence,Graph,Corpus}
    alias Ipse.Development.Fixtures.Knowledge,as: F
    def invoke(module,state,db,id,args) do
      assert Ipse.Extension.validate(args)==:ok
      run(module,module.handle("invoke.command",%{"id"=>id,"arguments"=>args},state),db)
    end
    def run(module,{:ok,%{"kind"=>"host_call","request"=>request},state},db) do
      {outcome,db}=host(db,request)
      run(module,module.handle("host.actions",%{"outcome"=>outcome},state),db)
    end
    def run(_,{:ok,%{"kind"=>"result","value"=>value},state},db),do: {value,state,db}
    def run(_,{:ok,%{bytes: bytes},state},db),do: {JSON.decode!(bytes),state,db}
    defp host(db,%{"op"=>"embedding.create"}=request) do
      bytes=<<1.0::little-float-size(32)>>
      descriptor=%{"version"=>2,"operation_id"=>String.duplicate("1",32),"kind"=>"embedding.f32le",
        "encoding"=>"float32le.base64","vector_count"=>1,"dimensions"=>1,"source_sha256"=>Evidence.sha256(bytes)}
      page=Map.merge(Map.drop(descriptor,["vector_count"]),%{"vector_index"=>0,"offset"=>0,
        "complete"=>true,"next"=>nil,"input_sha256"=>Evidence.sha256(hd(request["inputs"])),
        "vector_sha256"=>Evidence.sha256(bytes),"values"=>Base.encode64(bytes)})
      value=%{"version"=>2,"profile"=>request["profile"],"selection_sha256"=>Evidence.sha256("fixture encoder"),
        "reported_model"=>"fixture","result"=>descriptor,"usage"=>nil}
      {%{"status"=>"ok","value"=>value},db|>Map.put(:embedding_page,page)|>Map.update!(:requests,&[request|&1])}
    end
    defp host(db,%{"op"=>"effect.result.read","version"=>2}=request),
      do: {%{"status"=>"ok","value"=>db.embedding_page},Map.update!(db,:requests,&[request|&1])}
    defp host(db,request),do: F.host(db,request)

    def initial do
      empty=Map.new(~w(stores search fetch retrieval embedding rerank extraction),&{&1,%{}})
      base=Map.merge(empty,%{"version"=>1,"stores"=>%{"notes"=>%{"kind"=>"state","scope"=>"project","partition"=>"notes"}}})
      {:ok,graph}=Graph.init(Map.put(base,"extraction",%{"given"=>%{"kind"=>"explicit","version"=>1}}))
      retrieval=%{"words"=>%{"kind"=>"bm25","version"=>1},
        "graph"=>%{"kind"=>"graph","version"=>1,"lexical"=>"words","depth"=>1,"max_nodes"=>128,"max_edges"=>256},
        "hybrid"=>%{"kind"=>"hybrid","version"=>1,"lexical"=>"words","embedding"=>"native","graph"=>"graph","rrf_k"=>60,"missing_embedding"=>"lexical_with_gap"}}
      {:ok,corpus}=Corpus.init(base|>Map.put("retrieval",retrieval)|>Map.put("embedding",%{"native"=>%{"kind"=>"embedding","profile"=>"encoder"}}))
      refute Map.has_key?(graph,:invalid)
      refute Map.has_key?(corpus,:invalid)
      {graph,corpus,F.new()}
    end
    def source(graph,db,id,expires \\ nil) do
      attrs=%{"source_id"=>id,"generation"=>1,"expected_revision"=>0,"title"=>"S","text"=>"A",
        "uri"=>"local:a","observed_at_ms"=>1,"event_at_ms"=>nil,"expires_at_ms"=>expires}
      {result,graph,db}=invoke(Graph,graph,db,"source",%{"store"=>"notes","action"=>"put","args"=>attrs})
      assert result["status"]=="ok"
      {:ok,source}=Evidence.source(Map.drop(attrs,["expected_revision"])|>Map.merge(%{"partition"=>"notes",
        "origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}}))
      {:ok,[chunk]}=Evidence.chunks(source)
      {graph,db,source,chunk}
    end
    def fact(source,attrs) do
      {:ok,[chunk]}=Evidence.chunks(source)
      {:ok,citation}=Evidence.citation(source,chunk,0,1)
      {:ok,fact}=Evidence.fact(Map.merge(%{"subject"=>"entity1","predicate"=>"has","object"=>"object1",
        "polarity"=>"positive","inferred"=>false,"valid_from_ms"=>nil,"valid_to_ms"=>nil,
        "extraction"=>%{"kind"=>"explicit","profile"=>nil,"version"=>1},"citations"=>[citation]},attrs))
      fact
    end
    def extract(graph,db,source,chunk,facts) do
      Enum.reduce(Enum.chunk_every(facts,8),{graph,db},fn batch,{graph,db}->
        args=%{"store"=>"notes","extraction"=>"given","source_id"=>source["source_id"],"generation"=>1,
          "max_edges"=>8,"chunks"=>[chunk["chunk_id"]],"facts"=>batch}
        {result,graph,db}=invoke(Graph,graph,db,"extract",args)
        assert result["status"]=="ok",inspect(result)
        {graph,db}
      end)
    end
    def index(corpus,db,source,chunk) do
      {result,corpus,db}=invoke(Corpus,corpus,db,"index",%{"store"=>"notes","embedding"=>"native",
        "source_id"=>source["source_id"],"generation"=>1,"action"=>"next","chunks"=>[chunk["chunk_id"]]})
      assert result["status"]=="ok",inspect(result)
      {corpus,db}
    end
    def query(:graph,graph,_corpus,db,now) do
      {result,_,_}=invoke(Graph,graph,db,"query",%{"store"=>"notes","entity"=>"entity1","depth"=>1,
        "max_nodes"=>128,"max_edges"=>256,"top_k"=>1,"as_of_ms"=>now})
      result
    end
    def query(route,_graph,corpus,db,now) do
      retrieval=if route==:corpus_graph,do: "graph",else: "hybrid"
      {result,_,_}=invoke(Corpus,corpus,db,"query",%{"store"=>"notes","retrieval"=>retrieval,
        "rerank"=>nil,"query"=>"entity1","top_k"=>1,"as_of_ms"=>now})
      result
    end
  end

  defmodule GraphPopulationSuite do
    use ExUnit.Case,async: false
    alias PopulationDriver,as: D
    alias IpseKnowledge.Evidence,as: E
    @tag timeout: 120000
    test "public Graph and Corpus query261 facts including expired data and remote contradictions" do
      {graph,corpus,db}=D.initial()
      {graph,corpus,db,sources,facts}=Enum.reduce(1..9,{graph,corpus,db,[],[]},fn n,{graph,corpus,db,sources,facts}->
        {graph,db,source,chunk}=D.source(graph,db,"s#{n}",if(n==9,do: 20))
        batch=for i<-1..29,do: D.fact(source,%{"subject"=>"entity#{n}","object"=>"object#{i}"})
        {graph,db}=D.extract(graph,db,source,chunk,batch)
        {corpus,db}=D.index(corpus,db,source,chunk)
        {graph,corpus,db,sources++[source],facts++batch}
      end)
      assert length(facts)==261 and map_size(db.records)==162
      expected=Map.new(Enum.take(facts,29),&{&1["fact_id"],&1["citations"]})
      for now<-[10,20],route<-[:graph,:corpus_graph,:hybrid] do
        result=D.query(route,graph,corpus,db,now)
        assert result["status"]=="ok",inspect(result)
        assert result["coverage"]["complete"]
        assert Map.new(result["claims"],&{&1["fact_id"],&1["basis"]})==expected
        assert length(result["evidence"])==1
        if now==20,do: assert(Enum.any?(result["gaps"],&(&1["code"]=="excluded_fact")))
      end
      first=IpseKnowledge.Store.root_key("notes",hd(sources)["source_key"])
      second=IpseKnowledge.Store.root_key("notes",Enum.at(sources,1)["source_key"])
      {head_id,head}=Enum.find(db.records[first]["value"]["projections"],fn {_,head}->head["kind"]=="facts" end)
      duplicated=put_in(db.records[first]["value"]["projections"][E.sha256("other head")],head)
      cross_source=put_in(db.records[second]["value"]["projections"][head_id],head)
      for invalid<-[duplicated,cross_source],route<-[:graph,:corpus_graph,:hybrid] do
        result=D.query(route,graph,corpus,invalid,10)
        assert result["status"]=="refused" and result["gaps"]==[%{"code"=>"projection_corrupt"}]
        assert result["claims"]==[] and result["evidence"]==[]
      end
      negative=D.fact(List.last(sources),%{"polarity"=>"negative"})
      {:ok,[chunk]}=E.chunks(List.last(sources))
      {graph,db}=D.extract(graph,db,List.last(sources),chunk,[negative])
      for route<-[:graph,:corpus_graph,:hybrid] do
        result=D.query(route,graph,corpus,db,10)
        assert result["status"]=="ok" and length(result["claims"])==30
        assert Enum.count(result["claims"],&(&1["label"]=="conflict"))==2
        assert Enum.find(result["claims"],&(&1["fact_id"]==negative["fact_id"]))["basis"]==negative["citations"]
        assert Map.new(result["claims"],&{&1["fact_id"],&1["basis"]})|>Map.delete(negative["fact_id"])==expected
        expired=D.query(route,graph,corpus,db,20)
        assert expired["status"]=="ok" and expired["coverage"]["complete"]
        assert length(expired["claims"])==29 and Enum.all?(expired["claims"],&(&1["label"]=="supported"))
      end
    end

    @tag timeout: 120000
    test "public256-context success and257-context refusal agree across graph and hybrid routes" do
      {graph,corpus,db}=D.initial()
      {graph,db,source,chunk}=D.source(graph,db,"positive")
      facts=for i<-1..256,do: D.fact(source,%{"predicate"=>"p#{i}","object"=>"B"})
      {graph,db}=D.extract(graph,db,source,chunk,facts)
      {corpus,db}=D.index(corpus,db,source,chunk)
      {graph,db,other,chunk}=D.source(graph,db,"negative",20)
      negative=D.fact(other,%{"predicate"=>"p1","object"=>"B","polarity"=>"negative"})
      {graph,db}=D.extract(graph,db,other,chunk,[negative])
      {corpus,db}=D.index(corpus,db,other,chunk)
      for route<-[:graph,:corpus_graph,:hybrid] do
        success=D.query(route,graph,corpus,db,20)
        assert success["status"]=="ok" and success["coverage"]["complete"]
        assert length(success["claims"])==256 and Enum.all?(success["claims"],&(&1["label"]=="supported"))
        refused=D.query(route,graph,corpus,db,10)
        assert refused["status"]=="refused" and refused["gaps"]==[%{"code"=>"graph_context_limit"}]
        assert refused["claims"]==[] and refused["evidence"]==[]
      end
    end

    test "all facts validate before eligibility and the derived population ceiling remains finite" do
      {graph,_,db}=D.initial()
      {_,_,source,_}=D.source(graph,db,"one",20)
      fact=D.fact(source,%{})
      {:ok,validated}=E.validate_facts([source],List.duplicate(fact,256*32),10)
      assert length(validated["facts"])==256*32
      too_many=List.duplicate(fact,256*32+1)
      limits=%{"depth"=>1,"max_nodes"=>128,"max_edges"=>256,"top_k"=>1}
      assert {:error,:invalid_fact}=E.validate_facts([source],too_many,10)
      assert {:error,:invalid_fact}=E.graph_seed([source],too_many,"entity1",10)
      assert {:error,:invalid_fact}=E.traverse([source],too_many,"entity1",limits,10)
      citation=hd(fact["citations"])|>Map.put("quote","B")|>Map.put("quote_sha256",E.sha256("B"))
      {:ok,forged}=E.fact(Map.drop(fact,~w(version fact_id))|>Map.put("subject","unrelated")|>Map.put("citations",[citation]))
      for now<-[10,20] do
        input=List.duplicate(fact,260)++[forged]
        assert {:error,:invalid_span}=E.validate_facts([source],input,now)
        assert {:error,:invalid_span}=E.graph_seed([source],input,"entity1",now)
        assert {:error,:invalid_span}=E.traverse([source],input,"entity1",limits,now)
      end
    end

    test "negative context cannot be dropped to fit a one-edge traversal" do
      {graph,_,db}=D.initial()
      {_,_,source,_}=D.source(graph,db,"context")
      positive=D.fact(source,%{})
      negatives=for i<-1..256,do: D.fact(source,%{"polarity"=>"negative","predicate"=>"p#{i}"})
      limits=%{"depth"=>1,"max_nodes"=>2,"max_edges"=>1,"top_k"=>1}
      {:ok,within}=E.traverse([source],[positive|Enum.take(negatives,255)],"entity1",limits,10)
      assert within["coverage"]["context_facts"]==256 and length(within["claims"])==256
      assert within["coverage"]["edges"]==1 and within["coverage"]["negative_context"]==255
      assert {:error,:graph_context_limit}=E.traverse([source],[positive|negatives],"entity1",limits,10)
    end
  end
  result=ExUnit.run()
  System.halt(if(result.failures==0,do: 0,else: 1))
  """

  @tag timeout: 180_000
  test "query population controls run in an isolated domain VM" do
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", @suite],
        cd: @root,
        stderr_to_stdout: true
      )

    assert status == 0, output

    for module <- [IpseKnowledge.Evidence, IpseKnowledge.Graph, IpseKnowledge.Corpus],
        do: refute(Code.ensure_loaded?(module))
  end
end
