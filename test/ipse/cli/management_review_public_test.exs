defmodule Ipse.CLI.ManagementReviewPublicTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias Ipse.CLI.Knowledge.Management

  test "review refuses denied, headless and restricted modes before touching storage" do
    root = Path.join(System.tmp_dir!(), "ipse-public-review-mode-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    key = "pending." <> Ipse.JSON.sha256("synthetic pending target")

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
               Management.review(Map.merge(config, extra), root, Path.join(root, "sessions"), key)

      refute File.exists?(root)
    end
  end

  test "CLI overrides cannot replace native acceptance or select another provider" do
    root = Path.join(System.tmp_dir!(), "ipse-public-review-options-" <> Ipse.Usage.id())
    key = "pending." <> Ipse.JSON.sha256("synthetic pending target")

    for opts <- [
          [yes: true],
          [json: true],
          [provider: "demo"],
          [model: "synthetic"],
          [base_url: "http://127.0.0.1:1"],
          [timeout_ms: 120_000]
        ] do
      capture_io(:stderr, fn ->
        assert 1 == Ipse.CLI.Knowledge.run_target("review", key, opts, root, root)
      end)

      refute File.exists?(root)
    end
  end

  test "invalid targets and source directory refuse before creating management storage" do
    root = Path.join(System.tmp_dir!(), "ipse-public-review-target-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}

    for key <- ["pending.bad", "note." <> Ipse.JSON.sha256("other kind")] do
      assert {:error, :knowledge_management_refused} =
               Management.review(config, root, Path.join(root, "sessions"), key)
    end

    assert {:error, :knowledge_management_refused} =
             Management.review(config, root, "relative", "pending." <> Ipse.JSON.sha256("target"))

    refute File.exists?(root)
  end
end
