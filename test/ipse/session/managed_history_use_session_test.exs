defmodule Ipse.Session.ManagedHistoryUseSessionTest do
  use ExUnit.Case, async: false

  for scenario <- ~w(current) do
    @tag timeout: 90_000
    @tag history_use_scenario: scenario
    test "genuine Session supersession: #{scenario}" do
      root = Path.join(System.tmp_dir!(), "ipse-supersession-session-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      driver = Path.join(root, "pty")

      assert {"", 0} =
               System.cmd(
                 "rustc",
                 [
                   "--edition=2021",
                   "-D",
                   "warnings",
                   "test/support/operator_pty.rs",
                   "-o",
                   driver
                 ],
                 stderr_to_stdout: true
               )

      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      {output, status} =
        System.cmd(
          driver,
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              Path.expand("test/support/managed_history_use_session.exs"),
              root,
              unquote(scenario)
            ],
          stderr_to_stdout: true
        )

      assert status == 0, output
      if unquote(scenario) == "old_missing", do: refute(output =~ "Type correct ")

      marker =
        if unquote(scenario) == "current",
          do: "MANAGED_SUPERSESSION_SESSION_PASSED",
          else: "MANAGED_SUPERSESSION_#{String.upcase(unquote(scenario))}_PASSED"

      assert output =~ marker
      assert output =~ "MANAGED_HISTORY_USE_PASSED"
    end
  end
end
