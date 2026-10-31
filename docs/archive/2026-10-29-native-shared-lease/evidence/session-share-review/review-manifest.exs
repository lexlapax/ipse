root = "docs/archive/2026-10-29-native-shared-lease/evidence/session-share-candidate"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
manifest = root <> "/manifest.sha256"
true = sha.(File.read!(manifest)) == "77f7914becb6cd544634adbfee2571d7615a7db8006bff87a2f1e3659611166e"
parse = fn p ->
  p |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
entries = parse.(manifest)
Enum.each(entries, fn {p, hash} -> true = sha.(File.read!(Path.join(root, p))) == hash end)
counts = for {inventory, graph} <- [
  {"runtime.sha256", "_build/session-share-candidate-v4-sol-20261029"},
  {"runtime-old.sha256", "_build/session-share-old-sol-20261029"},
  {"runtime-diagnostic.sha256", "_build/session-share-diagnostic-sol-20261029"}
] do
  rows = parse.(Path.join(root, inventory))
  Enum.each(rows, fn {p, hash} -> true = sha.(File.read!(Path.join(graph, p))) == hash end)
  {inventory, length(rows)}
end
true = sha.(File.read!(root <> "/helper")) == sha.(File.read!("_build/session-share-candidate-v4-sol-20261029/lib/ipse/priv/ipse-runner"))
true = sha.(File.read!(root <> "/old-helper")) == sha.(File.read!("_build/session-share-old-sol-20261029/lib/ipse/priv/ipse-runner"))
{:ok, sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
IO.inspect(%{manifest_entries: length(entries), source_files: length(sources), runtime_inventory_counts: counts, matching_standard_helper: true, matching_old_helper: true}, label: "SESSION_SHARE_MANIFEST_OK")
