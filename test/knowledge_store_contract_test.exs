defmodule Ipse.KnowledgeStoreContractTest do
  use ExUnit.Case, async: false
  @root Path.expand("..", __DIR__)
  @suite ~S"""
  ExUnit.start()
  defmodule IpseKnowledge.ContractControls do
  use ExUnit.Case
  alias IpseKnowledge.Store.MCPCAS, as: M
  alias Ipse.Development.Fixtures.Knowledge, as: F
  defp hash(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)
  defp id(tag, parts), do: hash(JSON.encode!(["ipse-knowledge",1,tag,parts]))
  defp profile(v), do: %{"kind"=>"mcp_cas","binding"=>"storage","partition"=>"notes","contract"=>"ipse-cas-v#{v}"}
  defp root(name), do: %{"format"=>1,"kind"=>"root","partition"=>"notes","source_key"=>hash(name),"generation"=>1,"state"=>"staging","content_sha256"=>hash("body"),"draft"=>nil}
  defp args(name, extra \\ %{}) do
    root=root(name)
    Map.merge(%{"key"=>id("root",["notes",root["source_key"]]),"expected_revision"=>0,"expected_source_generation"=>nil,"expected_content_sha256"=>nil,"draft_id"=>nil,"next_root"=>root},extra)
  end
  defp envelope(v, a), do: %{"version"=>v,"contract"=>"ipse-cas-v#{v}","partition"=>"notes","request_id"=>Base.encode16(:crypto.strong_rand_bytes(16),case: :lower),"action"=>"cas_root","args"=>a}
  defp drive({:call,request,cont},db) do
    {outcome,db}=F.host(db,request)
    drive(M.resume(cont,outcome),db)
  end
  defp drive(result,db), do: {result,db}
  defp fake({:call, request, cont}, status, generation, value, transform \\ &Function.identity/1) do
    inner=request["arguments"] |> Map.drop(["args"]) |> Map.merge(%{"status"=>status,"generation"=>generation,"value"=>value}) |> transform.()
    text=JSON.encode!(inner)
    d=%{"version"=>1,"operation_id"=>String.duplicate("1",32),"kind"=>"mcp.text","source_sha256"=>hash(text),"byte_count"=>byte_size(text)}
    {:call,_,reading}=M.resume(cont,%{"status"=>"ok","value"=>d})
    page=d |> Map.delete("byte_count") |> Map.merge(%{"offset"=>0,"next"=>nil,"complete"=>true,"text"=>text})
    M.resume(reading,%{"status"=>"ok","value"=>page})
  end
  test "v2 transport and fenced generation acceptance" do
    a=args("first",%{"expected_generation"=>0})
    call={:call,request,_}=M.start(profile(2),:cas_root,a)
    assert request["version"]===1
    assert request["arguments"]["version"]===2
    assert request["arguments"]["contract"]=="ipse-cas-v2"
    assert map_size(request["arguments"]["args"])==7
    assert {{:done,{:ok,%{"generation"=>1}}},_}=drive(call,F.new())
    record=%{"key"=>a["key"],"revision"=>1,"deleted"=>false,"value"=>a["next_root"]}
    assert {:done,{:error,:store_response,%{}}}=fake(call,"ok",2,%{"record"=>record})
    assert {:done,{:error,:store_response,%{}}}=fake(call,"ok",1,%{"record"=>record},&Map.put(&1,"version",1))
  end
  test "v3 explicitly selects the same fenced CAS shape and rejects forged generations" do
    a=args("v3",%{"expected_generation"=>0})
    call={:call,request,_}=M.start(profile(3),:cas_root,a)
    assert request["arguments"]["version"]===3
    assert request["arguments"]["contract"]=="ipse-cas-v3"
    assert map_size(request["arguments"]["args"])==7
    assert {{:done,{:ok,%{"generation"=>1}}},db}=drive(call,F.new())
    assert {{:done,{:ok,snapshot}},_}=drive(M.start(profile(3),:snapshot,%{}),db)
    assert map_size(snapshot["records"])==1
    assert {{:done,{:error,:conflict,%{}}},_}=drive(M.start(profile(3),:cas_root,a),db)
    record=%{"key"=>a["key"],"revision"=>1,"deleted"=>false,"value"=>a["next_root"]}
    assert {:done,{:error,:store_response,%{}}}=fake(call,"ok",2,%{"record"=>record})
    assert {:done,{:error,:atomic_admission_unavailable,%{}}}=M.start(profile(3),:cas_root,Map.put(a,"expected_generation",nil))
  end
  test "v1 creation refuses locally, legacy reads and updates keep wire shape" do
    assert {:done,{:error,:atomic_admission_unavailable,%{}}}=M.start(profile(1),:cas_root,args("legacy"))
    {reply,db}=F.handle(F.new(),envelope(1,args("legacy")))
    assert reply["status"]=="ok"
    a=args("legacy",%{"expected_revision"=>1,"expected_source_generation"=>1,"expected_content_sha256"=>hash("body")})
    call={:call,request,_}=M.start(profile(1),:cas_root,a)
    assert request["arguments"]["args"]==a
    assert request["arguments"]["version"]===1
    {:call,request,_}=M.start(profile(1),:cas_root,Map.put(a,"expected_generation",nil))
    assert request["arguments"]["args"]==a
    assert {:done,{:error,:atomic_admission_unavailable,%{}}}=M.start(profile(1),:cas_root,Map.put(a,"expected_generation",1))
    assert {{:done,{:ok,_}},db}=drive(call,db)
    assert {{:done,{:ok,snapshot}},_}=drive(M.start(profile(1),:snapshot,%{}),db)
    assert map_size(snapshot["records"])==1
  end
  test "v2 requires a safe condition for missing creation in adapter and server" do
    for condition<-[nil,-1,0.0,9_007_199_254_740_992] do
      a=args("new",%{"expected_generation"=>condition})
      assert {:done,{:error,:atomic_admission_unavailable,%{}}}=M.start(profile(2),:cas_root,a)
      {reply,db}=F.handle(F.new(),envelope(2,a))
      assert reply["status"]=="refused" and db.records==%{}
    end
    {reply,_}=F.handle(F.new(),envelope(2,args("new")))
    assert reply["status"]=="refused"
  end
  test "stale distinct-key creators conflict and retain one root" do
    calls=for name<-~w(a b c d),do: M.start(profile(2),:cas_root,args(name,%{"expected_generation"=>0}))
    {results,db}=Enum.map_reduce(calls,F.new(),&drive/2)
    assert Enum.count(results,&match?({:done,{:ok,_}},&1))==1
    assert Enum.all?(tl(results),&match?({:done,{:error,:conflict,%{}}},&1))
    assert map_size(db.records)==1 and db.generation==1
  end
  test "v2 nullable replacement preserves source draft conflicts" do
    a=args("existing",%{"expected_generation"=>0})
    {{:done,{:ok,_}},db}=drive(M.start(profile(2),:cas_root,a),F.new())
    base=args("existing",%{"expected_revision"=>1,"expected_source_generation"=>1,"expected_content_sha256"=>hash("body")})
    {:call,request,_}=M.start(profile(2),:cas_root,base)
    assert request["arguments"]["args"]["expected_generation"]==nil
    for changed<-[%{"expected_revision"=>2},%{"expected_generation"=>0},%{"expected_source_generation"=>2},%{"expected_content_sha256"=>hash("other")},%{"draft_id"=>String.duplicate("f",32)}] do
      assert {{:done,{:error,:conflict,%{}}},unchanged}=drive(M.start(profile(2),:cas_root,Map.merge(base,changed)),db)
      assert unchanged.records==db.records and unchanged.generation==db.generation
    end
    call=M.start(profile(2),:cas_root,base)
    record=%{"key"=>base["key"],"revision"=>2,"deleted"=>false,"value"=>base["next_root"]}
    assert {:done,{:error,:store_response,%{}}}=fake(call,"ok",0,%{"record"=>record})
    equal=%{"key"=>base["key"],"revision"=>1,"deleted"=>false,"source_generation"=>1,"content_sha256"=>hash("body"),"draft_id"=>nil}
    for forged<-[equal,Map.put(equal,"key",hash("wrong")),Map.put(equal,"value",%{"text"=>"not opaque"}),Map.put(equal,"source_generation",0)] do
      assert {:done,{:error,:store_response,%{}}}=fake(call,"conflict",1,%{"record"=>forged})
    end
    assert {{:done,{:ok,_}},_}=drive(call,db)
  end
  test "v2 preserves permanent suppression and unknown-after-commit" do
    a=args("suppressed",%{"expected_generation"=>0})
    suppressed=%{"format"=>1,"kind"=>"root","partition"=>"notes","source_key"=>hash("suppressed"),"generation"=>1,"state"=>"suppressed","suppressed_at_ms"=>20}
    a=Map.put(a,"next_root",suppressed)
    {{:done,{:ok,_}},db}=drive(M.start(profile(2),:cas_root,a),F.new())
    update=%{a|"expected_revision"=>1,"expected_generation"=>nil,"expected_source_generation"=>1}
    assert {{:done,{:error,:store_refused,%{}}},_}=drive(M.start(profile(2),:cas_root,update),db)
    unknown=F.barrier(F.new(),"cas_root",:unknown_after)
    assert {{:stop,:unknown_effect},db}=drive(M.start(profile(2),:cas_root,a),unknown)
    assert map_size(db.records)==1
  end
  test "v2 owner refuses positive-revision root tombstones with either generation form" do
    a=args("deleted",%{"expected_revision"=>2})
    tombstone=%{"key"=>a["key"],"revision"=>2,"deleted"=>true,"value"=>nil}
    db=%{F.new()|records: %{a["key"]=>tombstone},generation: 2}
    for condition <- [nil,2] do
      {reply,unchanged}=F.handle(db,envelope(2,Map.put(a,"expected_generation",condition)))
      assert reply["status"]=="refused"
      assert unchanged.records==db.records and unchanged.generation==db.generation
    end
    {legacy,_}=F.handle(db,envelope(1,a))
    assert legacy["status"]=="ok"
  end
  test "synthetic canonical State owner checks generation after target revision" do
    req=%{"op"=>"state.put","scope"=>"project","key"=>hash("state-a"),"expected_revision"=>0,"expected_generation"=>0,"value"=>%{"synthetic"=>true}}
    {outcome,db}=F.host(F.new(),req)
    assert outcome["status"]=="ok"
    {outcome,next}=F.host(db,Map.put(req,"key",hash("state-b")))
    assert outcome["status"]=="conflict" and next.records==db.records
  end
  test "v2 positive reads writes and collection require consistent namespace generations" do
    a=args("receipt")
    row=%{"key"=>a["key"],"revision"=>2,"deleted"=>false,"value"=>a["next_root"]}
    metadata=row |> Map.delete("value") |> Map.put("kind","root")
    directory=%{"records"=>[metadata],"count"=>1,"bytes"=>100,"complete"=>true}
    page=%{"key"=>a["key"],"value"=>%{"synthetic"=>"page"}}
    written=%{"key"=>a["key"],"revision"=>1,"deleted"=>false,"value"=>page["value"]}
    collected=%{row|"revision"=>3,"deleted"=>true,"value"=>nil}
    p=profile(2)
    phantom=%{row|"revision"=>0}
    missing=%{phantom|"deleted"=>true,"value"=>nil}
    read=M.start(p,:get_many,%{"keys"=>[a["key"]]})
    assert {:done,{:error,:snapshot_changed,%{}}}=fake(read,"ok",0,%{"records"=>[phantom],"complete"=>true})
    assert {:done,{:ok,_}}=fake(read,"ok",0,%{"records"=>[missing],"complete"=>true})
    assert {:done,{:error,:store_response,%{}}}=fake(M.start(p,:snapshot,%{}),"ok",0,directory)
    assert {:done,{:error,:snapshot_changed,%{}}}=fake(M.start(p,:get_many,%{"keys"=>[a["key"]]}),"ok",0,%{"records"=>[row],"complete"=>true})
    assert {:done,{:error,:store_response,%{}}}=fake(M.start(p,:put_immutable_many,%{"pages"=>[page]}),"ok",0,%{"records"=>[written]})
    collect=M.start(p,:collect,%{"records"=>[row],"snapshot_generation"=>2})
    for generation <- [0,2,4] do
      assert {:done,{:error,:store_response,%{}}}=fake(collect,"ok",generation,%{"records"=>[collected]})
    end
    assert {:done,{:ok,_}}=fake(collect,"ok",3,%{"records"=>[collected]})
    for generation <- [2,10,9_007_199_254_740_991] do
      read=fake(M.start(p,:snapshot,%{}),"ok",generation,directory)
      assert {:done,{:ok,_}}=fake(read,"ok",generation,%{"records"=>[row],"complete"=>true})
      assert {:done,{:ok,_}}=fake(M.start(p,:get_many,%{"keys"=>[a["key"]]}),"ok",generation,%{"records"=>[row],"complete"=>true})
      assert {:done,{:ok,_}}=fake(M.start(p,:put_immutable_many,%{"pages"=>[page]}),"ok",generation,%{"records"=>[written]})
    end
    legacy=profile(1)
    assert {:done,{:ok,_}}=fake(M.start(legacy,:get_many,%{"keys"=>[a["key"]]}),"ok",0,%{"records"=>[phantom],"complete"=>true})
    assert {:done,{:ok,_}}=fake(M.start(legacy,:get_many,%{"keys"=>[a["key"]]}),"ok",0,%{"records"=>[row],"complete"=>true})
    assert {:done,{:ok,_}}=fake(M.start(legacy,:put_immutable_many,%{"pages"=>[page]}),"ok",0,%{"records"=>[written]})
    assert {:done,{:ok,_}}=fake(M.start(legacy,:collect,%{"records"=>[row],"snapshot_generation"=>2}),"ok",0,%{"records"=>[collected]})
    read=fake(M.start(legacy,:snapshot,%{}),"ok",0,directory)
    assert {:done,{:ok,_}}=fake(read,"ok",0,%{"records"=>[row],"complete"=>true})
  end
  test "profiles accept explicit v1 and v2 without changing capability grants" do
    empty=Map.new(~w(stores search fetch retrieval embedding rerank extraction),&{&1,%{}})
    for v<-[1,2] do
      o=Map.merge(empty,%{"version"=>1,"stores"=>%{"notes"=>profile(v)},"retrieval"=>%{"words"=>%{"kind"=>"bm25","version"=>1}}})
      assert {:ok,_}=IpseKnowledge.Profiles.validate("corpus","mcp-lexical",o)
    end
  end
  end

  """

  test "remote contract receipts preserve atomic admission and explicit compatibility" do
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    sources =
      ~w(extensions/knowledge/src/profiles.ex extensions/knowledge/src/store/mcp_cas.ex dev/verification/cli.exs)

    loads =
      Enum.flat_map(sources, &["-r", Path.join(@root, &1)]) ++
        ["-e", "Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)"]

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ loads ++ ["-e", @suite],
        stderr_to_stdout: true
      )

    assert status == 0, output

    for module <- [
          IpseKnowledge.Profiles,
          IpseKnowledge.Store.MCPCAS
        ] do
      refute Code.ensure_loaded?(module)
    end
  end
end
