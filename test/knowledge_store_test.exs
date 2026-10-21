defmodule Ipse.KnowledgeStoreTest do
  use ExUnit.Case, async: false
  @root Path.expand("..", __DIR__)

  defp isolated(body) do
    paths = ~w(evidence.ex store/state.ex store/mcp_cas.ex store.ex)

    args =
      Enum.flat_map(Enum.reject(:code.get_path(), &(&1 == ~c".")), &["-pa", List.to_string(&1)]) ++
        Enum.flat_map(paths, &["-r", Path.join(@root, "extensions/knowledge/src/" <> &1)]) ++
        [
          "-r",
          Path.join(@root, "dev/verification/cli.exs"),
          "-e",
          "Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)"
        ]

    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.Evidence, as: E
    alias IpseKnowledge.Store, as: S
    alias Ipse.Development.Fixtures.Knowledge, as: F
    defmodule Driver do
      def run({:call,request,continuation},db) do
        {outcome,db}=Ipse.Development.Fixtures.Knowledge.host(db,request)
        run(IpseKnowledge.Store.resume(continuation,outcome),db)
      end
      def run(result,db), do: {result,db}

      def hold({:call,%{"op"=>"mcp.call","arguments"=>%{"action"=>action}},_}=call,db)
        when action in ~w(put_immutable_many cas_root collect),do: {call,db}
      def hold({:call,request,continuation},db) do
        {outcome,db}=Ipse.Development.Fixtures.Knowledge.host(db,request)
        hold(IpseKnowledge.Store.resume(continuation,outcome),db)
      end

      def rewrite_projection(db,ref,transform) do
        row=db.records[ref["key"]]; body=row["value"]["body"]
        {db,previous}=if body["previous"]==nil,do: {db,nil},else: rewrite_projection(db,body["previous"],transform)
        {records,db}=Enum.map_reduce(body["records"],db,fn record,db ->
          {pages,db}=Enum.map_reduce(record["pages"],db,fn part,db ->
            rewrite_page(db,db.records[part["key"]],transform.(db.records[part["key"]]["value"]["body"]))
          end)
          {Map.put(transform.(record),"pages",pages),db}
        end)
        {ref,db}=rewrite_page(db,row,%{body|"previous"=>previous,"records"=>records})
        {db,ref}
      end

      def rewrite_page(db,row,body) do
        alias IpseKnowledge.Evidence, as: E
        value=put_in(row["value"],["body"],body)
        value=Map.put(value,"body_sha256",E.id("page-body",[value["page_kind"],ordered(body)]))
        key=E.id("page",[value["partition"],value["source_key"],value["generation"],value["draft_id"],value["page_kind"],value["ordinal"],value["body_sha256"]])
        row=%{row|"key"=>key,"value"=>value}
        ref=%{"key"=>key,"sha256"=>E.id("page-record",[ordered(value)])}
        {ref,put_in(db.records[key],row)}
      end

      defp ordered(map) when is_map(map),do: ["map",Enum.map(Enum.sort(map),fn {k,v}->[k,ordered(v)] end)]
      defp ordered(list) when is_list(list),do: ["list",Enum.map(list,&ordered/1)]
      defp ordered(value),do: value
    end
    state=%{"kind"=>"state","scope"=>"project","partition"=>"notes"}
    remote=%{"kind"=>"mcp_cas","binding"=>"storage","partition"=>"notes","contract"=>"ipse-cas-v3"}
    invoke=fn db,profile,op,args -> Driver.run(S.start("notes",profile,op,args),db) end
    put=fn text,extra -> Map.merge(%{"source_id"=>"manual:one","generation"=>1,"expected_revision"=>0,"title"=>"A manual","text"=>text,"uri"=>"local:manual","observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil},extra) end
    success=fn result -> assert {:done,{:ok,value}}=result; value end
    snapshot=fn db,profile -> {result,db}=invoke.(db,profile,:snapshot,%{}); {success.(result),db} end
    effects=fn db -> F.requests(db) |> Enum.count(&(&1["op"] not in ~w(state.scan state.get effect.result.read))) end
    selected_args=fn db,refs,extra -> Map.merge(%{"refs"=>refs,"store_generation"=>db.generation,"effects_used"=>1,"reads_used"=>2,"as_of_ms"=>20},extra) end
    '''

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["-e", bootstrap <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute Code.ensure_loaded?(IpseKnowledge.Store)
    refute Code.ensure_loaded?(IpseKnowledge.Store.State)
    refute Code.ensure_loaded?(IpseKnowledge.Store.MCPCAS)
  end

  test "source timestamps refuse before Store reads at unsafe integer values" do
    isolated(~S'''
    max=E.safe_integer_max()
    for profile <- [state,remote], operation <- [:put,:open] do
      args=put.("text",%{})
      args=if operation==:open,
        do: args |> Map.delete("text") |> Map.merge(%{"byte_count"=>4,"content_sha256"=>E.sha256("text")}),
        else: args
      for field <- ~w(observed_at_ms event_at_ms expires_at_ms) do
        assert {:call,_,_}=S.start("notes",profile,operation,Map.put(args,field,max))
        assert {:done,{:error,:invalid_store_arguments,%{}}}=
          S.start("notes",profile,operation,Map.put(args,field,max+1))
      end
    end
    ''')
  end

  @tag :projection_slot
  test "full projection heads refuse before Corpus and Graph inference but permit existing profiles" do
    isolated(~S"""
    for file <- ~w(profiles adapters corpus graph),
      do: Code.require_file(Path.join("extensions/knowledge/src", file <> ".ex"))

    defmodule HeadDriver do
      def run({:ok, %{"kind" => "host_call", "request" => %{"op" => op} = request}, _}, db, _)
          when op in ~w(embedding.create model.complete), do: {{:inference, request}, db}
      def run({:ok, %{"kind" => "host_call", "request" => request}, next}, db, module) do
        {outcome, db} = Ipse.Development.Fixtures.Knowledge.host(db, request)
        run(module.handle("host.actions", %{"outcome" => outcome}, next), db, module)
      end
      def run({:ok, %{"kind" => "result", "value" => value}, _}, db, _), do: {value, db}
      def invoke(module, resolved, id, args, db) do
        initial = %{resolved: resolved, phase: :idle, ctx: nil, cont: nil, pending: nil}
        module.handle("invoke.command", %{"id" => id, "arguments" => args}, initial)
        |> run(db, module)
      end
    end

    for backend <- [state, remote] do
      {result, db} = invoke.(F.new(), backend, :put, put.("Release requires tests.", %{}))
      success.(result)
      {snap, db} = snapshot.(db, backend)
      {:ok, [chunk]} = E.chunks(hd(snap["sources"]))
      chunks = [chunk["chunk_id"]]
      open = %{"source_id" => "manual:one", "generation" => 1, "chunks" => chunks}
      embedding = %{"kind" => "embedding", "profile" => "encoder1"}
      model = fn i -> %{"kind" => "model_complete", "profile" => "extractor#{i}", "version" => 1} end
      {:ok, vector} = E.vector(%{"chunk_id" => chunk["chunk_id"],
        "selection_sha256" => E.sha256("selection"), "input_sha256" => E.sha256("input"),
        "profile" => "encoder1", "model" => "synthetic", "dimensions" => 1, "values" => [1.0]})
      profiles = [{"vectors", embedding, [vector]}] ++
        Enum.map(1..7, &{"facts", model.(&1), []})
      db = Enum.reduce(profiles, db, fn {kind, profile, items}, db ->
        args = Map.merge(open, %{"projection_kind" => kind, "profile" => profile})
        {result, db} = invoke.(db, backend, :projection_open, args)
        opened = success.(result)
        {result, db} = invoke.(db, backend, :projection_commit,
          %{"draft" => opened["draft"], kind => items})
        success.(result)
        db
      end)
      [root] = Enum.filter(Map.values(db.records), &(get_in(&1, ["value", "kind"]) == "root"))
      assert map_size(root["value"]["projections"]) == 8
      assert root["value"]["draft"] == nil
      empty = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
        |> Map.put("version", 1) |> Map.put("stores", %{"notes" => backend})
        |> Map.put("retrieval", %{"words" => %{"kind" => "bm25", "version" => 1}})
      corpus_options = Map.put(empty, "embedding", %{"existing" => embedding,
        "ninth" => %{"kind" => "embedding", "profile" => "encoder9"}})
      graph_options = empty |> Map.put("retrieval", %{}) |> Map.put("extraction", %{"existing" => model.(1), "ninth" => model.(9)})
      corpus_preset = if backend["kind"] == "state", do: "state-dense", else: "mcp-dense"
      graph_preset = if backend["kind"] == "state", do: "state-model", else: "mcp-model"
      {:ok, corpus} = IpseKnowledge.Profiles.validate("corpus", corpus_preset, corpus_options)
      {:ok, graph} = IpseKnowledge.Profiles.validate("graph", graph_preset, graph_options)
      index = Map.merge(open, %{"store" => "notes", "action" => "next", "embedding" => "ninth"})
      extract = Map.merge(open, %{"store" => "notes", "extraction" => "ninth", "max_edges" => 1, "facts" => []})
      for {module, resolved, id, args, key, operation} <- [
        {IpseKnowledge.Corpus, corpus, "index", index, "embedding", "embedding.create"},
        {IpseKnowledge.Graph, graph, "extract", extract, "extraction", "model.complete"}
      ] do
        {result, unchanged} = HeadDriver.invoke(module, resolved, id, args, %{db | requests: []})
        assert result == %{"version" => 1, "status" => "refused", "evidence" => [], "claims" => [],
          "gaps" => [%{"code" => "projection_bounds"}], "coverage" => %{}, "continuation" => nil}
        assert unchanged.records == db.records
        assert unchanged.generation == db.generation
        refute Enum.any?(F.requests(unchanged), fn request ->
          request["op"] in ~w(state.put embedding.create model.complete) or
            get_in(request, ["arguments", "action"]) in ~w(cas_root put_immutable_many)
        end)
        assert {{:inference, %{"op" => ^operation}}, _} =
          HeadDriver.invoke(module, resolved, id, Map.put(args, key, "existing"), db)
      end
    end
    """)
  end

  test "State and independent MCP publish only selected immutable pages and permanently suppress a source" do
    isolated(~S'''
    for profile <- [state,remote] do
      {r,db}=invoke.(F.new(),profile,:put,put.("Le café preserves byte offsets.",%{})); stored=success.(r)
      assert stored["generation"]==1
      {snap,db}=snapshot.(db,profile)
      assert [source]=snap["sources"]
      assert source["text"]=="Le café preserves byte offsets."
      assert source["origin"]["kind"]=="provided"
      assert is_integer(snap["coverage"]["effects_used"])
      assert is_integer(snap["coverage"]["revalidate_effects_worst_case"])
      {r,db}=invoke.(db,profile,:inspect,%{"source_id"=>"manual:one"}); inspected=success.(r)
      assert length(inspected["chunks"])==1
      refute Map.has_key?(inspected,"text")
      {r,db}=invoke.(db,profile,:put,put.("second generation",%{"generation"=>2,"expected_revision"=>stored["revision"]})); stored2=success.(r)
      {r,db}=invoke.(db,profile,:revalidate,%{"tokens"=>snap["tokens"]})
      refute success.(r)["valid"]
      {snap,db}=snapshot.(db,profile); assert hd(snap["sources"])["text"]=="second generation"
      {r,db}=invoke.(db,profile,:forget,%{"source_id"=>"manual:one","expected_revision"=>stored2["revision"],"suppressed_at_ms"=>20}); suppressed=success.(r)
      assert suppressed["generation"]==3
      {r,db}=invoke.(db,profile,:put,put.("revive",%{"generation"=>4,"expected_revision"=>suppressed["revision"]}))
      assert {:done,{:error,:source_suppressed,%{}}}=r
      {snap,db}=snapshot.(db,profile); assert snap["sources"]==[]; assert [%{"code"=>"suppressed"}]=snap["gaps"]
      key=S.root_key("notes",E.sha256("manual:one")); root=db.records[key]["value"]
      assert Enum.sort(Map.keys(root))==Enum.sort(~w(format kind partition source_key generation state suppressed_at_ms))
      {r,db}=invoke.(db,profile,:collect,%{"limit"=>12}); assert success.(r)["record_slots_recovered"]==0
      assert Enum.any?(Map.values(db.records),& &1["deleted"])
      assert map_size(db.records)>1
    end
    ''')
  end

  test "named State partitions cannot collide and caller origin cannot grant fetch authority" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),state,:put,put.("partition one",%{})); success.(r)
    other=Map.put(state,"partition","other")
    {r,db}=invoke.(db,other,:put,put.("partition two",%{})); success.(r)
    {one,db}=snapshot.(db,state); {two,_}=snapshot.(db,other)
    assert hd(one["sources"])["text"]=="partition one"
    assert hd(two["sources"])["text"]=="partition two"
    refute S.root_key("notes",E.sha256("manual:one"))==S.root_key("other",E.sha256("manual:one"))
    forged=put.("forged",%{"origin"=>%{"kind"=>"fetch","receipt"=>%{"native"=>true}}})
    assert {:done,{:error,:invalid_store_arguments,%{}}}=S.start("notes",state,:put,forged)
    assert {:done,{:error,:invalid_store_arguments,%{}}}=S.start("notes",Map.put(state,"partition","../bad"),:snapshot,%{})
    ''')
  end

  test "64 KiB UTF8 ingestion is explicit contiguous append then hash-checked publication" do
    isolated(~S'''
    text=String.duplicate("é",32768)
    args=put.(text,%{}) |> Map.delete("text") |> Map.merge(%{"byte_count"=>byte_size(text),"content_sha256"=>E.sha256(text)})
    {r,db}=invoke.(F.new(),state,:open,args); draft=success.(r)
    {snap,db}=snapshot.(db,state); assert snap["sources"]==[]
    {r,db}=invoke.(db,state,:append,%{"source_id"=>"manual:one","draft_id"=>draft["draft_id"],"expected_revision"=>draft["revision"],"offset"=>1,"text"=>"é"})
    assert {:done,{:error,:invalid_append,%{}}}=r
    {draft,db}=Enum.reduce(0..15,{draft,db},fn index,{draft,db} ->
      part=binary_part(text,index*4096,4096)
      {r,db}=invoke.(db,state,:append,%{"source_id"=>"manual:one","draft_id"=>draft["draft_id"],"expected_revision"=>draft["revision"],"offset"=>index*4096,"text"=>part})
      draft=success.(r)
      if index==0 do
        {r,db2}=invoke.(db,state,:collect,%{"limit"=>12}); assert success.(r)["count"]==0; assert db2.records==db.records
      end
      {draft,db}
    end)
    {r,db}=invoke.(db,state,:publish,%{"source_id"=>"manual:one","draft_id"=>draft["draft_id"],"expected_revision"=>draft["revision"]}); success.(r)
    {snap,db}=snapshot.(db,state); assert [source]=snap["sources"]; assert source["text"]==text
    {:ok,chunks}=E.chunks(source); assert length(chunks)==32; assert Enum.map_join(chunks,& &1["text"])==text
    assert Enum.all?(Map.values(db.records),fn row -> byte_size(IO.iodata_to_binary(JSON.encode!(row["value"])))<=6000 end)
    assert effects.(db)>16
    # Each append is a separate explicit invocation; one invocation's ceiling stays16.
    ''')
  end

  test "two full4096 vectors publish through exactly16 accounted effects without truncation" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),state,:put,put.(String.duplicate("a",3000),%{})); success.(r)
    {snap,db}=snapshot.(db,state); source=hd(snap["sources"]); {:ok,chunks}=E.chunks(source)
    profile=%{"kind"=>"embedding","profile"=>"encoder"}; ids=Enum.map(chunks,& &1["chunk_id"])
    db=%{db|requests: []}
    {r,db}=invoke.(db,state,:projection_open,%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>"vectors","profile"=>profile,"chunks"=>ids})
    opened=success.(r); assert opened["coverage"]["total_effects"]==16
    assert opened["coverage"]["effects_remaining"]==15
    assert opened["coverage"]["commit_effects_worst_case"]==14
    values=Enum.map(1..4096,&(&1/4096))
    vectors=Enum.map(chunks,fn chunk -> {:ok,v}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"selection_sha256"=>E.sha256("selected encoder"),"input_sha256"=>E.sha256("host canonical input"<>chunk["chunk_id"]),"profile"=>"encoder","model"=>"native-model","dimensions"=>4096,"values"=>values}); v end)
    {r,db}=invoke.(db,state,:projection_commit,%{"draft"=>opened["draft"],"vectors"=>vectors}); success.(r)
    assert effects.(db)+1==16
    pages=Map.values(db.records) |> Enum.filter(&(get_in(&1,["value","page_kind"])=="vector"))
    assert length(pages)==12
    assert Enum.all?(pages,fn row -> body=row["value"]["body"]; byte_size(Base.decode64!(body["values"]))<=768*4 end)
    assert {:ok,inventory}=S.inventory(%{"records"=>db.records,"generation"=>db.generation},"notes")
    selected=MapSet.new(hd(inventory["roots"])["selected_refs"],& &1["key"])
    assert Enum.all?(pages,&MapSet.member?(selected,&1["key"]))
    {snap,_}=snapshot.(db,state); actual=snap["projections"][source["source_key"]]["vectors"]
    assert Enum.sort_by(actual,& &1["chunk_id"])==Enum.sort_by(vectors,& &1["chunk_id"])
    ''')
  end

  test "one full4096 vector fits MCP reservation and all existing page and SDK bounds" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),remote,:put,put.("maximum dimensions",%{})); success.(r)
    {snap,db}=snapshot.(db,remote); source=hd(snap["sources"]); {:ok,[chunk]}=E.chunks(source)
    selected=%{"kind"=>"embedding","profile"=>"encoder"}
    db=%{db|requests: []}
    {r,db}=invoke.(db,remote,:projection_open,%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>"vectors","profile"=>selected,"chunks"=>[chunk["chunk_id"]]})
    opened=success.(r); assert opened["coverage"]["total_effects"]<=16
    {:ok,vector}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"input_sha256"=>E.sha256("input"),"selection_sha256"=>E.sha256("selected encoder"),"profile"=>"encoder","model"=>"same-model","dimensions"=>4096,"values"=>[1.0|List.duplicate(0.0,4095)]})
    {r,db}=invoke.(db,remote,:projection_commit,%{"draft"=>opened["draft"],"vectors"=>[vector]}); success.(r)
    assert effects.(db)+1<=16
    assert Enum.all?(Map.values(db.records),fn row -> byte_size(IO.iodata_to_binary(JSON.encode!(row["value"])))<=6000 end)
    assert Enum.all?(F.requests(db),&(Ipse.Extension.validate(&1)==:ok))
    {snap,_}=snapshot.(db,remote); assert snap["projections"][source["source_key"]]["vectors"]==[vector]
    ''')
  end

  test "same selection appends while explicit changed selection atomically detaches old vectors in State and MCP" do
    isolated(~S'''
    for backend <- [state,remote] do
      {r,db}=invoke.(F.new(),backend,:put,put.(String.duplicate("a",3000),%{})); success.(r)
      {snap,db}=snapshot.(db,backend); source=hd(snap["sources"]); {:ok,[first,second]}=E.chunks(source)
      selected=%{"kind"=>"embedding","profile"=>"encoder"}
      index=fn db,chunk,selection ->
        args=%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>"vectors","profile"=>selected,"chunks"=>[chunk["chunk_id"]]}
        {r,db}=invoke.(db,backend,:projection_open,args); opened=success.(r)
        assert opened["draft"]["vector_version"] === 2
        assert opened["coverage"]["vector_version"] === 2
        {:ok,vector}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"input_sha256"=>E.sha256(chunk["text"]),"selection_sha256"=>selection,"profile"=>"encoder","model"=>"same-model","dimensions"=>1,"values"=>[1.0]})
        {r,db}=invoke.(db,backend,:projection_commit,%{"draft"=>opened["draft"],"vectors"=>[vector]}); success.(r)
        {snapshot,db}=snapshot.(db,backend)
        vectors=snapshot["projections"][source["source_key"]]["vectors"]
        {vectors,db}
      end
      {vectors,db}=index.(db,first,E.sha256("A")); assert length(vectors)==1
      {vectors,db}=index.(db,second,E.sha256("A")); assert length(vectors)==2
      {vectors,db}=index.(db,first,E.sha256("B")); assert length(vectors)==1
      assert hd(vectors)["chunk_id"]==first["chunk_id"] and hd(vectors)["selection_sha256"]==E.sha256("B")
      root=Enum.find(Map.values(db.records),&(get_in(&1,["value","kind"])=="root"))["value"]
      assert map_size(root["projections"])==1 and root["draft"]==nil
      [head]=Map.values(root["projections"])
      manifest=db.records[head["ref"]["key"]]["value"]
      assert manifest["body"]["previous"]==nil
      assert Enum.count(Map.values(db.records),&(get_in(&1,["value","page_kind"])=="vector"))==3
      {r,db}=invoke.(db,backend,:collect,%{"limit"=>12}); assert success.(r)["count"]>0
      {after_collect,_}=snapshot.(db,backend)
      assert after_collect["projections"][source["source_key"]]["vectors"]==vectors
    end
    ''')
  end

  test "explicit reindex replaces an incompatible reported model under the same selection" do
    isolated(~S'''
    for backend <- [state,remote] do
      {r,db}=invoke.(F.new(),backend,:put,put.("unchanged requested model",%{})); success.(r)
      {snap,db}=snapshot.(db,backend); source=hd(snap["sources"]); {:ok,[chunk]}=E.chunks(source)
      profile=%{"kind"=>"embedding","profile"=>"encoder"}
      args=%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>"vectors","profile"=>profile,"chunks"=>[chunk["chunk_id"]]}
      db=Enum.reduce(~w(resolved-v1 resolved-v2),db,fn model,db ->
        {r,db}=invoke.(db,backend,:projection_open,args); opened=success.(r)
        {:ok,v}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"input_sha256"=>E.sha256("input"),"selection_sha256"=>E.sha256("same approved selection"),"profile"=>"encoder","model"=>model,"dimensions"=>1,"values"=>[1.0]})
        {r,db}=invoke.(db,backend,:projection_commit,%{"draft"=>opened["draft"],"vectors"=>[v]}); success.(r)
        {snap,db}=snapshot.(db,backend)
        assert snap["projections"][source["source_key"]]["vectors"]==[v]
        db
      end)
      root=Enum.find(Map.values(db.records),&(get_in(&1,["value","kind"])=="root"))["value"]
      [head]=Map.values(root["projections"])
      assert db.records[head["ref"]["key"]]["value"]["body"]["previous"]==nil
      assert root["draft"]==nil
    end
    ''')
  end

  test "legacy pages stay readable and reindexable while mixed chains refuse before deduplication" do
    isolated(~S'''
    for backend <- [state,remote] do
      {r,db}=invoke.(F.new(),backend,:put,put.("same chunk",%{})); success.(r)
      {snap,db}=snapshot.(db,backend); source=hd(snap["sources"]); {:ok,[chunk]}=E.chunks(source)
      profile=%{"kind"=>"embedding","profile"=>"encoder"}
      args=%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>"vectors","profile"=>profile,"chunks"=>[chunk["chunk_id"]]}
      {:ok,v}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"input_sha256"=>E.sha256("input"),"selection_sha256"=>E.sha256("A"),"profile"=>"encoder","model"=>"same-model","dimensions"=>1,"values"=>[1.0]})
      db=Enum.reduce(1..2,db,fn _,db ->
        {r,db}=invoke.(db,backend,:projection_open,args); opened=success.(r)
        {r,db}=invoke.(db,backend,:projection_commit,%{"draft"=>opened["draft"],"vectors"=>[v]}); success.(r); db
      end)
      root_row=Enum.find(Map.values(db.records),&(get_in(&1,["value","kind"])=="root"))
      [{id,head}]=Map.to_list(root_row["value"]["projections"])
      downgrade=fn map ->
        map=Map.delete(map,"selection_sha256")
        if Map.has_key?(map,"version"),do: Map.put(map,"version",1),else: map
      end
      {legacy,new_ref}=Driver.rewrite_projection(db,head["ref"],downgrade)
      legacy=put_in(legacy.records[root_row["key"]]["value"]["projections"][id]["ref"],new_ref)
      {snap,legacy}=snapshot.(legacy,backend)
      [old]=snap["projections"][source["source_key"]]["vectors"]
      assert old["version"]===1 and E.valid_vector?(old) and not E.current_vector?(old)
      {r,legacy}=invoke.(legacy,backend,:projection_open,args); opened=success.(r)
      {r,legacy}=invoke.(legacy,backend,:projection_commit,%{"draft"=>opened["draft"],"vectors"=>[v]}); success.(r)
      {snap,_}=snapshot.(legacy,backend); assert snap["projections"][source["source_key"]]["vectors"]==[v]

      top=db.records[head["ref"]["key"]]
      previous=top["value"]["body"]["previous"]
      {mixed,changed}=Driver.rewrite_projection(db,previous,&Map.put(&1,"selection_sha256",E.sha256("B")))
      {new_ref,mixed}=Driver.rewrite_page(mixed,top,Map.put(top["value"]["body"],"previous",changed))
      mixed=put_in(mixed.records[root_row["key"]]["value"]["projections"][id]["ref"],new_ref)
      {r,_}=invoke.(mixed,backend,:snapshot,%{}); assert {:done,{:error,:projection_corrupt,%{}}}=r
    end
    ''')
  end

  test "old registered vector drafts remain inspectable and abortable but cannot be promoted" do
    isolated(~S'''
    for backend <- [state,remote] do
      {r,db}=invoke.(F.new(),backend,:put,put.("legacy draft",%{})); success.(r)
      {snap,db}=snapshot.(db,backend); source=hd(snap["sources"]); {:ok,[chunk]}=E.chunks(source)
      selected=%{"kind"=>"embedding","profile"=>"encoder"}
      args=%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>"vectors","profile"=>selected,"chunks"=>[chunk["chunk_id"]]}
      {r,db}=invoke.(db,backend,:projection_open,args); opened=success.(r)
      key=opened["draft"]["root_key"]; root=db.records[key]["value"]
      ordered_profile=["map",Enum.map(Enum.sort(selected),fn {k,v}->[k,v] end)]
      old_plan=E.id("projection-plan",[root["source_key"],1,root["content_sha256"],"vectors",ordered_profile,[chunk["chunk_id"]]])
      old_draft=root["draft"] |> Map.delete("vector_version") |> Map.put("plan_sha256",old_plan)
      db=put_in(db.records[key]["value"]["draft"],old_draft)
      token=opened["draft"] |> Map.delete("vector_version") |> put_in(["cache","records",key,"value","draft"],old_draft)
      {r,db}=invoke.(db,backend,:inspect,%{"source_id"=>"manual:one"}); inspected=success.(r)
      assert inspected["draft"]["id"]==old_draft["id"]
      {r,db}=invoke.(db,backend,:projection_open,args); assert {:done,{:error,:stale_or_busy_source,%{}}}=r
      {r,db}=invoke.(db,backend,:projection_commit,%{"draft"=>token,"vectors"=>[]}); assert {:done,{:error,:invalid_draft,%{}}}=r
      {r,db}=invoke.(db,backend,:projection_commit,%{"draft"=>Map.put(token,"vector_version",2),"vectors"=>[]}); assert {:done,{:error,:stale_draft,%{}}}=r
      {r,db}=invoke.(db,backend,:projection_abort,%{"draft"=>token}); success.(r)
      {r,_}=invoke.(db,backend,:projection_open,args); assert success.(r)["draft"]["vector_version"]===2
    end
    ''')
  end

  test "suppression racing delayed projection commit wins and exact public abort cannot clear another draft" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),state,:put,put.("model work is delayed",%{})); stored=success.(r)
    {snap,db}=snapshot.(db,state); {:ok,[chunk]}=E.chunks(hd(snap["sources"]))
    profile=%{"kind"=>"embedding","profile"=>"encoder"}; args=%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>"vectors","profile"=>profile,"chunks"=>[chunk["chunk_id"]]}
    {r,db}=invoke.(db,state,:projection_open,args); opened=success.(r)
    {r,db}=invoke.(db,state,:projection_abort,Map.drop(args,["projection_kind"]) |> Map.put("generation",2)); assert {:done,{:error,_,_}}=r
    {r,db}=invoke.(db,state,:projection_abort,Map.drop(args,["projection_kind"])); assert success.(r)["status"]=="aborted"
    {r,db}=invoke.(db,state,:projection_open,args); next=success.(r)
    {r,db}=invoke.(db,state,:forget,%{"source_id"=>"manual:one","expected_revision"=>next["draft"]["revision"]}); success.(r)
    {:ok,vector}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"selection_sha256"=>E.sha256("selected encoder"),"input_sha256"=>E.sha256("opaque input"),"profile"=>"encoder","model"=>"model","dimensions"=>1,"values"=>[1.0]})
    before=effects.(db)
    {r,db}=invoke.(db,state,:projection_commit,%{"draft"=>next["draft"],"vectors"=>[vector]}); assert {:done,{:error,:stale_draft,%{}}}=r
    assert effects.(db)==before
    assert stored["revision"] < opened["draft"]["revision"]
    {snap,_}=snapshot.(db,state); assert snap["sources"]==[]
    ''')
  end

  test "explicit source abort clears only the inspected projection draft and fences delayed work" do
    isolated(~S'''
    for profile <- [state,remote], kind <- ["facts","vectors"] do
      {r,db}=invoke.(F.new(),profile,:put,put.("Release requires quiescence.",%{})); success.(r)
      {snap,db}=snapshot.(db,profile); {:ok,[chunk]}=E.chunks(hd(snap["sources"]))
      selected=if kind=="facts",do: %{"kind"=>"model_complete","profile"=>"extractor","version"=>1},else: %{"kind"=>"embedding","profile"=>"encoder"}
      args=%{"source_id"=>"manual:one","generation"=>1,"projection_kind"=>kind,"profile"=>selected,"chunks"=>[chunk["chunk_id"]],"max_items"=>1}
      args=if kind=="vectors",do: Map.delete(args,"max_items"),else: args
      {r,db}=invoke.(db,profile,:projection_open,args); opened=success.(r)
      {r,db}=invoke.(db,profile,:inspect,%{"source_id"=>"manual:one"}); inspected=success.(r)
      abort=%{"source_id"=>"manual:one","draft_id"=>inspected["draft"]["id"],"expected_revision"=>inspected["revision"]}
      assert inspected["draft"]["kind"]==kind
      for bad <- [Map.put(abort,"expected_revision",0),Map.put(abort,"draft_id",String.duplicate("0",32))] do
        {r,unchanged}=invoke.(db,profile,:abort,bad); assert {:done,{:error,:stale_draft,%{}}}=r
        assert unchanged.records==db.records
      end
      {r,unchanged}=invoke.(db,profile,:publish,abort); assert {:done,{:error,:stale_draft,%{}}}=r
      assert unchanged.records==db.records
      {r,db}=invoke.(db,profile,:abort,abort); assert success.(r)["status"]=="aborted"
      {r,db}=invoke.(db,profile,:inspect,%{"source_id"=>"manual:one"}); inspected=success.(r)
      assert inspected["draft"]==nil and inspected["generation"]==1
      {r,db}=invoke.(db,profile,:projection_open,args); next=success.(r)
      {r,unchanged}=invoke.(db,profile,:abort,abort); assert {:done,{:error,:stale_draft,%{}}}=r
      assert unchanged.records==db.records
      commit=%{"draft"=>opened["draft"],kind=>[]}
      {r,unchanged}=invoke.(db,profile,:projection_commit,commit); assert {:done,{:error,:stale_draft,%{}}}=r
      assert unchanged.records==db.records
      {r,db}=invoke.(db,profile,:forget,%{"source_id"=>"manual:one","expected_revision"=>next["draft"]["revision"]}); success.(r)
      current_abort=%{"source_id"=>"manual:one","draft_id"=>next["draft"]["draft_id"],"expected_revision"=>next["draft"]["revision"]+1}
      {r,unchanged}=invoke.(db,profile,:abort,current_abort); assert {:done,{:error,:stale_draft,%{}}}=r
      assert unchanged.records==db.records
    end
    ''')
  end

  @tag :maximum_import
  test "public import at maximum generation remains forgettable with stale revision and resurrection fences" do
    isolated(~S'''
    for file <- ~w(profiles adapters corpus),do: Code.require_file(Path.join("extensions/knowledge/src",file<>".ex"))
    {r,db}=invoke.(F.new(),state,:put,put.("Maximum generation import.",%{})); success.(r)
    {r,_}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1}); envelope=success.(r)
    schema=Enum.find(IpseKnowledge.Corpus.describe()["exports"]["commands"],&(&1["id"]=="source"))["arguments_schema"]
    for backend <- [state,remote], generation <- [E.safe_integer_max()-1,E.safe_integer_max()] do
      options=Map.new(~w(stores search fetch retrieval embedding rerank extraction),&{&1,%{}})
        |> Map.put("version",1) |> Map.put("stores",%{"notes"=>backend})
        |> Map.put("retrieval",%{"words"=>%{"kind"=>"bm25","version"=>1}})
      preset=if backend["kind"]=="state",do: "state-lexical",else: "mcp-lexical"
      {:ok,resolved}=IpseKnowledge.Profiles.validate("corpus",preset,options)
      callback=%{resolved: resolved,phase: :idle,ctx: nil,cont: nil,pending: nil}
      drive=fn drive,result,db ->
        case result do
          {:ok,%{"kind"=>"host_call","request"=>request},next} ->
            {outcome,db}=F.host(db,request)
            drive.(drive,IpseKnowledge.Corpus.handle("host.actions",%{"outcome"=>outcome},next),db)
          {:ok,result,_} -> {result["value"],db}
        end
      end
      command=fn db,action,args ->
        outer=%{"store"=>"notes","action"=>action,"args"=>args}
        assert :ok=Ipse.MCP.Schema.validate_arguments(schema,outer)
        drive.(drive,IpseKnowledge.Corpus.handle("invoke.command",%{"id"=>"source","arguments"=>outer},callback),db)
      end
      exported=put_in(envelope,["source","generation"],generation)
      {imported,db}=command.(F.new(),"import",%{"expected_revision"=>0,"export"=>exported})
      assert imported["status"]=="ok"
      revision=imported["coverage"]["revision"]
      {denied,unchanged}=command.(db,"forget",%{"source_id"=>"manual:one","expected_revision"=>revision+1})
      assert denied["status"]=="refused" and unchanged.records==db.records
      {forgotten,db}=command.(db,"forget",%{"source_id"=>"manual:one","expected_revision"=>revision})
      assert forgotten["status"]=="ok",inspect(forgotten)
      assert forgotten["coverage"]["generation"]==E.safe_integer_max()
      assert forgotten["coverage"]["revision"]>revision
      {snap,db}=snapshot.(db,backend)
      assert snap["sources"]==[] and Enum.any?(snap["gaps"],&(&1["code"]=="suppressed"))
      {revived,unchanged}=command.(db,"import",%{"expected_revision"=>forgotten["coverage"]["revision"],"export"=>exported})
      assert revived["status"]=="refused" and unchanged.records==db.records
    end
    ''')
  end

  test "exports preserve historical provenance and large fragments require explicit paged migration" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),state,:put,put.("exact migration bytes é",%{})); success.(r)
    {r,db}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1}); exported=success.(r)
    assert exported["projection_coverage"]=="omitted_reindex_required"
    other=Map.put(state,"partition","archive")
    {r,db}=invoke.(db,other,:import,%{"expected_revision"=>0,"export"=>exported}); success.(r)
    {snap,db}=snapshot.(db,other); imported=hd(snap["sources"])
    assert imported["text"]==exported["text"]
    assert imported["origin"]["kind"]=="import"; assert imported["origin"]["historical"]
    {r,db}=invoke.(db,state,:inspect,%{"source_id"=>"manual:one"}); rev=success.(r)["revision"]
    {r,db}=invoke.(db,state,:put,put.(String.duplicate("x",5000),%{"generation"=>2,"expected_revision"=>rev})); success.(r)
    {r,db}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1}); first=success.(r)
    refute first["complete"]; refute Map.has_key?(first["source"],"text")
    {r,db}=invoke.(db,Map.put(state,"partition","migration"),:import,%{"expected_revision"=>0,"export"=>first}); assert {:done,{:error,:incomplete_import,%{}}}=r
    {r,_}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>first["next"],"limit"=>4}); last=success.(r)
    assert last["complete"]; assert first["text"]<>last["text"]==String.duplicate("x",5000)
    ''')
  end

  test "suppression imports respect source capacity and preserve replacement at the ceiling" do
    isolated(~S'''
    writes=fn db -> F.requests(db) |> Enum.count(&(&1["op"]=="state.put" or get_in(&1,["arguments","action"])=="cas_root")) end
    for profile <- [state,remote] do
      {r,db}=invoke.(F.new(),profile,:put,put.("retained live source",%{})); success.(r)
      {db,exports}=Enum.reduce(1..31,{db,[]},fn index,{db,exports} ->
        source_id="suppressed:#{index}"
        {r,donor}=invoke.(F.new(),profile,:forget,%{"source_id"=>source_id,"expected_revision"=>0,"suppressed_at_ms"=>20}); success.(r)
        {r,_}=invoke.(donor,profile,:export,%{"source_id"=>source_id,"cursor"=>nil,"limit"=>1}); exported=success.(r)
        {r,db}=invoke.(db,profile,:import,%{"expected_revision"=>0,"export"=>exported}); success.(r)
        {db,[exported|exports]}
      end)
      {snap,db}=snapshot.(db,profile)
      assert length(snap["tokens"])==32
      {r,db}=invoke.(db,profile,:revalidate,%{"tokens"=>snap["tokens"]}); assert success.(r)["valid"]
      extra=hd(exports) |> put_in(["root","source_key"],E.sha256("suppressed:33"))
      {r,unchanged}=invoke.(db,profile,:import,%{"expected_revision"=>0,"export"=>extra})
      assert {:done,{:error,:source_limit,%{}}}=r
      assert unchanged.records==db.records
      assert writes.(unchanged)==writes.(db)
      {r,donor}=invoke.(F.new(),profile,:forget,%{"source_id"=>"manual:one","expected_revision"=>0,"suppressed_at_ms"=>20}); success.(r)
      {r,_}=invoke.(donor,profile,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1}); exported=success.(r)
      key=S.root_key(profile["partition"],exported["root"]["source_key"])
      replacement=put_in(exported,["root","generation"],2)
      {r,replaced}=invoke.(db,profile,:import,%{"expected_revision"=>db.records[key]["revision"],"export"=>replacement}); success.(r)
      assert map_size(replaced.records)==map_size(db.records)
      assert replaced.records[key]["value"]["generation"]==2
    end
    ''')
  end

  test "concurrent root creators share one atomic admission at the source ceiling" do
    isolated(~S'''
    defmodule RootAdmissionHold do
      def run({:call,%{"op"=>"state.put"},_}=pending,db),do: {pending,db}
      def run({:call,%{"op"=>"mcp.call","arguments"=>%{"action"=>"cas_root"}},_}=pending,db),do: {pending,db}
      def run({:call,request,continuation},db) do
        {outcome,db}=Ipse.Development.Fixtures.Knowledge.host(db,request)
        run(IpseKnowledge.Store.resume(continuation,outcome),db)
      end
    end
    for profile <- [state,remote] do
      {seed,exported}=Enum.reduce(1..31,{F.new(),nil},fn index,{db,_} ->
        source_id="seed:#{index}"
        {r,donor}=invoke.(F.new(),profile,:forget,%{"source_id"=>source_id,"expected_revision"=>0,"suppressed_at_ms"=>20}); success.(r)
        {r,_}=invoke.(donor,profile,:export,%{"source_id"=>source_id,"cursor"=>nil,"limit"=>1}); exported=success.(r)
        {r,db}=invoke.(db,profile,:import,%{"expected_revision"=>0,"export"=>exported}); success.(r)
        {db,exported}
      end)
      {r,donor}=invoke.(F.new(),profile,:put,put.("A new source.",%{"source_id"=>"contender:source_import"})); success.(r)
      {r,_}=invoke.(donor,profile,:export,%{"source_id"=>"contender:source_import","cursor"=>nil,"limit"=>1}); source_export=success.(r)
      creators=[:put,:open,:forget,:import,:source_import]
      for winner <- creators do
        order=[winner|creators--[winner]]
        {pending,db}=Enum.map_reduce(order,seed,fn operation,db ->
          id="contender:#{operation}"
          args=case operation do
            :put -> put.("A new source.",%{"source_id"=>id})
            :open -> put.("A new source.",%{"source_id"=>id}) |> Map.delete("text") |> Map.merge(%{"byte_count"=>13,"content_sha256"=>E.sha256("A new source.")})
            :forget -> %{"source_id"=>id,"expected_revision"=>0,"suppressed_at_ms"=>20}
            :import -> %{"expected_revision"=>0,"export"=>put_in(exported,["root","source_key"],E.sha256(id))}
            :source_import -> %{"expected_revision"=>0,"export"=>source_export}
          end
          operation=if operation==:source_import,do: :import,else: operation
          {held,db}=RootAdmissionHold.run(S.start("notes",profile,operation,args),db)
          {:call,request,_}=held
          condition=if profile["kind"]=="state",do: request["expected_generation"],else: request["arguments"]["args"]["expected_generation"]
          assert condition==seed.generation
          {held,db}
        end)
        {results,db}=Enum.map_reduce(pending,db,fn held,db -> Driver.run(held,db) end)
        assert Enum.count(results,&match?({:done,{:ok,_}},&1))==1
        assert match?({:done,{:ok,_}},hd(results))
        assert Enum.all?(tl(results),&match?({:done,{:error,:conflict,%{}}},&1))
        {snap,db}=snapshot.(db,profile)
        assert length(snap["tokens"])==32
        {r,_}=invoke.(db,profile,:revalidate,%{"tokens"=>snap["tokens"]}); assert success.(r)["valid"]
      end
    end
    ''')
  end

  test "suppression imports reserve shared State namespace records and bytes before a write" do
    isolated(~S'''
    {r,donor}=invoke.(F.new(),state,:forget,%{"source_id"=>"suppressed:quota","expected_revision"=>0,"suppressed_at_ms"=>20}); success.(r)
    {r,_}=invoke.(donor,state,:export,%{"source_id"=>"suppressed:quota","cursor"=>nil,"limit"=>1}); exported=success.(r)
    seed=fn count,padding ->
      records=Map.new(1..count,fn index ->
        key=E.sha256("other-record-#{index}")
        {key,%{"key"=>key,"revision"=>1,"deleted"=>false,"operation_id"=>String.duplicate("1",32),
          "value"=>%{"partition"=>"other","text"=>String.duplicate("x",padding)}}}
      end)
      %{F.new()|records: records,generation: count}
    end
    encoded_size=fn db -> byte_size(JSON.encode!(%{"version"=>1,"namespace"=>String.duplicate("0",64),
      "generation"=>db.generation,"records"=>db.records})) end
    padding=div(1_048_576-10_000-encoded_size.(seed.(180,0)),180)
    near_bytes=seed.(180,padding)
    assert encoded_size.(near_bytes)<1_048_576
    assert encoded_size.(near_bytes)+12_300>1_048_576
    for {db,code} <- [{seed.(256,0),:record_limit},{near_bytes,:store_byte_limit}] do
      {r,unchanged}=invoke.(db,state,:import,%{"expected_revision"=>0,"export"=>exported})
      assert {:done,{:error,^code,%{}}}=r
      assert unchanged.records==db.records
      refute Enum.any?(F.requests(unchanged),&(&1["op"]=="state.put"))
    end
    ''')
  end

  test "canonical State binds distinct source creations to the same observed namespace" do
    isolated(~S'''
    defmodule CanonicalAdmissionDriver do
      def run({:call,request,continuation},root,namespace,hold) do
        if hold and request["op"]=="state.put" do
          {:held,request,continuation}
        else
          operation=Ipse.Usage.id()
          {status,value}=Ipse.Extensions.State.execute(root,namespace,request,operation)
          status=Atom.to_string(status)
          assert Ipse.Extensions.State.valid_outcome?(request,status,value,operation)
          run(IpseKnowledge.Store.resume(continuation,%{"status"=>status,"value"=>value}),root,namespace,hold)
        end
      end
      def run(result,_,_,_),do: result
      def release({:held,request,continuation},root,namespace),
        do: run({:call,request,continuation},root,namespace,false)
    end
    seed=Enum.reduce(1..31,F.new(),fn n,db ->
      {r,db}=invoke.(db,state,:forget,%{"source_id"=>"seed:#{n}","expected_revision"=>0}); success.(r); db
    end)
    root=Path.join(System.tmp_dir!(),"ipse-domain-admission-"<>Ipse.Usage.id())
    namespace=String.duplicate("a",64)
    try do
      path=Path.join(root,namespace)
      File.mkdir_p!(path); File.chmod!(root,0o700); File.chmod!(path,0o700)
      File.write!(Path.join(path,"state.json"),JSON.encode!(%{"version"=>1,"namespace"=>namespace,"generation"=>seed.generation,"records"=>seed.records}))
      File.chmod!(Path.join(path,"state.json"),0o600)
      held=for id <- ["first","second","third"] do
        pending=S.start("notes",state,:forget,%{"source_id"=>id,"expected_revision"=>0})
        {:held,request,_}=result=CanonicalAdmissionDriver.run(pending,root,namespace,true)
        assert request["expected_generation"]==31
        result
      end
      [winner|losers]=Enum.map(held,&CanonicalAdmissionDriver.release(&1,root,namespace))
      success.(winner)
      assert Enum.all?(losers,&match?({:done,{:error,:conflict,%{}}},&1))
      result=CanonicalAdmissionDriver.run(S.start("notes",state,:snapshot,%{}),root,namespace,false)
      assert length(success.(result)["tokens"])==32
      file=JSON.decode!(File.read!(Path.join(path,"state.json")))
      assert file["generation"]==32
      assert map_size(file["records"])==32
    after
      File.rm_rf!(root)
    end
    ''')
  end

  test "legacy remote profiles retain reads and suppression but refuse record additions" do
    isolated(~S'''
    legacy=Map.put(remote,"contract","ipse-cas-v1")
    {r,seed}=invoke.(F.new(),remote,:put,put.("legacy selected bytes",%{})); stored=success.(r)
    {snap,seed}=snapshot.(seed,legacy); assert hd(snap["sources"])["text"]=="legacy selected bytes"
    {r,unchanged}=invoke.(seed,legacy,:put,put.("updated legacy bytes",%{"generation"=>2,"expected_revision"=>stored["revision"]}))
    assert {:done,{:error,:atomic_capacity_unavailable,%{}}}=r
    assert unchanged.records==seed.records
    {r,seed}=invoke.(seed,legacy,:inspect,%{"source_id"=>"manual:one"}); assert success.(r)["revision"]==stored["revision"]
    {r,seed}=invoke.(seed,legacy,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1}); source_export=success.(r)
    {r,donor}=invoke.(F.new(),remote,:forget,%{"source_id"=>"another","expected_revision"=>0}); success.(r)
    {r,_}=invoke.(donor,remote,:export,%{"source_id"=>"another","cursor"=>nil,"limit"=>1}); suppression=success.(r)
    args=put.("new bytes",%{"source_id"=>"another"})
    source_export=source_export |> put_in(["source","source_id"],"another") |> put_in(["source","source_key"],E.sha256("another"))
    for {operation,arguments} <- [
      {:put,args},
      {:open,args |> Map.delete("text") |> Map.merge(%{"byte_count"=>9,"content_sha256"=>E.sha256("new bytes")})},
      {:forget,%{"source_id"=>"another","expected_revision"=>0}},
      {:import,%{"expected_revision"=>0,"export"=>suppression}},
      {:import,%{"expected_revision"=>0,"export"=>source_export}}
    ] do
      before=length(F.requests(seed))
      {result,unchanged}=invoke.(seed,legacy,operation,arguments)
      assert {:done,{:error,:atomic_capacity_unavailable,%{}}}=result
      assert unchanged.records==seed.records
      assert length(F.requests(unchanged))==before
      refute F.requests(unchanged) |> Enum.drop(before) |> Enum.any?(&(get_in(&1,["arguments","action"])=="cas_root"))
    end
    {r,_}=invoke.(seed,legacy,:forget,%{"source_id"=>"manual:one","expected_revision"=>stored["revision"]})
    assert success.(r)["status"]=="suppressed"
    assert F.requests(seed) |> Enum.any?(&(get_in(&1,["arguments","contract"])=="ipse-cas-v1"))
    ''')
  end

  test "overfull legacy stores refuse whole queries and retain addressed recovery and maintenance" do
    isolated(~S'''
    for profile <- [state,remote] do
      {r,db}=invoke.(F.new(),profile,:put,put.("preserved recovery bytes",%{})); stored=success.(r)
      db=Enum.reduce(1..32,db,fn n,db ->
        source_key=E.sha256("legacy:#{n}"); key=S.root_key("notes",source_key)
        root=%{"format"=>1,"kind"=>"root","partition"=>"notes","source_key"=>source_key,"generation"=>1,"state"=>"suppressed","suppressed_at_ms"=>20}
        row=%{"key"=>key,"revision"=>1,"deleted"=>false,"value"=>root,"operation_id"=>String.duplicate("1",32)}
        row=if profile["kind"]=="mcp_cas",do: Map.delete(row,"operation_id"),else: row
        %{db|records: Map.put(db.records,key,row),generation: db.generation+1}
      end)
      {r,db}=invoke.(db,profile,:snapshot,%{}); assert {:done,{:error,:root_capacity_exceeded,%{}}}=r
      {r,db}=invoke.(db,profile,:inspect,%{"source_id"=>"manual:one"}); assert success.(r)["revision"]==stored["revision"]
      {r,db}=invoke.(db,profile,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1}); assert success.(r)["source"]["text"]=="preserved recovery bytes"
      {r,db}=invoke.(db,profile,:put,put.("updated recovery bytes",%{"generation"=>2,"expected_revision"=>stored["revision"]})); stored=success.(r)
      {r,unchanged}=invoke.(db,profile,:forget,%{"source_id"=>"new","expected_revision"=>0}); assert {:done,{:error,:source_limit,%{}}}=r
      assert unchanged.records==db.records
      {r,db}=invoke.(db,profile,:forget,%{"source_id"=>"manual:one","expected_revision"=>stored["revision"]}); success.(r)
      {r,db}=invoke.(db,profile,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1}); assert success.(r)["kind"]=="suppression"
      {r,_}=invoke.(db,profile,:snapshot,%{}); assert {:done,{:error,:root_capacity_exceeded,%{}}}=r
    end
    ''')
  end

  test "positive-revision root tombstones cannot be reused as a free source slot" do
    isolated(~S'''
    for profile <- [state,remote] do
      key=S.root_key("notes",E.sha256("manual:one"))
      tombstone=%{"key"=>key,"revision"=>2,"deleted"=>true,"value"=>nil,"operation_id"=>String.duplicate("1",32)}
      tombstone=if profile["kind"]=="mcp_cas",do: Map.delete(tombstone,"operation_id"),else: tombstone
      db=%{F.new()|records: %{key=>tombstone},generation: 2}
      for {operation,args} <- [{:put,put.("new bytes",%{})},{:forget,%{"source_id"=>"manual:one","expected_revision"=>0}}] do
        {result,unchanged}=invoke.(db,profile,operation,args)
        assert {:done,{:error,:store_corrupt,%{}}}=result
        assert unchanged.records==db.records
        refute Enum.any?(F.requests(unchanged),&(&1["op"]=="state.put" or get_in(&1,["arguments","action"])=="cas_root"))
      end
    end
    ''')
  end

  test "remote snapshot ceiling also bounds addressed recovery before root-count diagnostics" do
    isolated(~S'''
    roots=Map.new(1..33,fn n ->
      source_key=E.sha256("legacy:#{n}"); key=S.root_key("notes",source_key)
      value=%{"format"=>1,"kind"=>"root","partition"=>"notes","source_key"=>source_key,"generation"=>1,"state"=>"suppressed","suppressed_at_ms"=>20}
      {key,%{"key"=>key,"revision"=>1,"deleted"=>false,"value"=>value}}
    end)
    tombstones=Map.new(1..56,fn n ->
      key=E.sha256("retained:#{n}")
      {key,%{"key"=>key,"revision"=>2,"deleted"=>true,"value"=>nil}}
    end)
    records=Map.merge(roots,tombstones)
    assert map_size(records)==89
    db=%{F.new()|records: records,generation: 145}
    operations=[{:snapshot,%{}},{:inspect,%{"source_id"=>"legacy:1"}},
      {:export,%{"source_id"=>"legacy:1","cursor"=>nil,"limit"=>1}},
      {:forget,%{"source_id"=>"legacy:1","expected_revision"=>1}}]
    for contract <- ["ipse-cas-v1","ipse-cas-v2"] do
      profile=Map.put(remote,"contract",contract)
      for {operation,args} <- operations do
        {result,unchanged}=invoke.(db,profile,operation,args)
        assert {:done,{:error,:remote_snapshot_limit,%{}}}=result
        assert unchanged.records==db.records and unchanged.generation==db.generation
        assert Enum.map(F.requests(unchanged) |> Enum.filter(&(&1["op"]=="mcp.call")),& &1["arguments"]["action"])==["snapshot"]
      end
      bounded=%{db|records: Map.delete(db.records,E.sha256("retained:56"))}
      {result,bounded}=invoke.(bounded,profile,:snapshot,%{})
      assert {:done,{:error,:root_capacity_exceeded,%{}}}=result
      {result,bounded}=invoke.(bounded,profile,:inspect,%{"source_id"=>"legacy:1"}); assert success.(result)["state"]=="suppressed"
      {result,_}=invoke.(bounded,profile,:export,%{"source_id"=>"legacy:1","cursor"=>nil,"limit"=>1}); assert success.(result)["kind"]=="suppression"
    end
    ''')
  end

  test "MCP echoed authority and result windows are exact and unknown effects never resume automatically" do
    isolated(~S'''
    for mode <- [:wrong_partition,:wrong_action,:wrong_request,:corrupt_window] do
      db=F.new() |> F.barrier("snapshot",mode)
      {r,db}=invoke.(db,remote,:snapshot,%{}); assert {:done,{:error,:store_response,%{}}}=r
      assert effects.(db)==1
    end
    for mode <- [:denied,:unknown,:unknown_after] do
      db=F.new() |> F.barrier("cas_root",mode)
      {r,db}=invoke.(db,remote,:put,put.("unknown mutation",%{}))
      if mode==:denied,do: assert(r=={:done,{:error,:denied,%{}}}),else: assert(r=={:stop,:unknown_effect})
      calls=F.requests(db) |> Enum.filter(&(&1["op"]=="mcp.call"))
      assert Enum.map(calls,& &1["arguments"]["action"])==["snapshot","cas_root"]
      assert Enum.count(Map.values(db.records),&(get_in(&1,["value","kind"])=="page"))==0
      if mode==:unknown_after,do: assert(map_size(db.records)==1),else: assert(db.records==%{})
    end
    ''')
  end

  test "selected reference tampering refuses and tombstones consume quota before registering a draft" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),state,:put,put.("immutable source",%{})); success.(r)
    row=Enum.find(Map.values(db.records),&(get_in(&1,["value","page_kind"])=="content"))
    corrupt=put_in(db.records[row["key"]]["value"]["body"]["text"],"tampered")
    {r,_}=invoke.(corrupt,state,:snapshot,%{}); assert {:done,{:error,:store_corrupt,%{}}}=r
    records=Enum.reduce(1..256,%{},fn n,records -> key=E.sha256("tombstone#{n}"); Map.put(records,key,%{"key"=>key,"revision"=>2,"deleted"=>true,"value"=>nil,"operation_id"=>String.duplicate("0",32)}) end)
    full=%{F.new()|records: records,generation: 512}
    {r,full}=invoke.(full,state,:put,put.("cannot fit",%{})); assert {:done,{:error,:record_limit,%{}}}=r
    assert effects.(full)==0
    assert map_size(full.records)==256
    ''')
  end

  test "read-only inventory separates selected draft orphan and namespace tombstone storage" do
    isolated(~S'''
    cache=fn db -> %{"records"=>db.records,"generation"=>db.generation} end
    inventory=fn db -> assert {:ok,report}=S.inventory(cache.(db),"notes"); report end
    fresh_text="private first draft"
    fresh_args=put.(fresh_text,%{}) |> Map.delete("text") |> Map.merge(%{"byte_count"=>byte_size(fresh_text),"content_sha256"=>E.sha256(fresh_text)})
    {r,fresh}=invoke.(F.new(),state,:open,fresh_args); opened=success.(r)
    {r,fresh}=invoke.(fresh,state,:append,%{"source_id"=>"manual:one","draft_id"=>opened["draft_id"],"expected_revision"=>opened["revision"],"offset"=>0,"text"=>fresh_text}); success.(r)
    first_draft=inventory.(fresh)
    assert first_draft["selected_pages"]["records"]==0
    assert first_draft["draft_pages"]["records"]>0
    assert hd(first_draft["roots"])["state"]=="staging"
    {r,db}=invoke.(F.new(),state,:put,put.("first-generation-private",%{})); stored=success.(r)
    initial=inventory.(db)
    assert initial["selected_pages"]["records"]>0
    assert initial["draft_pages"]["records"]==0
    assert length(initial["roots"])==1
    assert initial["root_records"]["encoded_value_bytes"]>0
    refute JSON.encode!(initial)=~"first-generation-private"
    refute JSON.encode!(initial)=~"manual:one"
    before=db.records
    assert inventory.(db)==initial
    assert db.records==before
    text="next-generation-private"
    args=put.(text,%{"generation"=>2,"expected_revision"=>stored["revision"]}) |> Map.delete("text") |> Map.merge(%{"byte_count"=>byte_size(text),"content_sha256"=>E.sha256(text)})
    {r,db}=invoke.(db,state,:open,args); opened=success.(r)
    {r,db}=invoke.(db,state,:append,%{"source_id"=>"manual:one","draft_id"=>opened["draft_id"],"expected_revision"=>opened["revision"],"offset"=>0,"text"=>text}); appended=success.(r)
    staged=inventory.(db)
    assert staged["selected_pages"]==initial["selected_pages"]
    assert staged["draft_pages"]["records"]>0
    assert hd(staged["roots"])["value_sha256"]!=hd(initial["roots"])["value_sha256"]
    {r,db}=invoke.(db,state,:abort,%{"source_id"=>"manual:one","draft_id"=>opened["draft_id"],"expected_revision"=>appended["revision"]}); success.(r)
    abandoned=inventory.(db)
    assert abandoned["draft_pages"]["records"]==0
    assert abandoned["orphan_pages"]["records"]>=staged["draft_pages"]["records"]
    {r,db}=invoke.(db,state,:inspect,%{"source_id"=>"manual:one"}); inspected=success.(r)
    {r,db}=invoke.(db,state,:forget,%{"source_id"=>"manual:one","expected_revision"=>inspected["revision"]}); success.(r)
    forgotten=inventory.(db)
    assert forgotten["selected_pages"]["records"]==0
    assert hd(forgotten["roots"])["state"]=="suppressed"
    slots=forgotten["namespace_slots"]
    {r,db}=invoke.(db,state,:collect,%{"limit"=>12}); success.(r)
    collected=inventory.(db)
    assert collected["namespace_slots"]==slots
    assert collected["namespace_tombstones"]["records"]>0
    assert collected["namespace_tombstones"]["encoded_value_bytes"]==0
    assert collected["namespace_tombstones"]["encoded_record_bytes"]>0
    assert collected["orphan_pages"]["records"]==0
    ''')
  end

  test "inventory refuses missing deleted forged and foreign selected references" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),state,:put,put.("private inventory source",%{})); success.(r)
    key=S.root_key("notes",E.sha256("manual:one"))
    root=db.records[key]["value"]
    ref=root["content_ref"]
    cache=fn records -> %{"records"=>records,"generation"=>db.generation} end
    assert {:ok,_}=S.inventory(cache.(db.records),"notes")
    forged=put_in(db.records[key]["value"]["content_ref"]["sha256"],String.duplicate("0",64)).records
    deleted=put_in(db.records[ref["key"]]["deleted"],true).records
    missing=Map.delete(db.records,ref["key"])
    conflicting=put_in(db.records[key]["value"]["chunks_ref"],root["chunks_ref"]++[Map.put(hd(root["chunks_ref"]),"sha256",String.duplicate("0",64))]).records
    for records <- [forged,deleted,missing,conflicting] do
      assert {:error,:inventory_unavailable}=S.inventory(cache.(records),"notes")
    end
    {r,other}=invoke.(F.new(),Map.put(state,"partition","foreign"),:put,put.("private inventory source",%{})); success.(r)
    other_key=S.root_key("foreign",E.sha256("manual:one"))
    foreign_ref=other.records[other_key]["value"]["content_ref"]
    foreign=Map.merge(db.records,other.records) |> put_in([key,"value","content_ref"],foreign_ref)
    assert {:error,:inventory_unavailable}=S.inventory(cache.(foreign),"notes")
    ''')
  end

  test "snapshot generation cannot change between State scan pages or remote record groups" do
    isolated(~S'''
    rows=Enum.map(1..17,fn n -> key=E.sha256("row#{n}"); %{"key"=>key,"revision"=>1,"deleted"=>true,"value"=>nil,"operation_id"=>String.duplicate("0",32)} end) |> Enum.sort_by(& &1["key"])
    {:call,_,first}=IpseKnowledge.Store.State.start(state,:snapshot,%{})
    {:call,_,second}=IpseKnowledge.Store.State.resume(first,%{"status"=>"ok","value"=>%{"generation"=>17,"records"=>Enum.take(rows,16),"next"=>Enum.at(rows,15)["key"]}})
    assert {:done,{:error,:store_response,%{}}}=IpseKnowledge.Store.State.resume(second,%{"status"=>"ok","value"=>%{"generation"=>18,"records"=>Enum.drop(rows,16),"next"=>nil}})
    {r,db}=invoke.(F.new(),remote,:put,put.("stable snapshot",%{})); success.(r)
    db=F.barrier(db,"get_many",:drift_generation)
    before=effects.(db)
    {r,db}=invoke.(db,remote,:snapshot,%{}); assert {:done,{:error,:store_response,%{}}}=r
    assert effects.(db)==before+2
    ''')
  end

  test "selected query references fetch only their current source pages and carry prior allowances" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),remote,:put,put.("inode identity survives releasing the lock",%{})); success.(r)
    {snap,db}=snapshot.(db,remote); source=hd(snap["sources"]); {:ok,[chunk]}=E.chunks(source)
    ref=source |> Map.take(~w(source_id source_key generation content_sha256)) |> Map.merge(%{"chunk_id"=>chunk["chunk_id"],"score"=>2.0})
    {r,db}=invoke.(db,remote,:put,put.("unselected secret body",%{"source_id"=>"manual:other"})); success.(r)
    foreign_keys=for {key,row} <- db.records, row["value"]["source_key"]==E.sha256("manual:other"), do: key
    unselected=Enum.find(Map.values(db.records),&(get_in(&1,["value","source_key"])==E.sha256("manual:other") and get_in(&1,["value","page_kind"])=="content"))
    db=put_in(db.records[unselected["key"]]["value"]["body"]["text"],"corrupt but unselected")
    db=%{db|requests: []}
    {r,db}=invoke.(db,remote,:snapshot_selected,selected_args.(db,[ref],%{})); selected=success.(r)
    assert selected["sources"]==[source]
    assert selected["coverage"]["cache_scope"]=="selected"
    refute selected["coverage"]["namespace_complete"]
    assert selected["coverage"]["projections"]=="omitted"
    assert selected["projections"][source["source_key"]]==%{"vectors"=>[],"facts"=>[]}
    calls=F.requests(db) |> Enum.filter(&(&1["op"]=="mcp.call"))
    assert Enum.all?(calls,&(&1["arguments"]["action"]=="get_many"))
    assert selected["coverage"]["effects_used"]==1+length(calls)
    assert selected["coverage"]["reads_used"]==2+Enum.count(F.requests(db),&(&1["op"]=="effect.result.read"))
    assert selected["coverage"]["revalidate_effects_worst_case"]==1
    assert Enum.all?(calls,fn request -> Enum.all?(request["arguments"]["args"]["keys"],&(&1 not in foreign_keys)) end)
    db=%{db|requests: []}
    {r,db}=invoke.(db,remote,:revalidate,%{"tokens"=>selected["tokens"],"effects_used"=>selected["coverage"]["effects_used"],"reads_used"=>selected["coverage"]["reads_used"]}); checked=success.(r); assert checked["valid"]
    assert effects.(db)==1
    assert checked["coverage"]["effects_used"]==selected["coverage"]["effects_used"]+1
    assert checked["coverage"]["reads_used"]==selected["coverage"]["reads_used"]+Enum.count(F.requests(db),&(&1["op"]=="effect.result.read"))
    assert Enum.all?(F.requests(db),&(&1["op"]!="mcp.call" or &1["arguments"]["action"]=="get_many"))
    ''')
  end

  test "empty selected refs do no Store IO and forged selectors refuse before any request" do
    isolated(~S'''
    db=F.new()
    {r,after_db}=invoke.(db,remote,:snapshot_selected,selected_args.(db,[],%{"effects_used"=>15,"reads_used"=>500})); empty=success.(r)
    assert after_db.requests==[]; assert empty["sources"]==[]; assert empty["tokens"]==[]
    assert empty["coverage"]["effects_used"]==15; assert empty["coverage"]["reads_used"]==500
    assert empty["coverage"]["revalidate_effects_worst_case"]==0
    ref=%{"source_id"=>"one","source_key"=>E.sha256("one"),"generation"=>1,"content_sha256"=>E.sha256("text"),"chunk_id"=>E.sha256("chunk"),"score"=>1.0}
    for refs <- [[Map.put(ref,"source_key",E.sha256("forged"))],[Map.put(ref,"score","invalid")],[ref,ref],[Map.put(ref,"binding","other")]] do
      assert {:done,{:error,:invalid_store_arguments,%{}}}=S.start("notes",remote,:snapshot_selected,selected_args.(db,refs,%{}))
    end
    assert {:done,{:error,:selected_store_required,%{}}}=S.start("notes",state,:snapshot_selected,selected_args.(db,[],%{}))
    assert {:done,{:error,:invalid_store_arguments,%{}}}=S.start("notes",remote,:snapshot_selected,selected_args.(db,[],%{"effects_used"=>17}))
    ''')
  end

  test "selected roots reject stale suppressed expired historical partition and chunk substitutions" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),remote,:put,put.("exact selected bytes",%{})); stored=success.(r)
    {snap,db}=snapshot.(db,remote); source=hd(snap["sources"]); {:ok,[chunk]}=E.chunks(source)
    ref=source |> Map.take(~w(source_id source_key generation content_sha256)) |> Map.merge(%{"chunk_id"=>chunk["chunk_id"],"score"=>1.0})
    for bad <- [Map.put(ref,"generation",2),Map.put(ref,"content_sha256",E.sha256("wrong")),Map.put(ref,"chunk_id",E.sha256("wrong chunk"))] do
      {r,_}=invoke.(db,remote,:snapshot_selected,selected_args.(db,[bad],%{})); assert {:done,{:error,_,_}}=r
    end
    key=S.root_key("notes",source["source_key"])
    for altered <- [put_in(db.records[key]["value"]["partition"],"foreign"),put_in(db.records[key]["value"]["expires_at_ms"],20),put_in(db.records[key]["value"]["origin"]["historical"],true)] do
      {r,_}=invoke.(altered,remote,:snapshot_selected,selected_args.(altered,[ref],%{})); assert {:done,{:error,:selected_source_unavailable,%{}}}=r
    end
    {r,forgotten}=invoke.(db,remote,:forget,%{"source_id"=>"manual:one","expected_revision"=>stored["revision"]}); success.(r)
    {r,_}=invoke.(forgotten,remote,:snapshot_selected,selected_args.(forgotten,[ref],%{})); assert {:done,{:error,:selected_source_unavailable,%{}}}=r
    {r,_}=invoke.(db,remote,:snapshot_selected,selected_args.(db,[ref],%{"store_generation"=>db.generation+1})); assert {:done,{:error,:snapshot_changed,%{}}}=r
    ''')
  end

  test "selected fetching reserves final validation before dispatch and unknown is never replayed" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),remote,:put,put.("bounded selection",%{})); success.(r)
    {snap,db}=snapshot.(db,remote); source=hd(snap["sources"]); {:ok,[chunk]}=E.chunks(source)
    ref=source |> Map.take(~w(source_id source_key generation content_sha256)) |> Map.merge(%{"chunk_id"=>chunk["chunk_id"],"score"=>1.0})
    for counters <- [%{"effects_used"=>15},%{"reads_used"=>500}] do
      fresh=%{db|requests: []}
      {r,fresh}=invoke.(fresh,remote,:snapshot_selected,selected_args.(fresh,[ref],counters)); assert {:done,{:error,:effect_limit,%{}}}=r
      assert fresh.requests==[]
    end
    for mode <- [:wrong_partition,:wrong_request,:corrupt_window,:drift_generation,:unknown,:denied] do
      fresh=%{db|requests: []} |> F.barrier("get_many",mode)
      {r,fresh}=invoke.(fresh,remote,:snapshot_selected,selected_args.(fresh,[ref],%{}))
      if mode==:unknown,do: assert(r=={:stop,:unknown_effect}),else: assert(match?({:done,{:error,_,_}},r))
      assert effects.(fresh)==1
    end
    assert {:done,{:error,:effect_limit,%{}}}=S.start("notes",remote,:revalidate,%{"tokens"=>snap["tokens"],"effects_used"=>16,"reads_used"=>0})
    ''')
  end

  test "independent query-v1 fixture returns only strict server assertions over selected roots" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),remote,:put,put.("retained inode identity",%{})); stored=success.(r)
    request=%{"version"=>1,"contract"=>"query-v1","partition"=>"notes","request_id"=>String.duplicate("a",32),"query"=>"inode","top_k"=>5,"as_of_ms"=>20}
    {reply,db}=F.query(db,request)
    assert reply["status"]=="ok"; assert reply["complete"]; assert reply["algorithm"]=="fixture_terms"; assert [ref]=reply["refs"]
    assert Enum.sort(Map.keys(ref))==Enum.sort(~w(source_id source_key generation content_sha256 chunk_id score))
    {r,db}=invoke.(db,remote,:snapshot_selected,selected_args.(db,reply["refs"],%{"store_generation"=>reply["generation"]})); assert length(success.(r)["sources"])==1
    {forged,_}=F.query(db,request |> Map.put("partition","other") |> Map.put("request_id",String.duplicate("b",32))); assert forged["status"]=="refused"; assert forged["refs"]==[]
    {replayed,_}=F.query(db,request); assert replayed["status"]=="refused"
    {r,db}=invoke.(db,remote,:forget,%{"source_id"=>"manual:one","expected_revision"=>stored["revision"]}); success.(r)
    {gone,_}=F.query(db,Map.put(request,"request_id",String.duplicate("c",32))); assert gone["refs"]==[]
    ''')
  end

  test "long-lived fixture backend preserves CAS across fresh stdio clients and confirmed disconnects" do
    isolated(~S'''
    defmodule FreshFixtureClient do
      def rpc(config,method,params) do
        port=Port.open({:spawn_executable,String.to_charlist(config["command"])},[:binary,:exit_status,:stderr_to_stdout,args: config["args"]])
        try do
          rpc=%{"jsonrpc"=>"2.0","id"=>1,"method"=>method,"params"=>params}
          true=Port.command(port,[JSON.encode!(rpc),"\n"])
          read(port,"")
        after
          try do Port.close(port) catch :error,:badarg -> :ok end
        end
      end
      defp read(port,text) do
        receive do
          {^port,{:data,bytes}} ->
            text=text<>bytes
            true=byte_size(text)<=131072
            case :binary.match(text,"\n") do
              {end_at,_}->JSON.decode!(binary_part(text,0,end_at))
              :nomatch->read(port,text)
            end
          {^port,{:exit_status,status}}->{:exit,status}
        after
          10000->raise "fixture child did not finish"
        end
      end
    end
    {:ok,backend}=F.start_backend("notes")
    try do
      config=F.stdio_config("notes","normal",backend.port)
      assert config["id"]=="knowledge_cas"
      listing=FreshFixtureClient.rpc(config,"tools/list",%{})
      assert Enum.map(listing["result"]["tools"],& &1["name"])==["cas","query"]
      assert F.backend_state(backend).requests==[]
      source_key=E.sha256("client-boundary"); key=S.root_key("notes",source_key)
      root=%{"format"=>1,"kind"=>"root","partition"=>"notes","source_key"=>source_key,"generation"=>1,"state"=>"suppressed","suppressed_at_ms"=>20}
      envelope=fn action,args,id -> %{"version"=>1,"contract"=>"ipse-cas-v1","partition"=>"notes","request_id"=>id,"action"=>action,"args"=>args} end
      claim=%{"key"=>key,"expected_revision"=>0,"expected_source_generation"=>nil,"expected_content_sha256"=>nil,"draft_id"=>nil,"next_root"=>root}
      rpc=FreshFixtureClient.rpc(config,"tools/call",%{"name"=>"cas","arguments"=>envelope.("cas_root",claim,String.duplicate("a",32))})
      assert JSON.decode!(hd(rpc["result"]["content"])["text"])["status"]=="ok"
      rpc=FreshFixtureClient.rpc(config,"tools/call",%{"name"=>"cas","arguments"=>envelope.("get_many",%{"keys"=>[key]},String.duplicate("b",32))})
      assert JSON.decode!(hd(rpc["result"]["content"])["text"])["value"]["records"]==[%{"key"=>key,"revision"=>1,"deleted"=>false,"value"=>root}]
      query=%{"version"=>1,"contract"=>"query-v1","partition"=>"notes","request_id"=>String.duplicate("c",32),"query"=>"boundary","top_k"=>5,"as_of_ms"=>20}
      rpc=FreshFixtureClient.rpc(config,"tools/call",%{"name"=>"query","arguments"=>query})
      reply=JSON.decode!(hd(rpc["result"]["content"])["text"])
      assert reply["status"]=="ok"; assert reply["generation"]==1; assert reply["refs"]==[]
      next_source=E.sha256("after-disconnect"); next_key=S.root_key("notes",next_source)
      claim=claim |> Map.put("key",next_key) |> Map.put("next_root",Map.put(root,"source_key",next_source))
      disconnected=F.stdio_config("notes","disconnect_after_cas",backend.port)
      assert {:exit,0}=FreshFixtureClient.rpc(disconnected,"tools/call",%{"name"=>"cas","arguments"=>envelope.("cas_root",claim,String.duplicate("d",32))})
      db=F.backend_state(backend)
      assert db.records[next_key]["revision"]==1
      assert Enum.count(F.requests(db),&(&1["arguments"]["request_id"]==String.duplicate("d",32)))==1
      assert db.generation==2
    after
      assert :ok=F.stop_backend(backend)
    end
    refute Process.alive?(backend.pid)
    assert {:error,:econnrefused}=:gen_tcp.connect({127,0,0,1},backend.port,[:binary,active: false],1000)
    assert :ok=F.stop_backend(backend)
    ''')
  end

  test "v3 atomic record capacity wins concurrent append races and keeps recovery available" do
    isolated(~S'''
    seed=Enum.reduce(1..15,F.new(),fn i,db ->
      {r,db}=invoke.(db,remote,:put,put.(String.duplicate("a",8192),%{"source_id"=>"seed:#{i}"}));success.(r);db
    end)
    text=String.duplicate("b",40960)
    open=fn id -> put.(text,%{"source_id"=>id}) |>Map.delete("text")|>Map.merge(%{"byte_count"=>byte_size(text),"content_sha256"=>E.sha256(text)})end
    {r,seed}=invoke.(seed,remote,:open,open.("a"));a=success.(r)
    {r,seed}=invoke.(seed,remote,:open,open.("b"));b=success.(r)
    append=fn id,draft -> %{"source_id"=>id,"draft_id"=>draft["draft_id"],"expected_revision"=>draft["revision"],"offset"=>draft["next_offset"],"text"=>String.duplicate("b",4096)}end
    {a,seed}=Enum.reduce(1..4,{a,seed},fn _,{a,db}->{r,db}=invoke.(db,remote,:append,append.("a",a));{success.(r),db}end)
    {r,seed}=invoke.(seed,remote,:forget,%{"source_id"=>"extra","expected_revision"=>0});success.(r)
    assert map_size(seed.records)==86
    held=for {id,draft}<-[{"a",a},{"b",b}] do
      {call,_}=Driver.hold(S.start("notes",remote,:append,append.(id,draft)),seed)
      {:call,_,cont}=call
      assert map_size(cont.cache["records"])==86 and length(cont.pages)==2
      {id,call}
    end
    for order<-[held,Enum.reverse(held)] do
      [{winner,first},{loser,second}]=order
      {r,db}=Driver.run(first,seed);success.(r)
      assert map_size(db.records)==88
      {r,db}=Driver.run(second,db)
      assert {:done,{:error,:store_refused,%{}}}=r
      assert map_size(db.records)==88
      for id<-[winner,loser],contract<-~w(ipse-cas-v1 ipse-cas-v2 ipse-cas-v3) do
        profile=Map.put(remote,"contract",contract)
        {r,_}=invoke.(db,profile,:inspect,%{"source_id"=>id});inspected=success.(r)
        assert inspected["draft"]!=nil
        {r,aborted}=invoke.(db,profile,:abort,%{"source_id"=>id,"draft_id"=>inspected["draft"]["id"],"expected_revision"=>inspected["revision"]})
        assert success.(r)["status"]=="aborted" and map_size(aborted.records)==88
        {r,forgotten}=invoke.(db,profile,:forget,%{"source_id"=>id,"expected_revision"=>inspected["revision"]})
        assert success.(r)["status"]=="suppressed" and map_size(forgotten.records)==88
      end
      {:call,request,_}=second
      for version<-[1,2,3] do
        old=request["arguments"] |>Map.put("version",version)|>Map.put("contract","ipse-cas-v#{version}")
        {reply,unchanged}=F.handle(db,Map.put(old,"request_id",Base.encode16(:crypto.strong_rand_bytes(16),case: :lower)))
        assert reply["status"]=="refused" and unchanged.records==db.records
      end
    end
    [{id,first}|_]=held
    {r,unknown}=Driver.run(first,F.barrier(seed,"put_immutable_many",:unknown_after))
    assert r=={:stop,:unknown_effect} and map_size(unknown.records)==88
    {r,_}=invoke.(unknown,remote,:append,append.("a",a))
    assert {:done,{:error,:record_limit,%{}}}=r
    {r,_}=invoke.(unknown,remote,:inspect,%{"source_id"=>id});inspected=success.(r)
    {r,aborted}=invoke.(unknown,remote,:abort,%{"source_id"=>id,"draft_id"=>inspected["draft"]["id"],"expected_revision"=>inspected["revision"]});success.(r)
    {r,collected}=invoke.(aborted,remote,:collect,%{"limit"=>12})
    assert success.(r)["record_slots_recovered"]==0 and map_size(collected.records)==88
    ''')
  end

  test "known fact pages admit exactly16 effects and refuse17 before claiming" do
    isolated(~S'''
    {r,db}=invoke.(F.new(),state,:put,put.(String.duplicate("a",1024),%{"source_id"=>"s","title"=>"s","uri"=>"s","observed_at_ms"=>1}));success.(r)
    {snap,db}=snapshot.(db,state);source=hd(snap["sources"]);{:ok,[chunk]}=E.chunks(source)
    facts=fn count ->
      {:ok,citation}=E.citation(source,chunk,0,count)
      for i<-1..32 do
        {:ok,fact}=E.fact(%{"subject"=>"A#{i}","predicate"=>"p","object"=>"B","polarity"=>"positive","inferred"=>false,"valid_from_ms"=>nil,"valid_to_ms"=>nil,"extraction"=>%{"kind"=>"explicit","profile"=>nil,"version"=>1},"citations"=>[citation]});fact
      end
    end
    open=%{"source_id"=>"s","generation"=>1,"projection_kind"=>"facts","profile"=>%{"kind"=>"explicit"},"chunks"=>[chunk["chunk_id"]],"max_items"=>32}
    for {quote_bytes,expected}<-[{700,16},{850,17}] do
      args=Map.put(open,"facts",facts.(quote_bytes))
      {r,next}=invoke.(%{db|requests: []},state,:projection_open,args)
      if expected==16 do
        opened=success.(r)
        assert opened["coverage"]["total_effects"]==16
        assert opened["coverage"]["model_effects"]==0 and opened["coverage"]["reserved_pages"]==14
        {r,next}=invoke.(next,state,:projection_commit,%{"draft"=>opened["draft"],"facts"=>args["facts"]});success.(r)
        assert effects.(next)==16
        {snapshot,_}=snapshot.(next,state)
        assert length(hd(Map.values(snapshot["projections"]))["facts"])==32
      else
        assert r=={:done,{:error,:effect_limit,%{}}}
        assert next.records==db.records and effects.(next)==0
      end
    end
    ''')
  end

  test "MCP model allowance admits actual paired32-fact pages and retains oversized drafts" do
    isolated(~S'''
    for quote_bytes<-[700,1024] do
      {r,db}=invoke.(F.new(),remote,:put,put.(String.duplicate("a",1024),%{"source_id"=>"s","title"=>"s","uri"=>"s","observed_at_ms"=>1}));success.(r)
      {snap,db}=snapshot.(db,remote);source=hd(snap["sources"]);{:ok,[chunk]}=E.chunks(source)
      {:ok,citation}=E.citation(source,chunk,0,quote_bytes)
      facts=for i<-1..32 do
        {:ok,fact}=E.fact(%{"subject"=>"A#{i}","predicate"=>"p","object"=>"B","polarity"=>"positive","inferred"=>false,"valid_from_ms"=>nil,"valid_to_ms"=>nil,"extraction"=>%{"kind"=>"explicit","profile"=>nil,"version"=>1},"citations"=>[citation]});fact
      end
      args=%{"source_id"=>"s","generation"=>1,"projection_kind"=>"facts","profile"=>%{"kind"=>"model_complete","profile"=>"extractor"},"chunks"=>[chunk["chunk_id"]],"max_items"=>32}
      {r,db}=invoke.(%{db|requests: []},remote,:projection_open,args);opened=success.(r)
      assert opened["coverage"]["reserved_pages"]==15
      {r,next}=invoke.(db,remote,:projection_commit,%{"draft"=>opened["draft"],"facts"=>facts})
      if quote_bytes==700 do
        success.(r)
        assert effects.(next)+1<=16
        assert Enum.count(Map.values(next.records),&(get_in(&1,["value","page_kind"]) in ~w(facts projection)))==14
        {snap,_}=snapshot.(next,remote)
        assert length(hd(Map.values(snap["projections"]))["facts"])==32
      else
        assert r=={:done,{:error,:projection_bounds,%{}}}
        assert next.records==db.records
        {r,_}=invoke.(next,remote,:inspect,%{"source_id"=>"s"});inspected=success.(r)
        assert inspected["draft"]["kind"]=="facts"
        {r,_}=invoke.(next,remote,:abort,%{"source_id"=>"s","draft_id"=>inspected["draft"]["id"],"expected_revision"=>inspected["revision"]})
        assert success.(r)["status"]=="aborted"
      end
    end
    ''')
  end

  test "bounded exports page escaped UTF8 and complete no-duplicate imports preserve bytes" do
    isolated(~S'''
    samples=[String.duplicate("\"\"\n",1330),String.duplicate("a\n",2048),String.duplicate("\"",3000),String.duplicate(<<1>>,6000),String.duplicate("é\n\"",1024)]
    for profile<-[state,remote],text<-samples do
      {r,db}=invoke.(F.new(),profile,:put,put.(text,%{}));success.(r)
      for limit<-1..4 do
        walk=fn walk,cursor,parts ->
          {r,_}=invoke.(db,profile,:export,%{"source_id"=>"manual:one","cursor"=>cursor,"limit"=>limit});value=success.(r)
          assert Ipse.Extension.validate(value)==:ok
          assert byte_size(JSON.encode!(value))<=12000
          assert value["cursor"]==(cursor||0)
          assert String.valid?(value["text"]) and byte_size(value["text"])>0
          assert byte_size(value["text"])<=min(limit*4096,8192)
          if value["next"]==nil,do: {parts++[value["text"]],value},else: walk.(walk,value["next"],parts++[value["text"]])
        end
        {parts,last}=walk.(walk,nil,[])
        assert Enum.join(parts)==text and last["complete"]
      end
    end
    text=String.duplicate("a",5000)
    {r,db}=invoke.(F.new(),state,:put,put.(text,%{}));success.(r)
    {r,_}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>1});one=success.(r)
    {r,_}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>4});complete=success.(r)
    assert byte_size(one["text"])==4096 and byte_size(complete["text"])==5000
    text=String.duplicate("\"",3000)
    {r,db}=invoke.(F.new(),state,:put,put.(text,%{}));success.(r)
    {r,_}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>4});complete=success.(r)
    assert complete["complete"] and not Map.has_key?(complete["source"],"text")
    {r,target}=invoke.(F.new(),state,:import,%{"expected_revision"=>0,"export"=>complete});success.(r)
    {snap,_}=snapshot.(target,state)
    assert hd(snap["sources"])["text"]==text and hd(snap["sources"])["origin"]["historical"]
    forged=put_in(complete,["source","content_sha256"],E.sha256("wrong"))
    {r,_}=invoke.(F.new(),state,:import,%{"expected_revision"=>0,"export"=>forged})
    assert {:done,{:error,:incomplete_import,%{}}}=r
    for profile<-[state,remote] do
      text=String.duplicate("é\n\"",4096)
      capture=fn initial,history,text ->
        args=put.(text,%{})|>Map.delete("text")|>Map.merge(%{"byte_count"=>byte_size(text),"content_sha256"=>E.sha256(text)})
        args=if history,do: Map.put(args,"historical_import",history),else: args
        {r,db}=invoke.(initial,profile,:open,args);draft=success.(r)
        {draft,db}=Enum.reduce(0..3,{draft,db},fn i,{draft,db}->
          part=binary_part(text,i*4096,4096)
          {r,db}=invoke.(db,profile,:append,%{"source_id"=>"manual:one","draft_id"=>draft["draft_id"],"expected_revision"=>draft["revision"],"offset"=>i*4096,"text"=>part})
          {success.(r),db}
        end)
        {r,db}=invoke.(db,profile,:publish,%{"source_id"=>"manual:one","draft_id"=>draft["draft_id"],"expected_revision"=>draft["revision"]});success.(r);db
      end
      source_db=capture.(F.new(),nil,text)
      walk=fn walk,cursor,parts ->
        {r,_}=invoke.(source_db,profile,:export,%{"source_id"=>"manual:one","cursor"=>cursor,"limit"=>4});value=success.(r)
        assert byte_size(JSON.encode!(value))<=12000 and String.valid?(value["text"])
        if value["next"]==nil,do: parts++[value],else: walk.(walk,value["next"],parts++[value])
      end
      pages=walk.(walk,nil,[])
      assert Enum.map_join(pages,& &1["text"])==text
      assert E.sha256(Enum.map_join(pages,& &1["text"]))==hd(pages)["source"]["content_sha256"]
      for page<-[hd(pages),List.last(pages)] do
        {r,_}=invoke.(F.new(),profile,:import,%{"expected_revision"=>0,"export"=>page})
        assert {:done,{:error,:incomplete_import,%{}}}=r
      end
      migrated=capture.(F.new(),hd(pages)["source"]["origin"],Enum.map_join(pages,& &1["text"]))
      {snapshot,_}=snapshot.(migrated,profile)
      assert hd(snapshot["sources"])["text"]==text and hd(snapshot["sources"])["origin"]["historical"]
    end
    ''')
  end

  test "fixture backend enforces packet bounds and closes when its explicit owner exits" do
    isolated(~S'''
    {:ok,backend}=F.start_backend("notes")
    try do
      request=%{"version"=>1,"contract"=>"query-v1","partition"=>"notes","request_id"=>String.duplicate("a",32),"query"=>"none","top_k"=>1,"as_of_ms"=>20}
      assert F.backend_request(backend.port,"notes","query",request)["status"]=="ok"
      before=length(F.requests(F.backend_state(backend)))
      assert_raise MatchError,fn -> F.backend_request(backend.port,"notes","query",Map.put(request,"query",String.duplicate("x",32769))) end
      assert length(F.requests(F.backend_state(backend)))==before
    after
      assert :ok=F.stop_backend(backend)
    end
    parent=self()
    owner=spawn(fn -> {:ok,owned}=F.start_backend("notes"); send(parent,{:owned_fixture,owned}); receive do :leave -> :ok end end)
    owned=receive do {:owned_fixture,owned}->owned after 5000->raise "fixture owner failed" end
    monitor=Process.monitor(owned.pid)
    send(owner,:leave)
    assert_receive {:DOWN,^monitor,:process,_,:normal},5000
    refute Process.alive?(owned.pid)
    assert {:error,:econnrefused}=:gen_tcp.connect({127,0,0,1},owned.port,[:binary,active: false],1000)
    ''')
  end
end
