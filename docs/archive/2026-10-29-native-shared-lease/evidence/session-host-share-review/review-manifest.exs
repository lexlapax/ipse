root = "docs/archive/2026-10-29-native-shared-lease/evidence/session-host-share"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "2f98a960b31c5607b041ffea3d157b6fb75511d7ab0e1bbb78573c4c2a7d292c"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {p, h} -> true = sha.(File.read!(Path.join(root, p))) == h end)
untar = fn path ->
  {:ok, entries} = :erl_tar.extract(String.to_charlist(path), [:memory])
  Map.new(entries, fn {p, bytes} -> {List.to_string(p), bytes} end)
end
sources = untar.(root <> "/source.tar")
true = map_size(sources) == 7
production = "_build/session-host-share-v2-sol-20261029/lib"
instrumented = "_build/session-host-share-probe-v2-sol-20261029/lib"
inventories = for {kind, graph} <- [{"production", production}, {"instrumented", instrumented}] do
  rows = parse.(root <> "/runtime-" <> kind <> ".sha256")
  Enum.each(rows, fn {p, h} -> true = sha.(File.read!(Path.join(graph, p))) == h end)
  {kind, Map.new(rows)}
end
[{_, prod}, {_, probe}] = inventories
true = Enum.sort(Map.keys(prod)) == Enum.sort(Map.keys(probe))
changed = for {p, h} <- prod, probe[p] != h, do: p
["./ipse/ebin/Elixir.Ipse.Extension.Host.beam"] = changed
for {tar, graph} <- [{"host-production.tar", production}, {"host-instrumented.tar", instrumented}] do
  %{ "Elixir.Ipse.Extension.Host.beam" => bytes } = untar.(root <> "/" <> tar)
  true = bytes == File.read!(Path.join(graph, "ipse/ebin/Elixir.Ipse.Extension.Host.beam"))
end
host = Map.fetch!(sources, "lib/ipse/extension/host.ex")
needle = "case execute_admitted_action(context, worker, intent, request) do"
replacement = "Ipse.Test.ShareHostProbe.pause(owner, job_ref, worker, intent)\n        " <> needle
true = File.read!(root <> "/instrumented-host.ex") == String.replace(host, needle, replacement)
true = File.read!(root <> "/helper") == File.read!(Path.join(production, "ipse/priv/ipse-runner"))
true = File.read!(root <> "/helper") == File.read!(Path.join(instrumented, "ipse/priv/ipse-runner"))
repair = untar.("docs/archive/2026-10-26-p30-p31-implementation/management-journal-owner-alias-repair/source.tar")
true = sources["lib/ipse/journal.ex"] == repair["lib/ipse/journal.ex"]
artifacts = for suffix <- ["standard", "sockets"] do
  files = untar.(root <> "/artifact-" <> suffix <> ".tar")
  {suffix, map_size(files)}
end
IO.inspect(%{manifest_entries: length(entries), source_files: map_size(sources), runtime_files: Enum.map(inventories, fn {k, rows} -> {k, map_size(rows)} end), graph_delta: changed, exact_instrumentation: true, helper_matches: true, alias_repair_preserved: true, artifact_files: artifacts}, label: "SESSION_HOST_SHARE_MANIFEST_OK")
