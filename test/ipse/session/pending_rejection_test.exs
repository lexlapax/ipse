defmodule Ipse.Session.PendingRejectionTest do
  use ExUnit.Case, async: false
  @moduletag :native_sandbox
  @moduletag :pending_rejection
  @moduletag timeout: 120_000
  @moduletag skip:
               if(:os.type() == {:unix, :linux}, do: false, else: "Linux native terminal fixture")

  test "public rejection after capture revocation preserves shared sources and suppresses only the selected candidate" do
    assert scenario("valid", "--management-review") =~ "PENDING_REJECTION_VALID_PASSED"
  end

  test "expired pending targets can still be rejected without original source acquisition" do
    assert scenario("expired", "--management-review") =~ "PENDING_REJECTION_EXPIRED_PASSED"
  end

  test "cancellation and a stale native code preserve the pending target and signed state" do
    assert scenario("cancel", "--management-review-cancel") =~ "PENDING_REJECTION_CANCEL_PASSED"
    assert scenario("stale", "--management-review-stale") =~ "PENDING_REJECTION_STALE_PASSED"
  end

  test "a management epoch or Collection root change during native input refuses the old proposal" do
    assert scenario("epoch-race", "--management-review-race") =~
             "PENDING_REJECTION_EPOCH-RACE_PASSED"

    assert scenario("root-race", "--management-review-race") =~
             "PENDING_REJECTION_ROOT-RACE_PASSED"
  end

  test "a shared literal's reviewed pin or forgetting does not prevent rejecting its pending candidate" do
    assert scenario("retained-peer", "--management-review") =~
             "PENDING_REJECTION_RETAINED-PEER_PASSED"

    assert scenario("forgotten-peer", "--management-review") =~
             "PENDING_REJECTION_FORGOTTEN-PEER_PASSED"
  end

  defp scenario(mode, driver_mode) do
    root = Path.join(System.tmp_dir!(), "ipse-pending-rejection-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    helper = Path.join(root, "pty-driver")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
               stderr_to_stdout: true
             )

    paths = Enum.flat_map(Enum.reverse(:code.get_path()), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(
        helper,
        [driver_mode, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          ["test/support/pending_rejection.exs", root, mode],
        stderr_to_stdout: true,
        env: [{"HOME", root}, {"IPSE_HOME", root <> "/home"}, {"TMPDIR", root}]
      )

    assert status == 0, output
    output
  end
end
