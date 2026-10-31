root = "docs/archive/2026-10-26-p30-p31-implementation/management-full-facts-display"
sha = fn b -> :crypto.hash(:sha256,b) |> Base.encode16(case: :lower) end
parse = fn p -> p |> File.read!() |> String.split("\n",trim: true) |> Enum.map(fn row -> [h,f] = String.split(row,"  ",parts: 2); {f,h} end) end
true = sha.(File.read!(root <> "/manifest.sha256")) == "6132862ddd8cf60f2bb197f638880ed94edc220c10508554b6ac4117b9b1266d"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
untar = fn p -> {:ok,rows} = :erl_tar.extract(String.to_charlist(p),[:memory]); Map.new(rows,fn {name,b} -> {List.to_string(name),b} end) end
sources = untar.(root <> "/source.tar")
negative = untar.(root <> "/negative-clock-source.tar")
negative_delta = for {p,b} <- negative, sources[p] != b, do: p
["native/ipse-terminal-lease.rs"] = negative_delta
physical = fn walk,p -> case File.lstat!(p).type do :regular -> [Path.expand(p)]; :directory -> Enum.flat_map(File.ls!(p),fn n -> walk.(walk,Path.join(p,n)) end); :symlink -> [] end end
names = ["management-facts-v1-sol-20261029", "management-facts-v2-sol-20261029", "management-facts-v4-sol-20261029", "management-facts-v4-loss-sol-20261029"]
graphs = for n <- names do
  graph = "_build/" <> n <> "/lib"
  rows = parse.(root <> "/runtime/" <> n <> ".sha256")
  Enum.each(rows,fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
  true = Enum.sort(Enum.map(rows,fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(physical.(physical,graph))
  beams = Path.wildcard(root <> "/runtime/" <> n <> "/*.beam")
  Enum.each(beams,fn p -> true = File.read!(p) == File.read!(Path.join(graph,"ipse/ebin/" <> Path.basename(p))) end)
  {n,Map.new(rows),length(beams)}
end
[{_,v1,_},{_,v2,_},{_,final,_},{_,loss,_}] = graphs
for {_,m,_} <- graphs, do: true = Enum.sort(Map.keys(m)) == Enum.sort(Map.keys(final))
delta = fn a,b -> for {p,h} <- a, b[p] != h, do: p end
true = Enum.sort(delta.(final,loss)) == ["./ipse/ebin/Elixir.Ipse.Runner.beam", "./ipse/priv/ipse-runner"]
for {name,helper} <- [{Enum.at(names,0),"ipse-management-facts-v1-helper"},{Enum.at(names,1),"ipse-management-facts-v1-helper"},{Enum.at(names,2),"ipse-management-facts-v4-helper"},{Enum.at(names,3),"ipse-management-facts-v4-hook-helper"}] do
  true = File.read!(root <> "/" <> helper) == File.read!("_build/" <> name <> "/lib/ipse/priv/ipse-runner")
end
prod = File.read!(root <> "/ipse-management-facts-v4-helper")
true = :binary.match(prod,"IPSE_TEST_TTY_") == :nomatch
artifact = untar.(root <> "/selected-artifact.tar")
[digest] = artifact |> Map.keys() |> Enum.map(&(String.split(&1,"/") |> hd())) |> Enum.uniq()
manifest_bytes = artifact[digest <> "/extension.json"]
true = sha.(manifest_bytes) == digest
manifest = :json.decode(manifest_bytes)
Enum.each(manifest["files"],fn row -> b = artifact[digest <> "/" <> row["path"]]; true = is_binary(b) and byte_size(b) == row["bytes"] and sha.(b) == row["sha256"] end)
for {p,b} <- artifact do
  relative = String.replace_prefix(p,digest <> "/", "")
  true = b == File.read!("_build/management-facts-v4-sol-20261029/lib/ipse/priv/extension-bundles/knowledge/" <> relative)
end
management = sources["lib/ipse/cli/knowledge/management.ex"]
terminal = sources["lib/ipse/runner/management_terminal.ex"]
stale_needle = "controlled_share_journal_candidate(config, cwd, overall, fn owned ->"
true = File.read!(root <> "/instrumentation/stale/management-instrumented.ex") == String.replace(management,stale_needle,":ok = Ipse.Test.ManagementDisplayProbe.pause_snapshot()\n      " <> stale_needle)
close_needle = ":ok <- Resources.management_control_prepare_close(owned.cli_control),"
true = File.read!(root <> "/instrumentation/close-loss/management-terminal-close-instrumented.ex") == String.replace(terminal,close_needle,":ok <- Ipse.Test.ManagementDisplayProbe.pause_close(owned, pid),\n             " <> close_needle)
loss_needle = ":ok <- send_frame(port, ?A, body),"
loss_source = terminal |> String.replace("_reader::32", "reader::32") |> String.replace(loss_needle,loss_needle <> "\n             :ok <- Ipse.Test.ManagementDisplayProbe.pause(owned, reader, pid, ids, journal),")
for mode <- ["v4-loss", "v4-journal-loss", "v4-cli-loss"], do: true = File.read!(root <> "/instrumentation/" <> mode <> "/management-terminal-instrumented.ex") == loss_source
IO.inspect(%{manifest_entries: length(entries), frozen_sources: map_size(sources), graph_files_and_retained_beams: Enum.map(graphs,fn {n,m,b} -> {n,map_size(m),b} end), v1_to_v2: Enum.sort(delta.(v1,v2)), v2_to_final: Enum.sort(delta.(v2,final)), final_to_hook: Enum.sort(delta.(final,loss)), selected_artifact_digest: digest, selected_artifact_files: map_size(artifact), declared_artifact_files: length(manifest["files"]), negative_source_delta: negative_delta, production_hook_markers_absent: true},label: "MANAGEMENT_FULL_FACTS_MANIFEST_OK")
