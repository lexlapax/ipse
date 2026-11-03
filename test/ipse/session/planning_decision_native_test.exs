defmodule Ipse.Session.PlanningDecisionNativeTest do
  use ExUnit.Case, async: false

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-plan-decision-driver-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    on_exit(fn -> File.rm_rf!(root) end)
    %{driver: driver}
  end

  for scenario <-
        ~w(plan_save plan_exit plan_cancel plan_stale plan_save_cancel plan_save_stale plan_revoked plan_interrupted plan_source plan_query_failure plan_intake_failure) do
    @tag timeout: 90_000
    @tag planning_decision_scenario: scenario
    test "native planning decision journey: #{scenario}", c do
      root = Path.join(System.tmp_dir!(), "ipse-plan-decision-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)

      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      {output, status} =
        System.cmd(
          c.driver,
          ["--planning-decision", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [Path.expand("test/support/planning_decision_cli.exs"), root, unquote(scenario)],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "PLANNING_DECISION_JOURNEY_PASSED"
    end
  end
end
