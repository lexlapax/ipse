base="/tmp/ipse-managed-binary-proof-20261026-01/bound"
parts=Path.wildcard(Path.join(base,"pages-*.json")) |> Enum.reject(&String.ends_with?(&1,"pages-candidate-safe-target.json")) |> Enum.map(fn p->{p,Jason.decode!(File.read!(p))}end)
anchors=for {p,r}<-parts,a<-r["parts"],a["kind"]!="live",do: {p,a}
lives=for {p,r}<-parts,a<-r["parts"],a["kind"]=="live",do: {p,a}
cases=for {ap,a}<-anchors,{lp,l}<-lives,a["clock_profile"]==l["clock_profile"] do
  metadata=a["encoded_page_bytes"]+l["encoded_page_bytes"]
  row=%{choice_format: a["kind"],clock_profile: a["clock_profile"],retirement_profile: a["retirement_profile"],dictionary_profile: l["dictionary_profile"],notes: l["notes"],source_anchors: a["rows"],anchor_page_bytes: a["encoded_page_bytes"],live_page_bytes: l["encoded_page_bytes"],total_page_bytes: metadata,metadata_allowance: 24*1024*1024-l["notes"]*6144,future_format_record_reservation: 6144,total_page_bytes_plus_format_reservation: metadata+6144,above_allowance_including_format_reservation: metadata+6144>24*1024*1024-l["notes"]*6144,above_allowance: metadata>24*1024*1024-l["notes"]*6144,record_slots: l["notes"]+a["pages"]+l["pages"]+1,anchor_report: Path.basename(ap),live_report: Path.basename(lp),actual_publications: 0,qualification_passed: false}
  row
end
sources = ~w(dev/knowledge/managed_metadata.ex dev/knowledge/managed_metadata_shapes.exs dev/knowledge/managed_metadata_binary.ex dev/knowledge/managed_metadata_binary_shapes.exs dev/knowledge/managed_metadata_binary_proof.exs dev/knowledge/managed_metadata_binary_measure.exs)
source_hashes=Map.new(sources,fn p->{p,Ipse.JSON.sha256(File.read!(p))}end)
report=%{kind: "joined_pure_binary_page_measurements",cases: cases,source_sha256: source_hashes,total_measured_parts: length(parts),actual_publications: 0,native_calls: 0,model_calls: 0,qualification_passed: false,scope: "Declared fields only; full-source and future-native projections separate; not actual Note admission, lifecycle integration, dynamic packing, native allocation or annual writes."}
File.write!(Path.join(base,"measurements-joined.json"),Jason.encode!(report,pretty: true)<>"\n")
Enum.each(cases,fn c -> if c.notes==3642 and c.dictionary_profile=="one_recipe_one_policy",do: IO.inspect(c) end)
