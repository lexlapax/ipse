Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.OllamaModelPinTest do
  use ExUnit.Case, async: true
  alias Ipse.{Config.Profiles, InferenceDispatch, Provider}
  alias Ipse.Provider.Ollama.Models
  alias Ipse.Test.ProviderFixture

  defp pin do
    %{
      "version" => 1,
      "trust_boundary" => "cooperative_service_metadata",
      "manifest_sha256" => String.duplicate("a", 64),
      "metadata_sha256" => String.duplicate("b", 64),
      "runtime_version" => "0.40.13",
      "minimum_context_tokens" => 8192
    }
  end

  test "pins are explicit bounded operator profile data, not an inferred service attestation" do
    profile = %{
      "provider" => "ollama",
      "model" => "fixture",
      "ollama_model_pin" => pin(),
      "ollama_context_tokens" => 8192
    }

    assert :ok = Profiles.validate_profile(profile)

    for bad <- [
          nil,
          %{},
          Map.put(pin(), "version", 1.0),
          Map.put(pin(), "trust_boundary", "immutable"),
          Map.put(pin(), "metadata_sha256", "not-a-digest"),
          Map.put(pin(), "runtime_version", "untrusted-private-value"),
          Map.put(pin(), "minimum_context_tokens", 8192.0),
          Map.put(pin(), "extra", true)
        ] do
      refute Models.valid_pin?(bad)

      assert {:error, error} =
               Profiles.validate_profile(Map.put(profile, "ollama_model_pin", bad))

      refute error =~ "untrusted-private-value"
    end

    assert {:error, _} =
             Profiles.validate_profile(Map.put(profile, "ollama_context_tokens", 4096))

    for provider <- ~w(openai chatgpt demo),
        do:
          assert({:error, _} = Profiles.validate_profile(Map.put(profile, "provider", provider)))
  end

  test "embedding selection binds the full pin and requested context without changing legacy hashes" do
    profile = %{
      "operation" => "embedding",
      "provider" => "ollama",
      "model" => "fixture",
      "dimensions" => 2,
      "dimension_mode" => "native",
      "base_url" => "http://127.0.0.1:11434"
    }

    config = %{
      extensions: [%{identity: %{"capabilities" => ["host.embedding"]}}],
      embedding_profiles: %{"search" => profile}
    }

    [legacy, selected] =
      for optional <- [%{}, %{"ollama_model_pin" => pin(), "ollama_context_tokens" => 8192}] do
        config = put_in(config, [:embedding_profiles, "search"], Map.merge(profile, optional))
        assert :ok = Profiles.embedding_configuration(config)
        snapshot = Profiles.embedding_snapshot(config)["search"]
        assert Profiles.public_embedding_profile?(snapshot)

        assert {:ok, runtime, execution} =
                 Profiles.prepare_embedding(config, %{"profile" => "search", "timeout_ms" => 1000})

        assert {:ok, hash} =
                 Profiles.embedding_selection_sha256(execution, snapshot["destination"])

        {snapshot, runtime, execution, hash}
      end

    {old, old_runtime, old_execution, old_hash} = legacy
    {current, runtime, execution, hash} = selected
    refute Map.has_key?(old, "ollama_model_pin")
    refute Map.has_key?(old_runtime, :ollama_model_pin)
    assert runtime.ollama_model_pin == pin()
    assert runtime.execution.ollama_model_pin == pin()
    assert current["ollama_model_pin"] == pin()
    refute old_hash == hash

    assert old_hash ==
             Ipse.JSON.digest([
               "ipse.embedding.selection",
               1,
               "search",
               "embedding",
               "ollama",
               "fixture",
               "local",
               old["destination"]["origin"],
               old["destination"]["target_sha256"],
               2,
               "native"
             ])

    changed =
      put_in(execution, ["ollama_model_pin", "manifest_sha256"], String.duplicate("c", 64))

    assert {:ok, changed_hash} =
             Profiles.embedding_selection_sha256(changed, current["destination"])

    refute changed_hash == hash
    assert Provider.Embedding.valid_result?(%{}, execution, ["fixture"]) == false
    assert {:ok, body} = Provider.Embedding.request_body(runtime, ["fixture"])
    assert body["options"] == %{"num_ctx" => 8192}
    assert body["truncate"] == false
    assert {:ok, old_body} = Provider.Embedding.request_body(old_runtime, ["fixture"])
    refute Map.has_key?(old_body, "options")
    refute Map.has_key?(old_execution, "ollama_model_pin")
  end

  test "project trust cannot introduce a model pin" do
    root = Path.join(System.tmp_dir!(), "ipse-project-pin-" <> Ipse.Usage.id())
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "operator")
    File.mkdir_p!(Path.join(cwd, ".ipse"))
    File.mkdir!(home)
    on_exit(fn -> File.rm_rf!(root) end)

    doc = %{
      "version" => 1,
      "profiles" => %{
        "local" => %{"provider" => "ollama", "model" => "fixture", "ollama_model_pin" => pin()}
      },
      "roles" => %{"main" => "local"}
    }

    File.write!(Path.join(cwd, ".ipse/config.json"), Jason.encode!(doc))
    assert {:error, error} = Ipse.Config.resolve(cwd, home, [trust_project_config: true], %{})
    assert error =~ "model pins"
  end

  test "unregistered or direct pinned calls refuse before inference and leak no event" do
    runtime = %{
      provider: :ollama,
      model: "fixture",
      base_url: "http://127.0.0.1:1",
      ollama_model_pin: pin(),
      ollama_context_tokens: 8192
    }

    assert {:error, :pinned_model_requires_registered_service} =
             InferenceDispatch.selection(%{}, runtime, "main", nil)

    assert {:error, _} =
             Provider.complete(runtime, [], [], fn _ -> flunk("unexpected emission") end)

    embedding =
      Map.merge(runtime, %{operation: :embedding, dimensions: 2, dimension_mode: "native"})

    assert {:error, _} =
             Provider.request_embedding(embedding, ["fixture"], fn _ ->
               flunk("unexpected embedding emission")
             end)

    assert {:error, _} = Models.request_allowed?(runtime)
    assert {:ok, nil} = Models.begin_job(Map.delete(runtime, :ollama_model_pin), :text, 1000)
  end

  test "changed expected metadata refuses after exactly one bounded preflight and no inference" do
    model = "fixture"
    version = %{"version" => "0.40.13"}

    row = %{
      "name" => model,
      "model" => model,
      "digest" => String.duplicate("a", 64),
      "size" => 1024
    }

    show = %{
      "details" => %{},
      "model_info" => %{"general.architecture" => "fixture"},
      "capabilities" => ["completion"]
    }

    bodies = [
      version,
      %{"models" => [row]},
      show,
      %{"models" => []},
      %{"models" => [row]},
      version
    ]

    {base, server} = ProviderFixture.sequence(Enum.map(bodies, &Jason.encode!/1))
    runtime = %{provider: :ollama, model: model, base_url: base, ollama_model_pin: pin()}

    runtime =
      Map.put(
        runtime,
        :execution,
        Profiles.manifest("local", %{
          "provider" => "ollama",
          "model" => model,
          "base_url" => base,
          "ollama_model_pin" => pin()
        })
      )

    assert {:error, _} = Models.begin_job(runtime, :text, 5000)
    assert length(Task.await(server)) == 6
    assert {:error, _} = Models.request_allowed?(runtime)
  end
end
