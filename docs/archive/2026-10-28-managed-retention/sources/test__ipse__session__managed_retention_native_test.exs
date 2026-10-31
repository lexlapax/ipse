defmodule Ipse.Session.ManagedRetentionNativeTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 120_000

  test "actual native choices preserve original clocks, invalidate stale dependencies and suppress recapture" do
    root = Path.join(System.tmp_dir!(), "ipse-native-retention-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    # Retain this small synthetic store on failure for read-only diagnosis.
    helper = Path.join(root, "pty-driver")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
               stderr_to_stdout: true
             )

    paths = Enum.reverse(:code.get_path()) |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(
        helper,
        ["--review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          ["test/support/managed_literal_retention.exs", root],
        stderr_to_stdout: true,
        env: [{"HOME", root}, {"IPSE_HOME", root <> "/ipse"}, {"TMPDIR", root}]
      )

    assert status == 0, output
    assert output =~ "NATIVE_LITERAL_RETENTION_AND_CURRENT_READER_PASSED"
  end
end
