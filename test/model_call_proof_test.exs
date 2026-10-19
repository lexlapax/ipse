Code.require_file("../examples/model-calls/proof.exs", __DIR__)

defmodule Ipse.ModelCallProofTest do
  use ExUnit.Case, async: false

  test "standalone independently built model artifact passes the shared source/release proof" do
    root = Path.join(System.tmp_dir!(), "ipse-model-artifact-#{Ipse.Usage.id()}")
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "examples/model-calls/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          root
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    report = IpseModelExample.Proof.run(root)
    assert map_size(report["checks"]) == 9
    assert Enum.all?(report["checks"], fn {_, passed} -> passed end)
    assert report["thinking_selection"] == "default"
    quiet = IpseModelExample.Proof.run(root, "none")
    assert quiet["thinking_selection"] == "none"
    assert map_size(quiet["checks"]) == 9
    assert Enum.all?(quiet["checks"], fn {_, passed} -> passed end)
  end
end
