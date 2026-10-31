graph = "_build/document-inline-v4-complete-sol-20261029"
archive = "docs/archive/2026-10-26-p30-p31-implementation/document-inline-v4"
false = File.exists?(archive)
File.mkdir_p!(archive <> "/sources")
File.mkdir_p!(archive <> "/logs")
File.mkdir_p!(archive <> "/launchers")
host = File.read!(graph <> "/host-inputs.sha256")
files = host |> String.split("\n", trim: true) |> Enum.map(fn line ->
  [sha, file] = String.split(line, "  ", parts: 2)
  true = sha === (:crypto.hash(:sha256, File.read!(graph <> "/" <> file)) |> Base.encode16(case: :lower))
  {String.to_charlist(file), File.read!(graph <> "/" <> file)}
end)
:ok = :erl_tar.create(String.to_charlist(archive <> "/host-sources.tar"), files, [])
File.write!(archive <> "/host-inputs.sha256", host)
for file <- ~w(lib/ipse/session/document_embedding.ex lib/ipse/extension/collection_store.ex lib/ipse/session.ex test/ipse/session/document_embedding_test.exs) do
  File.cp!(file, archive <> "/sources/" <> Path.basename(file))
end
File.cp!("/tmp/ipse-document-inline-v4-tests-initial-47234.exs", archive <> "/sources/test-initial-47234.exs")
for file <- Path.wildcard("/tmp/ipse-document-inline-v4-*.log") do
  File.cp!(file, archive <> "/logs/" <> Path.basename(file))
end
for file <- Path.wildcard("/tmp/ipse-document-inline-v4-*.exs"), not String.contains?(file, "tests-initial") do
  File.cp!(file, archive <> "/launchers/" <> Path.basename(file))
end
digest = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
inventory = fn root ->
  Path.wildcard(root <> "/**/*", match_dot: true)
  |> Enum.filter(&File.regular?/1)
  |> Enum.map(fn file -> digest.(file) <> "  " <> Path.relative_to(file, root) <> "\n" end)
end
File.write!(archive <> "/runtime.sha256", inventory.(graph))
File.write!(archive <> "/manifest.sha256", inventory.(archive))
IO.puts("Frozen inline-v4 implementation, initial launcher/test compile failures and focused passes; manifest " <> digest.(archive <> "/manifest.sha256"))
