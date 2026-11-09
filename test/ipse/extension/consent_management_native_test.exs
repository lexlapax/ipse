defmodule Ipse.Extension.ConsentManagementNativeTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-consent-management-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    helper = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
               stderr_to_stdout: true
             )

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, helper: helper}
  end

  for scenario <- ~w(revoked expired stale forbidden unknown fenced fenced_stale fenced_unknown) do
    @tag timeout: 60_000
    test "native management authority: #{scenario}", c do
      directory = Path.join(c.root, Ipse.Usage.id())
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)

      paths =
        :code.get_path()
        |> Enum.reject(&(&1 == ~c"."))
        |> Enum.flat_map(&["-pa", List.to_string(&1)])

      assert {output, status} =
               System.cmd(
                 c.helper,
                 ["--review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
                   paths ++
                   [
                     Path.expand("test/support/consent_management.exs"),
                     directory,
                     unquote(scenario)
                   ],
                 stderr_to_stdout: true
               )

      assert status == 0, output
      assert output =~ "CONSENT_MANAGEMENT_#{String.upcase(unquote(scenario))}_PASSED"
    end
  end
end
