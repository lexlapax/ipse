defmodule Ipse.Runner.AcceptedLeaseProbeTest do
  use ExUnit.Case, async: false

  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native terminal")

  test "six synthetic owners transfer distinct operations and invalid requests refuse" do
    root = Path.join(System.tmp_dir!(), "ipse-accepted-probe-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    runner = Path.join(root, "runner")
    pty = Path.join(root, "pty")
    rustc = System.find_executable("rustc")
    assert is_binary(rustc)

    for {source, output} <- [
          {"native/ipse-runner.rs", runner},
          {"test/support/operator_pty.rs", pty}
        ] do
      {message, status} =
        System.cmd(rustc, ["--edition=2021", "-D", "warnings", source, "-o", output],
          stderr_to_stdout: true
        )

      assert status == 0, message
    end

    {output, status} =
      System.cmd(
        pty,
        [
          System.find_executable("elixir"),
          "--erl",
          "+S 2:2",
          "test/support/accepted_lease_probe.exs",
          runner
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SIX_LEASE_INVALID_REFUSED"
    assert output =~ "GROUP_LEASE_INVALID_REFUSED"
    assert output =~ "SYNTHETIC_REVIEW_CONTENT_REFUSED"
    refute output =~ "PRIVATE_TEXT_MUST_NOT_BE_DISPLAYED"

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    for {mode, expected} <- [
          {"positive", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"group", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"group-wide", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"group-input", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"group-notice-input", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"group-wide-notice-input", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"group-notice-input-owner-loss", "GROUP_INPUT_OWNER_LOSS_REFUSED"},
          {"group-wide-input", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"group-input-owner-loss", "GROUP_INPUT_OWNER_LOSS_REFUSED"},
          {"group-wide-loss-middle", "SIX_LEASE_OWNER_LOSS_REFUSED"},
          {"group-loss-source", "SIX_LEASE_OWNER_LOSS_REFUSED"},
          {"group-loss-journal", "SIX_LEASE_OWNER_LOSS_REFUSED"},
          {"actual-session", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"actual-journal", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"actual-source", "SIX_LEASE_SYNTHETIC_PASSED"},
          {"loss-session", "SIX_LEASE_OWNER_LOSS_REFUSED"},
          {"loss-collection", "SIX_LEASE_OWNER_LOSS_REFUSED"},
          {"loss-journal", "SIX_LEASE_OWNER_LOSS_REFUSED"},
          {"loss-source", "SIX_LEASE_OWNER_LOSS_REFUSED"}
        ] do
      {output, status} =
        System.cmd(
          pty,
          cond do
            String.ends_with?(mode, "-owner-loss") -> ["--management-review-hold"]
            String.contains?(mode, "-input") -> ["--management-review"]
            true -> []
          end ++
            [System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              "test/support/accepted_lease_positive.exs",
              runner,
              Path.join(root, "locks-" <> mode),
              Path.join(Application.app_dir(:ipse), "ebin"),
              mode
            ],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ expected

      if String.contains?(mode, "loss-"),
        do: refute(output =~ "SYNTHETIC_ACCEPTED_LEASE_DISPLAY")
    end
  end
end
