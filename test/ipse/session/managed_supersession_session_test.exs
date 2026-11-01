defmodule Ipse.Session.ManagedSupersessionSessionTest do
  use ExUnit.Case, async: false

  for scenario <-
        ~w(current cross_session pin_history relation_cancel revoke old_missing terminal terminal_cancel terminal_unknown terminal_effect_unknown shared disabled) do
    @tag timeout: 90_000
    @tag supersession_scenario: scenario
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
              Path.expand("test/support/managed_supersession_session.exs"),
              root,
              unquote(scenario)
            ],
          stderr_to_stdout: true
        )

      assert status == 0, output

      if unquote(scenario) == "pin_history",
        do: assert(output =~ "NATIVE_PINNED_HISTORY_SESSION_PASSED")

      if unquote(scenario) in ~w(old_missing disabled), do: refute(output =~ "Type correct ")

      if unquote(scenario) == "shared" do
        output
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "HISTORY_COMPACTION_"))
        |> Enum.each(&IO.puts/1)
      end

      if unquote(scenario) == "terminal_effect_unknown" do
        output
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "AFTER_EFFECT_CONTROL_SOURCE_SHA256="))
        |> Enum.each(&IO.puts/1)
      end

      marker =
        if unquote(scenario) == "current",
          do: "MANAGED_SUPERSESSION_SESSION_PASSED",
          else: "MANAGED_SUPERSESSION_#{String.upcase(unquote(scenario))}_PASSED"

      assert output =~ marker
    end
  end
end
