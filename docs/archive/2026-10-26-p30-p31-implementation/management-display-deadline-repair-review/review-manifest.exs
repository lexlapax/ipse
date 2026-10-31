root = "docs/archive/2026-10-26-p30-p31-implementation/management-display-deadline-repair"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
parse = fn p -> p |> File.read!() |> String.split("\n",trim: true) |> Enum.map(fn row -> [h,f] = String.split(row,"  ",parts: 2); {f,h} end) end
true = sha.(File.read!(root <> "/manifest.sha256")) == "4e83f484e60e270f9f5b6099277f50112d8c99ec9c38b919e5b46a6375235413"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
untar = fn p -> {:ok,rows} = :erl_tar.extract(String.to_charlist(p),[:memory]); Map.new(rows,fn {n,b} -> {List.to_string(n),b} end) end
sources = untar.(root <> "/source.tar")
negative = untar.(root <> "/negative-source.tar")
["native/ipse-terminal-lease.rs"] = for {p,b} <- negative, sources[p] != b, do: p
graph = "_build/management-deadline-v1-sol-20261029/lib"
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows,fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
walk = fn f,p -> case File.lstat!(p).type do :regular -> [Path.expand(p)]; :directory -> Enum.flat_map(File.ls!(p),fn n -> f.(f,Path.join(p,n)) end); :symlink -> [] end end
true = Enum.sort(Enum.map(rows,fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(walk.(walk,graph))
beams = Path.wildcard(root <> "/runtime/*.beam")
Enum.each(beams,fn p -> true = File.read!(p) == File.read!(Path.join(graph,"ipse/ebin/" <> Path.basename(p))) end)
prior = parse.("docs/archive/2026-10-26-p30-p31-implementation/management-full-facts-display/runtime/management-facts-v4-sol-20261029.sha256") |> Map.new()
true = Enum.sort(Map.keys(prior)) == Enum.sort(Enum.map(rows,&elem(&1,0)))
delta = for {p,h} <- rows, prior[p] != h, do: p
true = Enum.sort(delta) == ["./ipse/ebin/Elixir.Ipse.CLI.Knowledge.Management.beam", "./ipse/ebin/Elixir.Ipse.Runner.beam", "./ipse/priv/ipse-runner"]
true = File.read!(root <> "/ipse-management-deadline-v1-helper") == File.read!(graph <> "/ipse/priv/ipse-runner")
true = :binary.match(File.read!(root <> "/ipse-management-deadline-v1-helper"),"IPSE_TEST_") == :nomatch
source = sources["lib/ipse/cli/knowledge/management.ex"]
true = File.read!(root <> "/instrumentation/v2/management-late-instrumented.ex") == String.replace(source,"management_display_completion(result, overall, wall)","management_display_completion(result, overall, System.system_time(:millisecond) - 1)")
IO.inspect(%{manifest_entries: length(entries), frozen_sources: map_size(sources), physical_runtime_files: length(rows), retained_beams: length(beams), runtime_delta: Enum.sort(delta), final_late_return_source_exact: true, production_test_markers_absent: true},label: "MANAGEMENT_DISPLAY_DEADLINE_REPAIR_OK")
