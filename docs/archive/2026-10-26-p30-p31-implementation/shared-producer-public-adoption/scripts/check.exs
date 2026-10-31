root = Path.expand("_build/shared-producer-public-adoption-20261029")
artifact = root <> "/artifact-current"
private = "_build/shared-producer-guard-session-20261029/package/extensions/knowledge"
canonical_ast = fn source ->
  source |> Code.string_to_quoted!() |> Macro.prewalk(fn
    {name, metadata, args} when is_list(metadata) -> {name, [], args}
    node -> node
  end)
end
true = canonical_ast.(File.read!(private <> "/src/corpus.ex")) === canonical_ast.(File.read!("extensions/knowledge/src/corpus.ex"))
true = File.read!("extensions/knowledge/src/adapters.ex") === File.read!(private <> "/src/adapters.ex")
expected_producer = private |> Kernel.<>("/src/store/collection/producer.ex") |> File.read!() |> String.replace("          \"source_dispatch_available\" => false,\n", "", global: false)
true = expected_producer === File.read!("extensions/knowledge/src/store/collection/producer.ex")
options = %{"version" => 1, "stores" => %{"notes" => %{"kind" => "collection", "scope" => "project", "partition" => "notes"}}, "search" => %{}, "fetch" => %{}, "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}}, "embedding" => %{"vectors" => %{"kind" => "embedding", "profile" => "encoder"}}, "rerank" => %{}, "extraction" => %{}}
inference = %{"embedding_profiles" => %{"encoder" => %{"operation" => "embedding", "provider" => "ollama", "model" => "operator-selected", "credential" => "none", "base_url" => "http://127.0.0.1:11434", "dimensions" => 1024, "dimension_mode" => "native", "timeout_ms" => 5000}}, "inference_services" => %{"local" => %{"version" => 1, "origins" => ["http://127.0.0.1:11434"]}}}
File.write!(root <> "/options.json", Jason.encode!(options))
File.write!(root <> "/inference.json", Jason.encode!(inference))
{output, 0} = System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2", "extensions/knowledge/config.exs", "--artifact", artifact, "--package", "corpus", "--preset", "collection-dense", "--instance", "producer", "--options", root <> "/options.json", "--inference-config", root <> "/inference.json", "--collection-source-use", "shared_producer_v1", "--output", root <> "/operator.json"], stderr_to_stdout: true)
config = Jason.decode!(File.read!(root <> "/operator.json"))
:ok = Ipse.Config.Semantics.validate_services(config["inference_services"])
true = config["inference_services"] === inference["inference_services"]
true = get_in(config, ["embedding_profiles", "encoder", "model"]) === "operator-selected"
[trust] = config["extension_trust"]
[binding] = trust["collection_bindings"]
true = binding["version"] === 2 and binding["source_use"] == "shared_producer_v1"
{:ok, _} = Ipse.Extension.Config.resolve([%{scope: "operator", path: root <> "/operator.json", data: config}], [])
canonical = Jason.decode!(File.read!(artifact <> "/extension.json"))
prior = Jason.decode!(File.read!("_build/shared-producer-guard-session-20261029/artifact/extension.json"))
true = Map.take(canonical, ~w(sdk id entrypoint capabilities exports options_schema)) === Map.take(prior, ~w(sdk id entrypoint capabilities exports options_schema))
IO.write(output)
IO.puts(Jason.encode!(%{corpus_ast_exact_private_delegation: true, adapters_bytes_exact: true, producer_only_delta: "remove obsolete source_dispatch_available selection coverage field", catalog_shapes_exact: true, actual_generator_v2: true, host_closed_services_valid: true, extension_config_valid: true, inference_or_storage_effects: 0, canonical_manifest_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(artifact <> "/extension.json")), case: :lower)}, pretty: true))
