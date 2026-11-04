defmodule Ipse.CLI.ChatReofferTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 240_000

  @tag :chat_reoffer
  test "known cancellation then explicit resume uses a fresh native review without recapture" do
    root = Path.join(System.tmp_dir!(), "ipse-chat-reoffer-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    driver = Path.join(root, "pty")
    support = Path.expand("../../support", __DIR__)

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.join(support, "chat_reoffer_pty.rs"),
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 === "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        [System.find_executable("elixir"), "--erl", "+S 1:1 +A 1"] ++
          paths ++ [Path.join(support, "chat_review_cli.exs"), root, "reoffer"],
        stderr_to_stdout: true
      )

    assert status === 0,
           "retained synthetic fixture #{root}\n" <> String.slice(output, -16_000, 16_000)

    assert output =~ "SAME_REPLY_CHAT_REOFFER_PASSED"
    assert output =~ "CHAT_RECALL_VERIFIED"
    IO.puts("CHAT_REOFFER_RECEIPT #{root}")
  end
end
