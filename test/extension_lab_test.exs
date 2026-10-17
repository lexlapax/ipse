defmodule Ipse.ExtensionLabTest do
  use ExUnit.Case, async: false

  @tag timeout: 120_000
  test "independent artifacts exercise the frozen SDK without loading domain modules in the host" do
    root = Path.join(System.tmp_dir!(), "ipse-lab-test-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    lab = Path.expand("../examples/extension-lab", __DIR__)
    sdk = Application.app_dir(:ipse, "ebin")
    artifacts = Path.join(root, "artifacts")
    elixir = System.find_executable("elixir")

    {build, 0} =
      System.cmd(elixir, [Path.join(lab, "build.exs"), "--sdk", sdk, "--output", artifacts],
        stderr_to_stdout: true
      )

    assert build =~ "Built seven inert local artifacts"
    refute build =~ "warning:"
    paths = sdk |> Path.dirname() |> Path.dirname() |> Path.join("*/ebin") |> Path.wildcard()
    args = Enum.flat_map(paths, &["-pa", &1]) ++ [Path.join(lab, "verify.exs"), artifacts]
    {output, status} = System.cmd(elixir, args, stderr_to_stdout: true)
    assert status == 0, output
    report = output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
    assert map_size(report["checks"]) >= 33
    assert Enum.all?(report["checks"], fn {_, passed} -> passed == true end)
    assert report["fixture_provider"] == "synthetic"
    assert report["safe_to_continue"] == false
    assert report["expected_terminal_cleanup"] == "unconfirmed"
  end
end
