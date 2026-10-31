alias Path, as: P
base = "docs/archive/2026-10-26-p30-p31-implementation"
hash = fn data -> :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) end
rows = fn path -> File.read!(path) |> String.split("\n", trim: true) |> Enum.map(fn line -> [h,p] = String.split(line,"  ",parts: 2); {p,h} end) end
check = fn list, root -> Enum.each(list, fn {p,h} -> true = hash.(File.read!(P.join(root,p))) === h end); length(list) end
for {name, expected, graph} <- [
 {"document-inline-v4", "4e3707b2170c413fe9d084121c8a6b5f3c53ba16f42b3142156d220b995c36df", "_build/document-inline-v4-complete-sol-20261029"},
 {"document-source-use-v4", "ff35d3a1b24985ea1bd5a96ea60b5c4f13820677a6269f70b4c6302fdc0353ca", "_build/document-source-use-v4-sol-20261029"}
] do
 dir = P.join(base,name)
 true = hash.(File.read!(dir <> "/manifest.sha256")) === expected
 direct = check.(rows.(dir <> "/manifest.sha256"),dir)
 runtime = check.(rows.(dir <> "/runtime.sha256"), graph)
 IO.puts("#{name}: #{direct} archive rows and #{runtime} runtime rows match")
end
dir = base <> "/document-inline-v4"
{:ok, entries} = :erl_tar.extract(String.to_charlist(dir <> "/host-sources.tar"), [:memory])
files = Map.new(entries, fn {p,b} -> {List.to_string(p),b} end)
inputs = rows.(dir <> "/host-inputs.sha256")
true = map_size(files) === length(inputs)
Enum.each(inputs, fn {p,h} -> true = hash.(Map.fetch!(files,p)) === h end)
for {snapshot, original} <- [{"collection_store.ex","lib/ipse/extension/collection_store.ex"},{"document_embedding.ex","lib/ipse/session/document_embedding.ex"},{"session.ex","lib/ipse/session.ex"}] do
 true = File.read!(dir <> "/sources/" <> snapshot) === Map.fetch!(files,original)
end
true = File.read!(base <> "/document-source-use-v4/sources/document_source_use.ex") === Map.fetch!(files,"lib/ipse/extension/collection/document_source_use.ex")
{:ok,[{:application,:ipse, properties}]} = :file.consult(~c"_build/document-inline-v4-complete-sol-20261029/_build/dev/lib/ipse/ebin/ipse.app")
IO.puts("#{length(inputs)} tar inputs match; independent source-use snapshot matches combined source; #{length(properties[:modules])} app modules")
a = Map.new(rows.(base <> "/document-source-use-v4/base-runtime.sha256"))
b = Map.new(rows.(base <> "/document-source-use-v4/runtime.sha256"))
true = Map.keys(a) |> Enum.sort() === (Map.keys(b) |> Enum.sort())
diff = Enum.filter(b, fn {p,h} -> Map.fetch!(a,p) !== h end)
[{"_build/dev/lib/ipse/ebin/Elixir.Ipse.Extension.Collection.DocumentSourceUse.beam",_}] = diff
check.(Map.to_list(a),"_build/document-source-use-sol-20261029")
IO.puts("#{map_size(a)} base runtime rows match; exact one-BEAM source-use delta")
