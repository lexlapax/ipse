defmodule Ipse.SemanticLoadingTest do
  use ExUnit.Case, async: true
  alias Ipse.Config

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-semantic-loading-" <> Ipse.Usage.id())
    project = Path.join(root, "workspace")
    home = Path.join(root, "operator")
    File.mkdir_p!(Path.join(project, ".git"))
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(root) end)
    %{project: project, home: home, path: Path.join(home, "config.json")}
  end

  defp selection do
    %{
      "notes" => %{
        "version" => 1,
        "project" => String.duplicate("a", 64),
        "policy_sha256" => String.duplicate("b", 64),
        "enabled" => true
      }
    }
  end

  defp client(c, extra \\ %{}) do
    Map.merge(
      %{
        base_url: nil,
        home: c.home,
        auth_dir: nil,
        operator_home: nil,
        workspace: c.project,
        mcp_config: nil,
        operator_questions: false,
        approval: :deny
      },
      extra
    )
  end

  test "operator references change fingerprint but do not imply executable or semantic grants",
       c do
    assert {:ok, empty} = Config.resolve(c.project, c.home, [], %{})
    assert empty.semantic_selections == %{}
    refute Map.has_key?(Config.manifest(empty), :semantic_selections)
    File.write!(c.path, Jason.encode!(%{"version" => 1, "semantic_selections" => selection()}))
    assert {:ok, selected} = Config.resolve(c.project, c.home, [], %{})
    assert selected.fingerprint != empty.fingerprint
    assert selected.settings == empty.settings
    assert selected.extensions == empty.extensions
    assert Config.manifest(selected).semantic_selections == selection()
    assert {:ok, runtime} = Config.runtime(selected, client(c))
    assert runtime.semantic_selections == selection()
    assert runtime.extensions == []
    assert runtime.approval_origin == "explicit"
    refute runtime.headless
  end

  test "trusted project sources cannot enable, change or erase semantic selections", c do
    path = Path.join(c.project, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(path))

    for value <- [selection(), %{}] do
      File.write!(path, Jason.encode!(%{"version" => 1, "semantic_selections" => value}))

      assert {:error, :semantic_configuration_operator_only} =
               Config.resolve(c.project, c.home, [trust_project_config: true], %{})
    end

    assert {:ok, _} = Config.resolve(c.project, c.home, [project_config: false], %{})
  end

  test "inference address aliases are operator-only configuration with distinct fingerprints",
       c do
    services = %{"local" => %{"version" => 1, "origins" => ["http://127.0.0.1:11434"]}}
    assert {:ok, empty} = Config.resolve(c.project, c.home, [], %{})
    File.write!(c.path, Jason.encode!(%{"version" => 1, "inference_services" => services}))
    assert {:ok, selected} = Config.resolve(c.project, c.home, [], %{})
    assert selected.fingerprint != empty.fingerprint
    assert selected.settings == empty.settings
    assert Config.manifest(selected).inference_services == services
    assert {:ok, runtime} = Config.runtime(selected, client(c))
    assert runtime.inference_services == services
    path = Path.join(c.project, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"version" => 1, "inference_services" => %{}}))

    assert {:error, :inference_services_operator_only} =
             Config.resolve(c.project, c.home, [trust_project_config: true], %{})
  end

  test "runtime preserves default headless reason independently from broad yes", c do
    assert {:ok, effective} = Config.resolve(c.project, c.home, [], %{})

    assert {:ok, denied} =
             Config.runtime(
               effective,
               client(
                 c,
                 %{approval_origin: :default_headless, headless: true}
               )
             )

    assert denied.approval == :deny and denied.approval_origin == "default_headless"
    assert denied.headless

    assert {:ok, yes} =
             Config.runtime(
               effective,
               client(
                 c,
                 %{
                   approval: :allow,
                   approval_origin: :yes,
                   headless: true,
                   enclosing_mode: :planning
                 }
               )
             )

    assert yes.approval == :allow and yes.approval_origin == "yes" and yes.headless
    assert yes.enclosing_mode == "planning"
    assert {:ok, mode} = Ipse.Extension.Mode.capture(yes)
    assert :deny = Ipse.Extension.Mode.ordinary(mode, true)
    assert {:error, _} = Ipse.Extension.Mode.knowledge(mode, "collection.publish")
  end

  test "contradictory modes and malformed operator selection fields refuse", c do
    assert {:ok, effective} = Config.resolve(c.project, c.home, [], %{})

    assert {:error, :invalid_execution_mode} =
             Config.runtime(
               effective,
               client(c, %{approval: :allow, approval_origin: :default_headless})
             )

    for entries <- [
          put_in(selection(), ["notes", "version"], 1.0),
          put_in(selection(), ["notes", "enabled"], "yes"),
          put_in(selection(), ["notes", "policy_sha256"], "unverified"),
          put_in(selection(), ["notes", "artifact_trust"], true),
          Map.new(1..9, &{"notes#{&1}", selection()["notes"]})
        ] do
      File.write!(c.path, Jason.encode!(%{"version" => 1, "semantic_selections" => entries}))
      assert {:error, _} = Config.resolve(c.project, c.home, [], %{})
    end
  end
end
