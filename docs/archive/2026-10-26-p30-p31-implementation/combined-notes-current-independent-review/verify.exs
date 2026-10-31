base = "docs/archive/2026-10-26-p30-p31-implementation/combined-notes-current"
root = "_build/combined-notes-assets-sol-20261029"
hash = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
rows = fn path -> File.read!(path) |> String.split("\n",trim: true) |> Map.new(fn l -> [h,p] = String.split(l,"  ",parts: 2); {p,h} end) end
check = fn list, dir -> Enum.each(list,fn {p,h} -> true = hash.(File.read!(Path.join(dir,p))) === h end) end
true = hash.(File.read!(base <> "/manifest.sha256")) === "5a387e279337eaa3aa2d17ded2c61d4bfe609800d5d71c646fc45a5ca629e6cd"
m = rows.(base <> "/manifest.sha256"); check.(m,base)
a = rows.(base <> "/base-runtime.sha256"); check.(a,"_build/document-inline-v4-complete-sol-20261029")
b = rows.(base <> "/runtime.sha256"); check.(b,root)
changed = Enum.filter(a, fn {p,h} -> b[p] !== h end) |> Enum.map(&elem(&1,0))
true = Enum.sort(changed) === Enum.sort(["priv/extension-bundles/catalog.json", "_build/dev/lib/ipse/priv/extension-bundles/catalog.json"])
[] = Enum.filter(a,fn {p,_} -> not Map.has_key?(b,p) end)
added = Map.keys(b) -- Map.keys(a)
true = Enum.all?(added, fn p -> String.starts_with?(p,"priv/extension-bundles/knowledge-current/") or String.starts_with?(p,"_build/dev/lib/ipse/priv/extension-bundles/knowledge-current/") or String.starts_with?(p,"extensions/knowledge/") or p === "knowledge-build-inputs.sha256" or p === "LICENSE" end)
true = File.read!(base <> "/host-inputs.sha256") === File.read!("docs/archive/2026-10-26-p30-p31-implementation/document-inline-v4/host-inputs.sha256")
inputs = rows.(base <> "/knowledge-build-inputs.sha256")
{:ok, tar} = :erl_tar.extract(String.to_charlist(base <> "/knowledge-build-sources.tar"),[:memory])
files = Map.new(tar,fn {p,b} -> {List.to_string(p),b} end)
true = map_size(files) === map_size(inputs)
Enum.each(inputs,fn {p,h} -> true = hash.(Map.fetch!(files,p)) === h end)
manifest_bytes = File.read!(base <> "/knowledge-current/extension.json")
"69eb134365d73256a75d31c99987502df809451c6d244396018a79dcee59447d" = hash.(manifest_bytes)
manifest = JSON.decode!(manifest_bytes)
true = manifest["subscriptions"] !== []
Code.prepend_paths(Path.wildcard(root <> "/_build/dev/lib/*/ebin"))
digest = &Ipse.JSON.digest/1
journal = File.read!(base <> "/journals/final.jsonl")
213879 = byte_size(journal)
true = journal === File.read!("/tmp/ipse-combined-notes-full-47243/home/sessions/b94bf0e8603bd11648bd9c4bba6d06f0.jsonl")
events = journal |> String.split("\n",trim: true) |> Enum.map(&JSON.decode!/1)
1 = Enum.count(events,&(&1["type"] === "input_received"))
4 = Enum.count(events,&(&1["type"] === "managed_source_lookup_prepared"))
true = Enum.any?(events,&(&1["type"] === "turn_finished" and &1["status"] === "ok"))
false = Enum.any?(events,&(&1["type"] === "managed_preflight_refused"))
[transition] = Enum.filter(events,&(&1["type"] === "managed_preflight_result" and get_in(&1,["projection","type"]) === "managed_root_transition"))
p = transition["projection"]
[old] = p["old_dependencies"]
0 = old["collection"]["generation"]
1 = p["fresh_dependency"]["collection"]["generation"]
[action] = Enum.filter(events,&(&1["type"] === "extension_action_result" and &1["operation_id"] === p["operation_id"]))
"ok" = action["outcome"]["status"]
true = p["own_action_sha256"] === digest.([action])
receipt = action["outcome"]["value"]["receipt"]
true = p["receipt_sha256"] === digest.([receipt])
true = p["inspection"]["operation"] === receipt
true = p["inspection"]["floor_anchor"] === p["operation_id"]
IO.puts("#{map_size(m)} archive rows, #{map_size(a)} parent and #{map_size(b)} candidate runtime rows verified; zero changed/deleted Host BEAMs")
IO.puts("#{length(added)} added artifact/build-source files; only replaced parent file is catalog; #{map_size(files)} knowledge build inputs verified")
IO.puts("#{length(events)} events, exact213879B original journal; one input/four source preflights/one root0→1 transition/known action+receipt/final turn ok")
IO.puts("Journal SHA256 " <> hash.(journal) <> "; operation " <> p["operation_id"])
