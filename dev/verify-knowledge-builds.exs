Code.require_file("verification/knowledge_builds.exs", __DIR__)
alias Ipse.Development.Verification.KnowledgeBuilds

[sdk, output] = System.argv()
sdk = Path.expand(sdk)
output = Path.expand(output)
false = File.exists?(output)
File.mkdir_p!(output)
builder = Path.expand("../extensions/knowledge/build.exs", __DIR__)

presets = [
  {"corpus",
   ~w(state-lexical state-dense state-rerank state-semantic mcp-lexical mcp-dense mcp-rerank mcp-semantic)},
  {"research", ~w(offline mcp mcp-model)},
  {"graph", ~w(state-explicit state-model mcp-explicit mcp-model)}
]

records =
  for {package, selections} <- presets, preset <- selections do
    directory = Path.join(output, package <> "-" <> preset)

    {log, 0} =
      System.cmd(
        System.find_executable("elixir"),
        [builder, "--sdk", sdk, "--output", directory, "--package", package, "--preset", preset],
        stderr_to_stdout: true
      )

    false = String.contains?(log, "warning:")
    bytes = File.read!(Path.join(directory, "extension.json"))
    {:ok, manifest} = Ipse.Extension.Artifact.decode(bytes)
    true = Ipse.Extension.Artifact.compatible?(manifest)
    true = KnowledgeBuilds.exports_match?(package, manifest["exports"])
    [] = manifest["exports"]["services"]
    false = Map.has_key?(manifest, "subscriptions")
    caps = manifest["capabilities"]

    for capability <- ~w(host.embedding host.model host.mcp),
        preset in ~w(state-lexical state-explicit offline),
        do: false = capability in caps

    if preset in ~w(state-dense mcp-dense), do: false = "host.model" in caps
    if preset in ~w(state-rerank mcp-rerank), do: false = "host.embedding" in caps

    {:ok, catalog} =
      Ipse.Extension.Catalog.snapshot(%{
        extensions: [
          %{
            exports: manifest["exports"],
            identity: %{"instance" => package}
          }
        ]
      })

    true = KnowledgeBuilds.catalog_match?(package, catalog)

    for item <- manifest["files"] do
      file = Path.join(directory, item["path"])
      true = File.stat!(file).size == item["bytes"]
      true = Ipse.JSON.sha256(File.read!(file)) == item["sha256"]
    end

    %{
      "package" => package,
      "preset" => preset,
      "artifact_sha256" => Ipse.JSON.sha256(bytes),
      "catalog_entries" => length(catalog["entries"])
    }
  end

for module <- [
      IpseKnowledge.Corpus,
      IpseKnowledge.Graph,
      IpseKnowledge.Research,
      IpseKnowledge.Profiles,
      IpseKnowledge.Evidence,
      IpseKnowledge.Adapters,
      IpseKnowledge.Store
    ],
    do: false = :code.is_loaded(module)

IO.puts(
  JSON.encode!(%{
    "builds" => records,
    "count" => length(records),
    "host_loaded_domain_modules" => false
  })
)
