archive = "docs/archive/2026-10-26-p30-p31-implementation/generation-compact-progress"
graph = "_build/generation-progress-sol-20261029"
artifact = "_build/generation-progress-corpus-sol-20261029"
File.mkdir_p!(archive)
File.cp!(__ENV__.file, archive <> "/freeze.exs")
helpers = ~w(evidence store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged adapters documents documents/zip documents/docx documents/parser_stage documents/pdf profiles corpus)
sources = Enum.map(helpers, &"extensions/knowledge/src/#{&1}.ex") ++ [
  "extensions/knowledge/build.exs", "extensions/knowledge/spec.exs", "LICENSE",
  "test/extensions/knowledge/collection_job_progress_test.exs",
  "test/extensions/knowledge/collection_adapter_session_test.exs",
  "test/support/collection_adapter_fixture.exs"]
digest = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
inventory = fn paths -> Enum.map_join(Enum.sort(paths), "", fn path -> digest.(path) <> "  " <> path <> "\n" end) end
File.write!(archive <> "/source.sha256", inventory.(sources))
{_, 0} = System.cmd("tar", ["-cf", archive <> "/source.tar", "--"] ++ sources, stderr_to_stdout: true)
for path <- Path.wildcard("/tmp/ipse-generation-progress-*.exs") ++ Path.wildcard("/tmp/ipse-generation-progress-*.log") do
  File.cp!(path, Path.join(archive, Path.basename(path)))
end
paths = fn prefix -> Path.wildcard(prefix <> "/**/*", match_dot: true) |> Enum.filter(&File.regular?/1) end
runtime = paths.(graph)
File.write!(archive <> "/runtime.sha256", inventory.(runtime))
File.write!(archive <> "/artifact.sha256", inventory.(paths.(artifact)))
fixtures = paths.("_build/generation-progress-evidence-47125") ++ paths.("_build/generation-progress-evidence-47126")
File.write!(archive <> "/session-artifacts.sha256", inventory.(fixtures))
File.write!(archive <> "/helper.sha256", inventory.([graph <> "/lib/ipse/priv/ipse-runner"]))
"7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067" = digest.(graph <> "/lib/ipse/priv/ipse-runner")
files = paths.(archive) |> Enum.reject(&String.ends_with?(&1, "/manifest.sha256"))
File.write!(archive <> "/manifest.sha256", inventory.(files))
IO.puts("source_files=#{length(sources)} runtime_files=#{length(runtime)} artifact_files=#{length(paths.(artifact))} session_artifact_files=#{length(fixtures)} manifest_entries=#{length(files)} manifest_sha256=#{digest.(archive <> "/manifest.sha256")}")
