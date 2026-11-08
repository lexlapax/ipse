defmodule Ipse.KnowledgeDomainRegressionsTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  for file <- ~w(evidence profiles adapters store/state store/mcp_cas store corpus graph research) do
    Code.require_file(Path.join("extensions/knowledge/src",file<>".ex"))
  end

  defmodule ResearchClock do
    def now do
      [tick|rest]=Process.get(:research_ticks)
      Process.put(:research_ticks,rest)
      tick
    end
  end

  defmodule ResearchWallClock do
    def now do
      case Process.get(:research_wall) do
        [value | rest] -> Process.put(:research_wall, rest); value
        [] -> raise "research wall clock exhausted"
        value -> value
      end
    end
  end

  # Exact boundary tests use a generated clock-controlled module; capture-completion tests use Research unchanged.
  File.read!("extensions/knowledge/src/research.ex")
  |> String.replace("defmodule IpseKnowledge.Research do","defmodule TimedResearch do")
  |> String.replace("System.monotonic_time(:millisecond)","ResearchClock.now()")
  |> Code.compile_string()

  File.read!("extensions/knowledge/src/research.ex")
  |> String.replace("defmodule IpseKnowledge.Research do","defmodule WallTimedResearch do")
  |> String.replace("System.system_time(:millisecond)","ResearchWallClock.now()")
  |> Code.compile_string()

  defmodule DomainRegressions do
    use ExUnit.Case, async: false
    alias IpseKnowledge.{Adapters,Corpus,Evidence,Graph,Research}

    test "public query callbacks and schemas enforce portable time before host proposals" do
      max=Evidence.safe_integer_max()
      options=%{"stores"=>%{"notes"=>%{"kind"=>"state","scope"=>"project","partition"=>"notes"}},
        "retrieval"=>%{"words"=>%{"kind"=>"bm25","version"=>1}},"rerank"=>%{}}
      state=%{resolved: %{"options"=>options},phase: :idle,ctx: nil,cont: nil,pending: nil}
      corpus=%{"store"=>"notes","retrieval"=>"words","rerank"=>nil,"query"=>"Release","top_k"=>1,"as_of_ms"=>max}
      graph=%{"store"=>"notes","entity"=>"Release","depth"=>1,"max_nodes"=>8,"max_edges"=>8,"top_k"=>1,"as_of_ms"=>max}
      for {module,args} <- [{Corpus,corpus},{Graph,graph}] do
        for at <- [max,nil] do
          assert {:ok,%{"kind"=>"host_call"},_}=
            module.handle("invoke.command",%{"id"=>"query","arguments"=>Map.put(args,"as_of_ms",at)},state)
        end
        assert {:ok,%{"value"=>%{"status"=>"refused"}},_}=
          module.handle("invoke.command",%{"id"=>"query","arguments"=>Map.put(args,"as_of_ms",max+1)},state)
        entry=Enum.find(module.describe()["exports"]["commands"],&(&1["id"]=="query"))
        assert :ok=Ipse.JSON.validate_arguments(entry["arguments_schema"],args)
        assert {:error,_}=Ipse.JSON.validate_arguments(entry["arguments_schema"],Map.put(args,"as_of_ms",max+1))
      end
    end

    test "provided source identities and remote fetch times refuse unsafe integers" do
      max=Evidence.safe_integer_max()
      options=%{"search"=>%{"given"=>%{"kind"=>"provided","version"=>1}},
        "fetch"=>%{"given"=>%{"kind"=>"provided","version"=>1}},
        "retrieval"=>%{"words"=>%{"kind"=>"bm25","version"=>1}},
        "rerank"=>%{"judge"=>%{"kind"=>"model_complete","profile"=>"judge","max_candidates"=>16,"quote_bytes"=>128}}}
      source=%{"source_id"=>"one","generation"=>1,"title"=>"One","text"=>"Release requires lock.",
        "uri"=>"local:one","observed_at_ms"=>1,"event_at_ms"=>nil,"expires_at_ms"=>nil}
      args=%{"search"=>"given","fetch"=>"given","retrieval"=>"words","rerank"=>"judge","query"=>"Release",
        "limits"=>%{"timeout_ms"=>30000,"max_sources"=>1,"max_body_bytes"=>49152},"sources"=>[source],"as_of_ms"=>max-1}
      state=%{resolved: %{"options"=>options},phase: :idle,cont: nil,ctx: nil}
      for field <- ~w(generation observed_at_ms event_at_ms expires_at_ms) do
        safe=put_in(args,["sources"],[Map.put(source,field,max)])
        assert {:ok,result,_}=Research.handle("invoke.command",%{"id"=>"investigate","arguments"=>safe},state)
        refute result["value"] && result["value"]["status"]=="refused"
        unsafe=put_in(args,["sources"],[Map.put(source,field,max+1)])
        assert {:ok,%{"value"=>%{"status"=>"refused"}},_}=
          Research.handle("invoke.command",%{"id"=>"investigate","arguments"=>unsafe},state)
      end
      for at <- [nil,max+1] do
        assert {:ok,%{"value"=>%{"status"=>"refused"}},_}=
          Research.handle("invoke.command",%{"id"=>"investigate","arguments"=>Map.put(args,"as_of_ms",at)},state)
      end
      for at <- [max,max+1] do
        resolved=%{"options"=>%{"fetch"=>%{"web"=>%{"kind"=>"mcp","binding"=>"f","contract"=>"fetch-v1"}}}}
        text="Release"
        response=%{"version"=>1,"contract"=>"fetch-v1","status"=>"ok","requested_uri"=>"local:one",
          "observed_uri"=>"local:one","media_type"=>"text/plain","observed_at_ms"=>at,"text"=>text,
          "body_sha256"=>Evidence.sha256(text),"complete"=>true,"start_byte"=>0,"end_byte"=>byte_size(text)}
        {:call,_,cont}=Adapters.start(resolved,:fetch,%{"profile"=>"web","uri"=>"local:one","timeout_ms"=>2000})
        {cont,page}=text_page(cont,response)
        result=Adapters.resume(cont,%{"status"=>"ok","value"=>page})
        if at==max,do: assert(match?({:done,{:ok,_}},result)),else: assert(match?({:done,{:error,:invalid_remote_result,%{}}},result))
      end
    end

    test "hybrid fuses one chunk while preserving graph claim bases and eligible seed" do
      text="Preface. Release requires lock. Release does not require lock."
      {:ok,source}=Evidence.source(%{"source_id"=>"one","partition"=>"notes","generation"=>1,
        "title"=>"One","text"=>text,"uri"=>"local:one","observed_at_ms"=>1,"event_at_ms"=>nil,
        "expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"notes",
          "partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}})
      {:ok,[chunk]}=Evidence.chunks(source)
      facts=for {polarity,quote} <- [{"positive","Release requires lock."},{"negative","Release does not require lock."}] do
        {start,length}=:binary.match(text,quote)
        {:ok,citation}=Evidence.citation(source,chunk,start,start+length)
        {:ok,fact}=Evidence.fact(%{"subject"=>"Release","predicate"=>"requires","object"=>"lock",
          "polarity"=>polarity,"inferred"=>false,"valid_from_ms"=>nil,"valid_to_ms"=>nil,
          "extraction"=>%{"kind"=>"explicit","profile"=>nil,"version"=>1},"citations"=>[citation]})
        fact
      end
      {:ok,excluded}=Evidence.fact(hd(facts) |> Map.drop(~w(version fact_id)) |> Map.merge(%{"subject"=>"A","valid_to_ms"=>20}))
      {:ok,vector}=Evidence.vector(%{"chunk_id"=>chunk["chunk_id"],"selection_sha256"=>Evidence.sha256("selection"),
        "input_sha256"=>Evidence.sha256(JSON.encode!([text])),"profile"=>"encoder","model"=>"fixture",
        "dimensions"=>1,"values"=>[1.0]})
      {cont,page}=embedding()
      snapshot=%{"sources"=>[source],"tokens"=>[],"gaps"=>[],"coverage"=>%{"generation"=>7},
        "projections"=>%{source["source_key"]=>%{"vectors"=>[vector],"facts"=>[excluded|facts]}}}
      state=%{phase: :query_embed,pending: :adapter,cont: cont,
        resolved: %{"options"=>%{"retrieval"=>%{"links"=>%{"kind"=>"graph","depth"=>2,"max_nodes"=>8,"max_edges"=>8}}}},
        ctx: %{snapshot: snapshot,as_of_ms: 20,query_time_scope: :full,query_time_transition: nil,
          store_profile: %{"kind"=>"state","scope"=>"project","partition"=>"notes"},
          args: %{"query"=>"A Release","top_k"=>1,"store"=>"notes","rerank"=>nil,"as_of_ms"=>20},
          retrieval: %{"kind"=>"hybrid","missing_embedding"=>"refuse","graph"=>"links"}}}
      assert {:ok,%{"kind"=>"host_call","request"=>request},pending}=
        Corpus.handle("host.actions",%{"outcome"=>%{"status"=>"ok","value"=>page}},state)
      assert request==%{"op"=>"state.get","scope"=>"project",
        "key"=>Evidence.id("namespace-generation-probe",["notes"])}
      missing=%{"key"=>request["key"],"revision"=>0,"deleted"=>true,"value"=>nil,"operation_id"=>nil}
      answer=fn generation -> %{"outcome"=>%{"status"=>"ok","value"=>%{"generation"=>generation,"record"=>missing}}} end
      assert {:ok,%{"value"=>%{"status"=>"conflict","evidence"=>[],"claims"=>[]}},_}=
        Corpus.handle("host.actions",answer.(8),pending)
      assert {:ok,%{"value"=>result},_}=Corpus.handle("host.actions",answer.(7),pending)
      assert result["status"]=="ok"
      assert [candidate]=result["evidence"]
      assert candidate["score"]==3/61
      assert candidate["citation"]["start_byte"]==0
      assert candidate["citation"]["quote"]==text
      assert result["coverage"]["components"]["graph"]["seed"]=="Release"
      assert Enum.map(result["claims"],& &1["basis"])==Enum.map(facts,& &1["citations"])
      assert Enum.all?(result["claims"],&(&1["label"]=="conflict"))
    end

    test "hybrid graph failures retain their stage instead of blaming embeddings" do
      {cont,page}=embedding()
      state=%{phase: :query_embed,pending: :adapter,cont: cont,
        resolved: %{"options"=>%{"retrieval"=>%{}}},
        ctx: %{snapshot: %{"sources"=>[],"projections"=>%{}},as_of_ms: 20,
          args: %{"query"=>"Release","top_k"=>1},
          retrieval: %{"kind"=>"hybrid","missing_embedding"=>"refuse","graph"=>"missing"}}}
      assert {:ok,%{"value"=>%{"status"=>"refused","gaps"=>[%{"code"=>"invalid_graph_profile"}]}},_}=
        Corpus.handle("host.actions",%{"outcome"=>%{"status"=>"ok","value"=>page}},state)
    end

    test "generated-clock fetch samples the remaining deadline once at 999, 1000 and 1001 milliseconds" do
      for remaining <- [999,1000,1001] do
        resolved=%{"options"=>%{"search"=>%{"s"=>%{"kind"=>"mcp","binding"=>"s","contract"=>"search-v1"}},
          "fetch"=>%{"f"=>%{"kind"=>"mcp","binding"=>"f","contract"=>"fetch-v1"}}}}
        args=%{"search"=>"s","fetch"=>"f","rerank"=>nil,"query"=>"Release",
          "limits"=>%{"timeout_ms"=>1001,"max_sources"=>1}}
        hit=%{"source_id"=>"one","uri"=>"local:one","title"=>"One","snippet"=>"Release"}
        response=%{"version"=>1,"contract"=>"search-v1","status"=>"ok","hits"=>[hit],
          "coverage"=>%{"complete"=>true},"next"=>nil}
        {:call,_,cont}=Adapters.start(resolved,:search,%{"profile"=>"s","query"=>"Release","limit"=>1})
        {cont,page}=text_page(cont,response)
        state=%{phase: :search,cont: cont,resolved: resolved,ctx: %{args: args,started: 0,
          hits: [],remaining: [],receipts: []}}
        Process.put(:research_ticks,[1001-remaining,1002-remaining])
        {:ok,result,_}=TimedResearch.handle("host.actions",%{"outcome"=>%{"status"=>"ok","value"=>page}},state)
        if remaining<1000 do
          assert result["value"]["gaps"]==[%{"code"=>"time_limit"}]
        else
          assert result["kind"]=="host_call"
          assert result["request"]["timeout_ms"]==remaining
        end
        assert length(Process.get(:research_ticks))==1
      end
    end

    test "generated-clock model rerank samples the same 1000 millisecond deadline guard and dispatch value" do
      for remaining <- [999,1000,1001] do
        options=%{"version"=>1,"stores"=>%{},"embedding"=>%{},"extraction"=>%{},
          "search"=>%{"given"=>%{"kind"=>"provided","version"=>1}},
          "fetch"=>%{"given"=>%{"kind"=>"provided","version"=>1}},
          "retrieval"=>%{"words"=>%{"kind"=>"bm25","version"=>1}},
          "rerank"=>%{"judge"=>%{"kind"=>"model_complete","profile"=>"judge","max_candidates"=>16,"quote_bytes"=>128}}}
        args=%{"search"=>"given","fetch"=>"given","retrieval"=>"words","rerank"=>"judge",
          "query"=>"Release","limits"=>%{"timeout_ms"=>1001,"max_sources"=>1,"max_body_bytes"=>49152},
          "sources"=>[%{"source_id"=>"one","generation"=>1,"title"=>"One","text"=>"Release requires lock.",
            "uri"=>"local:one","observed_at_ms"=>1,"event_at_ms"=>nil,"expires_at_ms"=>nil}]}
        state=%{resolved: %{"options"=>options},phase: :idle,cont: nil,ctx: nil}
        Process.put(:research_ticks,[0,1001-remaining,1002-remaining])
        {:ok,result,_}=TimedResearch.handle("invoke.command",%{"id"=>"investigate","arguments"=>args},state)
        if remaining<1000 do
          assert result["value"]["gaps"]==[%{"code"=>"time_limit"}]
        else
          assert result["kind"]=="host_call"
          assert result["request"]["timeout_ms"]==remaining
        end
        assert length(Process.get(:research_ticks))==1
      end
    end

    test "unmodified Research publishes a complete empty search below the next-action time allowance" do
      {resolved,args}=research_selection()
      response=%{"version"=>1,"contract"=>"search-v1","status"=>"ok","hits"=>[],
        "coverage"=>%{"complete"=>true},"next"=>nil}
      {:call,_,cont}=Adapters.start(resolved,:search,%{"profile"=>"web","query"=>"release","limit"=>2})
      {cont,page}=text_page(cont,response)

      for remaining <- [1,500,999] do
        state=research_state(resolved,args,:search,cont,[],remaining)
        assert {:ok,%{"kind"=>"result","value"=>result},_}=
          Research.handle("host.actions",%{"outcome"=>%{"status"=>"ok","value"=>page}},state)
        assert result["status"]=="abstain" and result["gaps"]==[]
        assert result["evidence"]==[] and result["coverage"]["complete"]
        assert result["coverage"]["source_count"]==0 and result["coverage"]["bytes"]==0
      end
    end

    test "unmodified Research retains a hash-valid final capture below the next-action time allowance" do
      {resolved,args}=research_selection()
      hit=research_hit("one")
      {cont,page,text}=fetch_page(resolved,hit)

      for remaining <- [1,500,999] do
        state=research_state(resolved,args,:fetch,cont,[hit],remaining)
        assert {:ok,%{"kind"=>"result","value"=>result},_}=
          Research.handle("host.actions",%{"outcome"=>%{"status"=>"ok","value"=>page}},state)
        assert result["status"]=="ok" and result["gaps"]==[]
        assert result["coverage"]["complete"] and result["coverage"]["source_count"]==1
        assert result["coverage"]["bytes"]==byte_size(text)
        assert [candidate]=result["evidence"]
        assert candidate["citation"]["quote"]==text
        assert candidate["citation"]["quote_sha256"]==Evidence.sha256(text)
        assert candidate["citation"]["origin"]["receipt"]["body_sha256"]==Evidence.sha256(text)
      end
    end

    test "unmodified Research still refuses a queued next fetch below 1000 milliseconds" do
      {resolved,args}=research_selection()
      hit=research_hit("one")
      {cont,page,_}=fetch_page(resolved,hit)
      state=research_state(resolved,args,:fetch,cont,[hit,research_hit("two")],999)
      assert {:ok,%{"kind"=>"result","value"=>%{"status"=>"refused","gaps"=>[%{"code"=>"time_limit"}]}},_}=
        Research.handle("host.actions",%{"outcome"=>%{"status"=>"ok","value"=>page}},state)
    end

    test "research rechecks all current source transitions after reranking" do
      source = fn id, observed, expires ->
        {:ok, value} = Evidence.source(%{
          "source_id" => id, "partition" => "research-provided", "generation" => 1,
          "title" => id, "text" => "Release requires an audit.", "uri" => "local:" <> id,
          "observed_at_ms" => observed, "event_at_ms" => nil, "expires_at_ms" => expires,
          "origin" => %{"kind" => "provided", "store_profile" => nil,
            "partition_or_scope" => nil, "receipt" => nil, "historical" => false}
        })
        value
      end

      current = source.("current", 1, 200)
      future = source.("future", 150, nil)
      resolved = %{"options" => %{"rerank" => %{"judge" => %{"kind" => "model_complete",
        "profile" => "judge", "max_candidates" => 16, "quote_bytes" => 128}}}}
      run = fn sources, args, wall ->
        {:ok, ranked} = Evidence.rank_lexical(sources, "release", 10, 100)
        {:call, _, cont} = Adapters.start(resolved, :rerank,
          %{"profile" => "judge", "query" => "release", "candidates" => ranked["evidence"]})
        state = %{resolved: resolved, phase: :rerank, cont: cont,
          ctx: %{args: Map.merge(%{"query" => "release"}, args), ranked: ranked, at: 100,
            sources: sources, bytes: 1, profile: %{"kind" => "provided"}}}
        Process.put(:research_wall, wall)
        outcome = %{"status" => "ok", "value" => %{"profile" => "judge",
          "text" => JSON.encode!(%{"order" => ["e1"]}), "usage" => %{}}}
        {:ok, %{"kind" => "result", "value" => result}, _} =
          WallTimedResearch.handle("host.actions", %{"outcome" => outcome}, state)
        result
      end

      assert run.([current, future], %{}, 149)["status"] == "ok"
      for {sources, wall} <- [{[current, future], 150}, {[current], 200}, {[current], 99},
                              {[current], [199, 200]}, {[current], [199, 198]}] do
        result = run.(sources, %{}, wall)
        assert result["status"] == "refused"
        assert result["gaps"] == [%{"code" => "query_time_changed"}]
        assert result["evidence"] == [] and result["claims"] == []
      end
      assert run.([current, future], %{"as_of_ms" => 100}, 201)["status"] == "ok"
      for expires <- [130, 150] do
        never_current = source.("never-current", 150, expires)
        assert run.([current, never_current], %{}, 160)["status"] == "ok"
      end
      historical_source = put_in(source.("historical", 150, nil), ["origin", "historical"], true)
      assert run.([current, historical_source], %{}, 160)["status"] == "ok"

      provided = Map.take(current, ~w(source_id generation title text uri observed_at_ms event_at_ms expires_at_ms))
      options = %{"options" => %{
        "search" => %{"given" => %{"kind" => "provided", "version" => 1}},
        "fetch" => %{"given" => %{"kind" => "provided", "version" => 1}},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "rerank" => resolved["options"]["rerank"]}}
      args = %{"search" => "given", "fetch" => "given", "retrieval" => "words",
        "rerank" => "judge", "query" => "release", "sources" => [provided],
        "limits" => %{"max_sources" => 1, "max_body_bytes" => 1024, "timeout_ms" => 30000}}
      initial = %{resolved: options, phase: :idle, ctx: nil, cont: nil}
      for {wall, kind} <- [{199, "host_call"}, {200, "result"}] do
        Process.put(:research_wall, [100, 100, wall])
        {:ok, reply, _} = WallTimedResearch.handle("invoke.command",
          %{"id" => "investigate", "arguments" => args}, initial)
        assert reply["kind"] == kind
        if kind == "result" do
          assert reply["value"]["gaps"] == [%{"code" => "query_time_changed"}]
          assert reply["value"]["evidence"] == [] and reply["value"]["claims"] == []
        end
      end
      Process.put(:research_wall, [100, 100, 199])
      {:ok, %{"kind" => "host_call"}, pending} = WallTimedResearch.handle("invoke.command",
        %{"id" => "investigate", "arguments" => args}, initial)
      Process.put(:research_wall, [198])
      rerank_outcome = %{"status" => "ok", "value" => %{"profile" => "judge",
        "text" => JSON.encode!(%{"order" => ["e1"]}), "usage" => %{}}}
      {:ok, %{"kind" => "result", "value" => rollback}, _} =
        WallTimedResearch.handle("host.actions", %{"outcome" => rerank_outcome}, pending)
      assert rollback["gaps"] == [%{"code" => "query_time_changed"}]
      assert rollback["evidence"] == [] and rollback["claims"] == []

      Process.put(:research_wall, [100, 100, 200])
      {:ok, no_rerank, _} = WallTimedResearch.handle("invoke.command",
        %{"id" => "investigate", "arguments" => Map.put(args, "rerank", nil)}, initial)
      assert no_rerank["value"]["gaps"] == [%{"code" => "query_time_changed"}]
      assert no_rerank["value"]["evidence"] == []

      Process.put(:research_wall, [100, 200])
      {:ok, historical, historical_state} = WallTimedResearch.handle("invoke.command",
        %{"id" => "investigate", "arguments" => Map.put(args, "as_of_ms", 100)}, initial)
      assert historical["kind"] == "host_call"
      Process.put(:research_wall, [])
      {:ok, %{"kind" => "result", "value" => historical_result}, _} =
        WallTimedResearch.handle("host.actions", %{"outcome" => rerank_outcome}, historical_state)
      assert historical_result["status"] == "ok"
      assert Process.get(:research_wall) == []
    end

    test "research discards a prepared paged result when source time crosses during encoding" do
      sources = for n <- 1..10 do
        id = "paged-#{n}"
        {:ok, source} = Evidence.source(%{
          "source_id" => id, "partition" => "research-provided", "generation" => 1,
          "title" => id, "text" => "release " <> String.duplicate("x", 980),
          "uri" => "local:" <> id, "observed_at_ms" => 1, "event_at_ms" => nil,
          "expires_at_ms" => 200,
          "origin" => %{"kind" => "provided", "store_profile" => nil,
            "partition_or_scope" => nil, "receipt" => nil, "historical" => false}
        })
        source
      end

      {:ok, ranked} = Evidence.rank_lexical(sources, "release", 10, 100)
      assert length(ranked["evidence"]) == 10
      resolved = %{"options" => %{"rerank" => %{"judge" => %{"kind" => "model_complete",
        "profile" => "judge", "max_candidates" => 16, "quote_bytes" => 128}}}}
      {:call, _, cont} = Adapters.start(resolved, :rerank,
        %{"profile" => "judge", "query" => "release", "candidates" => ranked["evidence"]})
      state = %{resolved: resolved, phase: :rerank, cont: cont,
        ctx: %{args: %{"query" => "release"}, ranked: ranked, at: 100,
          sources: sources, bytes: 9880, profile: %{"kind" => "provided"}}}
      order = Enum.map(1..10, &("e" <> Integer.to_string(&1)))
      outcome = %{"status" => "ok", "value" => %{"profile" => "judge",
        "text" => JSON.encode!(%{"order" => order}), "usage" => %{}}}

      Process.put(:research_wall, [199, 199])
      assert {:ok, %Ipse.Extension.ResultPublication.Output{} = paged, stable_state} =
        WallTimedResearch.handle("host.actions", %{"outcome" => outcome}, state)
      assert paged.byte_count > 12_000
      assert %{"status" => "ok", "evidence" => evidence} = JSON.decode!(paged.bytes)
      assert length(evidence) == 10
      assert stable_state == %{state | phase: :idle}
      assert Process.get(:research_wall) == []

      Process.put(:research_wall, [199, 200])
      assert {:ok, %{"kind" => "result", "value" => refusal}, refused_state} =
        WallTimedResearch.handle("host.actions", %{"outcome" => outcome}, state)
      assert refusal["status"] == "refused"
      assert refusal["gaps"] == [%{"code" => "query_time_changed"}]
      assert refusal["evidence"] == [] and refusal["claims"] == []
      assert refused_state == %{state | phase: :idle}
      assert Process.get(:research_wall) == []

      Process.put(:research_wall, [199, 198])
      assert {:ok, %{"kind" => "result", "value" => rollback}, _} =
        WallTimedResearch.handle("host.actions", %{"outcome" => outcome}, state)
      assert rollback["gaps"] == [%{"code" => "query_time_changed"}]
      assert rollback["evidence"] == [] and rollback["claims"] == []
    end

    defp research_selection do
      resolved=%{"options"=>%{"search"=>%{"web"=>%{"kind"=>"mcp","binding"=>"search","contract"=>"search-v1"}},
        "fetch"=>%{"web"=>%{"kind"=>"mcp","binding"=>"fetch","contract"=>"fetch-v1"}},
        "retrieval"=>%{"words"=>%{"kind"=>"bm25","version"=>1}},"rerank"=>%{}}}
      args=%{"search"=>"web","fetch"=>"web","retrieval"=>"words","rerank"=>nil,"query"=>"release",
        "limits"=>%{"max_sources"=>2,"max_body_bytes"=>1024,"timeout_ms"=>2000},"sources"=>[]}
      {resolved,args}
    end

    defp research_state(resolved,args,phase,cont,remaining_hits,remaining_ms) do
      %{resolved: resolved,phase: phase,cont: cont,
        ctx: %{args: args,at: 0,profile: %{"kind"=>"mcp"},fetch_profile: %{"kind"=>"mcp"},
          hits: remaining_hits,remaining: remaining_hits,sources: [],bytes: 0,receipts: [],
          started: System.monotonic_time(:millisecond)-(args["limits"]["timeout_ms"]-remaining_ms)}}
    end

    defp research_hit(id),
      do: %{"source_id"=>id,"uri"=>"local:"<>id,"title"=>id,"snippet"=>"release"}

    defp fetch_page(resolved,hit) do
      text="Release requires quiescence."
      response=%{"version"=>1,"contract"=>"fetch-v1","status"=>"ok","requested_uri"=>hit["uri"],
        "observed_uri"=>hit["uri"],"media_type"=>"text/plain","observed_at_ms"=>1,"text"=>text,
        "body_sha256"=>Evidence.sha256(text),"complete"=>true,"start_byte"=>0,"end_byte"=>byte_size(text)}
      {:call,_,cont}=Adapters.start(resolved,:fetch,%{"profile"=>"web","uri"=>hit["uri"],"timeout_ms"=>2000})
      {cont,page}=text_page(cont,response)
      {cont,page,text}
    end

    defp embedding do
      resolved=%{"options"=>%{"embedding"=>%{"enc"=>%{"kind"=>"embedding","profile"=>"encoder"}}}}
      {:call,_,cont}=Adapters.start(resolved,:embed,%{"profile"=>"enc",
        "inputs"=>[%{"chunk_id"=>Evidence.sha256("query:Release"),"text"=>"Release"}]})
      bytes=<<1.0::little-float-size(32)>>
      descriptor=%{"version"=>2,"kind"=>"embedding.f32le","encoding"=>"float32le.base64","vector_count"=>1,
        "dimensions"=>1,"source_sha256"=>Evidence.sha256("host result"),"operation_id"=>String.duplicate("1",32)}
      {:call,_,cont}=Adapters.resume(cont,%{"status"=>"ok","value"=>%{"version"=>2,
        "selection_sha256"=>Evidence.sha256("selection"),"profile"=>"encoder","reported_model"=>"fixture",
        "usage"=>%{},"result"=>descriptor}})
      page=Map.merge(Map.take(descriptor,~w(version kind encoding dimensions source_sha256 operation_id)),
        %{"vector_index"=>0,"offset"=>0,"complete"=>true,"next"=>nil,
          "input_sha256"=>Evidence.sha256(JSON.encode!(["Release"])),"vector_sha256"=>Evidence.sha256(bytes),
          "values"=>Base.encode64(bytes)})
      {cont,page}
    end

    defp text_page(cont,response) do
      text=JSON.encode!(response)
      descriptor=%{"version"=>1,"kind"=>"mcp.text","operation_id"=>String.duplicate("2",32),
        "source_sha256"=>Evidence.sha256(text),"byte_count"=>byte_size(text)}
      {:call,_,cont}=Adapters.resume(cont,%{"status"=>"ok","value"=>descriptor})
      {cont,Map.merge(descriptor,%{"offset"=>0,"complete"=>true,"next"=>nil,"text"=>text})}
    end
  end
  result=ExUnit.run()
  System.halt(if(result.failures==0 and result.total==11 and result.skipped==0 and result.excluded==0,do: 0,else: 1))
  """

  test "domain regressions execute in the isolated extension VM" do
    paths =
      for module <- [Ipse.Extension, Jason, JSONSchex, ExJSONPointer],
          path = module |> :code.which() |> to_string() |> Path.dirname(),
          do: ["-pa", path]

    {output, status} =
      System.cmd(System.find_executable("elixir"), List.flatten(paths) ++ ["-e", @suite],
        cd: Path.expand("../../..", __DIR__),
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
