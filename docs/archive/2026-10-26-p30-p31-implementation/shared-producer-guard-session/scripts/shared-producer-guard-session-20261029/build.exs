root = Path.expand("_build/shared-producer-guard-session-20261029")
package = Path.join(root, "package/extensions/knowledge")
File.mkdir_p!(Path.dirname(package))
{:ok, _} = File.cp_r("extensions/knowledge", package)
File.cp!("LICENSE", Path.join(root, "package/LICENSE"))
corpus = Path.join(package, "src/corpus.ex")
source = File.read!(corpus)
gate = "finish(state, refused(:shared_producer_source_dispatch_unavailable))"
true = length(String.split(source, gate)) === 2

private = """
advance(
  IpseKnowledge.Store.Collection.Producer.start(state.resolved, profile, Map.delete(args, "store")),
  %{state | phase: :collection_producer, ctx: %{args: args}}
)
"""

File.write!(corpus, String.replace(source, gate, private, global: false))
sdk = Path.expand("_build/document-embedding-admission-sol-20261029/_build/dev/lib/ipse/ebin")
output = Path.join(root, "artifact")

{text, status} =
  System.cmd(
    System.find_executable("elixir"),
    [
      "--erl",
      "+S 2:2",
      Path.join(package, "build.exs"),
      "--sdk",
      sdk,
      "--output",
      output,
      "--package",
      "corpus",
      "--preset",
      "collection-dense"
    ], stderr_to_stdout: true)

IO.write(text)
0 = status
IO.puts("PRIVATE_FIXTURE_ARTIFACT #{output}; production Corpus page gate unchanged")
