defmodule Ipse.CLI.KnowledgeManagementTest do
  use ExUnit.Case, async: true
  alias Ipse.CLI.Knowledge.Management

  test "native management cannot widen execution ceilings or explicit effect denial" do
    root = Path.join(System.tmp_dir!(), "ipse-management-denied-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    key = "note." <> Ipse.JSON.sha256("synthetic denied target")

    for extra <- [
          %{approval: :deny},
          %{headless: true},
          %{approval_origin: :yes},
          %{execution_mode: :read_only},
          %{execution_mode: :planning},
          %{execution_mode: :draft},
          %{enclosing_mode: :planning}
        ] do
      assert {:error, :knowledge_management_refused} =
               Management.forget(Map.merge(config, extra), root, key)

      assert {:error, :knowledge_management_refused} =
               Management.retain(Map.merge(config, extra), root, key, %{"kind" => "pin"})

      refute File.exists?(root)
    end
  end

  test "retention options cannot widen unrelated CLI commands or admit malformed choices" do
    key = "note." <> Ipse.JSON.sha256("synthetic option target")

    for args <- [
          ["run", "synthetic", "--policy", "pin"],
          ["knowledge", "forget", key, "--days", "7"],
          ["knowledge", "retention", key, "--policy", "pin", "--days", "7"],
          ["knowledge", "retention", key, "--policy", "automatic", "--days", "89"],
          ["knowledge", "retention", key, "--policy", "duration"],
          ["knowledge", "retention", key, "--policy", "duration", "--days", "0"],
          ["knowledge", "retention", key, "--policy", "duration", "--days", "9007199254740991"],
          ["knowledge", "retention", key, "--policy", "unknown"]
        ] do
      output = ExUnit.CaptureIO.capture_io(:stderr, fn -> assert Ipse.CLI.run(args) == 1 end)
      assert output != ""
    end
  end
end
