root = "docs/archive/2026-10-29-native-shared-lease/evidence/owner-controls"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "43989ae3734b17b600bbc3848789c780f36354c63df9a6dbed041311a52882a2"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
untar = fn path ->
  {:ok, entries} = :erl_tar.extract(String.to_charlist(path), [:memory])
  Map.new(entries, fn {p,bytes} -> {List.to_string(p),bytes} end)
end
sources = untar.(root <> "/source.tar")
graphs = [{"session", "_build/owner-control-v4-sol-20261029/lib"}, {"host-instrumented", "_build/owner-control-host-v4-sol-20261029/lib"}]
physical_files = fn walk, path ->
  case File.lstat!(path).type do
    :regular -> [Path.expand(path)]
    :directory -> Enum.flat_map(File.ls!(path), fn name -> walk.(walk, Path.join(path,name)) end)
    :symlink -> []
  end
end
inventories = for {kind,graph} <- graphs do
  rows = parse.(root <> "/runtime-" <> kind <> ".sha256")
  Enum.each(rows, fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
  inventoried = Enum.map(rows, fn {p,_} -> Path.expand(Path.join(graph,p)) end) |> Enum.sort()
  actual = physical_files.(physical_files, graph) |> Enum.sort()
  true = inventoried == actual
  true = File.read!(root <> "/helper-v4") == File.read!(Path.join(graph,"ipse/priv/ipse-runner"))
  {kind,Map.new(rows)}
end
[{_,session},{_,host}] = inventories
true = Enum.sort(Map.keys(session)) == Enum.sort(Map.keys(host))
changed = for {p,h} <- session, host[p] != h, do: p
["./ipse/ebin/Elixir.Ipse.Extension.Host.beam"] = changed
%{"Elixir.Ipse.Extension.Host.beam" => host_beam} = untar.(root <> "/host-instrumented-beam.tar")
true = host_beam == File.read!("_build/owner-control-host-v4-sol-20261029/lib/ipse/ebin/Elixir.Ipse.Extension.Host.beam")
true = File.read!(root <> "/instrumented-host.ex") == File.read!("docs/archive/2026-10-29-native-shared-lease/evidence/session-host-share/instrumented-host.ex")
for file <- ["Elixir.Ipse.Session.beam", "Elixir.Ipse.Session.Lock.beam", "Elixir.Ipse.Journal.beam", "Elixir.Ipse.Journal.Writer.beam"] do
  true = File.read!("_build/owner-control-v4-sol-20261029/lib/ipse/ebin/" <> file) == File.read!("_build/session-host-share-v2-sol-20261029/lib/ipse/ebin/" <> file)
end
true = sha.(File.read!(root <> "/helper-v4")) == "a3f4c20e597820ad2618cf7f2da4c2d6f11afe80389ca52d83ece7804bde38cd"
IO.inspect(%{manifest_entries: length(entries), source_files: map_size(sources), runtime_files: Enum.map(inventories, fn {k,v} -> {k,map_size(v)} end), graph_delta: changed, helper_matches: true, instrumented_host_matches: true, session_lock_journal_writer_inherited: true, artifact_files: map_size(untar.(root <> "/host-fixture-artifact.tar"))}, label: "OWNER_CONTROLS_MANIFEST_OK")
