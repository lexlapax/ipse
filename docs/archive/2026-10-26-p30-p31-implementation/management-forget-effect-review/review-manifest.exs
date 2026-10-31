root = "docs/archive/2026-10-26-p30-p31-implementation/management-forget-effect"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
parse = fn p -> p |> File.read!() |> String.split("\n",trim: true) |> Enum.map(fn r -> [h,f] = String.split(r,"  ",parts: 2); {f,h} end) end
true = sha.(File.read!(root <> "/manifest.sha256")) == "5c8848fa68cb17613956f12648188e32f41afa8c405fde95a105b59f7e48d6ad"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
{:ok,source_rows} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
sources = Map.new(source_rows,fn {p,b} -> {List.to_string(p),b} end)
true = sha.(sources["lib/ipse/extension/collection.ex"]) == "95f70bbfc695d6b1d54476c33e0209f7b641e616754c4fc3cbd3029787ed6e96"
true = sha.(sources["lib/ipse/cli/knowledge/management.ex"]) == "95513f827ce858d28f4618dd4882e02fb532dcb2f29091ebca00dcb510cc2ba4"
true = sources["lib/ipse/extension/collection.ex"] == File.read!("docs/archive/2026-10-26-p30-p31-implementation/reviewed-forget-core/lib__ipse__extension__collection.ex.txt")
graph = "_build/management-forget-effect-sol-20261029/lib"
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows,fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
walk = fn f,p -> case File.lstat!(p).type do :regular -> [Path.expand(p)]; :directory -> Enum.flat_map(File.ls!(p),fn n -> f.(f,Path.join(p,n)) end); :symlink -> [] end end
true = Enum.sort(Enum.map(rows,fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(walk.(walk,graph))
beams = Path.wildcard(root <> "/beams/*.beam")
Enum.each(beams,fn p -> true = File.read!(p) == File.read!(Path.join(graph,"ipse/ebin/" <> Path.basename(p))) end)
prior_root = "docs/archive/2026-10-26-p30-p31-implementation/management-review-input"
prior = parse.(prior_root <> "/runtime.sha256") |> Map.new()
true = Enum.sort(Map.keys(prior)) == Enum.sort(Enum.map(rows,&elem(&1,0)))
delta = for {p,h} <- rows, prior[p] != h, do: p
true = Enum.sort(delta) == ["./ipse/ebin/Elixir.Ipse.CLI.Knowledge.Management.beam", "./ipse/ebin/Elixir.Ipse.Extension.Collection.beam"]
true = File.read!(prior_root <> "/ipse-runner") == File.read!(graph <> "/ipse/priv/ipse-runner")
journals = for p <- Path.wildcard(root <> "/journals/*.jsonl") do
  events = File.stream!(p) |> Enum.map(&:json.decode/1)
  [%{"type" => "session", "metadata" => metadata} | tail] = events
  true = metadata["kind"] == "knowledge_management" and not Map.has_key?(metadata,"release_receipt_layout")
  intents = Enum.filter(tail,&(&1["type"] == "managed_lifecycle_intent"))
  results = Enum.filter(tail,&(&1["type"] == "managed_lifecycle_result"))
  true = length(intents) <= 1 and length(results) <= 1 and length(tail) == length(intents)+length(results)
  if intents != [] and results != [], do: true = hd(intents)["operation_id"] == hd(results)["operation_id"]
  {Path.basename(p),Enum.map(events,& &1["type"]),Enum.map(results,& &1["status"])}
end
IO.inspect(%{manifest_entries: length(entries), source_snapshots: map_size(sources), physical_runtime_files: length(rows), retained_beams: length(beams), runtime_delta: Enum.sort(delta), core_source_exact: true, helper_unchanged: true, copied_synthetic_journals: journals},label: "MANAGEMENT_FORGET_EFFECT_VERIFIED")
