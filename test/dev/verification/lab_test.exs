defmodule Ipse.ExtensionLabTest do
  use ExUnit.Case, async: false

  @tag timeout: 120_000
  test "independent artifacts exercise the frozen SDK without loading domain modules in the host" do
    root = Path.join(System.tmp_dir!(), "ipse-lab-test-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    sdk = Application.app_dir(:ipse, "ebin")
    artifacts = Path.join(root, "artifacts")
    elixir = System.find_executable("elixir")

    {build, 0} =
      System.cmd(
        elixir,
        [
          Path.expand("../../../dev/build-artifact.exs", __DIR__),
          "extension-lab",
          "--sdk",
          sdk,
          "--output",
          artifacts
        ],
        stderr_to_stdout: true
      )

    assert build =~ "Built #{artifacts}."
    assert length(Path.wildcard(Path.join(artifacts, "*/extension.json"))) == 7
    refute build =~ "warning:"

    args = [
      Path.expand("../../../dev/verify.exs", __DIR__),
      "source",
      "lab",
      "--sdk",
      sdk,
      "--input",
      artifacts
    ]

    {output, status} = System.cmd(elixir, args, stderr_to_stdout: true)
    assert status == 0, output
    report = output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()

    assert %{"scenario" => "lab", "mode" => "source", "inventories_unchanged" => true} =
             report["verification"]

    assert map_size(report["checks"]) >= 41
    assert Enum.all?(report["checks"], fn {_, passed} -> passed == true end)
    assert report["fixture_provider"] == "synthetic"
    assert report["safe_to_continue"] == false
    assert report["expected_terminal_cleanup"] == "unconfirmed"
  end
end
