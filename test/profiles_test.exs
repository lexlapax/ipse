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

  test "project profiles cannot choose endpoints or replace operator profile identities", c do
    File.write!(
      Path.join(c.home, "config.json"),
      Jason.encode!(%{version: 1, profiles: %{main: %{provider: "openai", model: "operator"}}})
    )

    project = Path.join(c.root, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(project))

    for {id, profile} <- [
          {"project",
           %{
             "provider" => "openai",
             "model" => "fixture",
             "base_url" => "https://example.invalid/v1"
           }},
          {"project",
           %{
             "provider" => "anthropic",
             "model" => "fixture",
             "base_url" => "https://example.invalid"
           }},
          {"project",
           %{"provider" => "ollama", "model" => "fixture", "base_url" => "http://127.0.0.1:12345"}},
          {"main", %{"provider" => "openai", "model" => "project-replacement"}}
        ] do
      File.write!(project, Jason.encode!(%{version: 1, profiles: %{id => profile}}))
      assert {:error, _} = Config.resolve(c.root, c.home, [trust_project_config: true], %{})
    end

    File.write!(
      project,
      Jason.encode!(%{
        version: 1,
        profiles: %{project: %{provider: "ollama", model: "project-local"}},
        roles: %{routine: "project"}
      })
    )

    assert {:ok, config} = Config.resolve(c.root, c.home, [trust_project_config: true], %{})
    assert config.profiles["main"] == %{"provider" => "openai", "model" => "operator"}
    assert config.profiles["project"] == %{"provider" => "ollama", "model" => "project-local"}
    assert config.roles["routine"] == "project"

    File.write!(
      Path.join(c.home, "config.json"),
      Jason.encode!(%{
        version: 1,
        profiles: %{
          main: %{
            provider: "openai",
            model: "operator",
            base_url: "https://proxy.example.invalid/operator"
          }
        }
      })
    )

    assert {:ok, selected} =
             Config.resolve(c.root, c.home, [trust_project_config: true, profile: "main"], %{})

    assert selected.execution.base_url == "https://proxy.example.invalid/operator"
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

  test "Ollama thinking suppression is an explicit profile selection" do
    assert :ok =
             Profiles.validate_profile(%{
               "provider" => "ollama",
               "model" => "fixture",
               "reasoning_effort" => "none"
             })

    assert {:error, _} =
             Profiles.validate_profile(%{
               "provider" => "ollama",
               "model" => "fixture",
               "reasoning_effort" => false
             })
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

  test "selected children cannot widen or drop an inherited output cap or route it to unsupported providers",
       c do
    config = %{
      provider: :openai,
      model: "parent",
      max_output_tokens: 128,
      profiles: %{
        "local" => %{"provider" => "ollama", "model" => "fixture", "max_output_tokens" => 256},
        "subscription" => %{"provider" => "chatgpt", "model" => "fixture"}
      }
    }

    assert {:ok, local} = Profiles.child_config(config, %{}, %{"profile" => "local"})
    assert local.max_output_tokens == 128
    narrow = put_in(config, [:profiles, "local", "max_output_tokens"], 64)
    assert {:ok, local} = Profiles.child_config(narrow, %{}, %{"profile" => "local"})
    assert local.max_output_tokens == 64
    assert {:ok, inherited} = Profiles.child_config(config, %{}, %{})
    assert inherited.max_output_tokens == 128
    assert {:error, _} = Profiles.validate_route(config, %{"profile" => "subscription"})
    assert {:error, _} = Profiles.child_config(config, %{}, %{"profile" => "subscription"})

    assert {:error, _} =
             Profiles.validate_profile(%{
               "provider" => "chatgpt",
               "model" => "fixture",
               "max_output_tokens" => 128
             })

    assert :ok =
             Profiles.validate_profile(%{
               "provider" => "openai",
               "model" => "fixture",
               "max_output_tokens" => 128
             })

    assert {:ok, cfg} =
             Config.resolve(
               c.root,
               c.home,
               [project_config: false, provider: "ollama", max_output_tokens: 32],
               %{}
             )

    assert cfg.settings["max_output_tokens"] == 32
  end

  test "switching a parallel child profile preserves hardlink mutation denial", c do
    target = Path.join(c.root, "original.txt")
    alias_path = Path.join(c.root, "alias.txt")
    File.write!(target, "original evidence")
    File.ln!(target, alias_path)

    parent = %{
      provider: :chatgpt,
      model: "parent",
      sandbox: :off,
      parallel_child: true,
      profiles: profiles(),
      roles: %{"routine" => "local"}
    }

    assert {:ok, child} = Profiles.child_config(parent, %{}, %{})

    context = %{
      cwd: c.root,
      sandbox: child.sandbox,
      parallel_child: Map.get(child, :parallel_child, false)
    }

    assert {:error, message} =
             Ipse.Tools.execute(
               "write",
               %{"path" => "alias.txt", "content" => "must not change"},
               context
             )

    assert message =~ "hardlinked"
    assert File.read!(target) == "original evidence"
    assert File.read!(alias_path) == "original evidence"
  end
end
