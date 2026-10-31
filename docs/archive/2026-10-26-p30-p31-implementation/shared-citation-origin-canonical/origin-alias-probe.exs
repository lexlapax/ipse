root = Path.expand("_build/shared-projection-codec-20261029")
Path.wildcard(root<>"/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
for p<-Path.wildcard(root<>"/tested-fixture-directory/ebin/*.beam"),do: :code.load_abs(String.to_charlist(Path.rootname(p)))
alias IpseKnowledge.{Evidence,Store.Collection,Store.Collection.Generation,Store.Collection.Directory}
profile=%{"kind"=>"collection","scope"=>"project","partition"=>"notes"}
selection=%{"selection_sha256"=>Evidence.sha256("shape"),"profile"=>"fixture","model"=>"fixture","dimensions"=>32,"encoding"=>"float32le"}
extraction=%{"kind"=>"explicit","profile"=>nil,"version"=>1}
{bundles,supplied}=Enum.map(0..7,fn n->
  attrs=%{"source_id"=>"fixture:#{n}","partition"=>"notes","generation"=>1,"title"=>"Fixture","text"=>"Vega orbit source fixture:directory-#{n}.","uri"=>"provided:fixture","observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"documents","partition_or_scope"=>"notes","receipt"=>%{"version"=>1},"historical"=>false}}
  {:call,_,p}=Collection.start(profile,:put,%{"source"=>attrs,"expected_revision"=>0,"continuation"=>nil})
  {:ok,head}=Collection.planned_source_head(p,n)
  source=p.source
  {:ok,[chunk]}=Evidence.chunks(source)
  {:ok,input}=Ipse.Extension.canonical_digest([chunk["text"]])
  {:ok,vector}=Evidence.vector(Map.merge(Map.delete(selection,"encoding"),%{"chunk_id"=>chunk["chunk_id"],"input_sha256"=>input,"values"=>List.duplicate(1.0,32)}))
  {:ok,citation}=Evidence.citation(source,chunk,0,10)
  {:ok,fact}=Evidence.fact(%{"subject"=>"Subject#{n}","object"=>"Object#{n}","predicate"=>"rel","polarity"=>"positive","inferred"=>false,"valid_from_ms"=>nil,"valid_to_ms"=>nil,"extraction"=>extraction,"citations"=>[citation]})
  {%{"source"=>source,"head"=>head},%{"source_key"=>source["source_key"],"source_bundle_sha256"=>Evidence.sha256(IO.iodata_to_binary(JSON.encode!(source))),"vectors"=>[vector],"facts"=>[fact]}}
end) |> Enum.sort_by(fn {b,_}->b["source"]["source_key"] end) |> Enum.unzip()
{:ok,plan}=Generation.pack_group("notes",0,bundles,supplied,selection,extraction)
expected=%{"cursor"=>0,"vector_selection"=>selection,"fact_selection"=>extraction}
IO.inspect(Directory.capture("notes",plan,bundles,expected),limit: 3)
data=put_in(supplied,[Access.at(0),"facts",Access.at(0),"citations",Access.at(0),"origin","receipt","version"],1.0)
fact=hd(hd(data)["facts"])
IO.inspect({Evidence.valid_fact?(fact),Evidence.valid_span?(hd(bundles)["source"],hd(fact["citations"]))},label: "accepted")
{:ok,other}=Generation.pack_group("notes",0,bundles,data,selection,extraction)
{:ok,out}=Generation.unpack_group("notes",other.header,Map.new(other.values,&{&1.key,&1.value}),bundles,expected)
IO.inspect(data === out,label: "exact_roundtrip")
