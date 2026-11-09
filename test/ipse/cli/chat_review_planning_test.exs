defmodule Ipse.CLI.ChatReviewPlanningTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  @moduletag timeout: 180_000

  @tag :chat_review
  @tag :chat_review_planning
  test "witnessed planning exit stays normal through review and same conversation resume" do
    root = Path.join(System.tmp_dir!(), "ipse-chat-review-planning-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.expand("../../support/operator_cli_pty.rs", __DIR__),
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
        ["--chat-review-planning", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("../../support/chat_review_cli.exs", __DIR__), root, "planning_accept"],
        stderr_to_stdout: true
      )

    assert status == 0,
           "retained synthetic fixture #{root}\n" <> String.slice(output, -12_000, 12_000)

    assert output =~ "SAME_REPLY_CHAT_PLANNING_ACCEPT_PASSED"
    assert output =~ "CHAT_PLAN_EXIT_MODE_CHECKED"
    assert output =~ "CHAT_RESUME_AUTHORITY_CHECKED"
    assert output =~ "CHAT_RECALL_VERIFIED"
    IO.puts("CHAT_REVIEW_PLANNING_RECEIPT #{root}")
  end
end
