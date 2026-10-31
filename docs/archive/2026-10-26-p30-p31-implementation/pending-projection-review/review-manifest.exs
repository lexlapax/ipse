root = "docs/archive/2026-10-26-p30-p31-implementation/pending-projection"
sha = fn bytes -> :crypto.hash(:sha256,bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  File.read!(path) |> String.split("\n",trim: true) |> Map.new(fn row ->
    [h,p] = String.split(row,"  ",parts: 2)
    {p,h}
  end)
end
entries = parse.(root <> "/manifest.sha256")
true = sha.(File.read!(root <> "/manifest.sha256")) == "5a8fb333b709ab3e88bc455ab86497cbe7ddb5b352f736eec84a8bf1d7fd5bdd"
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(p)) == h end)
ancestor = "docs/archive/2026-10-26-p30-p31-implementation/document-descriptor-inventory/manifest.json"
true = sha.(File.read!(ancestor)) == "afa3cb876e4ee6ccf9af21f8fd17331af1900272f79b0e92841327c3f586f7e0"
m = Jason.decode!(File.read!(ancestor))
Enum.each(m["runtime"],fn {p,e} ->
  bytes = File.read!(p)
  true = sha.(bytes) == e["sha256"] and byte_size(bytes) == e["byte_count"]
end)
IO.inspect(%{manifest_sha256: sha.(File.read!(root <> "/manifest.sha256")), manifest_entries: map_size(entries), source_snapshots: 4, runtime_files: map_size(m["runtime"]), inherited_manifest: "afa3cb876e4ee6ccf9af21f8fd17331af1900272f79b0e92841327c3f586f7e0"},label: "PENDING_PROJECTION_MANIFEST_OK")
