root = "docs/archive/2026-10-26-p30-p31-implementation/management-share-controls"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "3dd4c3e51017e1e6258b69a438373431dfbb1ca4998949da2e915a7b6d515121"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
{:ok, source_rows} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
sources = Map.new(source_rows, fn {p,b} -> {List.to_string(p),b} end)
physical = fn walk, path ->
  case File.lstat!(path).type do
    :regular -> [Path.expand(path)]
    :directory -> Enum.flat_map(File.ls!(path), fn name -> walk.(walk,Path.join(path,name)) end)
    :symlink -> []
  end
end
names = ["management-controls-sol-20261029", "management-share-candidate-v2-sol-20261029", "management-share-candidate-old-sol-20261029"]
inventories = for name <- names do
  graph = "_build/" <> name <> "/lib"
  rows = parse.(root <> "/runtime/" <> name <> ".sha256")
  Enum.each(rows, fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
  true = Enum.sort(Enum.map(rows, fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(physical.(physical,graph))
  helper = if String.contains?(name,"-old-"), do: "old-helper", else: "new-helper"
  true = File.read!(root <> "/" <> helper) == File.read!(Path.join(graph,"ipse/priv/ipse-runner"))
  beams = Path.wildcard(root <> "/runtime/" <> name <> "/*.beam")
  Enum.each(beams, fn p -> true = File.read!(p) == File.read!(Path.join(graph,"ipse/ebin/" <> Path.basename(p))) end)
  {name,Map.new(rows),length(beams)}
end
[{_,current,_},{_,earlier,_},{_,old,_}] = inventories
true = Enum.sort(Map.keys(current)) == Enum.sort(Map.keys(earlier))
true = Enum.sort(Map.keys(earlier)) == Enum.sort(Map.keys(old))
current_delta = for {p,h} <- earlier, current[p] != h, do: p
old_delta = for {p,h} <- earlier, old[p] != h, do: p
true = Enum.sort(current_delta) == ["./ipse/ebin/Elixir.Ipse.CLI.Knowledge.Management.beam", "./ipse/ebin/Elixir.Ipse.Runner.beam", "./ipse/ebin/Elixir.Ipse.Session.Resources.beam"]
true = Enum.sort(old_delta) == ["./ipse/ebin/Elixir.Ipse.Runner.beam", "./ipse/priv/ipse-runner"]
true = File.read!(root <> "/new-helper") == File.read!("docs/archive/2026-10-29-native-shared-lease/evidence/tty-session-bridge/ipse-tty-session-bridge-v2-helper")
{:ok, previous_rows} = :erl_tar.extract(~c"docs/archive/2026-10-29-native-shared-lease/evidence/tty-session-bridge/source.tar", [:memory])
previous = Map.new(previous_rows, fn {p,b} -> {List.to_string(p),b} end)
true = sources["lib/ipse/journal.ex"] == previous["lib/ipse/journal.ex"]
true = sources["lib/ipse/journal/writer.ex"] == previous["lib/ipse/journal/writer.ex"]
IO.inspect(%{manifest_entries: length(entries), frozen_source_files: map_size(sources), runtime_files_and_retained_beams: Enum.map(inventories, fn {n,m,b} -> {n,map_size(m),b} end), earlier_to_current_delta: Enum.sort(current_delta), old_helper_delta: Enum.sort(old_delta), native_helper_unchanged_from_bridge: true, journal_writer_sources_unchanged_from_bridge: true},label: "MANAGEMENT_SHARE_CONTROLS_MANIFEST_OK")
