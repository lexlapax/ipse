defmodule Ipse.KnowledgeStoreTest do
  use ExUnit.Case, async: false
  @root Path.expand("..", __DIR__)

  defp isolated(body) do
    paths = ~w(evidence.ex store/state.ex store/mcp_cas.ex store.ex)

    args =
      Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)]) ++
        Enum.flat_map(paths, &["-r", Path.join(@root, "extensions/knowledge/src/" <> &1)]) ++
        ["-r", Path.join(@root, "test/support/knowledge_mcp_fixture.exs")]

    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.Evidence, as: E
    alias IpseKnowledge.Store, as: S
    alias IpseKnowledge.Test.CASFixture, as: F
    defmodule Driver do
      def run({:call,request,continuation},db) do
        {outcome,db}=IpseKnowledge.Test.CASFixture.host(db,request)
        run(IpseKnowledge.Store.resume(continuation,outcome),db)
      end
      def run(result,db), do: {result,db}
    end
    state=%{"kind"=>"state","scope"=>"project","partition"=>"notes"}
    remote=%{"kind"=>"mcp_cas","binding"=>"storage","partition"=>"notes","contract"=>"ipse-cas-v1"}
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
    vectors=Enum.map(chunks,fn chunk -> {:ok,v}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"input_sha256"=>E.sha256("host canonical input"<>chunk["chunk_id"]),"profile"=>"encoder","model"=>"native-model","dimensions"=>4096,"values"=>values}); v end)
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
    {:ok,vector}=E.vector(%{"chunk_id"=>chunk["chunk_id"],"input_sha256"=>E.sha256("opaque input"),"profile"=>"encoder","model"=>"model","dimensions"=>1,"values"=>[1.0]})
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
    {r,db}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>nil,"limit"=>4}); first=success.(r)
    refute first["complete"]; refute Map.has_key?(first["source"],"text")
    {r,db}=invoke.(db,Map.put(state,"partition","migration"),:import,%{"expected_revision"=>0,"export"=>first}); assert {:done,{:error,:incomplete_import,%{}}}=r
    {r,_}=invoke.(db,state,:export,%{"source_id"=>"manual:one","cursor"=>first["next"],"limit"=>4}); last=success.(r)
    assert last["complete"]; assert first["text"]<>last["text"]==String.duplicate("x",5000)
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
