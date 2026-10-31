root = "docs/archive/2026-10-29-mcp-discovery-outcome/extension"
sha = fn bytes -> :crypto.hash(:sha256,bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  File.read!(path) |> String.split("\n",trim: true) |> Map.new(fn row ->
    [h,p] = String.split(row,"  ",parts: 2)
    {p,h}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "ffae8498fde218c740501a27c9175730814d25c59faaa18ee9872a622d34d326"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(p)) == h end)
{:ok,sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
source_map = Map.new(sources,fn {p,b} -> {List.to_string(p),b} end)
source_rows = parse.(root <> "/source.sha256")
true = Enum.sort(Map.keys(source_map)) == Enum.sort(Map.keys(source_rows))
Enum.each(source_rows,fn {p,h} -> true = sha.(source_map[p]) == h end)
runtime = parse.(root <> "/runtime.sha256")
Enum.each(runtime,fn {p,h} -> true = sha.(File.read!(p)) == h end)
graph = Path.expand("_build/extension-discovery-unknown-sol-20261029")
base = parse.("docs/archive/2026-10-29-mcp-discovery-outcome/runtime.sha256")
relative = fn rows,dir -> Map.new(rows,fn {p,h} -> {Path.relative_to(Path.expand(p),Path.expand(dir)),h} end) end
old = relative.(base,"_build/mcp-discovery-unknown-sol-20261029")
new = relative.(runtime,graph)
true = Enum.all?(Map.keys(old), &Map.has_key?(new,&1))
changed = for {p,h} <- old, new[p] != h, do: Path.basename(p)
true = Enum.sort(changed) == ~w(Elixir.Ipse.Extension.MCPCall.beam Elixir.Ipse.Extension.ToolAction.beam)
[{helper,h}] = Map.to_list(parse.(root <> "/helper.sha256"))
true = sha.(File.read!(helper)) == h
true = h == "7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067"
IO.inspect(%{manifest_entries: map_size(entries), sources: map_size(source_map), runtime_files: map_size(runtime), base_inventory_files: map_size(old), additional_pinned_files: map_size(new)-map_size(old), changed_modules: Enum.sort(changed), helper_unchanged: true},label: "EXTENSION_DISCOVERY_MANIFEST_OK")
