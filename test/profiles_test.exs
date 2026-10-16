defmodule Ipse.ProfilesTest do
  use ExUnit.Case, async: true
  alias Ipse.{Profiles, Config, Delegation}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-profiles-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, ".git"))
    home = Path.join(root, "home")
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: home}
  end

  defp profiles do
    %{
      "strong" => %{
        "provider" => "chatgpt",
        "model" => "gpt-6.1-sol",
        "reasoning_effort" => "high"
      },
      "local" => %{"provider" => "ollama", "model" => "fixture-local", "max_steps" => 4},
      "reviewer" => %{"provider" => "anthropic", "model" => "fixture-review"}
    }
  end

  test "named main selection, explicit overrides and role validation", c do
    File.write!(
      Path.join(c.home, "config.json"),
      Jason.encode!(%{
        version: 1,
        profiles: profiles(),
        roles: %{main: "strong", routine: "local", review: "reviewer"}
      })
    )

    assert {:ok, cfg} = Config.resolve(c.root, c.home, [max_steps: 20], %{})
    assert cfg.settings["provider"] == "chatgpt"
    assert cfg.settings["max_steps"] == 20
    assert cfg.execution.id == "strong"
    assert Profiles.runtime(cfg).reasoning_effort == "high"
    assert {:ok, other} = Config.resolve(c.root, c.home, [profile: "local"], %{})
    assert other.settings["provider"] == "ollama"
    refute other.fingerprint == cfg.fingerprint
    assert {:error, _} = Config.resolve(c.root, c.home, [profile: "invented"], %{})
    assert {:error, _} = Config.resolve(c.root, c.home, [model: "unconfigured"], %{})
    assert {:error, _} = Config.resolve(c.root, c.home, [base_url: "http://127.0.0.1"], %{})
    assert {:ok, env_selected} = Config.resolve(c.root, c.home, [], %{"IPSE_PROFILE" => "local"})
    assert env_selected.execution.id == "local"
    assert {:error, _} = Profiles.validate(profiles(), %{"routine" => "missing"})
    assert {:error, _} = Profiles.validate(profiles(), %{"invented-role" => "local"})
  end

  test "reasoning and credential references reject unsupported combinations and unsafe endpoints" do
    for provider <- ~w(chatgpt openai), effort <- ~w(low medium high xhigh max) do
      assert :ok =
               Profiles.validate_profile(%{
                 "provider" => provider,
                 "model" => "gpt-6.1-sol",
                 "reasoning_effort" => effort
               })
    end

    for profile <- [
          %{"provider" => "openai", "model" => "gpt-4.1-mini", "reasoning_effort" => "high"},
          %{"provider" => "chatgpt", "model" => "gpt-6.1-sol", "reasoning_effort" => "none"},
          %{"provider" => "ollama", "model" => "fixture", "reasoning_effort" => "high"},
          %{"provider" => "anthropic", "model" => "fixture", "reasoning_effort" => "high"},
          %{"provider" => "ollama", "model" => "fixture", "credential" => "OPENAI_API_KEY"},
          %{
            "provider" => "chatgpt",
            "model" => "fixture",
            "base_url" => "https://attacker.invalid"
          },
          %{
            "provider" => "openai",
            "model" => "fixture",
            "base_url" => "https://secret@example.com"
          },
          %{"provider" => "ollama", "model" => "fixture", "base_url" => "http://remote.invalid"},
          %{"provider" => "openai", "model" => "fixture", "api_key" => "must-not-be-accepted"}
        ] do
      assert {:error, _} = Profiles.validate_profile(profile)
    end

    assert {:error, _} =
             Ipse.Provider.complete(
               %{provider: :ollama, model: "fixture", reasoning_effort: "high"},
               [],
               [],
               fn _ -> flunk("no request") end
             )
  end

  test "child profile isolates credentials and parent payloads while preserving host policy" do
    config = %{
      provider: :chatgpt,
      model: "parent",
      api_key: "parent-secret",
      auth_dir: "/private-auth",
      provider_module: :parent_module,
      messages: [%{"provider_data" => %{"opaque" => "parent-native"}}],
      base_url: "https://parent-endpoint.invalid",
      profiles: profiles(),
      roles: %{"routine" => "local"},
      subagents: true,
      mcp_servers: [:server],
      sandbox: :native,
      context_bytes: 20_000,
      max_steps: 30
    }

    assert {:ok, child} =
             Profiles.child_config(config, %{"parent_session_id" => "p", "call_id" => "c"}, %{})

    assert child.provider == :ollama
    assert child.model == "fixture-local"
    assert child.max_steps == 4
    assert child.context_bytes == 20_000
    assert child.sandbox == :native
    assert child.approval == :ask
    assert child.mcp_servers == []
    assert child.subagents == false
    assert child.operator_questions == false

    for key <- [
          :api_key,
          :auth_dir,
          :base_url,
          :provider_module,
          :messages,
          :profiles,
          :configuration
        ],
        do: refute(Map.has_key?(child, key))

    assert child.execution.role == "routine"

    assert {:ok, reviewer} =
             Profiles.child_config(%{config | roles: %{"review" => "reviewer"}}, %{}, %{
               "role" => "review"
             })

    assert reviewer.provider == :anthropic
    assert reviewer.execution.role == "review"
    assert {:error, _} = Profiles.validate_route(config, %{"role" => "review"})
    assert {:error, _} = Profiles.child_config(config, %{}, %{"profile" => "invented"})
    [tool] = Delegation.definitions(config)

    assert tool["function"]["parameters"]["properties"]["profile"]["enum"] == [
             "local",
             "reviewer",
             "strong",
             nil
           ]

    assert :ok =
             Delegation.validate(%{
               "task" => "task",
               "context" => "selected",
               "profile" => "local"
             })
  end

  test "Responses maps configured effort separately from model identity and preserves native data" do
    for provider <- [:chatgpt, :openai] do
      body =
        Ipse.Provider.OpenAI.request_body(
          %{provider: provider, model: "gpt-6.1-sol", reasoning_effort: "high"},
          [],
          []
        )

      assert body["model"] == "gpt-6.1-sol"
      assert body["reasoning"] == %{"effort" => "high"}
      assert body["store"] == false
    end

    assert :ok = Profiles.validate_profile(%{"provider" => "anthropic", "model" => "fixture"})
    assert :ok = Profiles.validate_profile(%{"provider" => "ollama", "model" => "fixture"})
  end
end
