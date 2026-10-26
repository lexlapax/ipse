defmodule Ipse.DecisionLoadingTest do
  use ExUnit.Case, async: true
  alias Ipse.Config

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-decision-loading-" <> Ipse.Usage.id())
    project = Path.join(root, "workspace")
    home = Path.join(root, "operator")
    File.mkdir_p!(Path.join(project, ".git"))
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(root) end)
    %{project: project, home: home, path: Path.join(home, "config.json")}
  end

  defp profile,
    do: %{
      "operation" => "decision",
      "provider" => "system_one",
      "model" => "jev-latest",
      "expected_model" => "jev-fixture",
      "service_id" => "typesafe"
    }

  test "operator decision registry changes configuration identity without choosing the main provider",
       ctx do
    assert {:ok, empty} = Config.resolve(ctx.project, ctx.home, [], %{})
    assert empty.decision_profiles == %{}
    refute Map.has_key?(Config.manifest(empty), :decision_profiles)

    File.write!(
      ctx.path,
      Jason.encode!(%{"version" => 1, "decision_profiles" => %{"advice" => profile()}})
    )

    assert {:ok, selected} = Config.resolve(ctx.project, ctx.home, [], %{})
    assert selected.settings == empty.settings
    assert selected.execution == empty.execution
    assert selected.fingerprint != empty.fingerprint
    assert Config.manifest(selected).decision_profiles == %{"advice" => profile()}

    client = %{
      base_url: nil,
      home: ctx.home,
      auth_dir: nil,
      operator_home: nil,
      workspace: ctx.project,
      mcp_config: nil,
      operator_questions: false,
      approval: :ask
    }

    assert {:ok, runtime} = Config.runtime(selected, client)
    assert runtime.decision_profiles == selected.decision_profiles
    refute Ipse.Config.Decisions.enabled?(runtime)
    assert Ipse.Config.Decisions.snapshot(runtime) == nil
  end

  test "trusted project configuration cannot add, replace or erase decision profiles", ctx do
    File.write!(
      ctx.path,
      Jason.encode!(%{"version" => 1, "decision_profiles" => %{"advice" => profile()}})
    )

    path = Path.join(ctx.project, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(path))

    for profiles <- [
          %{},
          %{"advice" => profile()},
          %{"other" => Map.put(profile(), "base_url", "https://different.invalid/v1")}
        ] do
      File.write!(path, Jason.encode!(%{"version" => 1, "decision_profiles" => profiles}))

      assert {:error, message} =
               Config.resolve(ctx.project, ctx.home, [trust_project_config: true], %{})

      assert message =~ "operator-only"
    end

    assert {:ok, _} = Config.resolve(ctx.project, ctx.home, [project_config: false], %{})
  end

  test "operator profile fields are closed and bounded before runtime or endpoint dispatch",
       ctx do
    for profiles <- [
          %{"advice" => Map.put(profile(), "api_key", "synthetic")},
          %{"advice" => Map.put(profile(), "provider", "chatgpt")},
          %{"advice" => Map.put(profile(), "base_url", "http://remote.invalid")},
          %{"advice" => Map.put(profile(), "pricing", String.duplicate("x", 1025))},
          Map.new(1..9, &{"profile#{&1}", profile()})
        ] do
      File.write!(ctx.path, Jason.encode!(%{"version" => 1, "decision_profiles" => profiles}))
      assert {:error, _} = Config.resolve(ctx.project, ctx.home, [], %{})
    end
  end
end
