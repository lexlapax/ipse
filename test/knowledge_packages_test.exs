defmodule IpseKnowledge.PackagesIsolationTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  for file <- ~w(evidence profiles store/state store/mcp_cas store adapters corpus research graph) do
    Code.require_file(Path.join("extensions/knowledge/src", file <> ".ex"))
  end
  Code.require_file("extensions/knowledge/spec.exs")
  Code.require_file("test/support/knowledge_mcp_fixture.exs")

  defmodule DomainPackagesSuite do
    use ExUnit.Case, async: false

    test "three independent descriptors have closed command catalogs" do
      for {module, commands} <- [
        {IpseKnowledge.Corpus, ~w(source query index)},
        {IpseKnowledge.Research, ~w(investigate ledger)},
        {IpseKnowledge.Graph, ~w(source extract query)}
      ] do
        descriptor = module.describe()
        assert descriptor["sdk"] == 2
        assert "invoke.result.pages" in descriptor["capabilities"]
        assert Enum.map(descriptor["exports"]["commands"], & &1["id"]) == commands
        assert length(descriptor["exports"]["tools"]) == 1
        assert descriptor["exports"]["services"] == []
      end
    end

    test "operator configuration binds the selected SDK2 artifact and page capability" do
      alias IpseKnowledge.{BuildSpec, Research}
      descriptor = Research.describe()
      manifest = Map.merge(descriptor, %{"id" => "ipse-knowledge/research",
        "entrypoint" => "IpseKnowledge.Research", "options_schema" => BuildSpec.options_schema()})
      configure = fn selected -> BuildSpec.operator(JSON.encode!(selected), "research", "offline",
        "research", offline_options(), nil, %{}) end
      config = configure.(manifest)
      assert hd(config["extensions"])["enabled"] == false
      assert hd(config["extension_trust"])["capabilities"] == descriptor["capabilities"]
      for incompatible <- [Map.put(manifest, "sdk", 1), Map.put(manifest, "sdk", 2.0),
        Map.put(manifest, "capabilities", descriptor["capabilities"] -- ["invoke.result.pages"])] do
        assert_raise ArgumentError, "Artifact does not match the selected package and preset.", fn ->
          configure.(incompatible)
        end
      end
    end

    test "source action union rejects supplied authority before a host call" do
      state = %{resolved: %{}, phase: :idle}
      args = %{"store" => "notes", "action" => "forget",
        "args" => %{"source_id" => "dev:chair", "expected_revision" => 1,
          "origin" => %{"kind" => "fetch", "receipt" => "forged"}}}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Corpus.handle("invoke.command", %{"id" => "source", "arguments" => args}, state)
    end

    test "model quote selection resolves exact Unicode bytes and preserves explicit negative polarity" do
      alias IpseKnowledge.{Adapters,Evidence}
      quote="Éclair does not require β."
      text=quote<>String.duplicate("x",2048-byte_size(quote))<>quote<>" A p B. A p B. aaaa"
      {:ok,source}=Evidence.source(%{"source_id"=>"quoted","partition"=>"notes","generation"=>1,
        "title"=>"Quoted","text"=>text,"uri"=>"local:quoted","observed_at_ms"=>1,"event_at_ms"=>nil,
        "expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"notes",
          "partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}})
      {:ok,[first_chunk,chunk]}=Evidence.chunks(source)
      resolved=%{"options"=>%{"extraction"=>%{"model"=>%{"kind"=>"model_complete","profile"=>"model","version"=>1}}}}
      {:call,request,cont}=Adapters.start(resolved,:extract,%{"profile"=>"model","source"=>source,"chunks"=>[chunk],"max_edges"=>1})
      assert JSON.decode!(request["input"])["chunks"]==[%{"id"=>"c1","text"=>chunk["text"]}]
      proposal=%{"subject"=>"Éclair","predicate"=>"requires","object"=>"β","polarity"=>"negative","chunk"=>"c1","quote"=>quote}
      respond=fn raw -> Adapters.resume(cont,%{"status"=>"ok","value"=>%{"profile"=>"model","text"=>raw,"usage"=>nil}}) end
      assert {:done,{:ok,%{"facts"=>[fact]}}}=respond.(JSON.encode!(%{"facts"=>[proposal]}))
      assert fact["polarity"]=="negative"
      assert [citation]=fact["citations"]
      assert citation["start_byte"]==2048 and citation["end_byte"]==2048+byte_size(quote)
      assert citation["quote"]==quote and Evidence.valid_span?(source,citation)
      {:call,_,two_chunks}=Adapters.start(resolved,:extract,%{"profile"=>"model","source"=>source,"chunks"=>[first_chunk,chunk],"max_edges"=>1})
      selected=Map.put(proposal,"chunk","c2")
      assert {:done,{:ok,%{"facts"=>[second_fact]}}}=Adapters.resume(two_chunks,%{"status"=>"ok","value"=>%{"profile"=>"model","text"=>JSON.encode!(%{"facts"=>[selected]}),"usage"=>nil}})
      assert hd(second_fact["citations"])["start_byte"]==2048
      for bad <- [Map.put(proposal,"quote","A p B."),Map.put(proposal,"quote","aaa"),
        Map.put(proposal,"quote","Éclair does not require β."),Map.put(proposal,"chunk","c2"),
        Map.put(proposal,"polarity","unknown"),Map.delete(proposal,"polarity"),Map.put(proposal,"start_byte",2048)] do
        assert {:done,{:error,:invalid_model_output,%{}}}=respond.(JSON.encode!(%{"facts"=>[bad]}))
      end
      duplicate=JSON.encode!(%{"facts"=>[proposal]}) |> String.replace(~s("polarity":"negative"),~s("polarity":"positive","polarity":"negative"))
      assert {:done,{:error,:invalid_model_output,%{}}}=respond.(duplicate)
    end

    test "model rerank manipulates short IDs while canonical references remain independently checkable" do
      alias IpseKnowledge.{Adapters,Evidence}
      candidates=for i<-1..3,do: %{"citation"=>%{"chunk_id"=>Evidence.sha256("chunk#{i}"),"start_byte"=>0,"end_byte"=>5,"quote"=>"same!"}}
      resolved=%{"options"=>%{"rerank"=>%{"model"=>%{"kind"=>"model_complete","profile"=>"model","max_candidates"=>16,"quote_bytes"=>128}}}}
      {:call,request,cont}=Adapters.start(resolved,:rerank,%{"profile"=>"model","query"=>"same","candidates"=>candidates})
      input=JSON.decode!(request["input"])
      assert Enum.map(input["candidates"],& &1["id"])==~w(e1 e2 e3)
      canonical=Enum.map(candidates,&Evidence.candidate_id/1)
      assert Enum.map(input["candidates"],& &1["ref"])==canonical
      respond=fn raw -> Adapters.resume(cont,%{"status"=>"ok","value"=>%{"profile"=>"model","text"=>raw,"usage"=>nil}}) end
      assert {:done,{:ok,%{"order"=>order}}}=respond.(~s({"order":["e3","e1","e2"]}))
      assert order==[Enum.at(canonical,2),hd(canonical),Enum.at(canonical,1)]
      for bad <- [[],~w(e1 e2),~w(e1 e1 e3),~w(e1 e2 e4),canonical] do
        assert {:done,{:error,:invalid_model_output,%{}}}=respond.(JSON.encode!(%{"order"=>bad}))
      end
      assert {:done,{:error,:invalid_model_output,%{}}}=respond.(~s({"order":[],"order":["e1","e2","e3"]}))
    end

    test "extraction gives the model its fact bound and enforces that bound on returned proposals" do
      alias IpseKnowledge.{Adapters, Evidence}
      {:ok, source} = Evidence.source(%{"source_id"=>"dev:release", "partition"=>"notes", "generation"=>1,
        "title"=>"Release", "text"=>"Release requires quiescence.", "uri"=>"local:release", "observed_at_ms"=>1,
        "event_at_ms"=>nil, "expires_at_ms"=>nil, "origin"=>%{"kind"=>"provided", "store_profile"=>"notes",
        "partition_or_scope"=>"notes", "receipt"=>nil, "historical"=>false}})
      {:ok, [chunk]}=Evidence.chunks(source)
      resolved=%{"options"=>%{"extraction"=>%{"assisted"=>%{"kind"=>"model_complete","profile"=>"host_extract","version"=>1}}}}
      args=%{"profile"=>"assisted","source"=>source,"chunks"=>[chunk],"max_edges"=>1,"as_of_ms"=>20}
      {:call, request, continuation}=Adapters.start(resolved,:extract,args)
      input=JSON.decode!(request["input"])
      assert input["max_facts"]==1
      assert Enum.sort(Map.keys(input))==~w(chunks max_facts)
      assert request["instruction"] =~ "max_facts"
      assert request["instruction"] =~ "unique exact supporting quote"
      assert request["profile"]=="host_extract"
      proposal=%{"subject"=>"Release","predicate"=>"requires","object"=>"quiescence",
        "polarity"=>"positive","chunk"=>"c1","quote"=>source["text"]}
      good=%{"profile"=>"host_extract","text"=>JSON.encode!(%{"facts"=>[proposal]}),"usage"=>%{}}
      assert {:done,{:ok,%{"facts"=>[_]}}}=Adapters.resume(continuation,%{"status"=>"ok","value"=>good})
      excessive=Map.put(good,"text",JSON.encode!(%{"facts"=>[proposal,proposal]}))
      assert {:done,{:error,:invalid_model_output,%{}}}=Adapters.resume(continuation,%{"status"=>"ok","value"=>excessive})
      assert {:done,{:error,:invalid_model_output,%{}}}=Adapters.resume(continuation,%{"status"=>"ok","value"=>Map.put(good,"profile","other")})
    end

    test "Graph publishes all32 bounded model proposals and exact-size explicit batches" do
      alias IpseKnowledge.{Evidence,Graph,Store}
      alias IpseKnowledge.Test.CASFixture,as: F
      profiles=[%{"kind"=>"state","scope"=>"project","partition"=>"notes"},
        %{"kind"=>"mcp_cas","binding"=>"storage","partition"=>"notes","contract"=>"ipse-cas-v3"}]
      for profile<-profiles do
        empty=Map.new(~w(stores search fetch retrieval embedding rerank extraction),&{&1,%{}})
        options=Map.merge(empty,%{"version"=>1,"stores"=>%{"notes"=>profile},
          "extraction"=>%{"model"=>%{"kind"=>"model_complete","profile"=>"host_extract","version"=>1},
            "explicit"=>%{"kind"=>"explicit","version"=>1}}})
        state=%{resolved: %{ "options"=>options},phase: :idle,ctx: nil,cont: nil,pending: nil}
        text=Enum.map_join(1..32," ",&"A#{&1} p B.")
        attrs=%{"source_id"=>"model32","generation"=>1,"expected_revision"=>0,"title"=>"Facts",
          "text"=>text,"uri"=>"local:facts","observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil}
        {stored,state,db}=graph_command(state,F.new(),"source",%{"store"=>"notes","action"=>"put","args"=>attrs})
        assert stored["status"]=="ok"
        {inspected,state,db}=graph_command(state,db,"source",%{"store"=>"notes","action"=>"inspect","args"=>%{"source_id"=>"model32"}})
        [chunk]=inspected["coverage"]["chunks"]
        db=%{db|requests: []}
        extract=%{"store"=>"notes","extraction"=>"model","source_id"=>"model32","generation"=>1,
          "max_edges"=>32,"chunks"=>[chunk["chunk_id"]],"facts"=>[]}
        {published,state,db}=graph_command(state,db,"extract",extract)
        assert published["status"]=="ok"
        requests=F.requests(db)
        assert Enum.count(requests,&(&1["op"]=="model.complete"))==1
        effects=Enum.count(requests,&(&1["op"] not in ~w(state.scan state.get effect.result.read)))
        assert effects<=16
        assert Enum.all?(requests,&(Ipse.Extension.validate(&1)==:ok))
        drive=fn drive,result,db ->
          case result do
            {:call,request,cont}->{outcome,db}=F.host(db,request);drive.(drive,Store.resume(cont,outcome),db)
            other->{other,db}
          end
        end
        {{:done,{:ok,snapshot}},db}=drive.(drive,Store.start("notes",profile,:snapshot,%{}),db)
        facts=hd(Map.values(snapshot["projections"]))["facts"]
        assert length(facts)==32 and length(Enum.uniq_by(facts,& &1["fact_id"]))==32
        assert Enum.all?(facts,&Evidence.valid_fact?/1)
        assert hd(snapshot["sources"])["text"]==text
        db=%{db|requests: []}
        explicit=extract|>Map.put("extraction","explicit")|>Map.put("facts",Enum.take(facts,3))
        {published,_,db}=graph_command(state,db,"extract",explicit)
        assert published["status"]=="ok"
        refute Enum.any?(F.requests(db),&(&1["op"]=="model.complete"))
      end
    end

    test "explicit Graph publication retains facts for their selected query time" do
      alias IpseKnowledge.{Evidence, Graph}
      alias IpseKnowledge.Test.CASFixture, as: F
      future=System.system_time(:millisecond)+3_600_000
      for {id,observed,from,until,inside,outside} <- [
        {"future-fact",1,future,nil,future,future-1},
        {"past-fact",1,nil,10,5,10},
        {"future-source",future,nil,nil,future,future-1}
      ] do
        empty=Map.new(~w(stores search fetch retrieval embedding rerank extraction),&{&1,%{}})
        options=Map.merge(empty,%{"version"=>1,
          "stores"=>%{"notes"=>%{"kind"=>"state","scope"=>"project","partition"=>"notes"}},
          "extraction"=>%{"asserted"=>%{"kind"=>"explicit","version"=>1}}})
        {:ok,state}=Graph.init(options)
        attrs=%{"source_id"=>id,"generation"=>1,"title"=>"Release","text"=>"Release requires quiescence.",
          "uri"=>"local:release","observed_at_ms"=>observed,"event_at_ms"=>nil,"expires_at_ms"=>nil}
        {stored,state,db}=graph_command(state,F.new(),"source",%{"store"=>"notes","action"=>"put",
          "args"=>Map.put(attrs,"expected_revision",0)})
        assert stored["status"]=="ok"
        {:ok,source}=Evidence.source(Map.merge(attrs,%{"partition"=>"notes",
          "origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}}))
        {:ok,[chunk]}=Evidence.chunks(source)
        {:ok,citation}=Evidence.citation(source,chunk,0,byte_size(source["text"]))
        fact_args=%{"subject"=>"Release","predicate"=>"requires","object"=>"quiescence","polarity"=>"positive",
          "inferred"=>false,"valid_from_ms"=>from,"valid_to_ms"=>until,
          "extraction"=>%{"kind"=>"explicit","profile"=>nil,"version"=>1},"citations"=>[citation]}
        {:ok,fact}=Evidence.fact(fact_args)
        extract=%{"store"=>"notes","extraction"=>"asserted","source_id"=>id,"generation"=>1,
          "max_edges"=>1,"chunks"=>[chunk["chunk_id"]],"facts"=>[fact]}
        {published,state,db}=graph_command(state,db,"extract",extract)
        assert published["status"]=="ok"
        query=%{"store"=>"notes","entity"=>"Release","depth"=>2,"max_nodes"=>8,"max_edges"=>8,"top_k"=>5,"as_of_ms"=>outside}
        {excluded,state,db}=graph_command(state,db,"query",query)
        assert excluded["status"]=="abstain" and excluded["coverage"]["complete"]
        assert Enum.any?(excluded["gaps"],&(&1["code"]=="excluded_fact"))
        {included,state,db}=graph_command(state,db,"query",Map.put(query,"as_of_ms",inside))
        assert included["status"]=="ok" and included["coverage"]["complete"]
        assert Enum.any?(included["claims"],&(&1["fact_id"]==fact["fact_id"]))
        {:ok,forged}=Evidence.fact(Map.put(fact_args,"citations",[Map.put(citation,"generation",2)]))
        {refused,_,_}=graph_command(state,db,"extract",Map.put(extract,"facts",[forged]))
        assert refused["status"]=="refused"
      end
    end

    test "model extraction validates attribution without discarding future-observed sources" do
      alias IpseKnowledge.{Adapters, Evidence}
      {:ok,source}=Evidence.source(%{"source_id"=>"future-model","partition"=>"notes","generation"=>1,
        "title"=>"Release","text"=>"Release requires quiescence.","uri"=>"local:release","observed_at_ms"=>30,
        "event_at_ms"=>nil,"expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"notes",
        "partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}})
      {:ok,[chunk]}=Evidence.chunks(source)
      resolved=%{"options"=>%{"extraction"=>%{"assisted"=>%{"kind"=>"model_complete","profile"=>"host_extract","version"=>1}}}}
      args=%{"profile"=>"assisted","source"=>source,"chunks"=>[chunk],"max_edges"=>1,"as_of_ms"=>20}
      {:call,_,cont}=Adapters.start(resolved,:extract,args)
      proposal=%{"subject"=>"Release","predicate"=>"requires","object"=>"quiescence",
        "polarity"=>"positive","chunk"=>"c1","quote"=>source["text"]}
      value=%{"profile"=>"host_extract","text"=>JSON.encode!(%{"facts"=>[proposal]}),"usage"=>%{}}
      assert {:done,{:ok,%{"facts"=>[fact]}}}=Adapters.resume(cont,%{"status"=>"ok","value"=>value})
      assert Evidence.valid_fact?(fact) and Evidence.valid_span?(source,hd(fact["citations"]))
    end

    test "model rerank requires the declared object and all candidate IDs exactly once" do
      alias IpseKnowledge.{Adapters, Evidence}
      chunks=Enum.map(~w(one two),&Evidence.sha256/1)
      text="Synthetic candidate text."
      candidates=Enum.map(chunks, &%{"citation"=>%{"chunk_id"=>&1,"quote"=>text,"start_byte"=>0,"end_byte"=>byte_size(text)}})
      ids=Enum.map(candidates,&Evidence.candidate_id/1)
      resolved=%{"options"=>%{"rerank"=>%{"ordered"=>%{"kind"=>"model_complete","profile"=>"host_rank","max_candidates"=>16,"quote_bytes"=>128}}}}
      {:call,request,continuation}=Adapters.start(resolved,:rerank,%{"profile"=>"ordered","query"=>"query","candidates"=>candidates})
      assert request["instruction"] =~ ~s({"order":[)
      assert JSON.decode!(request["input"])["required_count"]==2
      assert request["instruction"] =~ "do not filter or omit"
      good=%{"profile"=>"host_rank","text"=>JSON.encode!(%{"order"=>~w(e2 e1)}),"usage"=>%{}}
      assert {:done,{:ok,%{"order"=>order}}}=Adapters.resume(continuation,%{"status"=>"ok","value"=>good})
      assert order==Enum.reverse(ids)
      for bad <- [ids,%{"order"=>[]},%{"order"=>Enum.take(ids,1)},%{"order"=>[hd(ids),hd(ids)]},%{"order"=>[Evidence.sha256("foreign"),hd(ids)]}] do
        value=Map.put(good,"text",JSON.encode!(bad))
        assert {:done,{:error,:invalid_model_output,%{}}}=Adapters.resume(continuation,%{"status"=>"ok","value"=>value})
      end
    end

    test "rerank quote_bytes bounds UTF8 bytes even for a single large combining grapheme" do
      alias IpseKnowledge.{Adapters, Evidence}
      quote="a"<>String.duplicate(<<0x0301::utf8>>,300)
      assert String.length(quote)==1 and byte_size(quote)>128
      resolved=%{"options"=>%{"rerank"=>%{"ordered"=>%{"kind"=>"model_complete","profile"=>"host_rank","max_candidates"=>16,"quote_bytes"=>128}}}}
      {:call,request,_}=Adapters.start(resolved,:rerank,%{"profile"=>"ordered","query"=>"query","candidates"=>[%{"citation"=>%{"chunk_id"=>Evidence.sha256("one"),"quote"=>quote,"start_byte"=>0,"end_byte"=>byte_size(quote)}}]})
      [candidate]=JSON.decode!(request["input"])["candidates"]
      assert byte_size(candidate["quote"])<=128
      assert String.valid?(candidate["quote"]) and String.starts_with?(quote,candidate["quote"])
    end

    test "dense and hybrid citations keep a valid byte span for a long combining grapheme" do
      alias IpseKnowledge.{Evidence, Corpus}
      for kind <- ~w(dense hybrid),
          text <- [String.duplicate("a", 1100), "a" <> String.duplicate(<<0x0301::utf8>>, 600)],
          indexed <- [true, false] do
        {:ok, source}=Evidence.source(%{"source_id"=>"unicode", "partition"=>"notes", "generation"=>1,
          "title"=>"Unicode", "text"=>text, "uri"=>"local:unicode", "observed_at_ms"=>1,
          "event_at_ms"=>nil, "expires_at_ms"=>nil, "origin"=>%{"kind"=>"provided",
          "store_profile"=>"notes", "partition_or_scope"=>"notes", "receipt"=>nil, "historical"=>false}})
        {:ok,[chunk]}=Evidence.chunks(source)
        {:ok,vector}=Evidence.vector(%{"chunk_id"=>chunk["chunk_id"], "selection_sha256"=>Evidence.sha256("selected encoder"), "input_sha256"=>Evidence.sha256(text),
          "profile"=>"encoder", "model"=>"test", "dimensions"=>1, "values"=>[1.0]})
        input=%{"chunk_id"=>Evidence.sha256("query"), "text"=>"query"}
        bytes=<<1.0::little-float-size(32)>>
        descriptor=%{"version"=>2, "kind"=>"embedding.f32le", "encoding"=>"float32le.base64",
          "vector_count"=>1, "dimensions"=>1, "source_sha256"=>Evidence.sha256("source"),
          "operation_id"=>String.duplicate("1",32)}
        page=Map.merge(Map.take(descriptor,~w(version kind encoding dimensions source_sha256 operation_id)),
          %{"vector_index"=>0, "offset"=>0, "complete"=>true, "next"=>nil,
            "input_sha256"=>Evidence.sha256("query"), "vector_sha256"=>Evidence.sha256(bytes), "values"=>Base.encode64(bytes)})
        cont=%{phase: :embedding_read, descriptor: descriptor, inference: %{"selection_sha256"=>Evidence.sha256("selected encoder"),"reported_model"=>"test", "usage"=>%{}},
          host_profile: "encoder", inputs: [input], raw_hashes: [Evidence.sha256("query")], vector_index: 0,
          offset: 0, bytes: <<>>, input_hash: nil, vector_hash: nil, vectors: [], reads: 0, effects: 1}
        snapshot=%{"sources"=>[source], "projections"=>%{source["source_key"]=>%{"vectors"=>if(indexed,do: [vector],else: [])}},
          "tokens"=>[], "gaps"=>[], "coverage"=>%{}}
        ctx=%{snapshot: snapshot, args: %{"query"=>"query", "top_k"=>1, "store"=>"notes", "rerank"=>nil},
          retrieval: %{"kind"=>kind, "missing_embedding"=>"refuse"},
          store_profile: %{"kind"=>"state", "scope"=>"project", "partition"=>"notes"}, as_of_ms: 2}
        state=%{resolved: %{}, phase: :query_embed, pending: :adapter, cont: cont, ctx: ctx}
        assert {:ok,%{"kind"=>"result", "value"=>result},_}=
          Corpus.handle("host.actions",%{"outcome"=>%{"status"=>"ok", "value"=>page}},state)
        if indexed do
          assert result["status"]=="ok" and result["gaps"]==[]
          assert result["coverage"]["revalidated"]
          [candidate]=result["evidence"]
          citation=candidate["citation"]
          assert String.valid?(citation["quote"]) and byte_size(citation["quote"]) in 1..1024
          assert citation["quote"]==binary_part(text,0,citation["end_byte"])
          assert citation["start_byte"]==0 and citation["quote_sha256"]==Evidence.sha256(citation["quote"])
          assert byte_size(citation["quote"])==if(String.starts_with?(text,"aa"),do: 200,else: 1023)
        else
          assert result["status"]=="refused"
          assert result["gaps"]==[%{"code"=>"missing_embedding"}]
        end
      end
    end

    test "successful model rerank preserves Corpus and Research contexts through completion" do
      alias IpseKnowledge.{Adapters, Corpus, Evidence, Research}
      sources=Enum.map(~w(one two),fn id ->
        {:ok,source}=Evidence.source(%{"source_id"=>id,"partition"=>"notes","generation"=>1,
          "title"=>id,"text"=>"Release requires quiescence.","uri"=>"local:"<>id,"observed_at_ms"=>1,
          "event_at_ms"=>nil,"expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"notes",
          "partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}})
        source
      end)
      {:ok,rank}=Evidence.rank_lexical(sources,"release",10,20)
      ids=Enum.map(rank["evidence"], &Evidence.candidate_id/1) |> Enum.reverse()
      resolved=%{"options"=>%{"rerank"=>%{"ordered"=>%{"kind"=>"model_complete","profile"=>"host_rank","max_candidates"=>16,"quote_bytes"=>128}}}}
      {:call,_,cont}=Adapters.start(resolved,:rerank,%{"profile"=>"ordered","query"=>"release","candidates"=>rank["evidence"]})
      outcome=%{"status"=>"ok","value"=>%{"profile"=>"host_rank","text"=>JSON.encode!(%{"order"=>~w(e2 e1)}),"usage"=>%{}}}
      snapshot=%{"tokens"=>[],"coverage"=>%{"fixture"=>"captured snapshot"},"gaps"=>[],"sources"=>sources}
      ctx=%{args: %{"store"=>"notes","query"=>"release"},store_profile: %{"kind"=>"state","scope"=>"project","partition"=>"notes"},snapshot: snapshot,rank: rank,as_of_ms: 20}
      state=%{resolved: resolved,phase: :query_rerank,pending: :adapter,cont: cont,ctx: ctx}
      assert {:ok,%{"kind"=>"result","value"=>result},_}=Corpus.handle("host.actions",%{"outcome"=>outcome},state)
      assert result["status"]=="ok" and result["coverage"]["revalidated"]
      assert result["coverage"]["store"]==snapshot["coverage"]
      assert Enum.map(result["evidence"], &Evidence.candidate_id/1)==ids
      research_ctx=%{args: %{"query"=>"release"},ranked: rank,at: 20,sources: sources,bytes: 56,profile: %{"kind"=>"mcp"}}
      state=%{resolved: resolved,phase: :rerank,cont: cont,ctx: research_ctx}
      assert {:ok,%{"kind"=>"result","value"=>result},_}=Research.handle("host.actions",%{"outcome"=>outcome},state)
      assert result["status"]=="ok" and result["coverage"]["source_count"]==2
      assert result["coverage"]["as_of_ms"]==20 and result["coverage"]["bytes"]==56
      assert Enum.map(result["evidence"], &Evidence.candidate_id/1)==ids
    end

    test "offline research returns cited provided evidence with no host action" do
      {:ok, state} = IpseKnowledge.Research.init(offline_options())
      source = %{"source_id" => "dev:locks", "generation" => 1, "title" => "Locks",
        "text" => "Session lock files remain on disk. Releasing the OS lock preserves inode identity.",
        "uri" => "local:locks", "observed_at_ms" => 1_700_000_000_000,
        "event_at_ms" => nil, "expires_at_ms" => nil}
      assert {:ok, %{"kind" => "result", "value" => result}, _} =
        IpseKnowledge.Research.handle("invoke.command",
          %{"id" => "investigate", "arguments" => investigation([source])}, state)
      assert result["status"] == "ok"
      assert result["evidence"] != []
      assert result["coverage"]["bytes"] == byte_size(source["text"])
      assert Enum.all?(result["evidence"], fn c ->
        c["citation"]["origin"]["kind"] == "provided" and
          c["citation"]["origin"]["receipt"] == nil
      end)
    end

    test "research returns ten cited sources and refuses an eleventh" do
      sources = Enum.map(1..11, fn n ->
        %{"source_id" => "s#{n}", "generation" => 1, "title" => "Locks",
          "text" => "Lock files preserve inode identity.", "uri" => "local:s#{n}",
          "observed_at_ms" => 1, "event_at_ms" => nil, "expires_at_ms" => nil}
      end)
      descriptor = IpseKnowledge.Research.describe()
      schema = hd(descriptor["exports"]["commands"])["arguments_schema"]
      assert schema["properties"]["limits"]["properties"]["max_sources"]["maximum"] == 10
      assert schema["properties"]["sources"]["maxItems"] == 10
      for {count, expected} <- [{10, "ok"}, {11, "refused"}] do
        {:ok, state} = IpseKnowledge.Research.init(offline_options())
        args = investigation(Enum.take(sources, count))
          |> put_in(["limits", "max_sources"], count)
        assert {:ok, %{"kind" => "result", "value" => result}, _} =
          IpseKnowledge.Research.handle("invoke.command", %{"id" => "investigate", "arguments" => args}, state)
        assert result["status"] == expected, inspect(Map.take(result, ~w(status gaps coverage)))
        if count == 10 do
          assert length(result["evidence"]) == 10
          assert Enum.sort(Enum.map(result["evidence"], & &1["citation"]["source_id"])) ==
            Enum.sort(Enum.map(Enum.take(sources, 10), & &1["source_id"]))
          assert byte_size(JSON.encode!(result)) <= 12_000
          assert result["claims"] == [%{"label" => "open",
            "evidence_indexes" => Enum.to_list(0..9),
            "uncertainty" => "semantic_support_unassessed"}]
        end
      end
    end

    test "ten full citations use SDK2 publication without losing quote bytes or provenance" do
      alias IpseKnowledge.Evidence
      sources = Enum.map(1..10, fn n ->
        %{"source_id" => "s#{n}", "generation" => 1, "title" => "Locks",
          "text" => "Lock " <> String.duplicate("files ", 170), "uri" => "local:s#{n}",
          "observed_at_ms" => 1, "event_at_ms" => nil, "expires_at_ms" => nil}
      end)
      {:ok, state} = IpseKnowledge.Research.init(offline_options())
      args = investigation(sources) |> put_in(["limits", "max_sources"], 10)
        |> Map.put("as_of_ms", 20)
      assert {:ok, %Ipse.Extension.ResultPublication.Output{} = publication, %{phase: :idle}} =
        IpseKnowledge.Research.handle("invoke.command", %{"id" => "investigate", "arguments" => args}, state)
      assert publication.byte_count > 12_000
      assert publication.byte_count == byte_size(publication.bytes)
      assert publication.sha256 == Evidence.sha256(publication.bytes)
      result = JSON.decode!(publication.bytes)
      assert result["status"] == "ok"
      normalized = Enum.map(sources, fn source ->
        {:ok, value} = Evidence.source(Map.merge(source, %{"partition" => "research-provided",
          "origin" => %{"kind" => "provided", "store_profile" => nil,
            "partition_or_scope" => nil, "receipt" => nil, "historical" => false}}))
        value
      end)
      {:ok, rank} = Evidence.rank_lexical(normalized, args["query"], 10, 20)
      assert result["evidence"] == rank["evidence"]
      assert length(result["evidence"]) == 10
      for item <- result["evidence"] do
        citation = item["citation"]
        source = Enum.find(normalized, &(&1["source_id"] == citation["source_id"]))
        assert byte_size(citation["quote"]) == 1024
        assert Evidence.valid_span?(source, citation)
      end
      assert result["claims"] == [%{"label" => "open", "evidence_indexes" => Enum.to_list(0..9),
        "uncertainty" => "semantic_support_unassessed"}]
      assert result["coverage"]["source_count"] == 10
      assert result["coverage"]["bytes"] == Enum.sum(Enum.map(sources, &byte_size(&1["text"])))
    end

    test "one escaped citation crosses a transport fragment without changing its quote" do
      text = "Lock " <> String.duplicate(<<1>>, 1019)
      sources = Enum.map(1..10, fn n ->
        %{"source_id" => "s#{n}", "generation" => 1, "title" => "Locks",
          "text" => if(n == 1, do: text, else: "Lock files preserve inode identity."),
          "uri" => "local:s#{n}", "observed_at_ms" => 1,
          "event_at_ms" => nil, "expires_at_ms" => nil}
      end)
      {:ok, state} = IpseKnowledge.Research.init(offline_options())
      args = investigation(sources) |> put_in(["limits", "max_sources"], 10)
      assert byte_size(JSON.encode!(args)) <= 12_000
      assert {:ok, %Ipse.Extension.ResultPublication.Output{} = publication, _} =
        IpseKnowledge.Research.handle("invoke.command", %{"id" => "investigate", "arguments" => args}, state)
      result = JSON.decode!(publication.bytes)
      assert length(result["evidence"]) == 10
      citation = Enum.find_value(result["evidence"], fn item ->
        if item["citation"]["source_id"] == "s1", do: item["citation"]
      end)
      assert byte_size(JSON.encode!(citation)) > 4096
      assert citation["quote"] == text
      assert citation["quote_sha256"] == IpseKnowledge.Evidence.sha256(text)
      assert citation["origin"]["kind"] == "provided"
    end

    test "explicit research time applies observation and expiry while invalid times refuse" do
      source = %{"source_id" => "dev:locks", "generation" => 1, "title" => "Locks",
        "text" => "Session lock files preserve inode identity.", "uri" => "local:locks",
        "observed_at_ms" => 10, "event_at_ms" => nil, "expires_at_ms" => 100}
      for {at, expected} <- [{9, "abstain"}, {10, "ok"}, {99, "ok"}, {100, "abstain"}, {-1, "refused"}, {"50", "refused"}, {nil, "refused"}] do
        {:ok, state} = IpseKnowledge.Research.init(offline_options())
        args = investigation([source]) |> Map.put("as_of_ms", at)
        assert {:ok, %{"kind" => "result", "value" => result}, _} =
          IpseKnowledge.Research.handle("invoke.command", %{"id" => "investigate", "arguments" => args}, state)
        assert result["status"] == expected
        if expected != "refused", do: assert(result["coverage"]["as_of_ms"] == at)
      end
    end

    test "research selects current time after capture and keeps genuinely future sources excluded" do
      alias IpseKnowledge.{Adapters, Evidence, Research}
      uri = "fixture:captured"
      text = "Session lock files remain on disk."
      resolved = %{"options" => %{"fetch" => %{"web" => %{"kind" => "mcp",
        "binding" => "fetcher", "contract" => "fetch-v1"}}}}
      {:call, _request, continuation} = Adapters.start(resolved, :fetch,
        %{"profile" => "web", "uri" => uri, "timeout_ms" => 30_000})
      for {observed, expected} <- [{1, "ok"}, {System.system_time(:millisecond) + 86_400_000, "abstain"}] do
        ctx = %{args: investigation([]) |> Map.put("fetch", "web"), at: 0,
          profile: %{"kind" => "mcp"}, fetch_profile: %{}, sources: [], receipts: [],
          hits: [], remaining: [%{"source_id" => "remote:locks", "uri" => uri, "title" => "Locks"}],
          bytes: 0, started: System.monotonic_time(:millisecond)}
        state = %{resolved: resolved, phase: :fetch, ctx: ctx, cont: continuation}
        data = %{"version" => 1, "contract" => "fetch-v1", "status" => "ok",
          "requested_uri" => uri, "observed_uri" => uri, "media_type" => "text/plain",
          "observed_at_ms" => observed, "text" => text, "body_sha256" => Evidence.sha256(text),
          "complete" => true, "start_byte" => 0, "end_byte" => byte_size(text)}
        encoded = JSON.encode!(data)
        descriptor = %{"version" => 1, "kind" => "mcp.text", "operation_id" => String.duplicate("3",32),
          "source_sha256" => Evidence.sha256(encoded), "byte_count" => byte_size(encoded)}
        {:ok, %{"kind" => "host_call"}, reading} = Research.handle("host.actions",
          %{"outcome" => %{"status" => "ok", "value" => descriptor}}, state)
        page = Map.take(descriptor, ~w(version kind operation_id source_sha256))
          |> Map.merge(%{"offset" => 0, "text" => encoded, "complete" => true, "next" => nil})
        {:ok, %{"kind" => "result", "value" => result}, _} = Research.handle("host.actions",
          %{"outcome" => %{"status" => "ok", "value" => page}}, reading)
        assert result["status"] == expected
        assert result["coverage"]["as_of_ms"] > 0
        assert result["coverage"]["bytes"] == byte_size(text)
      end
    end

    test "provided source and ledger cannot self-promote fetched or native receipt" do
      {:ok, state} = IpseKnowledge.Research.init(offline_options())
      source = %{"source_id" => "fake", "generation" => 1, "title" => "Fake",
        "text" => "fabricated", "uri" => "local:fake", "observed_at_ms" => 1,
        "event_at_ms" => nil, "expires_at_ms" => nil,
        "origin" => %{"kind" => "fetch", "receipt" => %{"operation_id" => "fake"}}}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Research.handle("invoke.command",
          %{"id" => "investigate", "arguments" => investigation([source])}, state)
      bad = %{"action" => "inspect", "args" => %{"ledger" => [%{"claim" => "x",
        "basis" => [], "label" => "supported", "native_receipt" => true}]}}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Research.handle("invoke.command",
          %{"id" => "ledger", "arguments" => bad}, state)
    end

    test "unknown result stops and forged vector page cannot complete" do
      assert {:stop, :unknown_effect} =
        IpseKnowledge.Adapters.resume(%{phase: :embedding_read}, %{"status" => "unknown"})
      descriptor = %{"version" => 2, "kind" => "embedding.f32le", "encoding" => "float32le.base64",
        "operation_id" => "op", "source_sha256" => String.duplicate("a", 64), "dimensions" => 1,
        "vector_count" => 1}
      state = %{phase: :embedding_read, descriptor: descriptor, vector_index: 0, offset: 0,
        bytes: <<>>, input_hash: nil, reads: 0, inputs: [%{"chunk_id" => String.duplicate("b", 64),
          "text" => "a"}], raw_hashes: [String.duplicate("c", 64)], vectors: [],
        inference: %{"reported_model" => "model"}, host_profile: "emb"}
      page = %{"version" => 2, "kind" => "embedding.f32le", "encoding" => "float32le.base64",
        "operation_id" => "different", "source_sha256" => descriptor["source_sha256"],
        "vector_index" => 0, "offset" => 0, "dimensions" => 1,
        "input_sha256" => String.duplicate("d", 64), "vector_sha256" => String.duplicate("e", 64),
        "values" => Base.encode64(<<1.0::float-little-32>>), "complete" => true, "next" => nil}
      assert {:done, {:error, :invalid_embedding_result, %{}}} =
        IpseKnowledge.Adapters.resume(state, %{"status" => "ok", "value" => page})
    end

    test "embedding preserves finite float32 extremes and refuses non-finite bit patterns" do
      alias IpseKnowledge.{Adapters, Evidence}
      decode=fn bytes ->
        resolved=%{"options"=>%{"embedding"=>%{"encoder"=>%{"kind"=>"embedding","profile"=>"host_encoder"}}}}
        input=%{"chunk_id"=>Evidence.sha256("chunk"),"text"=>"synthetic"}
        {:call,_,cont}=Adapters.start(resolved,:embed,%{"profile"=>"encoder","inputs"=>[input]})
        descriptor=%{"version"=>2,"kind"=>"embedding.f32le","encoding"=>"float32le.base64",
          "operation_id"=>String.duplicate("1",32),"source_sha256"=>Evidence.sha256("source"),
          "vector_count"=>1,"dimensions"=>div(byte_size(bytes),4)}
        inference=%{"version"=>2,"selection_sha256"=>Evidence.sha256("selection"),"result"=>descriptor,
          "profile"=>"host_encoder","reported_model"=>"synthetic","usage"=>%{}}
        {:call,_,reading}=Adapters.resume(cont,%{"status"=>"ok","value"=>inference})
        page=Map.merge(Map.take(descriptor,~w(version kind encoding dimensions source_sha256 operation_id)),
          %{"vector_index"=>0,"offset"=>0,"complete"=>true,"next"=>nil,
            "input_sha256"=>Evidence.sha256("opaque"),"vector_sha256"=>Evidence.sha256(bytes),"values"=>Base.encode64(bytes)})
        Adapters.resume(reading,%{"status"=>"ok","value"=>page})
      end
      bytes=for bits<-[0x7f7fffff,0xff7fffff,0,1],into: <<>>,do: <<bits::little-unsigned-size(32)>>
      assert {:done,{:ok,%{"vectors"=>[vector]}}}=decode.(bytes)
      assert vector["values"]==[3.4028234663852886e38,-3.4028234663852886e38,0.0,1.401298464324817e-45]
      assert Evidence.valid_vector?(vector)
      for bits<-[0x7f800000,0xff800000,0x7fc00000,0x7f800001] do
        assert {:done,{:error,:invalid_embedding_result,%{}}}=decode.(<<bits::little-unsigned-size(32)>>)
      end
    end

    test "embedding initializes reader state and reconstructs two complete4096 vectors" do
      alias IpseKnowledge.{Adapters, Evidence}
      resolved=%{"options"=>%{"embedding"=>%{"encoder"=>%{"kind"=>"embedding","profile"=>"host_encoder"}}}}
      inputs=for index<-0..1,do: %{"chunk_id"=>Evidence.sha256("chunk#{index}"),"text"=>"input#{index}"}
      {:call,request,cont}=Adapters.start(resolved,:embed,%{"profile"=>"encoder","inputs"=>inputs})
      assert request["inputs"]==["input0","input1"]
      assert request["version"]===2
      descriptor=%{"version"=>2,"kind"=>"embedding.f32le","encoding"=>"float32le.base64",
        "operation_id"=>String.duplicate("1",32),"source_sha256"=>String.duplicate("a",64),
        "vector_count"=>2,"dimensions"=>4096}
      inference=%{"version"=>2,"selection_sha256"=>Evidence.sha256("selected encoder"),"result"=>descriptor,"profile"=>"host_encoder","reported_model"=>"fixture4096","usage"=>%{}}
      for invalid <- [Map.delete(inference,"selection_sha256"),Map.put(inference,"selection_sha256","bad"),Map.put(inference,"version",1)] do
        assert {:done,{:error,:invalid_embedding_result,%{}}}=Adapters.resume(cont,%{"status"=>"ok","value"=>invalid})
      end
      first=Adapters.resume(cont,%{"status"=>"ok","value"=>inference})
      result=Enum.reduce(1..12,first,fn _,{:call,read,continuation}->
        index=read["vector_index"]; offset=read["offset"]; count=min(768,4096-offset)
        bytes=for n<-0..4095,into: <<>>,do: <<(if n==index,do: 1.0,else: 0.0)::little-float-size(32)>>
        complete=offset+count==4096
        page=%{"version"=>2,"kind"=>"embedding.f32le","encoding"=>"float32le.base64",
          "operation_id"=>descriptor["operation_id"],"source_sha256"=>descriptor["source_sha256"],
          "vector_index"=>index,"offset"=>offset,"dimensions"=>4096,
          "input_sha256"=>Evidence.sha256("opaque#{index}"),"vector_sha256"=>Evidence.sha256(bytes),
          "values"=>Base.encode64(binary_part(bytes,offset*4,count*4)),
          "complete"=>complete,"next"=>if(complete,do: nil,else: offset+count)}
        Adapters.resume(continuation,%{"status"=>"ok","value"=>page})
      end)
      assert {:done,{:ok,value}}=result
      assert length(value["vectors"])==2
      assert Enum.all?(value["vectors"],&(length(&1["values"])==4096 and Evidence.valid_vector?(&1)))
      assert value["receipt"]["raw_input_sha256"]==Enum.map(inputs,&Evidence.sha256(&1["text"]))
      assert Enum.map(value["vectors"],& &1["input_sha256"])==Enum.map(0..1,&Evidence.sha256("opaque#{&1}"))
    end

    test "query-v1 emits only the selected binding and exact bounded arguments" do
      {:call, request, _} = query_adapter()
      assert request["op"] == "mcp.call"
      assert request["binding"] == "query_tool"
      assert Map.keys(request["arguments"]) |> Enum.sort() ==
        ~w(as_of_ms contract partition query request_id top_k version)
      assert request["arguments"]["partition"] == "bench"
      assert request["arguments"]["request_id"] =~ ~r/\A[0-9a-f]{32}\z/
      assert request["arguments"]["query"] == "lock files"
    end

    test "query-v1 accepts exact refs and carries actual query action counts" do
      {:call, request, continuation} = query_adapter()
      ref = remote_ref(source())
      result = complete_query(continuation, remote_data(request, [ref]))
      assert {:done, {:ok, value}} = result
      assert value["refs"] == [ref]
      assert value["store_generation"] == 3
      assert value["effects_used"] == 1
      assert value["reads_used"] == 1
      assert value["coverage"]["scanned_chunks"] == 1

      {:call, empty_request, empty_continuation} = query_adapter()
      assert {:done, {:ok, %{"refs" => [], "effects_used" => 1, "reads_used" => 1}}} =
        complete_query(empty_continuation, remote_data(empty_request, []))
    end

    test "query-v1 rejects forged echoes, hashes, generations and partial responses" do
      {:call, request, continuation} = query_adapter()
      valid = remote_data(request, [remote_ref(source())])
      bad_ref = hd(valid["refs"])

      forged = [
        Map.put(valid, "request_id", String.duplicate("f", 32)),
        Map.put(valid, "partition", "other"),
        Map.put(valid, "complete", false),
        put_in(valid, ["refs", Access.at(0), "source_key"], String.duplicate("f", 64)),
        put_in(valid, ["refs", Access.at(0), "generation"], 0),
        Map.put(valid, "refs", [bad_ref, bad_ref]),
        Map.put(valid, "status", "refused")
      ]

      for response <- forged do
        assert {:done, {:error, :invalid_remote_result, %{}}} =
          complete_query(continuation, response)
      end
    end

    test "query-v1 no-replay unknown and incompatible store refuse before remote action" do
      {:call, _request, continuation} = query_adapter()
      assert {:stop, :unknown_effect} =
        IpseKnowledge.Adapters.resume(continuation, %{"status" => "unknown"})

      state = %{resolved: query_resolved("other"), phase: :idle,
        ctx: nil, cont: nil, pending: nil}
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
        IpseKnowledge.Corpus.handle("invoke.command",
          %{"id" => "query", "arguments" => query_args()}, state)

      valid_state = %{state | resolved: query_resolved()}
      assert {:ok, %{"kind" => "host_call", "request" => request}, _} =
        IpseKnowledge.Corpus.handle("invoke.command",
          %{"id" => "query", "arguments" => query_args()}, valid_state)
      assert request["op"] == "mcp.call"
      assert request["binding"] == "query_tool"
    end

    test "remote ranking refuses stale and historical sources as a whole" do
      valid = source()
      ref = remote_ref(valid)
      assert {:ok, %{"evidence" => [_]}} =
        IpseKnowledge.Evidence.rank_remote([valid], [ref], 1, 10)

      expired = %{valid | "expires_at_ms" => 10}
      assert {:error, :invalid_remote_selection} =
        IpseKnowledge.Evidence.rank_remote([expired], [ref], 1, 10)

      historical = put_in(valid, ["origin", "historical"], true)
      assert {:error, :invalid_remote_selection} =
        IpseKnowledge.Evidence.rank_remote([historical], [ref], 1, 10)

      assert {:error, :invalid_remote_selection} =
        IpseKnowledge.Evidence.rank_remote([], [ref], 1, 10)

      assert {:ok, %{"evidence" => []}} =
        IpseKnowledge.Evidence.rank_remote([], [], 1, 10)
    end

    defp query_resolved(store_partition \\ "bench") do
      %{"options" => %{
        "stores" => %{"remote" => %{"kind" => "mcp_cas", "binding" => "cas_tool",
          "partition" => store_partition, "contract" => "ipse-cas-v1"}},
        "retrieval" => %{"remote" => %{"kind" => "mcp_query", "binding" => "query_tool",
          "partition" => "bench", "contract" => "query-v1"}},
        "rerank" => %{}
      }}
    end

    defp query_args do
      %{"store" => "remote", "retrieval" => "remote", "rerank" => nil,
        "query" => "lock files", "top_k" => 1, "as_of_ms" => 10}
    end

    defp query_adapter do
      IpseKnowledge.Adapters.start(query_resolved(), :query_refs,
        %{"profile" => "remote", "query" => "lock files", "top_k" => 1,
          "as_of_ms" => 10})
    end

    defp source do
      {:ok, value} = IpseKnowledge.Evidence.source(%{
        "source_id" => "local:locks", "partition" => "bench", "generation" => 1,
        "title" => "Locks", "text" => "Session lock files remain on disk.",
        "uri" => "local:locks", "observed_at_ms" => 1,
        "event_at_ms" => nil, "expires_at_ms" => nil,
        "origin" => %{"kind" => "provided", "store_profile" => "remote",
          "partition_or_scope" => "bench", "receipt" => nil, "historical" => false}
      })
      value
    end

    defp remote_ref(source) do
      {:ok, [chunk]} = IpseKnowledge.Evidence.chunks(source)
      Map.take(source, ~w(source_id source_key generation content_sha256))
      |> Map.merge(%{"chunk_id" => chunk["chunk_id"], "score" => 0.75})
    end

    defp remote_data(request, refs) do
      args = request["arguments"]
      %{"version" => 1, "contract" => "query-v1", "partition" => args["partition"],
        "request_id" => args["request_id"], "status" => "ok", "generation" => 3,
        "algorithm" => "remote.1", "algorithm_version" => 1,
        "scanned_sources" => 1, "scanned_chunks" => 1, "complete" => true,
        "refs" => refs}
    end

    defp complete_query(continuation, response) do
      text = JSON.encode!(response)
      source_hash = IpseKnowledge.Evidence.sha256(text)
      descriptor = %{"version" => 1, "kind" => "mcp.text", "operation_id" => String.duplicate("2",32),
        "source_sha256" => source_hash, "byte_count" => byte_size(text)}
      {:call, _read, read_cont} = IpseKnowledge.Adapters.resume(continuation,
        %{"status" => "ok", "value" => descriptor})
      IpseKnowledge.Adapters.resume(read_cont, %{"status" => "ok", "value" => %{
        "version" => 1, "kind" => "mcp.text", "operation_id" => String.duplicate("2",32),
        "source_sha256" => source_hash, "offset" => 0, "text" => text,
        "complete" => true, "next" => nil
      }})
    end

    defp graph_command(state,db,command,args),
      do: graph_drive(IpseKnowledge.Graph.handle("invoke.command",%{"id"=>command,"arguments"=>args},state),db)

    defp graph_drive({:ok,%{"kind"=>"host_call","request"=>%{"op"=>"model.complete"}=request},state},db) do
      input=JSON.decode!(request["input"])
      [chunk]=input["chunks"]
      facts=for i<-1..input["max_facts"] do
        quote="A#{i} p B."
        %{"subject"=>"A#{i}","predicate"=>"p","object"=>"B","polarity"=>"positive",
          "chunk"=>chunk["id"],"quote"=>quote}
      end
      text=JSON.encode!(%{"facts"=>facts})
      assert byte_size(text)<=request["max_output_bytes"]
      db=%{db|requests: [request|db.requests]}
      outcome=%{"status"=>"ok","value"=>%{"profile"=>request["profile"],"text"=>text,"usage"=>nil}}
      graph_drive(IpseKnowledge.Graph.handle("host.actions",%{"outcome"=>outcome},state),db)
    end

    defp graph_drive({:ok,%{"kind"=>"host_call","request"=>request},state},db) do
      {outcome,db}=IpseKnowledge.Test.CASFixture.host(db,request)
      graph_drive(IpseKnowledge.Graph.handle("host.actions",%{"outcome"=>outcome},state),db)
    end

    defp graph_drive({:ok,%{"kind"=>"result","value"=>value},state},db),do: {value,state,db}

    defp offline_options do
      %{"version" => 1, "stores" => %{},
        "search" => %{"local" => %{"kind" => "provided", "version" => 1}},
        "fetch" => %{"local" => %{"kind" => "provided", "version" => 1}},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{}, "rerank" => %{}, "extraction" => %{}}
    end

    defp investigation(sources) do
      %{"search" => "local", "fetch" => "local", "retrieval" => "words",
        "rerank" => nil, "query" => "lock files inode",
        "limits" => %{"max_sources" => 1, "max_body_bytes" => 49_152, "timeout_ms" => 30_000},
        "sources" => sources}
    end
  end

  result = ExUnit.run()
  System.halt(if(result.failures == 0, do: 0, else: 1))
  """

  test "packages run in a separate VM without loading domain modules into host" do
    assert Code.ensure_loaded?(Ipse.Extension)
    sdk_ebin = Ipse.Extension |> :code.which() |> to_string() |> Path.dirname()
    root = Path.expand("..", __DIR__)
    elixir = System.find_executable("elixir")
    assert is_binary(elixir)

    dependency_paths =
      for module <- [Jason, JSONSchex, ExJSONPointer],
          path = module |> :code.which() |> to_string() |> Path.dirname(),
          do: ["-pa", path]

    {output, status} =
      System.cmd(elixir, ["-pa", sdk_ebin] ++ List.flatten(dependency_paths) ++ ["-e", @suite],
        cd: root,
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute Code.ensure_loaded?(IpseKnowledge.Corpus)
    refute Code.ensure_loaded?(IpseKnowledge.Research)
    refute Code.ensure_loaded?(IpseKnowledge.Graph)
  end
end
