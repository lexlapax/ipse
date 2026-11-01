defmodule Ipse.Session.OperatorAssertionIntegrationTest do
  use ExUnit.Case, async: false

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-assertion-driver-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    driver = Path.join(root, "pty")

    assert {output, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    assert output == ""
    on_exit(fn -> File.rm_rf!(root) end)
    %{driver: driver}
  end

  for scenario <-
        ~w(save save_display_owners save_managed_approval save_managed_approval_active save_managed_approval_resume save_managed_approval_deny save_managed_approval_stale_token save_managed_approval_cancel save_managed_approval_exit save_managed_approval_delayed save_managed_approval_source_stale save_managed_approval_revoked save_managed_approval_owner_loss save_managed_approval_shell save_managed_approval_shell_source_stale save_forget save_forget_cancel save_forget_stale save_retention save_expire save_history_expire cancel stale planning revoked) do
    @tag timeout: 90_000
    @tag assertion_scenario: scenario
    @tag managed_approval: String.starts_with?(scenario, "save_managed_approval")
    @tag managed_shell_approval: String.starts_with?(scenario, "save_managed_approval_shell")
    test "actual native CLI statement review: #{scenario}", c do
      root = Path.join(System.tmp_dir!(), "ipse-assertion-" <> Ipse.Usage.id())
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

      assert {output, status} =
               System.cmd(
                 c.driver,
                 ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
                   paths ++
                   [Path.expand("test/support/operator_assertion.exs"), root, unquote(scenario)],
                 stderr_to_stdout: true
               )

      assert status == 0, output
      assert output =~ "NATIVE_ASSERTION_#{String.upcase(unquote(scenario))}_PASSED"
    end
  end
end
