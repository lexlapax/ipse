root = "docs/archive/2026-10-29-native-shared-lease/evidence/terminal-lease-inert"
graph = "_build/terminal-lease-inert-v2-sol-20261029/lib"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash,file] = String.split(row,"  ",parts: 2)
    {file,hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "a6472791750540594ad05a2c061bd5e03338f5b83b05d4b36bccd2d14b18e24e"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
{:ok,sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows,fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
physical = fn walk,path ->
  case File.lstat!(path).type do
    :regular -> [Path.expand(path)]
    :directory -> Enum.flat_map(File.ls!(path),fn n -> walk.(walk,Path.join(path,n)) end)
    :symlink -> []
  end
end
true = Enum.sort(Enum.map(rows,fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(physical.(physical,graph))
true = File.read!(root <> "/helper-v2") == File.read!(Path.join(graph,"ipse/priv/ipse-runner"))
true = sha.(File.read!(root <> "/helper-v2")) == "9b1ba1d304925279cccfd1d1bcbd5d377b9ee1f46089eed7db2fd710ac2df68b"
for file <- ["Elixir.Ipse.Session.beam","Elixir.Ipse.Session.Lock.beam","Elixir.Ipse.Journal.beam","Elixir.Ipse.Journal.Writer.beam"] do
  true = File.read!(Path.join(graph,"ipse/ebin/" <> file)) == File.read!("_build/owner-control-v4-sol-20261029/lib/ipse/ebin/" <> file)
end
source_map = Map.new(sources,fn {p,b} -> {List.to_string(p),b} end)
true = Map.has_key?(source_map,"native/ipse-terminal-lease.rs")
true = Map.has_key?(source_map,"dev/fixtures/terminal_lease_probe.rs")
IO.inspect(%{manifest_entries: length(entries), source_files: length(sources), runtime_files: length(rows), helper_matches: true, inherited_owner_control_session_graph: true, final_fixture_and_operator_binaries_pinned: true},label: "TERMINAL_LEASE_INERT_MANIFEST_OK")
