defmodule Ipse.Session.ManagedLifecycleTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage

  @moduletag timeout: 120_000
  test "actual native-reviewed Core forget retains signed suppression and rejects recapture/old import" do
    assert scenario("valid", "--review") =~ "NATIVE_MANAGED_LITERAL_FORGET_VALID_PASSED"
  end

  test "changed client facts and cancellation leave the actual signed store unchanged" do
    assert scenario("changed", "--review") =~ "NATIVE_MANAGED_LITERAL_FORGET_CHANGED_PASSED"
    assert scenario("cancel", "--review-cancel") =~ "NATIVE_MANAGED_LITERAL_FORGET_CANCEL_PASSED"
  end

  defp scenario(mode, driver_mode) do
    root = Path.join(System.tmp_dir!(), "ipse-managed-forget-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    # Keep failed stores for diagnosis; no prior capacity store is ever opened.
    paths = Enum.flat_map(Enum.reverse(:code.get_path()), &["-pa", List.to_string(&1)])
    helper = Path.join(root, "pty-driver")

    {compiled, 0} =
      System.cmd(
        "rustc",
        ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
        stderr_to_stdout: true
      )

    assert compiled == ""

    {output, status} =
      System.cmd(
        helper,
        [driver_mode, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          ["test/support/managed_literal_forget.exs", root, mode],
        stderr_to_stdout: true,
        env: [{"HOME", root}, {"IPSE_HOME", root <> "/ipse"}, {"TMPDIR", root}]
      )

    assert status == 0, output
    output
  end
end
