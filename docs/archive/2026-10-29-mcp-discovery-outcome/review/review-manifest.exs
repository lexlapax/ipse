root = "docs/archive/2026-10-29-mcp-discovery-outcome"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
manifest = root <> "/manifest.sha256"
true = sha.(File.read!(manifest)) == "d4f6d20d94f460f4eb2334b8ef144a9e39f14ef16f4c00bfa5479c28c8d43af5"
parse = fn file ->
  file |> File.read!() |> String.split("\n", trim: true) |> Map.new(fn row ->
    [hash, p] = String.split(row, "  ", parts: 2)
    {p, hash}
  end)
end
entries = parse.(manifest)
Enum.each(entries, fn {p, hash} -> true = sha.(File.read!(Path.join(root, p))) == hash end)
sources = Jason.decode!(File.read!(root <> "/sources.json"))
{:ok, archive} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
true = Enum.sort(Map.keys(sources)) == Enum.sort(Enum.map(archive, fn {p, _} -> List.to_string(p) end))
Enum.each(archive, fn {p, bytes} -> true = sha.(bytes) == sources[List.to_string(p)] end)
runtime = parse.(root <> "/runtime.sha256")
Enum.each(runtime, fn {p, hash} -> true = sha.(File.read!(p)) == hash end)
cohort = Jason.decode!(File.read!(root <> "/cohort.json"))
base_path = cohort["base_runtime_inventory"]["path"]
true = sha.(File.read!(base_path)) == cohort["base_runtime_inventory"]["sha256"]
base = parse.(base_path) |> Map.new(fn {p, hash} -> {String.replace_prefix(p, "_build/document-decision-sol-20261029/", "_build/mcp-discovery-unknown-sol-20261029/"), hash} end)
true = Enum.sort(Map.keys(base)) == Enum.sort(Map.keys(runtime))
changed = Enum.filter(base, fn {p, hash} -> runtime[p] != hash end) |> Enum.map(fn {p, _} -> Path.basename(p) end) |> Enum.sort()
true = changed == ~w(Elixir.Ipse.MCP.beam Elixir.Ipse.Session.beam)
true = sha.(File.read!("_build/mcp-discovery-unknown-sol-20261029/lib/ipse/priv/ipse-runner")) == cohort["helper_sha256"]
IO.inspect(%{manifest_entries: map_size(entries), frozen_sources: map_size(sources), runtime_files: map_size(runtime), changed_runtime_files: changed, helper: cohort["helper_sha256"]}, label: "MCP_DISCOVERY_REVIEW_MANIFEST_OK")
