defmodule Ipse.CLI.ManagementRejectPublicTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias Ipse.CLI.Knowledge.Management

  test "rejection refuses restricted modes and wrong target kinds before storage" do
    root = Path.join(System.tmp_dir!(), "ipse-reject-mode-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    key = "pending." <> Ipse.JSON.sha256("synthetic target")

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
               Management.reject(Map.merge(config, extra), root, key)

      refute File.exists?(root)
    end

    for target <- [
          "pending.bad",
          "note." <> Ipse.JSON.sha256("other target"),
          "reject." <> Ipse.JSON.sha256("old target")
        ] do
      assert {:error, :knowledge_management_refused} = Management.reject(config, root, target)
      refute File.exists?(root)
    end
  end

  test "CLI overrides cannot replace native rejection or select inference" do
    root = Path.join(System.tmp_dir!(), "ipse-reject-options-" <> Ipse.Usage.id())
    key = "pending." <> Ipse.JSON.sha256("synthetic target")

    for opts <- [
          [yes: true],
          [json: true],
          [provider: "demo"],
          [model: "synthetic"],
          [base_url: "http://127.0.0.1:1"],
          [state_dir: "/tmp"],
          [timeout_ms: 120_000]
        ] do
      capture_io(:stderr, fn ->
        assert 1 == Ipse.CLI.Knowledge.run_target("reject", key, opts, root, root)
      end)

      refute File.exists?(root)
    end
  end
end
