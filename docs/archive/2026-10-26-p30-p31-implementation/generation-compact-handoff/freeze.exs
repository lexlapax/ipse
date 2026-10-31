archive = "docs/archive/2026-10-26-p30-p31-implementation/generation-compact-handoff"
graph = "_build/generation-progress-sol-20261029"
File.mkdir_p!(archive)
File.cp!(__ENV__.file, archive <> "/freeze.exs")
sources = ["test/extensions/knowledge/collection_adapter_session_test.exs"]
digest = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
inventory = fn paths -> Enum.map_join(Enum.sort(paths), "", fn path -> digest.(path) <> "  " <> path <> "\n" end) end
paths = fn prefix -> Path.wildcard(prefix <> "/**/*", match_dot: true) |> Enum.filter(&File.regular?/1) end
File.write!(archive <> "/source.sha256", inventory.(sources))
{_, 0} = System.cmd("tar", ["-cf", archive <> "/source.tar", "--"] ++ sources, stderr_to_stdout: true)
for path <- ["/tmp/ipse-generation-progress-handoff-47128.exs", "/tmp/ipse-generation-progress-handoff-47128.log"] do
  File.cp!(path, Path.join(archive, Path.basename(path)))
end
File.write!(archive <> "/runtime.sha256", inventory.(paths.(graph)))
File.write!(archive <> "/artifacts.sha256", inventory.(paths.("_build/generation-progress-evidence-47128")))
files = paths.(archive) |> Enum.reject(&String.ends_with?(&1, "/manifest.sha256"))
File.write!(archive <> "/manifest.sha256", inventory.(files))
IO.puts("entries=#{length(files)} runtime_files=#{length(paths.(graph))} artifact_files=#{length(paths.("_build/generation-progress-evidence-47128"))} manifest_sha256=#{digest.(archive <> "/manifest.sha256")}")
