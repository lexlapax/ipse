archive = "docs/archive/2026-10-26-p30-p31-implementation/collection-held-read-v2"
graph = "_build/collection-held-read-v2-sol-20261029"
File.mkdir_p!(archive)
File.cp!(__ENV__.file, archive <> "/freeze.exs")
sources = ["lib/ipse/extension/collection.ex", "test/ipse/extension/collection_held_read_test.exs"]
digest = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
inventory = fn paths -> Enum.map_join(Enum.sort(paths), "", fn path -> digest.(path) <> "  " <> path <> "\n" end) end
File.write!(archive <> "/source.sha256", inventory.(sources))
{_, 0} = System.cmd("tar", ["-cf", archive <> "/source.tar", "--"] ++ sources, stderr_to_stdout: true)
for path <- Path.wildcard("/tmp/ipse-collection-held-read-v2-*.exs") ++ Path.wildcard("/tmp/ipse-collection-held-read-v2-*.log") do
  File.cp!(path, Path.join(archive, Path.basename(path)))
end
runtime = Path.wildcard(graph <> "/**/*", match_dot: true) |> Enum.filter(&File.regular?/1)
File.write!(archive <> "/runtime.sha256", inventory.(runtime))
File.write!(archive <> "/helper.sha256", inventory.([graph <> "/lib/ipse/priv/ipse-runner"]))
files = Path.wildcard(archive <> "/**/*", match_dot: true) |> Enum.filter(&File.regular?/1) |> Enum.reject(&String.ends_with?(&1, "/manifest.sha256"))
File.write!(archive <> "/manifest.sha256", inventory.(files))
IO.puts("runtime_files=#{length(runtime)} manifest_entries=#{length(files)} manifest_sha256=#{digest.(archive <> "/manifest.sha256")}")
