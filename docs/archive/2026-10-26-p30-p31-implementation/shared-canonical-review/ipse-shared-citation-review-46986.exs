root = Path.expand("_build/shared-projection-codec-20261029")
Path.wildcard(root<>"/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
for p<-Path.wildcard(root<>"/tested-fixture-canonical/ebin/*.beam"),do: :code.load_abs(String.to_charlist(Path.rootname(p)))
alias IpseKnowledge.{Evidence,Store.Collection,Store.Collection.Generation,Store.Collection.Directory}
profile=%{"kind"=>"collection","scope"=>"project","partition"=>"notes"}
selection=%{"selection_sha256"=>Evidence.sha256("shape"),"profile"=>"fixture","model"=>"fixture","dimensions"=>32,"encoding"=>"float32le"}
extraction=%{"kind"=>"explicit","profile"=>nil,"version"=>1}
{bundles,supplied}=Enum.map(0..7,fn n->
  attrs=%{"source_id"=>"fixture:#{n}","partition"=>"notes","generation"=>1,"title"=>"Fixture","text"=>"Vega orbit source fixture:directory-#{n}.","uri"=>"provided:fixture","observed_at_ms"=>10,"event_at_ms"=>nil,"expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"documents","partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}}
  {:ok, attrs} = Evidence.collection_source(attrs)
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
values = Map.new(plan.values, &{&1.key, &1.value})
{:ok, ^supplied} = Generation.unpack_group("notes", plan.header, values, bundles, expected)
[bundle | _] = bundles
[data | _] = supplied
[fact] = data["facts"]
[citation] = fact["citations"]
noncanonical = Map.update!(citation, "version", &(&1 * 1.0))
IO.inspect(%{source: bundle["source"]["version"], citation: citation["version"], noncanonical_valid: Evidence.valid_span?(bundle["source"], noncanonical)}, label: "CITATION_SHAPE")
false = Evidence.valid_span?(bundle["source"], noncanonical)
{:ok, changed_fact} = Evidence.fact(fact |> Map.drop(~w(version fact_id)) |> Map.put("citations", [noncanonical]))
changed = put_in(supplied, [Access.at(0), "facts"], [changed_fact])
{:error, :invalid_shared_projection_group} = Generation.pack_group("notes", 0, bundles, changed, selection, extraction)
IO.inspect(%{canonical_roundtrip: true, citation_version: noncanonical["version"], noncanonical_span_refused: true, noncanonical_pack_refused: true}, label: "SHARED_CITATION_REVIEW")
