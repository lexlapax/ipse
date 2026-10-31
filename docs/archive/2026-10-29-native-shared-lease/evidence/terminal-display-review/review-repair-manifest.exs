root = "docs/archive/2026-10-29-native-shared-lease/evidence/terminal-display-repair"
previous = "docs/archive/2026-10-29-native-shared-lease/evidence/terminal-display-synthetic"
sha = fn bytes -> :crypto.hash(:sha256,bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  File.read!(path) |> String.split("\n",trim: true) |> Map.new(fn row ->
    [h,p] = String.split(row,"  ",parts: 2)
    {p,h}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "731aa89426fa645c9a68d8869e67a27edef3171da69e1e91a2db05a57a9188b6"
true = sha.(File.read!(previous <> "/manifest.sha256")) == "ba2dc99c6151256e22ab94bbea7a06f553b01d40c75c406ed28c0be9b48f0ab7"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
untar = fn path ->
  {:ok,entries} = :erl_tar.extract(String.to_charlist(path),[:memory])
  Map.new(entries,fn {p,b} -> {List.to_string(p),b} end)
end
sources = untar.(root <> "/source.tar")
old = untar.(previous <> "/source.tar")
true = Enum.sort(Map.keys(sources)) == Enum.sort(Map.keys(old))
changed = for {p,b} <- sources,old[p] != b,do: p
true = Enum.sort(changed) == ["dev/fixtures/terminal_lease_probe.rs","native/ipse-terminal-lease.rs"]
negative = untar.(root <> "/negative-source.tar")
true = Map.keys(sources)--Map.keys(negative) == ["dev/fixtures/terminal_lease_probe.rs"]
negative_delta = for {p,b} <- negative,sources[p] != b,do: p
["native/ipse-terminal-lease.rs"] = negative_delta
needle = "if !wall_current(expiry) || Instant::now() >= deadline {\n            return false;\n        }\n        #[cfg(ipse_terminal_display_test_hook)]\n        if prewrite_stop"
replacement = "if !wall_current(expiry) {\n            return false;\n        }\n        #[cfg(ipse_terminal_display_test_hook)]\n        if prewrite_stop"
true = length(String.split(sources["native/ipse-terminal-lease.rs"],needle)) == 2
true = String.replace(sources["native/ipse-terminal-lease.rs"],needle,replacement) == negative["native/ipse-terminal-lease.rs"]
production = File.read!(root <> "/ipse-terminal-display-v7-helper")
hook = File.read!(root <> "/ipse-terminal-display-v7-hook-helper")
for marker <- ["IPSE_TEST_TTY_PREWRITE_STOP","IPSE_TEST_TTY_PARTIAL_STOP","IPSE_TEST_TTY_READY_STOP"] do
  false = String.contains?(production,marker)
  true = String.contains?(hook,marker)
end
IO.inspect(%{manifest_entries: map_size(entries),source_files: map_size(sources),changed_sources: Enum.sort(changed),negative_source_files: map_size(negative),negative_delta: negative_delta,production_helper: sha.(production),hook_helper: sha.(hook),production_has_no_test_markers: true},label: "TERMINAL_DISPLAY_REPAIR_MANIFEST_OK")
