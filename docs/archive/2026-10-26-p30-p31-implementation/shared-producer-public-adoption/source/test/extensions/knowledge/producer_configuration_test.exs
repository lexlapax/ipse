Code.require_file("extensions/knowledge/spec.exs")

defmodule Ipse.ProducerConfigurationTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.BuildSpec

  test "source-bound producer binding and service registry are explicit and old configuration is exact" do
    manifest =
      File.read!(
        Path.join(System.fetch_env!("IPSE_PRODUCER_CANONICAL_ARTIFACT"), "extension.json")
      )

    options = %{
      "version" => 1,
      "stores" => %{
        "notes" => %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
      },
      "search" => %{},
      "fetch" => %{},
      "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
      "embedding" => %{"vectors" => %{"kind" => "embedding", "profile" => "encoder"}},
      "rerank" => %{},
      "extraction" => %{}
    }

    inference = %{
      "embedding_profiles" => %{
        "encoder" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "operator-selected",
          "credential" => "none",
          "base_url" => "http://127.0.0.1:11434",
          "dimensions" => 1024,
          "dimension_mode" => "native",
          "timeout_ms" => 5000
        }
      }
    }

    configure = fn selected, source_use ->
      BuildSpec.operator(
        manifest,
        "corpus",
        "collection-dense",
        "producer",
        options,
        nil,
        %{},
        selected,
        source_use
      )
    end

    old = configure.(inference, nil)
    [old_trust] = old["extension_trust"]
    [old_binding] = old_trust["collection_bindings"]

    assert old_binding === %{
             "version" => 1,
             "instance" => "producer",
             "id" => "documents",
             "scope" => "project",
             "profile" => "document_graph_v1"
           }

    assert old ===
             BuildSpec.operator(
               manifest,
               "corpus",
               "collection-dense",
               "producer",
               options,
               nil,
               %{},
               inference
             )

    services = %{"local" => %{"version" => 1, "origins" => ["http://127.0.0.1:11434"]}}
    guarded = configure.(Map.put(inference, "inference_services", services), "shared_producer_v1")
    [trust] = guarded["extension_trust"]

    assert trust["collection_bindings"] === [
             old_binding |> Map.put("version", 2) |> Map.put("source_use", "shared_producer_v1")
           ]

    assert guarded["inference_services"] === services
    assert guarded["embedding_profiles"] === inference["embedding_profiles"]
    assert hd(guarded["extensions"])["enabled"] === false
    assert Ipse.Config.Semantics.validate_services(guarded["inference_services"]) == :ok

    for source_use <- ["automatic", "", true] do
      assert_raise ArgumentError, fn -> configure.(inference, source_use) end
    end

    assert_raise ArgumentError, fn ->
      configure.(Map.put(inference, "inference_services", []), "shared_producer_v1")
    end

    assert_raise ArgumentError, fn ->
      BuildSpec.operator(
        manifest,
        "corpus",
        "collection-documents",
        "producer",
        options,
        nil,
        %{},
        inference,
        "shared_producer_v1"
      )
    end

    assert_raise ArgumentError, fn ->
      BuildSpec.operator(
        manifest,
        "research",
        "offline",
        "producer",
        options,
        nil,
        %{},
        inference,
        "shared_producer_v1"
      )
    end

    invalid_services = %{
      "local" => %{"version" => 1, "origins" => ["http://127.0.0.1:11434"], "fallback" => true}
    }

    generated =
      configure.(Map.put(inference, "inference_services", invalid_services), "shared_producer_v1")

    assert Ipse.Config.Semantics.validate_services(generated["inference_services"]) ==
             {:error, :invalid_inference_services}
  end
end
