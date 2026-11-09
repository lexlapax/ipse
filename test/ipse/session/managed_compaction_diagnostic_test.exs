defmodule Ipse.Session.ManagedCompactionDiagnosticTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage

  for scenario <- ~w(shared) do
    @tag timeout: 90_000
    @tag compaction_diagnostic: scenario
    test "genuine Session supersession: #{scenario}" do
      root = Path.join(System.tmp_dir!(), "ipse-supersession-session-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      IO.puts("COMPACTION_DIAGNOSTIC_RETAINED_ROOT=" <> root)
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
              Path.expand("test/support/managed_compaction_diagnostic_session.exs"),
              root,
              unquote(scenario)
            ],
          stderr_to_stdout: true
        )

      assert status == 0, output
      if unquote(scenario) == "old_missing", do: refute(output =~ "Type correct ")

      if unquote(scenario) == "shared" do
        output
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "COMPACTION_DIAGNOSTIC="))
        |> Enum.each(&IO.puts/1)
      end

      marker =
        if unquote(scenario) == "current",
          do: "MANAGED_SUPERSESSION_SESSION_PASSED",
          else: "MANAGED_SUPERSESSION_#{String.upcase(unquote(scenario))}_PASSED"

      assert output =~ marker
      assert output =~ "COMPACTION_DIAGNOSTIC_PASSED"
    end
  end
end
