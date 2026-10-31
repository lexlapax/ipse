root = "docs/archive/2026-10-29-native-shared-lease/evidence/tty-session-bridge"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "8125763a87ec0ef4f620cdc5cf2c39ab6038ddc92c1ef9056ef35591e2214392"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
{:ok, source_rows} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
sources = Map.new(source_rows, fn {p,bytes} -> {List.to_string(p),bytes} end)
physical = fn walk, path ->
  case File.lstat!(path).type do
    :regular -> [Path.expand(path)]
    :directory -> Enum.flat_map(File.ls!(path), fn name -> walk.(walk,Path.join(path,name)) end)
    :symlink -> []
  end
end
names = ["tty-session-bridge-v2-sol-20261029", "tty-session-bridge-final-probe-sol-20261029", "tty-session-bridge-loss-sol-20261029"]
inventories = for name <- names do
  graph = "_build/" <> name <> "/lib"
  rows = parse.(root <> "/runtime/" <> name <> ".sha256")
  Enum.each(rows, fn {p,h} -> true = sha.(File.read!(Path.join(graph,p))) == h end)
  true = Enum.sort(Enum.map(rows, fn {p,_} -> Path.expand(Path.join(graph,p)) end)) == Enum.sort(physical.(physical,graph))
  true = File.read!(root <> "/ipse-tty-session-bridge-v2-helper") == File.read!(Path.join(graph,"ipse/priv/ipse-runner"))
  beam_paths = Path.wildcard(root <> "/runtime/" <> name <> "/*.beam")
  Enum.each(beam_paths, fn path -> true = File.read!(path) == File.read!(Path.join(graph,"ipse/ebin/" <> Path.basename(path))) end)
  {name,Map.new(rows),length(beam_paths)}
end
[{_,production,_},{_,positive,_},{_,loss,_}] = inventories
true = Enum.sort(Map.keys(production)) == Enum.sort(Map.keys(positive))
true = Enum.sort(Map.keys(positive)) == Enum.sort(Map.keys(loss))
positive_delta = for {p,h} <- production, positive[p] != h, do: p
loss_delta = for {p,h} <- positive, loss[p] != h, do: p
["./ipse/ebin/Elixir.Ipse.Extension.Host.beam"] = positive_delta
["./ipse/ebin/Elixir.Ipse.Runner.LeasedTerminal.beam"] = loss_delta
for name <- names do
  for file <- ["Elixir.Ipse.Journal.beam", "Elixir.Ipse.Journal.Writer.beam"] do
    true = File.read!("_build/" <> name <> "/lib/ipse/ebin/" <> file) == File.read!("_build/session-control-wiring-v3-sol-20261029/lib/ipse/ebin/" <> file)
  end
end
IO.inspect(%{manifest_entries: length(entries), source_files: map_size(sources), runtime_files_and_retained_beams: Enum.map(inventories, fn {name,rows,beams} -> {name,map_size(rows),beams} end), positive_delta: positive_delta, cancellation_delta: loss_delta, helper_sha256: sha.(File.read!(root <> "/ipse-tty-session-bridge-v2-helper")), inherited_journal_writer: true, artifact_archive_claimed: false},label: "TTY_SESSION_BRIDGE_MANIFEST_OK")
