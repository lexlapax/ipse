defmodule Ipse.Development.ManagedV3TurnoverNativeTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 120_000

  test "typed correction and historical expiry record actual review and simulated as-of separately" do
    root = Path.join(System.tmp_dir!(), "ipse-turnover-trace-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    helper = Path.join(root, "pty-driver")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
               stderr_to_stdout: true
             )

    paths = Enum.reverse(:code.get_path()) |> Enum.flat_map(&["-pa", List.to_string(&1)])
    graph = Ipse.Runner |> :code.which() |> List.to_string() |> Path.dirname() |> Path.expand()

    for {mode, expected_events} <- [{"ordinary", 1}, {"history_expiry", 2}] do
      directory = Path.join(root, mode)
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)

      {output, status} =
        System.cmd(
          helper,
          ["--review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              "-pa",
              graph,
              "test/support/managed_literal_supersession.exs",
              directory,
              "turnover_" <> mode
            ],
          stderr_to_stdout: true,
          env: [{"HOME", directory}, {"IPSE_HOME", directory <> "/ipse"}, {"TMPDIR", directory}]
        )

      assert status == 0, output
      assert output =~ "NATIVE_SUPERSESSION_PASSED:" <> mode

      events =
        output
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "TURNOVER_EVENT="))
        |> Enum.map(fn line ->
          line |> String.replace_prefix("TURNOVER_EVENT=", "") |> Jason.decode!()
        end)

      assert length(events) == expected_events
      [review | remaining] = events
      assert review["clock_kind"] == "actual_wall_clock" and review["qualification"] == false

      assert Ipse.JSON.sha256?(review["review_sha256"]) and
               Ipse.JSON.sha256?(review["source_sha256"])

      assert review["source_scope"] == "synthetic_trusted_fixture"
      frame = review["clock_frame"]

      assert review["virtual_ms"] ==
               frame["virtual_anchor_ms"] + review["real_or_as_of_ms"] - frame["real_anchor_ms"]

      if mode == "history_expiry" do
        [expiry] = remaining
        assert expiry["clock_kind"] == "explicit_synthetic_as_of"
        assert expiry["real_or_as_of_ms"] == review["history_deadline_actual_ms"]
        assert expiry["virtual_ms"] == review["history_deadline_virtual_ms"]
        assert expiry["real_or_as_of_ms"] > expiry["real_wall_after_ms"]
        assert expiry["virtual_ms"] - review["virtual_ms"] == 365 * 86_400_000
      end

      Enum.each(events, &IO.puts("TURNOVER_EVENT=" <> Jason.encode!(&1)))
    end
  end
end
