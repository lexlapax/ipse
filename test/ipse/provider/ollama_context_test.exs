Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.OllamaContextTest do
  use ExUnit.Case, async: true
  alias Ipse.{Config, Provider}
  alias Ipse.Config.Profiles
  alias Ipse.Extension.ModelCall
  alias Ipse.Test.ProviderFixture

  defp profile,
    do: %{"provider" => "ollama", "model" => "fixture", "ollama_context_tokens" => 8192}

  test "operator profile preserves the exact request through selection, draft and child routing" do
    root = Path.join(System.tmp_dir!(), "ipse-context-profile-" <> Ipse.Usage.id())
    home = Path.join(root, "operator")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    on_exit(fn -> File.rm_rf!(root) end)

    doc = %{
      "version" => 1,
      "profiles" => %{"local" => profile()},
      "roles" => %{"main" => "local"}
    }

    File.write!(Path.join(home, "config.json"), Jason.encode!(doc))
    assert {:ok, resolved} = Config.resolve(cwd, home, [], %{})
    assert resolved.execution.ollama_context_tokens == 8192
    runtime = Profiles.runtime(resolved)
    assert runtime.ollama_context_tokens == 8192
    assert Config.manifest(resolved).execution.ollama_context_tokens == 8192
    assert Ipse.Session.Draft.draft_config(runtime).ollama_context_tokens == 8192
    assert {:ok, child} = Profiles.child_config(runtime, %{}, %{"profile" => "local"})
    assert child.ollama_context_tokens == 8192
    assert child.execution.ollama_context_tokens == 8192

    other =
      update_in(
        runtime,
        [:profiles],
        &Map.put(&1, "plain", Map.delete(profile(), "ollama_context_tokens"))
      )

    assert {:ok, other_child} = Profiles.child_config(other, %{}, %{"profile" => "plain"})
    refute Map.has_key?(other_child, :ollama_context_tokens)

    changed = put_in(doc, ["profiles", "local", "ollama_context_tokens"], 16384)
    File.write!(Path.join(home, "config.json"), Jason.encode!(changed))
    assert {:ok, later} = Config.resolve(cwd, home, [], %{})
    refute later.fingerprint == resolved.fingerprint

    File.rm!(Path.join(home, "config.json"))
    File.mkdir!(Path.join(cwd, ".ipse"))
    File.write!(Path.join(cwd, ".ipse/config.json"), Jason.encode!(doc))
    assert {:error, error} = Config.resolve(cwd, home, [trust_project_config: true], %{})
    assert error =~ "Project configuration cannot"
    assert error =~ "Ollama context requests"
  end

  test "extension execution binds optional context while legacy snapshots remain unchanged" do
    config = %{
      profiles: %{"local" => profile()},
      extensions: [%{identity: %{"capabilities" => ["host.model"]}}]
    }

    request = %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => "local",
      "instruction" => "Summarize",
      "input" => "fixture",
      "max_output_bytes" => 100,
      "timeout_ms" => 1000
    }

    snapshot = ModelCall.snapshot(config)["local"]
    assert snapshot["ollama_context_tokens"] == 8192
    assert ModelCall.valid_profile?(snapshot)
    assert {:ok, runtime, execution} = ModelCall.prepare(config, request)
    assert runtime.ollama_context_tokens == 8192
    assert execution["ollama_context_tokens"] == 8192

    legacy_config =
      update_in(config, [:profiles, "local"], &Map.delete(&1, "ollama_context_tokens"))

    legacy = ModelCall.snapshot(legacy_config)["local"]
    refute Map.has_key?(legacy, "ollama_context_tokens")
    assert ModelCall.valid_profile?(legacy)
    assert {:ok, old_runtime, old_execution} = ModelCall.prepare(legacy_config, request)
    assert old_execution == Map.put(legacy, "timeout_ms", 1000)
    refute Map.has_key?(old_runtime, :ollama_context_tokens)

    assert Provider.Registry.profile_values(%{
             "provider" => "openrouter",
             "upstream" => "fixture"
           }) ==
             %{"upstream" => "fixture", "data_collection" => "deny"}
  end

  test "actual native wire carries context alongside output caps in normal, draft and summary requests" do
    response =
      ProviderFixture.ndjson([
        %{
          "model" => "fixture",
          "message" => %{"role" => "assistant", "content" => "ok"},
          "done" => true
        }
      ])

    {base, server} = ProviderFixture.sequence([response, response, response])

    config = %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 5000,
      ollama_context_tokens: 8192,
      max_output_tokens: 50
    }

    configs = [
      config,
      Ipse.Session.Draft.draft_config(config),
      Map.put(config, :summary_schema, %{"type" => "object"})
    ]

    for selected <- configs do
      assert {:ok, %{"content" => "ok"}, _} =
               Provider.complete(
                 selected,
                 [%{"role" => "user", "content" => "fixture"}],
                 [],
                 fn _ -> :ok end
               )
    end

    [normal, draft, summary] =
      for {headers, request} <- Task.await(server), do: {headers, request}

    for {headers, request} <- [normal, draft, summary] do
      assert headers =~ "POST /api/chat HTTP/1.1"
      assert request["options"]["num_ctx"] == 8192
      assert request["options"]["num_predict"] == 50
    end

    assert elem(summary, 1)["options"]["temperature"] == 0
    assert elem(summary, 1)["think"] == false
    assert elem(summary, 1)["format"] == %{"type" => "object"}

    assert Provider.Ollama.request_body(Map.delete(config, :ollama_context_tokens), [], [])[
             "options"
           ] == %{"num_predict" => 50}
  end

  test "invalid requests and use by another provider refuse without a provider dispatch" do
    for value <- [nil, 511, 262_145, 8192.0, "8192", false] do
      assert {:error, _} =
               Profiles.validate_profile(Map.put(profile(), "ollama_context_tokens", value))

      if value != nil do
        assert {:error, error} =
                 Provider.complete(
                   %{
                     provider: :ollama,
                     model: "fixture",
                     base_url: "http://127.0.0.1:1",
                     ollama_context_tokens: value
                   },
                   [],
                   [],
                   fn _ -> flunk("unexpected provider event") end
                 )

        assert error =~ "Ollama context request"
      end
    end

    for provider <- ~w(openai chatgpt anthropic openrouter demo) do
      assert {:error, _} = Profiles.validate_profile(Map.put(profile(), "provider", provider))
    end

    for limit <- [512, 262_144],
        do:
          assert(
            :ok = Profiles.validate_profile(Map.put(profile(), "ollama_context_tokens", limit))
          )
  end
end
