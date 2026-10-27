defmodule Ipse.Runner.ReviewNativeTest do
  use ExUnit.Case, async: false

  test "real native review binds five commands and rejects replay, cross-task and forged permits" do
    assert scenario("valid", "--review") =~ "NATIVE_REVIEW_VALID_PASSED"
  end

  test "bare yes and mismatched challenge cancel actual terminal review" do
    assert scenario("cancel", "--review-cancel") =~ "NATIVE_REVIEW_CANCEL_PASSED"
    assert scenario("stale", "--review-stale") =~ "NATIVE_REVIEW_STALE_PASSED"
  end

  test "changed facts refuse and consumed failures remain unconfirmed" do
    for mode <- ~w(changed callback_error closed_scope),
        do:
          assert(
            scenario(mode, "--review") =~ "NATIVE_REVIEW_" <> String.upcase(mode) <> "_PASSED"
          )
  end

  test "pipe input cannot create a native review permit" do
    assert scenario("pipe", nil) =~ "NATIVE_REVIEW_PIPE_PASSED"
  end

  defp scenario(mode, driver_mode) do
    root = Path.join(System.tmp_dir!(), "ipse-native-review-test-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    elixir = System.find_executable("elixir")

    args = [
      "--erl",
      "+S 2",
      "-pa",
      Path.join(Mix.Project.build_path(), "lib/*/ebin"),
      "test/support/native_review.exs",
      root,
      mode
    ]

    env = [{"HOME", root}, {"IPSE_HOME", Path.join(root, "home")}, {"TMPDIR", root}]

    {output, status} =
      if driver_mode do
        helper = Path.join(root, "pty-driver")

        {compiled, 0} =
          System.cmd(
            "rustc",
            ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
            stderr_to_stdout: true
          )

        assert compiled == ""
        System.cmd(helper, [driver_mode, elixir | args], stderr_to_stdout: true, env: env)
      else
        System.cmd(elixir, args, stderr_to_stdout: true, env: env)
      end

    assert status == 0, output
    output
  end
end
