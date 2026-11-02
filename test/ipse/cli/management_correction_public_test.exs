defmodule Ipse.CLI.ManagementCorrectionPublicTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "pending correction refuses narrowed modes before storage or a source read" do
    root = Path.join(System.tmp_dir!(), "ipse-pending-correction-mode-" <> Ipse.Usage.id())
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
      assert {:error, :pending_correction_refused} =
               Ipse.CLI.Knowledge.Correction.run(
                 Map.merge(config, extra),
                 root,
                 root <> "/sessions",
                 key,
                 "corrected pending text"
               )

      refute File.exists?(root)
    end
  end

  test "CLI overrides cannot provide correction attestation or invoke another model" do
    root = Path.join(System.tmp_dir!(), "ipse-pending-correction-options-" <> Ipse.Usage.id())
    key = "pending." <> Ipse.JSON.sha256("synthetic target")

    for opts <- [
          [yes: true],
          [json: true],
          [provider: "demo"],
          [model: "synthetic"],
          [base_url: "http://127.0.0.1:1"],
          [timeout_ms: 120_000]
        ] do
      capture_io(:stderr, fn ->
        assert 1 == Ipse.CLI.Knowledge.run_correction(key, "new pending text", opts, root, root)
      end)

      refute File.exists?(root)
    end
  end
end
