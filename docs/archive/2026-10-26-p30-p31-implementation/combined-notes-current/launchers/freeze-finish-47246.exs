graph = "_build/combined-notes-assets-sol-20261029"
archive = "docs/archive/2026-10-26-p30-p31-implementation/combined-notes-current"
false = File.exists?(archive <> "/manifest.sha256")
[release] = Path.wildcard("/tmp/ipse-combined-notes-full-47243/home/sessions/.release-*", match_dot: true)
File.cp!(release, archive <> "/journals/final.release.json")
File.write!(archive <> "/logs/freeze-47245-failure.log", "Initial archive copy stopped at hidden release-file glob before manifest generation. Native run/inspection were already terminal passes; no operation was rerun. Finalizer uses match_dot: true.\n")
File.cp!("/tmp/ipse-combined-notes-freeze-47245.exs", archive <> "/launchers/freeze-initial-47245.exs")
File.cp!("/tmp/ipse-combined-notes-freeze-finish-47246.exs", archive <> "/launchers/freeze-finish-47246.exs")
digest = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
inventory = fn root -> Path.wildcard(root <> "/**/*", match_dot: true) |> Enum.filter(&File.regular?/1) |> Enum.map(fn path -> digest.(path) <> "  " <> Path.relative_to(path, root) <> "\n" end) end
File.write!(archive <> "/runtime.sha256", inventory.(graph))
base = "_build/document-inline-v4-complete-sol-20261029"
File.write!(archive <> "/base-runtime.sha256", inventory.(base))
File.write!(archive <> "/manifest.sha256", inventory.(archive))
IO.puts("Combined notes native/Saved/release control frozen: " <> digest.(archive <> "/manifest.sha256"))
