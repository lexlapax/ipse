defmodule Ipse.CLI.ManagementBatchPublicTest do
  use ExUnit.Case, async: true
  alias Ipse.CLI.Knowledge.Batch

  test "batch review cannot widen execution denial or accept malformed selection" do
    root = Path.join(System.tmp_dir!(), "ipse-batch-denied-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    keys = Enum.map(1..2, &("pending." <> Ipse.JSON.sha256("target #{&1}")))

    for extra <- [
          %{headless: true},
          %{approval: :deny},
          %{approval_origin: :yes},
          %{execution_mode: :read_only},
          %{execution_mode: :planning},
          %{enclosing_mode: :planning}
        ] do
      assert {:error, :pending_batch_refused} =
               Batch.run(Map.merge(config, extra), root, root, keys)
    end

    for selected <- [
          [],
          keys ++ keys,
          ["pending.short"],
          Enum.map(1..9, &("pending." <> Ipse.JSON.sha256("target #{&1}")))
        ] do
      assert {:error, :pending_batch_refused} = Batch.run(config, root, root, selected)
    end

    refute File.exists?(root)
  end

  test "batch CLI refuses JSON, provider overrides, yes and excess keys before storage" do
    root = Path.join(System.tmp_dir!(), "ipse-batch-options-" <> Ipse.Usage.id())
    keys = Enum.map(1..2, &("pending." <> Ipse.JSON.sha256("target #{&1}")))

    for extra <- [["--json"], ["--yes"], ["--provider", "demo"], ["--policy", "pin"]] do
      assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
               assert Ipse.CLI.run(["knowledge", "review" | keys] ++ ["--cwd", root] ++ extra) ==
                        1
             end) != ""
    end

    refute File.exists?(root)
  end
end
