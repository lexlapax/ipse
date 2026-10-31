target = "_build/combined-notes-assets-sol-20261029"
root = target <> "/priv/extension-bundles"
catalog = JSON.decode!(File.read!(root <> "/catalog.json"))
manifest = File.read!(root <> "/knowledge-current/extension.json")
digest = :crypto.hash(:sha256, manifest) |> Base.encode16(case: :lower)
catalog = Map.update!(catalog, "artifacts", fn entries ->
  Enum.map(entries, fn entry ->
    if entry["id"] == "knowledge",
      do: %{entry | "path" => "knowledge-current", "manifest_sha256" => digest},
      else: entry
  end)
end)
File.write!(root <> "/catalog.json", JSON.encode!(catalog))
files = ~w(extensions/knowledge/build.exs extensions/knowledge/spec.exs extensions/knowledge/src/profiles.ex extensions/knowledge/src/knowledge.ex extensions/knowledge/src/notes.ex extensions/knowledge/src/knowledge/records.ex extensions/knowledge/src/knowledge/contracts.ex extensions/knowledge/src/knowledge/decision_policy.ex LICENSE)
for file <- files do
  File.mkdir_p!(Path.dirname(target <> "/" <> file))
  File.cp!(file, target <> "/" <> file)
end
File.write!(target <> "/knowledge-build-inputs.sha256", Enum.map(files, fn file ->
  sha = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower)
  sha <> "  " <> file <> "\n"
end))
Path.wildcard(target <> "/_build/dev/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
{:ok, entries} = Ipse.Extension.Bundles.inventory(root)
entry = Enum.find(entries, &(&1.id == "knowledge"))
true = entry.digest === digest
true = entry.manifest["subscriptions"] != []
IO.puts("Explicit freshly built full knowledge artifact with recall subscriptions: " <> digest)
