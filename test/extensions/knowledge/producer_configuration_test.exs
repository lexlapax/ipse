if System.get_env("IPSE_PRODUCER_CONFIG_CHILD") == "1" do
  Code.require_file("extensions/knowledge/src/profiles.ex")
  Code.require_file("extensions/knowledge/spec.exs")
end

defmodule Ipse.ProducerConfigurationTest do
  use ExUnit.Case, async: false
  @compile {:no_warn_undefined, IpseKnowledge.BuildSpec}
  alias IpseKnowledge.BuildSpec

  setup do
    if System.get_env("IPSE_PRODUCER_CONFIG_CHILD") == "1", do: setup_artifact(), else: %{}
  end

  defp setup_artifact do
    artifact =
      case System.get_env("IPSE_PRODUCER_CANONICAL_ARTIFACT") do
        nil ->
          output = Path.join(System.tmp_dir!(), "ipse-producer-configuration-" <> Ipse.Usage.id())
          on_exit(fn -> File.rm_rf!(output) end)
          sdk = Path.dirname(List.to_string(:code.which(Ipse.Extension)))

          {log, status} =
            System.cmd(
              System.find_executable("elixir"),
              [
                "--erl",
                "+S 2:2",
                "extensions/knowledge/build.exs",
                "--sdk",
                sdk,
                "--output",
                output,
                "--package",
                "corpus",
                "--preset",
                "collection-dense"
              ],
              stderr_to_stdout: true
            )

          assert status == 0, log
          output

        path ->
          Path.expand(path)
      end

    %{manifest: File.read!(Path.join(artifact, "extension.json"))}
  end

  @tag :producer_config_child
  test "source-bound producer binding and service registry are explicit and old configuration is exact",
       c do
    if System.get_env("IPSE_PRODUCER_CONFIG_CHILD") == "1" do
      check_configuration(c)
    else
      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          ["--erl", "+S 2:2"] ++ paths ++ ["test/support/producer_configuration_entry.exs"],
          env: [{"IPSE_PRODUCER_CONFIG_CHILD", "1"}],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "1 passed"
    end
  end

  defp check_configuration(c) do
    manifest = c.manifest

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

    validator = %{
      "command_id" => "source",
      "action" => "restore_validate_page",
      "export_action" => "backup_page",
      "plan_action" => "backup_plan"
    }

    configure_validation = fn source_use, validation ->
      BuildSpec.operator(
        manifest,
        "corpus",
        "collection-dense",
        "producer",
        options,
        nil,
        %{},
        Map.put(inference, "inference_services", services),
        source_use,
        validation
      )
    end

    [validated_trust] = configure_validation.(nil, "document_completed_v1")["extension_trust"]

    assert validated_trust["collection_bindings"] === [
             old_binding
             |> Map.put("version", 3)
             |> Map.put("source_use", nil)
             |> Map.put("input_validation", validator)
           ]

    [validated_guarded] =
      configure_validation.("shared_producer_v1", "document_completed_v1")["extension_trust"]

    assert validated_guarded["collection_bindings"] === [
             old_binding
             |> Map.put("version", 3)
             |> Map.put("source_use", "shared_producer_v1")
             |> Map.put("input_validation", validator)
           ]

    assert configure_validation.("shared_producer_v1", nil) === guarded

    for validation <- ["automatic", "", true] do
      assert_raise ArgumentError, fn -> configure_validation.(nil, validation) end
    end

    assert_raise ArgumentError, fn ->
      BuildSpec.operator(
        manifest,
        "corpus",
        "state-dense",
        "producer",
        options,
        nil,
        %{},
        inference,
        nil,
        "document_completed_v1"
      )
    end

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
