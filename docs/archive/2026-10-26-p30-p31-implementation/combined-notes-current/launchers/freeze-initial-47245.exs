graph = "_build/combined-notes-assets-sol-20261029"
archive = "docs/archive/2026-10-26-p30-p31-implementation/combined-notes-current"
false = File.exists?(archive)
for dir <- ~w(logs launchers sources journals), do: File.mkdir_p!(archive <> "/" <> dir)
for file <- Path.wildcard("/tmp/ipse-combined-notes-*.log"),
  do: File.cp!(file, archive <> "/logs/" <> Path.basename(file))
for file <- Path.wildcard("/tmp/ipse-combined-notes-*.exs"),
    not String.contains?(file, "freeze"),
    do: File.cp!(file, archive <> "/launchers/" <> Path.basename(file))
for file <- ~w(test/support/headless_typed_root_transition.exs test/support/provider_fixture.ex test/support/operator_pty.rs),
  do: File.cp!(file, archive <> "/sources/" <> Path.basename(file))
File.cp_r!(graph <> "/priv/extension-bundles/knowledge-current", archive <> "/knowledge-current")
File.cp!(graph <> "/priv/extension-bundles/catalog.json", archive <> "/catalog.json")
File.cp!(graph <> "/host-inputs.sha256", archive <> "/host-inputs.sha256")
File.cp!(graph <> "/knowledge-build-inputs.sha256", archive <> "/knowledge-build-inputs.sha256")
inputs = File.read!(graph <> "/knowledge-build-inputs.sha256") |> String.split("\n", trim: true)
  |> Enum.map(fn line -> [_, file] = String.split(line, "  ", parts: 2); {String.to_charlist(file), File.read!(graph <> "/" <> file)} end)
:ok = :erl_tar.create(String.to_charlist(archive <> "/knowledge-build-sources.tar"), inputs, [])
[journal] = Path.wildcard("/tmp/ipse-combined-notes-full-47243/home/sessions/*.jsonl")
File.cp!(journal, archive <> "/journals/final.jsonl")
[release] = Path.wildcard("/tmp/ipse-combined-notes-full-47243/home/sessions/.release-*")
File.cp!(release, archive <> "/journals/final.release.json")
digest = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
inventory = fn root -> Path.wildcard(root <> "/**/*", match_dot: true) |> Enum.filter(&File.regular?/1) |> Enum.map(fn path -> digest.(path) <> "  " <> Path.relative_to(path, root) <> "\n" end) end
File.write!(archive <> "/runtime.sha256", inventory.(graph))
base = "_build/document-inline-v4-complete-sol-20261029"
base_inventory = inventory.(base)
File.write!(archive <> "/base-runtime.sha256", base_inventory)
File.write!(archive <> "/manifest.sha256", inventory.(archive))
IO.puts("Combined notes final native/Saved/release control frozen: " <> digest.(archive <> "/manifest.sha256"))
