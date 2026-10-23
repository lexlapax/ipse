defmodule Ipse.Config.ProfilesTest do
  use ExUnit.Case, async: false
  alias Ipse.Config.Profiles
  alias Ipse.Config
  alias Ipse.Tools.Delegation
  alias Ipse.Provider.Embedding

  describe "profiles" do
    setup do
      root = Path.join(System.tmp_dir!(), "ipse-profiles-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, ".git"))
      home = Path.join(root, "home")
      File.mkdir_p!(home)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root, home: home}
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
             %{
               "provider" => "ollama",
               "model" => "fixture",
               "base_url" => "http://127.0.0.1:12345"
             }},
            {"project",
             %{"provider" => "ollama", "model" => "fixture", "model_call_timeout_ms" => 600_000}},
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

      assert {:ok, env_selected} =
               Config.resolve(c.root, c.home, [], %{"IPSE_PROFILE" => "local"})

      assert env_selected.execution.id == "local"
      assert {:error, _} = Profiles.validate(profiles(), %{"routine" => "missing"})
      assert {:error, _} = Profiles.validate(profiles(), %{"invented-role" => "local"})
    end

    test "operator model-call deadlines do not become ordinary profile settings", c do
      File.write!(
        Path.join(c.home, "config.json"),
        Jason.encode!(%{
          version: 1,
          profiles: %{
            answer: %{provider: "ollama", model: "fixture", model_call_timeout_ms: 480_000}
          },
          roles: %{main: "answer"}
        })
      )

      assert {:ok, cfg} = Config.resolve(c.root, c.home, [], %{})
      assert cfg.profiles["answer"]["model_call_timeout_ms"] == 480_000
      refute Map.has_key?(cfg.settings, "model_call_timeout_ms")
      refute Map.has_key?(Profiles.runtime(cfg), :model_call_timeout_ms)
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
            %{
              "provider" => "ollama",
              "model" => "fixture",
              "base_url" => "http://remote.invalid"
            },
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

  describe "embedding profiles" do
    test "embedding profiles are closed operator-selected operations without text settings" do
      assert Profiles.validate_embeddings(%{"corpus" => profile()}) == :ok
      assert Profiles.validate_embeddings(%{}) == :ok

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
          do: assert({:error, _} = Profiles.validate_embedding_profile(changed))

      assert {:error, _} = Profiles.validate_embeddings(%{"bad id" => profile()})

      assert {:error, _} =
               Profiles.validate_embeddings(Map.new(1..9, &{"profile#{&1}", profile()}))

      assert {:error, _} =
               Profiles.validate_embedding_profile(Map.put(profile(), "model", "unsafe\nmodel"))

      for url <- [
            "http://remote.example.invalid",
            "https://name:key@example.invalid",
            "https://example.invalid?key=value",
            "https://example.invalid#fragment",
            "https://example.invalid/ bad"
          ] do
        assert {:error, _} =
                 Profiles.validate_embedding_profile(Map.put(profile(), "base_url", url))
      end
    end

    test "only operator sources can introduce or replace embedding profiles" do
      original = source("operator", %{"corpus" => profile()})
      replacement = source("operator", %{"corpus" => Map.put(profile(), "dimensions", 4096)})

      assert {:ok, %{"corpus" => %{"dimensions" => 4096}}} =
               Profiles.resolve_embeddings([original, replacement])

      assert {:error, _} = Profiles.resolve_embeddings([original, source("project", %{})])

      assert {:error, _} =
               Profiles.resolve_embeddings([source("project", %{"other" => profile()})])

      assert {:error, _} = Profiles.resolve_embeddings([source("operator", nil)])

      first = source("operator", Map.new(1..8, &{"profile#{&1}", profile()}))

      assert {:error, _} =
               Profiles.resolve_embeddings([first, source("operator", %{"ninth" => profile()})])
    end

    test "profile availability alone does not enable embedding authority" do
      disabled = %{embedding_profiles: %{"corpus" => profile()}, extensions: []}
      refute Profiles.embeddings_enabled?(disabled)
      assert Profiles.embedding_snapshot(disabled) == nil
      assert Profiles.embedding_configuration(%{embedding_profiles: :invalid}) == :ok
      assert {:error, _} = Profiles.prepare_embedding(disabled, request())
      assert Profiles.embeddings_enabled?(config())

      assert {:error, _} =
               Profiles.embedding_configuration(%{config() | embedding_profiles: :invalid})
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

      snapshot = Profiles.embedding_snapshot(config)
      selected = snapshot["corpus"]
      assert Profiles.public_embedding_profile?(selected)
      assert selected["timeout_ms"] == 10_000
      assert selected["billing_mode"] == "api"
      assert selected["endpoint_sha256"] == Ipse.JSON.sha256(profile["base_url"])
      assert selected["destination"]["origin"] == "https://proxy.example.invalid"

      assert selected["destination"]["target_sha256"] ==
               Ipse.JSON.sha256("https://proxy.example.invalid/private-tenant/v1/embeddings")

      encoded = Jason.encode!(snapshot)
      refute encoded =~ "private-tenant"
      refute encoded =~ "OPENAI_API_KEY"
      refute encoded =~ "base_url"

      assert {:ok, execution} =
               Profiles.embedding_execution(%{"embedding_profiles" => snapshot}, %{
                 request()
                 | "timeout_ms" => 3000
               })

      assert execution["timeout_ms"] == 3000
      assert execution == Map.delete(%{selected | "timeout_ms" => 3000}, "destination")

      assert {:error, _} =
               Profiles.embedding_execution(%{"embedding_profiles" => snapshot}, %{
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
               Profiles.prepare_embedding(parent, %{request() | "timeout_ms" => 3000})

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
      assert destination == Profiles.embedding_snapshot(parent)["corpus"]["destination"]
      assert execution["timeout_ms"] == 3000
    end

    test "public snapshot shape is closed and default targets cannot drift" do
      selected = Profiles.embedding_snapshot(config())["corpus"]
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
          do: refute(Profiles.public_embedding_profile?(changed))

      for value <- [nil, [], %{}, 1, %{atom: :private}] do
        assert {:error, _} = Profiles.validate_embedding_profile(value)
        refute Profiles.public_embedding_profile?(value)
        assert {:error, _} = Profiles.embedding_execution(value, request())
      end
    end

    test "selection identity binds configuration while excluding operational timeouts" do
      fingerprint = fn selected_config, selected_request ->
        {:ok, runtime, execution} = Profiles.prepare_embedding(selected_config, selected_request)
        {:ok, destination} = Embedding.destination(runtime)
        {:ok, hash} = Profiles.embedding_selection_sha256(execution, destination)
        hash
      end

      original = fingerprint.(config(), request())
      assert byte_size(original) == 64
      assert original == fingerprint.(Map.put(config(), :timeout_ms, 2000), request())

      assert original ==
               fingerprint.(config(), %{request() | "timeout_ms" => 1000, "inputs" => ["other"]})

      explicit_default =
        put_in(config(), [:embedding_profiles, "corpus", "base_url"], "http://127.0.0.1:11434")

      assert original == fingerprint.(explicit_default, request())

      for {field, value} <- [
            {"model", "different-model"},
            {"dimensions", 4096},
            {"dimension_mode", "request"},
            {"base_url", "http://localhost:11435"},
            {"base_url", "http://localhost:11434/other"},
            {"provider", "openai"}
          ] do
        changed = put_in(config(), [:embedding_profiles, "corpus", field], value)
        refute original == fingerprint.(changed, request())
      end

      renamed = put_in(config(), [:embedding_profiles], %{"other" => profile()})
      refute original == fingerprint.(renamed, %{request() | "profile" => "other"})
      selected = Profiles.embedding_snapshot(config())["corpus"]
      execution = Map.delete(selected, "destination")

      assert {:error, _} =
               Profiles.embedding_selection_sha256(
                 Map.put(execution, "dimensions", 0),
                 selected["destination"]
               )

      assert {:error, _} = Profiles.embedding_selection_sha256(selected, selected["destination"])
      assert {:error, _} = Profiles.embedding_selection_sha256(execution, %{})
    end
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
