root = "docs/archive/2026-10-29-native-shared-lease/evidence/terminal-display-synthetic"
sha = fn bytes -> :crypto.hash(:sha256,bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  File.read!(path) |> String.split("\n",trim: true) |> Map.new(fn row ->
    [h,p] = String.split(row,"  ",parts: 2)
    {p,h}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "ba2dc99c6151256e22ab94bbea7a06f553b01d40c75c406ed28c0be9b48f0ab7"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries,fn {p,h} -> true = sha.(File.read!(Path.join(root,p))) == h end)
{:ok,sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"),[:memory])
source_map = Map.new(sources,fn {p,b} -> {List.to_string(p),b} end)
fixture = source_map["dev/fixtures/terminal_lease_probe.rs"]
expected_probe = fixture |> String.replace("for i in 0..4","for i in 0..1") |> String.replace("body.push(4);","body.push(1);") |> String.replace("summary.push(4);","summary.push(1);") |> String.replace("TTY_FOUR_LEASES_TWO_OWNER_CONTROLS_REAPED_AND_SETTLED","TTY_ONE_LEASE_ACTIVE_DISPLAY_AND_CLOSE_ACCEPTED")
true = expected_probe == File.read!("docs/archive/2026-10-29-native-shared-lease/evidence/terminal-display-review/one-lease-probe.rs")
production = File.read!(root <> "/ipse-terminal-display-v6-helper")
hook = File.read!(root <> "/ipse-terminal-display-v6-hook-helper")
for marker <- ["IPSE_TEST_TTY_PREWRITE_STOP","IPSE_TEST_TTY_PARTIAL_STOP"] do
  false = String.contains?(production,marker)
  true = String.contains?(hook,marker)
end
IO.inspect(%{manifest_entries: map_size(entries), source_files: map_size(source_map), production_helper: sha.(production), hook_helper: sha.(hook), exact_one_lease_fixture_delta: true, no_beam_runtime_graph_claimed: true},label: "TERMINAL_DISPLAY_MANIFEST_OK")
