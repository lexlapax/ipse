defmodule Ipse.EmbeddingConfigTest do
  use ExUnit.Case, async: true
  alias Ipse.Extensions.{EmbeddingCall, Operation, Catalog}

  setup do
    root =
      Path.join(System.tmp_dir!(), "ipse-embedding-config-#{System.unique_integer([:positive])}")

    project = Path.join(root, "workspace")
    home = Path.join(root, "operator")
    File.mkdir_p!(Path.join(project, ".git"))
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(root) end)
    %{project: project, home: home}
  end

  test "operator registry participates in fingerprint but cannot be replaced by project data",
       c do
    assert {:ok, empty} = Ipse.Config.resolve(c.project, c.home, [], %{})
    refute Map.has_key?(Ipse.Config.manifest(empty), :embedding_profiles)
    path = Path.join(c.home, "config.json")

    File.write!(
      path,
      Jason.encode!(%{"version" => 1, "embedding_profiles" => %{"corpus" => profile()}})
    )

    assert {:ok, config} = Ipse.Config.resolve(c.project, c.home, [], %{})
    assert config.embedding_profiles == %{"corpus" => profile()}
    assert config.fingerprint != empty.fingerprint
    assert Ipse.Config.manifest(config).embedding_profiles == config.embedding_profiles
    project_path = Path.join(c.project, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(project_path))
    File.write!(project_path, Jason.encode!(%{"version" => 1, "embedding_profiles" => %{}}))

    assert {:error, error} =
             Ipse.Config.resolve(c.project, c.home, [trust_project_config: true], %{})

    assert error =~ "operator-only"
  end

  test "embedding authority is separate and every selected request has exact safe egress" do
    assert Operation.validate(request()) == :ok
    assert Operation.mutating?(request())
    assert Operation.capability(request()) == "host.embedding"
    assert {:error, _} = Catalog.validate(Catalog.empty(), ["host.embedding"])
    assert Catalog.validate(Catalog.empty(), ~w(host.actions host.embedding)) == :ok
    assert {:ok, binding} = EmbeddingCall.binding(config(), request())
    scope = %{"embedding_profiles" => Ipse.EmbeddingProfiles.snapshot(config())}
    assert EmbeddingCall.valid_binding?(binding, request(), scope)

    assert binding["destination"]["target_sha256"] ==
             Ipse.JSON.sha256("http://127.0.0.1:11434/api/embed")

    assert binding["execution"]["timeout_ms"] == 3000

    refute EmbeddingCall.valid_binding?(
             put_in(binding, ["destination", "target_sha256"], String.duplicate("a", 64)),
             request(),
             scope
           )

    refute EmbeddingCall.valid_binding?(
             put_in(binding, ["execution", "dimensions"], 5),
             request(),
             scope
           )

    proposed = %{
      "extension" => "fixture",
      "artifact_sha256" => String.duplicate("b", 64),
      "namespace" => Ipse.Usage.id(),
      "request" => request(),
      "effect_binding" => binding,
      "execution" => binding["execution"],
      "destination" => binding["destination"]
    }

    assert EmbeddingCall.delegated_approval?("extension:embedding.create", proposed)
    refute EmbeddingCall.delegated_approval?("extension:model.complete", proposed)

    refute EmbeddingCall.delegated_approval?(
             "extension:embedding.create",
             Map.delete(proposed, "effect_binding")
           )
  end

  test "request byte, cardinality, routing and timeout boundaries stay closed" do
    for invalid <- [
          Map.put(request(), "inputs", []),
          Map.put(request(), "inputs", [""]),
          Map.put(request(), "inputs", List.duplicate("a", 9)),
          Map.put(request(), "version", 1.0),
          Map.put(request(), "inputs", [String.duplicate("é", 2049)]),
          Map.put(request(), "inputs", List.duplicate(String.duplicate("a", 4096), 4)),
          Map.put(request(), "timeout_ms", 999),
          Map.put(request(), "dimensions", 3),
          Map.put(request(), "api_key", "fixture"),
          Map.put(request(), "provider", "ollama")
        ] do
      assert {:error, _} = EmbeddingCall.validate(invalid)
    end

    assert EmbeddingCall.validate(
             Map.put(request(), "inputs", List.duplicate(String.duplicate("a", 4096), 3))
           ) == :ok
  end

  defp profile,
    do: %{
      "operation" => "embedding",
      "provider" => "ollama",
      "model" => "fixture",
      "dimensions" => 768,
      "dimension_mode" => "native"
    }

  defp config,
    do: %{
      embedding_profiles: %{"corpus" => profile()},
      timeout_ms: 5000,
      extensions: [%{identity: %{"capabilities" => ~w(host.actions host.embedding)}}]
    }

  defp request,
    do: %{
      "op" => "embedding.create",
      "version" => 1,
      "profile" => "corpus",
      "inputs" => ["fixture input"],
      "timeout_ms" => 3000
    }
end
