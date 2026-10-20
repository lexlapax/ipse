defmodule Ipse.ConfigTest do
  use ExUnit.Case, async: true
  alias Ipse.Config

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-config-#{System.unique_integer([:positive])}")
    project = Path.join(root, "project")
    cwd = Path.join(project, "nested/deep")
    home = Path.join(root, "operator")
    File.mkdir_p!(Path.join(project, ".git"))
    File.mkdir_p!(cwd)
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, project: project, cwd: cwd, home: home}
  end

  defp put(path, settings) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"version" => 1, "settings" => settings}))
  end

  test "defaults are credential-free and configuration reads never load private state", c do
    File.mkdir_p!(Path.join(c.home, "auth"))
    File.write!(Path.join(c.home, "auth/private.json"), "must not be read")
    assert {:ok, config} = Config.resolve(c.cwd, c.home, [], %{})
    assert config.settings["provider"] == "chatgpt"
    assert config.settings["model"] == "gpt-6.1-sol"
    assert config.sources == []
    assert Config.legacy_compatible?(config)

    assert config.fingerprint ==
             Ipse.JSON.digest([
               %{
                 "settings" => config.settings,
                 "sources" => config.sources,
                 "profiles" => config.profiles,
                 "roles" => config.roles,
                 "execution" => config.execution
               }
             ])

    refute Jason.encode!(Config.manifest(config)) =~ "must not be read"
  end

  test "journal bounds are operator-only, finite and inherited by routed children", c do
    policy = %{"max_bytes" => 32_768, "max_events" => 64, "max_record_bytes" => 8_192}

    File.write!(
      Path.join(c.home, "config.json"),
      Jason.encode!(%{"version" => 1, "journal" => policy})
    )

    assert {:ok, config} = Config.resolve(c.cwd, c.home, [], %{})
    assert config.journal == policy
    assert Config.manifest(config)[:journal] == policy

    runtime = %{
      journal: policy,
      profiles: %{"routine" => %{"provider" => "demo", "model" => "fixture"}},
      roles: %{"routine" => "routine"},
      subagents: true,
      provider: :demo,
      model: "fixture"
    }

    assert {:ok, routed} =
             Ipse.Profiles.child_config(runtime, %{}, %{
               "task" => "fixture",
               "context" => "fixture"
             })

    assert routed.journal == policy
    assert Ipse.Delegation.child_config(runtime, %{}).journal == policy

    for invalid <- [
          %{"max_bytes" => 0},
          %{"max_bytes" => 134_217_729},
          %{"max_events" => 2.0},
          %{"max_record_bytes" => 511},
          %{"unknown" => 1},
          false
        ] do
      assert {:error, _} = Ipse.Journal.Limits.normalize(invalid)
    end

    project = Path.join(c.project, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(project))
    File.write!(project, Jason.encode!(%{"version" => 1, "journal" => policy}))
    assert {:error, error} = Config.resolve(c.cwd, c.home, [trust_project_config: true], %{})
    assert error =~ "Journal policy is operator-only"
  end

  test "extension data is scoped, inspected without options and cannot self-authorize", c do
    artifact = String.duplicate("a", 64)

    instance = %{
      "instance" => "test",
      "artifact" => artifact,
      "enabled" => true,
      "options" => %{"text" => "synthetic-private-option"},
      "order" => 1,
      "lifetime" => "persistent"
    }

    trust = %{
      "artifact" => artifact,
      "capabilities" => ["transform.prompt"],
      "allow_project" => true,
      "allow_children" => false
    }

    operator_path = Path.join(c.home, "config.json")
    File.write!(operator_path, Jason.encode!(%{"version" => 1, "extension_trust" => [trust]}))
    project_path = Path.join(c.project, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(project_path))
    File.write!(project_path, Jason.encode!(%{"version" => 1, "extensions" => [instance]}))
    assert {:error, _} = Config.resolve(c.cwd, c.home, [], %{})
    assert {:ok, config} = Config.resolve(c.cwd, c.home, [trust_project_config: true], %{})
    assert [%{"enabled" => true, "scope" => "project"}] = config.extensions["instances"]
    refute Jason.encode!(Config.manifest(config)) =~ "synthetic-private-option"

    assert {:ok, disabled} =
             Config.resolve(c.cwd, c.home, [trust_project_config: true, extensions: false], %{})

    assert [%{"enabled" => false}] = disabled.extensions["instances"]
    refute disabled.fingerprint == config.fingerprint

    File.write!(
      project_path,
      Jason.encode!(%{"version" => 1, "extensions" => [instance], "extension_trust" => [trust]})
    )

    assert {:error, _} = Config.resolve(c.cwd, c.home, [trust_project_config: true], %{})
  end

  test "precedence is built-in operator project nearer directory environment then CLI", c do
    put(Path.join(c.home, "config.json"), %{
      "provider" => "ollama",
      "model" => "operator-model",
      "max_steps" => 5
    })

    put(Path.join(c.project, ".ipse/config.json"), %{"model" => "project-model", "max_steps" => 6})

    put(Path.join(c.project, "nested/.ipse/config.json"), %{
      "model" => "nested-model",
      "max_steps" => 7
    })

    opts = [trust_project_config: true, max_steps: 9]

    assert {:ok, config} =
             Config.resolve(c.cwd, c.home, opts, %{
               "IPSE_MODEL" => "environment-model",
               "IPSE_MAX_STEPS" => "8"
             })

    assert config.settings["provider"] == "ollama"
    assert config.settings["model"] == "environment-model"
    assert config.settings["max_steps"] == 9
    assert config.provenance["model"] == "environment"
    assert config.provenance["max_steps"] == "CLI"
    assert length(config.sources) == 3
    assert Config.runtime_settings(config).provider == "ollama"
  end

  test "project sandbox settings only tighten; explicit operator environment and CLI retain authority",
       c do
    operator = Path.join(c.home, "config.json")
    project = Path.join(c.project, ".ipse/config.json")
    nearer = Path.join(c.project, "nested/.ipse/config.json")
    opts = [trust_project_config: true]

    put(operator, %{"sandbox" => "native"})
    put(project, %{"sandbox" => "off"})
    put(nearer, %{"sandbox" => "off"})
    assert {:ok, protected} = Config.resolve(c.cwd, c.home, opts, %{})
    assert protected.settings["sandbox"] == "native"
    assert protected.provenance["sandbox"] == operator

    assert {:ok, environment} =
             Config.resolve(c.cwd, c.home, opts, %{"IPSE_SANDBOX" => "off"})

    assert environment.settings["sandbox"] == "off"
    assert environment.provenance["sandbox"] == "environment"
    assert {:ok, cli} = Config.resolve(c.cwd, c.home, opts ++ [sandbox: "off"], %{})
    assert cli.settings["sandbox"] == "off"
    assert cli.provenance["sandbox"] == "CLI"

    put(operator, %{"sandbox" => "off"})
    put(project, %{"sandbox" => "native"})
    assert {:ok, tightened} = Config.resolve(c.cwd, c.home, opts, %{})
    assert tightened.settings["sandbox"] == "native"
    assert tightened.provenance["sandbox"] == project
  end

  test "project config requires explicit trust even for read-only runs and can be disabled", c do
    put(Path.join(c.project, ".ipse/config.json"), %{"provider" => "openai"})
    assert {:error, error} = Config.resolve(c.cwd, c.home, [], %{})
    assert error =~ "--trust-project-config"
    assert {:ok, config} = Config.resolve(c.cwd, c.home, [project_config: false], %{})
    assert config.settings["provider"] == "chatgpt"
    assert {:ok, config} = Config.resolve(c.cwd, c.home, [trust_project_config: true], %{})
    assert config.settings["provider"] == "openai"
  end

  test "output caps follow scoped profile environment CLI precedence with explicit provider refusals",
       c do
    put(Path.join(c.home, "config.json"), %{"provider" => "ollama", "max_output_tokens" => 96})
    assert {:ok, file} = Config.resolve(c.cwd, c.home, [], %{})
    assert Config.runtime_settings(file).max_output_tokens == 96

    File.write!(
      Path.join(c.home, "config.json"),
      Jason.encode!(%{
        version: 1,
        settings: %{provider: "ollama", max_output_tokens: 96},
        profiles: %{capped: %{provider: "ollama", model: "fixture", max_output_tokens: 80}},
        roles: %{main: "capped"}
      })
    )

    assert {:ok, profile} = Config.resolve(c.cwd, c.home, [], %{})
    assert profile.settings["max_output_tokens"] == 80
    assert profile.provenance["max_output_tokens"] == "profile capped"
    assert {:ok, env} = Config.resolve(c.cwd, c.home, [], %{"IPSE_MAX_OUTPUT_TOKENS" => "64"})
    assert env.settings["max_output_tokens"] == 64

    assert {:ok, cli} =
             Config.resolve(c.cwd, c.home, [max_output_tokens: 32], %{
               "IPSE_MAX_OUTPUT_TOKENS" => "64"
             })

    assert cli.settings["max_output_tokens"] == 32
    assert cli.provenance["max_output_tokens"] == "CLI"
    refute cli.fingerprint == env.fingerprint
    assert {:error, message} = Config.resolve(c.cwd, c.home, [provider: "chatgpt"], %{})
    assert message =~ "does not support"

    assert {:error, _} =
             Config.resolve(c.cwd, c.home, [provider: "openai", max_output_tokens: 15], %{})

    for value <- ["0", "-1", "1.5", "none", "1000001"] do
      assert {:error, _} = Config.resolve(c.cwd, c.home, [], %{"IPSE_MAX_OUTPUT_TOKENS" => value})
    end
  end

  test "a config outside the nearest repository is never inherited", c do
    put(Path.join(c.root, ".ipse/config.json"), %{"provider" => "anthropic"})
    assert {:ok, config} = Config.resolve(c.cwd, c.home, [], %{})
    assert config.sources == []
  end

  test "unknown fields, inline credentials, malformed/oversized files and invalid settings fail safely",
       c do
    path = Path.join(c.home, "config.json")

    for raw <- [
          "{",
          String.duplicate("x", 16_385),
          Jason.encode!(%{"version" => 2}),
          Jason.encode!(%{"version" => 1, "api_key" => "secret-not-for-output"}),
          Jason.encode!(%{"version" => 1, "settings" => %{"approval" => "allow"}}),
          Jason.encode!(%{"version" => 1, "settings" => %{"max_steps" => 0}})
        ] do
      File.write!(path, raw)
      assert {:error, error} = Config.resolve(c.cwd, c.home, [], %{})
      refute error =~ "secret-not-for-output"
    end

    File.rm!(path)
    assert {:error, _} = Config.resolve(c.cwd, c.home, [config: path], %{})
    assert {:error, _} = Config.resolve(c.cwd, c.home, [], %{"IPSE_COMPACT" => "maybe"})
    assert {:error, _} = Config.resolve(c.cwd, c.home, [subagent_concurrency: 2], %{})
  end

  test "automatic project symlinks cannot escape scope while explicit operator files may be aliases",
       c do
    external = Path.join(c.root, "shared.json")
    put(external, %{"model" => "alias-model"})
    File.mkdir_p!(Path.join(c.project, ".ipse"))
    File.ln_s!(external, Path.join(c.project, ".ipse/config.json"))
    assert {:error, _} = Config.resolve(c.cwd, c.home, [trust_project_config: true], %{})

    assert {:ok, config} =
             Config.resolve(c.cwd, c.home, [project_config: false, config: external], %{})

    assert config.settings["model"] == "alias-model"
  end

  test "fingerprints change on source drift but not equivalent CLI provenance", c do
    path = Path.join(c.home, "config.json")
    put(path, %{"model" => "fixed"})
    assert {:ok, a} = Config.resolve(c.cwd, c.home, [], %{})
    assert {:ok, b} = Config.resolve(c.cwd, c.home, [model: "fixed"], %{})
    assert a.fingerprint == b.fingerprint
    File.write!(path, File.read!(path) <> "\n")
    assert {:ok, cfg} = Config.resolve(c.cwd, c.home, [], %{})
    refute cfg.fingerprint == a.fingerprint
  end
end
