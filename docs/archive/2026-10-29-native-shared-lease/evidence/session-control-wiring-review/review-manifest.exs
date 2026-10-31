root = "docs/archive/2026-10-29-native-shared-lease/evidence/session-control-wiring"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "ba1b5cae42b49b56de91e19d18dedb544bc3940d1300a5910d2d47212130382e"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
untar = fn path ->
  {:ok, entries} = :erl_tar.extract(String.to_charlist(path), [:memory])
  Map.new(entries, fn {p,bytes} -> {List.to_string(p),bytes} end)
end
sources = untar.(root <> "/source.tar")
physical = fn walk, path ->
  case File.lstat!(path).type do
    :regular -> [Path.expand(path)]
    :directory -> Enum.flat_map(File.ls!(path), fn name -> walk.(walk,Path.join(path,name)) end)
    :symlink -> []
  end
end
graphs = [{"production", "_build/session-control-wiring-v3-sol-20261029/lib"}, {"instrumented", "_build/session-control-wiring-probe-v3-sol-20261029/lib"}]
inventories = for {kind,graph} <- graphs do
  rows = parse.(root <> "/runtime-" <> kind <> ".sha256")
  Enum.each(rows, fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
  true = Enum.sort(Enum.map(rows, fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(physical.(physical,graph))
  true = File.read!(root <> "/helper") == File.read!(Path.join(graph,"ipse/priv/ipse-runner"))
  {kind,Map.new(rows)}
end
[{_,production},{_,probe}] = inventories
true = Enum.sort(Map.keys(production)) == Enum.sort(Map.keys(probe))
changed = for {p,h} <- production, probe[p] != h, do: p
["./ipse/ebin/Elixir.Ipse.Extension.Host.beam"] = changed
for {file,graph} <- [{"host-production-beam.tar", "_build/session-control-wiring-v3-sol-20261029/lib"}, {"host-instrumented-beam.tar", "_build/session-control-wiring-probe-v3-sol-20261029/lib"}] do
  %{"Elixir.Ipse.Extension.Host.beam" => beam} = untar.(root <> "/" <> file)
  true = beam == File.read!(Path.join(graph,"ipse/ebin/Elixir.Ipse.Extension.Host.beam"))
end
host_source = sources["lib/ipse/extension/host.ex"]
needle = "case execute_admitted_action(context, worker, intent, request) do"
true = File.read!(root <> "/instrumented-host.ex") == String.replace(host_source,needle,"Ipse.Test.ShareHostProbe.pause(owner, job_ref, worker, intent)\n        " <> needle)
true = File.read!(root <> "/helper") == File.read!("docs/archive/2026-10-29-native-shared-lease/evidence/owner-controls/helper-v4")
repair = untar.("docs/archive/2026-10-26-p30-p31-implementation/management-journal-owner-alias-repair/source.tar")
true = sources["lib/ipse/journal.ex"] == repair["lib/ipse/journal.ex"]
for file <- ["Elixir.Ipse.Session.Lock.beam", "Elixir.Ipse.Journal.beam", "Elixir.Ipse.Journal.Writer.beam"] do
  true = File.read!("_build/session-control-wiring-v3-sol-20261029/lib/ipse/ebin/" <> file) == File.read!("_build/owner-control-v4-sol-20261029/lib/ipse/ebin/" <> file)
end
artifacts = for kind <- ["nonsocket", "socket"], do: {kind,map_size(untar.(root <> "/artifact-" <> kind <> ".tar"))}
IO.inspect(%{manifest_entries: length(entries), source_files: map_size(sources), runtime_files: Enum.map(inventories,fn {k,v} -> {k,map_size(v)} end), graph_delta: changed, exact_test_rendezvous: true, helper_unchanged: true, lock_journal_writer_inherited: true, alias_repair_preserved: true, artifacts: artifacts},label: "SESSION_CONTROL_WIRING_MANIFEST_OK")
