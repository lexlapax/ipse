defmodule Ipse.EmbeddingProfilesTest do
  use ExUnit.Case, async: true
  alias Ipse.EmbeddingProfiles
  alias Ipse.Provider.Embedding

  test "embedding profiles are closed operator-selected operations without text settings" do
    assert EmbeddingProfiles.validate(%{"corpus" => profile()}) == :ok
    assert EmbeddingProfiles.validate(%{}) == :ok

    for changed <- [
          Map.put(profile(), "provider", "chatgpt"),
          Map.put(profile(), "provider", "anthropic"),
          Map.put(profile(), "provider", "demo"),
          Map.put(profile(), "operation", "text"),
          Map.put(profile(), "dimensions", 4097),
          Map.put(profile(), "dimensions", 768.0),
          Map.put(profile(), "dimension_mode", "automatic"),
          Map.put(profile(), "max_output_tokens", 128),
          Map.put(profile(), "credential", "SOME_OTHER_SECRET"),
          Map.put(profile(), "base_url", nil),
          Map.put(profile(), "timeout_ms", 999),
          Map.delete(profile(), "dimensions")
        ],
        do: assert({:error, _} = EmbeddingProfiles.validate_profile(changed))

    assert {:error, _} = EmbeddingProfiles.validate(%{"bad id" => profile()})
    assert {:error, _} = EmbeddingProfiles.validate(Map.new(1..9, &{"profile#{&1}", profile()}))

    assert {:error, _} =
             EmbeddingProfiles.validate_profile(Map.put(profile(), "model", "unsafe\nmodel"))

    for url <- [
          "http://remote.example.invalid",
          "https://name:key@example.invalid",
          "https://example.invalid?key=value",
          "https://example.invalid#fragment",
          "https://example.invalid/ bad"
        ] do
      assert {:error, _} = EmbeddingProfiles.validate_profile(Map.put(profile(), "base_url", url))
    end
  end

  test "only operator sources can introduce or replace embedding profiles" do
    original = source("operator", %{"corpus" => profile()})
    replacement = source("operator", %{"corpus" => Map.put(profile(), "dimensions", 4096)})

    assert {:ok, %{"corpus" => %{"dimensions" => 4096}}} =
             EmbeddingProfiles.resolve([original, replacement])

    assert {:error, _} = EmbeddingProfiles.resolve([original, source("project", %{})])
    assert {:error, _} = EmbeddingProfiles.resolve([source("project", %{"other" => profile()})])
    assert {:error, _} = EmbeddingProfiles.resolve([source("operator", nil)])

    first = source("operator", Map.new(1..8, &{"profile#{&1}", profile()}))

    assert {:error, _} =
             EmbeddingProfiles.resolve([first, source("operator", %{"ninth" => profile()})])
  end

  test "profile availability alone does not enable embedding authority" do
    disabled = %{embedding_profiles: %{"corpus" => profile()}, extensions: []}
    refute EmbeddingProfiles.enabled?(disabled)
    assert EmbeddingProfiles.snapshot(disabled) == nil
    assert EmbeddingProfiles.configuration(%{embedding_profiles: :invalid}) == :ok
    assert {:error, _} = EmbeddingProfiles.prepare(disabled, request())
    assert EmbeddingProfiles.enabled?(config())

    assert {:error, _} =
             EmbeddingProfiles.configuration(%{config() | embedding_profiles: :invalid})
  end

  test "safe immutable snapshots bind the actual hidden route and parent timeout" do
    profile =
      profile()
      |> Map.put("base_url", "https://proxy.example.invalid/private-tenant/v1/")
      |> Map.put("provider", "openai")
      |> Map.put("credential", "OPENAI_API_KEY")
      |> Map.put("timeout_ms", 20_000)

    config =
      %{config() | embedding_profiles: %{"corpus" => profile}} |> Map.put(:timeout_ms, 10_000)

    snapshot = EmbeddingProfiles.snapshot(config)
    selected = snapshot["corpus"]
    assert EmbeddingProfiles.public_profile?(selected)
    assert selected["timeout_ms"] == 10_000
    assert selected["billing_mode"] == "api"
    assert selected["endpoint_sha256"] == Ipse.Extensions.Manifest.sha256(profile["base_url"])
    assert selected["destination"]["origin"] == "https://proxy.example.invalid"

    assert selected["destination"]["target_sha256"] ==
             Ipse.Extensions.Manifest.sha256(
               "https://proxy.example.invalid/private-tenant/v1/embeddings"
             )

    encoded = Jason.encode!(snapshot)
    refute encoded =~ "private-tenant"
    refute encoded =~ "OPENAI_API_KEY"
    refute encoded =~ "base_url"

    assert {:ok, execution} =
             EmbeddingProfiles.execution(%{"embedding_profiles" => snapshot}, %{
               request()
               | "timeout_ms" => 3000
             })

    assert execution["timeout_ms"] == 3000
    assert execution == Map.delete(%{selected | "timeout_ms" => 3000}, "destination")

    assert {:error, _} =
             EmbeddingProfiles.execution(%{"embedding_profiles" => snapshot}, %{
               request()
               | "profile" => "absent"
             })
  end

  test "fresh private preparation carries policy references but prunes parent execution content and credentials" do
    checkpoint = make_ref()

    parent =
      config()
      |> Map.merge(%{
        api_key: "parent-private-key",
        messages: ["private conversation"],
        provider_module: __MODULE__,
        tools: [:private],
        continuation: "native continuation",
        max_output_tokens: 16,
        reasoning_effort: "high",
        summary_schema: %{},
        budget: %{"version" => 1, "max_requests" => 2},
        budget_root: %{"session_id" => "parent"},
        budget_checkpoint: checkpoint,
        delegation_origin: %{"parent_session_id" => "parent"},
        timeout_ms: 5000
      })

    assert {:ok, runtime, execution} =
             EmbeddingProfiles.prepare(parent, %{request() | "timeout_ms" => 3000})

    assert runtime.operation == :embedding
    assert runtime.provider == :ollama
    assert runtime.dimension_mode == "native"
    assert runtime.timeout_ms == 3000
    assert runtime.execution.role == "extension"
    assert runtime.budget_checkpoint == checkpoint
    assert runtime.budget_root == parent.budget_root
    assert runtime.delegation_origin == parent.delegation_origin

    for key <- [
          :api_key,
          :messages,
          :provider_module,
          :tools,
          :continuation,
          :max_output_tokens,
          :reasoning_effort,
          :summary_schema
        ],
        do: refute(Map.has_key?(runtime, key))

    assert {:ok, destination} = Embedding.destination(runtime)
    assert destination == EmbeddingProfiles.snapshot(parent)["corpus"]["destination"]
    assert execution["timeout_ms"] == 3000
  end

  test "public snapshot shape is closed and default targets cannot drift" do
    selected = EmbeddingProfiles.snapshot(config())["corpus"]
    assert selected["endpoint_sha256"] == nil

    for changed <- [
          Map.put(selected, "credential", "none"),
          Map.put(selected, "provider", "chatgpt"),
          Map.put(selected, "billing_mode", "api"),
          Map.put(selected, "timeout_ms", 0),
          Map.put(selected, "dimensions", 0),
          Map.put(selected, "endpoint_sha256", "raw endpoint"),
          put_in(selected, ["destination", "target_sha256"], String.duplicate("a", 64))
        ],
        do: refute(EmbeddingProfiles.public_profile?(changed))

    for value <- [nil, [], %{}, 1, %{atom: :private}] do
      assert {:error, _} = EmbeddingProfiles.validate_profile(value)
      refute EmbeddingProfiles.public_profile?(value)
      assert {:error, _} = EmbeddingProfiles.execution(value, request())
    end
  end

  defp profile,
    do: %{
      "operation" => "embedding",
      "provider" => "ollama",
      "model" => "fixture-embedding",
      "dimensions" => 768,
      "dimension_mode" => "native"
    }

  defp config,
    do: %{
      embedding_profiles: %{"corpus" => profile()},
      extensions: [%{identity: %{"capabilities" => ["host.actions", "host.embedding"]}}]
    }

  defp request,
    do: %{
      "op" => "embedding.create",
      "version" => 1,
      "profile" => "corpus",
      "inputs" => ["chunk"],
      "timeout_ms" => 30_000
    }

  defp source(scope, registry), do: %{scope: scope, data: %{"embedding_profiles" => registry}}
end
