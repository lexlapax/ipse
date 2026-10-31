root = "docs/archive/2026-10-26-p30-p31-implementation/generation-compact-handoff"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
parse = fn p -> p |> File.read!() |> String.split("\n",trim: true) |> Enum.map(fn r -> [h,f] = String.split(r,"  ",parts: 2); {f,h} end) end
true = sha.(File.read!(root <> "/manifest.sha256")) == "c20a02ad8bc4c314eff4e90ca9f9b38848fc765fa16003780b8871b4b94f8ca8"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(p)) == h end)
{:ok,source_rows} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
sources = Map.new(source_rows,fn {p,b} -> {List.to_string(p),b} end)
Enum.each(parse.(root <> "/source.sha256"),fn {p,h} -> true = sha.(Map.fetch!(sources,p)) == h end)
counts = for name <- ~w(runtime artifacts) do
  rows = parse.(root <> "/" <> name <> ".sha256")
  Enum.each(rows,fn {p,h} -> true = sha.(File.read!(p)) == h end)
  {name,length(rows)}
end
true = File.read!(root <> "/runtime.sha256") == File.read!("docs/archive/2026-10-26-p30-p31-implementation/generation-compact-progress/runtime.sha256")
IO.inspect(%{manifest_entries: length(entries), source_snapshots: map_size(sources), inventories: counts, compact_parent_runtime_exact: true}, label: "GENERATION_COMPACT_HANDOFF_OK")
