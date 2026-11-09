defmodule Ipse.CLI.ManagementJournalTest do
  use ExUnit.Case, async: false
  @moduletag :management_journal_caller
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native owner")

  @tag timeout: 60_000
  @tag :native_storage
  test "standalone management creates native-owned journals and refuses unsafe directories" do
    caller("MANAGEMENT_JOURNAL_NATIVE_CALLER_PASSED")
  end

  @tag :management_journal_old
  @tag skip: System.get_env("IPSE_MANAGEMENT_OLD_HELPER_TEST") != "1"
  @tag timeout: 60_000
  test "older pinned helper refuses management before publishing a header" do
    caller("MANAGEMENT_JOURNAL_OLD_HELPER_REFUSED")
  end

  defp caller(marker) do
    root = Path.join(System.tmp_dir!(), "ipse-management-caller-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    helper = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    assert {output, status} =
             System.cmd(
               helper,
               ["--review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
                 paths ++ [Path.expand("test/support/management_journal.exs"), root],
               stderr_to_stdout: true
             )

    assert status == 0, output
    assert output =~ marker
  end
end
