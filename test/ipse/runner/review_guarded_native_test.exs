defmodule Ipse.Runner.ReviewGuardedNativeTest do
  use ExUnit.Case, async: false

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-guarded-review-driver-" <> Ipse.Usage.id())
    File.mkdir!(root)
    driver = Path.join(root, "operator-pty")

    {output, 0} =
      System.cmd(
        "rustc",
        ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
        stderr_to_stdout: true
      )

    assert output == ""
    on_exit(fn -> File.rm_rf!(root) end)
    %{driver: driver}
  end

  test "protected display lock is released before the confirmation input", c do
    assert scenario(c.driver, "valid", "--review-guarded") =~ "GUARDED_REVIEW_VALID_PASSED"
  end

  test "expired, duplicate and foreign continuations cannot authorize a review", c do
    for mode <- ~w(expired double foreign stored) do
      output = scenario(c.driver, mode, "--review")
      assert output =~ "GUARDED_REVIEW_" <> String.upcase(mode) <> "_PASSED"
      if mode in ~w(expired foreign stored), do: refute(output =~ "SYNTHETIC_GUARDED_REVIEW")
    end
  end

  test "owner loss interrupts a backpressured guarded display before later bytes", c do
    output = scenario(c.driver, "backpressure", "--guard-backpressure")
    assert output =~ "GUARDED_REVIEW_BACKPRESSURE_PASSED"
    refute output =~ "GUARDED_LATE_SECRET_PREFIX"
  end

  test "cancellation queued at display acknowledgement does not issue a permit", c do
    assert scenario(c.driver, "queued_cancel", "--review") =~
             "GUARDED_REVIEW_QUEUED_CANCEL_PASSED"
  end

  defp scenario(driver, mode, driver_mode) do
    root = Path.join(System.tmp_dir!(), "ipse-guarded-review-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    paths =
      :code.get_path()
      |> Enum.map(&to_string/1)
      |> Enum.filter(&String.contains?(&1, "/_build/"))
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    args =
      [driver_mode, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++ ["test/support/guarded_review.exs", root, mode]

    {output, status} =
      System.cmd(driver, args,
        stderr_to_stdout: true,
        env: [{"HOME", root}, {"IPSE_HOME", Path.join(root, "home")}, {"TMPDIR", root}]
      )

    assert status == 0, output
    output
  end
end
