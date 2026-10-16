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
    refute Jason.encode!(Config.manifest(config)) =~ "must not be read"
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

  test "project config requires explicit trust even for read-only runs and can be disabled", c do
    put(Path.join(c.project, ".ipse/config.json"), %{"provider" => "openai"})
    assert {:error, error} = Config.resolve(c.cwd, c.home, [], %{})
    assert error =~ "--trust-project-config"
    assert {:ok, config} = Config.resolve(c.cwd, c.home, [project_config: false], %{})
    assert config.settings["provider"] == "chatgpt"
    assert {:ok, config} = Config.resolve(c.cwd, c.home, [trust_project_config: true], %{})
    assert config.settings["provider"] == "openai"
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
