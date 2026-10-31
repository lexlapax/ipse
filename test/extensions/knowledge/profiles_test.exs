defmodule Ipse.KnowledgeProfilesTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  defp pure(body) do
    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.Profiles, as: P
    empty=Map.new(~w(stores search fetch retrieval embedding rerank extraction),&{&1,%{}})|>Map.put("version",1)
    lexical=Map.merge(empty,%{"stores"=>%{"notes"=>%{"kind"=>"state","scope"=>"project","partition"=>"notes"}},"retrieval"=>%{"words"=>%{"kind"=>"bm25","version"=>1}}})
    '''

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["-r", Path.join(@root, "extensions/knowledge/src/profiles.ex"), "-e", bootstrap <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "lexical and offline builds omit unused network and inference authority" do
    pure(~S'''
    {:ok,r}=P.validate("corpus","state-lexical",lexical)
    assert {:ok,%{"partition"=>"notes"}}=P.lookup(r,"stores","notes")
    assert {:ok,nil}=P.lookup(r,"rerank",nil)
    assert {:error,:unknown_profile}=P.lookup(r,"stores","not-granted")
    caps=P.capabilities("corpus","state-lexical")
    assert "invoke.tool" in caps and "host.state.bound" in caps
    refute Enum.any?(~w(host.mcp host.embedding host.model host.results),&(&1 in caps))
    offline=Map.merge(empty,%{"search"=>%{"given"=>%{"kind"=>"provided","version"=>1}},"fetch"=>%{"given"=>%{"kind"=>"provided","version"=>1}},"retrieval"=>%{"words"=>%{"kind"=>"bm25","version"=>1}}})
    assert {:ok,_}=P.validate("research","offline",offline)
    assert P.capabilities("research","offline")==["invoke.command","invoke.result.pages","invoke.tool"]
    assert {:error,:invalid_preset}=P.capabilities("corpus","invented")
    ''')
  end

  test "workspace document acquisition is an explicit preset capability without widening existing presets" do
    pure(~S'''
    state_caps=P.capabilities("corpus","state-lexical")
    document_caps=P.capabilities("corpus","state-documents")
    assert document_caps--state_caps==["host.tools"]
    assert state_caps--document_caps==[]
    assert {:ok,_}=P.validate("corpus","state-documents",lexical)
    remote=put_in(lexical,["stores","notes"],%{"kind"=>"mcp_cas","binding"=>"storage","partition"=>"notes","contract"=>"ipse-cas-v3"})
    assert P.capabilities("corpus","mcp-documents")--P.capabilities("corpus","mcp-lexical")==["host.tools"]
    assert {:ok,_}=P.validate("corpus","mcp-documents",remote)
    for preset<-~w(state-lexical state-dense state-rerank state-semantic mcp-lexical mcp-dense mcp-rerank mcp-semantic) do
      refute "host.tools" in P.capabilities("corpus",preset)
    end
    ''')
  end

  test "profile references and compiled preset authority are checked before dispatch" do
    pure(~S'''
    dense=lexical|>put_in(["embedding","encoder"],%{"kind"=>"embedding","profile"=>"reviewed"})|>put_in(["retrieval","semantic"],%{"kind"=>"dense","version"=>1,"embedding"=>"encoder"})
    assert {:error,:profile_authority_mismatch}=P.validate("corpus","state-lexical",dense)
    assert {:ok,_}=P.validate("corpus","state-dense",dense)
    refute "host.model" in P.capabilities("corpus","state-dense")
    assert {:error,:invalid_profile_reference}=P.validate("corpus","state-dense",put_in(dense,["retrieval","semantic","embedding"],"absent"))
    rerank=put_in(lexical,["rerank","judge"],%{"kind"=>"model_complete","profile"=>"judge","max_candidates"=>16,"quote_bytes"=>128})
    assert {:ok,_}=P.validate("corpus","state-rerank",rerank)
    refute "host.embedding" in P.capabilities("corpus","state-rerank")
    assert {:error,:profile_authority_mismatch}=P.validate("corpus","state-dense",rerank)
    graph=put_in(lexical,["retrieval","links"],%{"kind"=>"graph","version"=>1,"lexical"=>"words","depth"=>4,"max_nodes"=>128,"max_edges"=>256})
    assert {:ok,_}=P.validate("corpus","state-lexical",graph)
    assert {:error,:invalid_profile_reference}=P.validate("corpus","state-lexical",put_in(graph,["retrieval","links","lexical"],"links"))
    ''')
  end

  test "dense and hybrid query prefixes are explicit bounded retrieval options" do
    pure(~S'''
    dense=%{"kind"=>"dense","version"=>1,"embedding"=>"encoder"}
    hybrid=%{"kind"=>"hybrid","version"=>1,"lexical"=>"words","embedding"=>"encoder","graph"=>nil,"rrf_k"=>60,"missing_embedding"=>"refuse"}
    base=put_in(lexical,["embedding","encoder"],%{"kind"=>"embedding","profile"=>"reviewed"})
    for profile<-[dense,hybrid] do
      selected=put_in(base,["retrieval","semantic"],profile)
      assert {:ok,_}=P.validate("corpus","state-dense",selected)
      for prefix<-["Instruct: Retrieve relevant passages.\nQuery:",String.duplicate("a",1024),"雪"] do
        assert {:ok,_}=P.validate("corpus","state-dense",put_in(selected,["retrieval","semantic","query_prefix"],prefix))
      end
      for prefix<-[nil,"",true,42,String.duplicate("a",1025),String.duplicate("雪",342),"bad"<><<0>>] do
        assert {:error,:invalid_profile}=P.validate("corpus","state-dense",put_in(selected,["retrieval","semantic","query_prefix"],prefix))
      end
    end
    assert {:error,:invalid_profile}=P.validate("corpus","state-dense",put_in(base,["retrieval","words","query_prefix"],"not applicable"))
    assert {:error,:invalid_profile}=P.validate("corpus","state-dense",put_in(base,["embedding","encoder","query_prefix"],"wrong owner"))
    ''')
  end

  test "Collection semantic retrieval stays within the explicit embedding preset" do
    pure(~S'''
    base=put_in(lexical,["stores","notes","kind"],"collection")
    assert {:ok,_}=P.validate("corpus","collection-documents",base)
    selected=base
      |> put_in(["embedding","encoder"],%{"kind"=>"embedding","profile"=>"reviewed"})
      |> put_in(["retrieval","similar"],%{"kind"=>"dense","version"=>1,"embedding"=>"encoder"})
    assert {:ok,_}=P.validate("corpus","collection-dense",selected)
    assert {:error,:profile_authority_mismatch}=P.validate("corpus","collection-documents",selected)
    hybrid=%{"kind"=>"hybrid","version"=>1,"lexical"=>"words","embedding"=>"encoder","graph"=>nil,"rrf_k"=>60,"missing_embedding"=>"refuse"}
    selected=put_in(selected,["retrieval","combined"],hybrid)
    assert {:ok,_}=P.validate("corpus","collection-dense",selected)
    assert {:error,:profile_authority_mismatch}=P.validate("corpus","collection-dense",put_in(selected,["retrieval","combined","missing_embedding"],"lexical_with_gap"))
    graph=%{"kind"=>"graph","version"=>1,"lexical"=>"words","depth"=>1,"max_nodes"=>16,"max_edges"=>32}
    graph_options=put_in(selected,["retrieval","links"],graph)
    assert {:error,:profile_authority_mismatch}=P.validate("corpus","collection-dense",graph_options)
    graph_options=put_in(graph_options,["retrieval","combined","graph"],"links")
    assert {:error,:profile_authority_mismatch}=P.validate("corpus","collection-dense",graph_options)
    ''')
  end

  test "partitions and exact profile variants cannot be supplied through raw commands or modules" do
    pure(~S'''
    assert {:error,:invalid_profile}=P.validate("corpus","state-lexical",update_in(lexical,["stores","notes"],&Map.delete(&1,"partition")))
    assert {:error,:invalid_profile}=P.validate("corpus","state-lexical",put_in(lexical,["stores","notes","partition"],"../../other"))
    assert {:error,:invalid_profile}=P.validate("corpus","state-lexical",put_in(lexical,["retrieval","words","module"],"Elixir.File"))
    remote=put_in(lexical,["stores","notes"],%{"kind"=>"mcp_cas","binding"=>"reviewed","partition"=>"project-a","contract"=>"ipse-cas-v1"})
    assert {:ok,_}=P.validate("corpus","mcp-lexical",remote)
    assert {:ok,_}=P.validate("corpus","mcp-lexical",put_in(remote,["stores","notes","contract"],"ipse-cas-v2"))
    assert {:ok,_}=P.validate("corpus","mcp-lexical",put_in(remote,["stores","notes","contract"],"ipse-cas-v3"))
    assert {:error,:invalid_profile}=P.validate("corpus","mcp-lexical",put_in(remote,["stores","notes","contract"],"ipse-cas-v4"))
    assert {:error,:profile_authority_mismatch}=P.validate("corpus","state-lexical",remote)
    assert {:error,:invalid_profile}=P.validate("corpus","mcp-lexical",put_in(remote,["stores","notes","endpoint"],"https://unreviewed"))
    assert {:error,:invalid_options}=P.validate("corpus","state-lexical",Map.delete(lexical,"extraction"))
    assert {:error,:invalid_options}=P.validate("corpus","state-lexical",Map.put(lexical,"raw_request",%{}))
    ''')
  end

  test "native structured output is a closed opt-in on existing model authority" do
    pure(~S'''
    model=%{"kind"=>"model_complete","profile"=>"judge","max_candidates"=>16,"quote_bytes"=>128}
    for family<-~w(rerank extraction) do
      {package,preset,options,profile}=if family=="rerank",
        do: {"corpus","state-rerank",lexical,model},
        else: {"graph","state-model",Map.merge(empty,%{"stores"=>lexical["stores"]}),%{"kind"=>"model_complete","profile"=>"extractor","version"=>1}}
      options=put_in(options,[family,"chosen"],profile)
      assert {:ok,_}=P.validate(package,preset,options)
      selected=put_in(options,[family,"chosen","output_contract"],"json_schema_v2")
      assert {:ok,_}=P.validate(package,preset,selected)
      for invalid<-[nil,"json","json_schema_v1","text",true] do
        assert {:error,:invalid_profile}=P.validate(package,preset,put_in(selected,[family,"chosen","output_contract"],invalid))
      end
      assert {:error,:invalid_profile}=P.validate(package,preset,put_in(selected,[family,"chosen","response_schema"],%{"type"=>"object"}))
    end
    ''')
  end

  test "Graph and Research reject retrieval profiles their package cannot execute" do
    pure(~S'''
    words=%{"kind"=>"bm25","version"=>1}
    remote=%{"kind"=>"mcp_query","binding"=>"unused","partition"=>"notes","contract"=>"query-v1"}
    graph=Map.merge(empty,%{"stores"=>%{"notes"=>%{"kind"=>"mcp_cas","binding"=>"store","partition"=>"notes","contract"=>"ipse-cas-v2"}},"extraction"=>%{"asserted"=>%{"kind"=>"explicit","version"=>1}}})
    assert {:ok,_}=P.validate("graph","mcp-explicit",graph)
    for profile <- [words,remote] do
      assert {:error,:profile_authority_mismatch}=P.validate("graph","mcp-explicit",put_in(graph,["retrieval","unused"],profile))
    end
    research=Map.merge(empty,%{"search"=>%{"s"=>%{"kind"=>"mcp","binding"=>"search","contract"=>"search-v1"}},"fetch"=>%{"f"=>%{"kind"=>"mcp","binding"=>"fetch","contract"=>"fetch-v1"}},"retrieval"=>%{"words"=>words}})
    assert {:ok,_}=P.validate("research","mcp",research)
    assert {:error,:profile_authority_mismatch}=P.validate("research","mcp",put_in(research,["retrieval","unused"],remote))
    ''')
  end

  test "closed graph and hybrid configurations preserve explicit algorithms and bounded options" do
    pure(~S'''
    opts=Map.merge(empty,%{"stores"=>lexical["stores"],"extraction"=>%{"asserted"=>%{"kind"=>"explicit","version"=>1}}})
    assert {:ok,_}=P.validate("graph","state-explicit",opts)
    model=put_in(opts,["extraction","learned"],%{"kind"=>"model_complete","profile"=>"reviewed","version"=>1})
    assert {:error,:profile_authority_mismatch}=P.validate("graph","state-explicit",model)
    assert {:ok,_}=P.validate("graph","state-model",model)
    hybrid=lexical|>put_in(["embedding","encoder"],%{"kind"=>"embedding","profile"=>"reviewed"})|>put_in(["retrieval","mix"],%{"kind"=>"hybrid","version"=>1,"lexical"=>"words","embedding"=>"encoder","graph"=>nil,"rrf_k"=>60,"missing_embedding"=>"lexical_with_gap"})
    assert {:ok,_}=P.validate("corpus","state-semantic",hybrid)
    assert {:error,:invalid_profile}=P.validate("corpus","state-semantic",put_in(hybrid,["retrieval","mix","missing_embedding"],"switch_provider"))
    too_many=Map.put(lexical,"retrieval",Map.new(1..9,&{"rank#{&1}",%{"kind"=>"bm25","version"=>1}}))
    assert {:error,:invalid_profile}=P.validate("corpus","state-lexical",too_many)
    ''')
  end
end
