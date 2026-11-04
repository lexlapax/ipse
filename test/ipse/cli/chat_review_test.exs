defmodule Ipse.CLI.ChatReviewTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 180_000

  for mode <- ~w(accept cancel stale_cancel stale_turn same_followup) do
    @tag :chat_review
    @tag chat_review_stale: mode in ~w(stale_cancel stale_turn)
    @tag chat_review_accept_cancel: mode in ~w(accept cancel)
    @tag same_id_followup: mode == "same_followup"
    test "one completed reply offers native review and #{mode} preserves the conversation" do
      mode = unquote(mode)
      root = Path.join(System.tmp_dir!(), "ipse-chat-review-" <> Ipse.Usage.id())
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
                   if(mode in ~w(stale_cancel stale_turn),
                     do: "test/support/operator_pty.rs",
                     else: "test/support/operator_cli_pty.rs"
                   ),
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

      option =
        case mode do
          "accept" -> "--chat-review"
          "cancel" -> "--chat-review-cancel"
          "same_followup" -> "--chat-review-followup"
          _ -> "--knowledge"
        end

      {output, status} =
        System.cmd(
          driver,
          [option, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [Path.expand("test/support/chat_review_cli.exs"), root, mode],
          stderr_to_stdout: true
        )

      assert status == 0,
             "retained synthetic fixture #{root}\n" <> String.slice(output, -12_000, 12_000)

      assert output =~ "SAME_REPLY_CHAT_#{String.upcase(mode)}_PASSED"

      if mode == "same_followup" do
        assert output =~ "SAME_ID_FOLLOWUP_PROVIDER_COMPLETED"
        assert output =~ "Conversation resumed: "
        refute output =~ "FIXED_SYNTHETIC_NOMINATION_CONTINUATION"
        terminal = output |> String.split("Conversation resumed: ") |> List.last()
        assert terminal =~ "Finished."
        refute terminal =~ "Finished with an error."

        assert %{
                 "provider_requests" => 3,
                 "turn_statuses" => ["ok", "ok"],
                 "strict_saved" => "pass",
                 "source_receipt_verified" => "pass",
                 "close_confirmed" => "pass"
               } =
                 root
                 |> Path.join("same-id-followup-diagnostic.json")
                 |> File.read!()
                 |> Jason.decode!()
      else
        unless mode in ~w(stale_cancel stale_turn) do
          assert output =~ "Conversation resumed: "
          assert output =~ "CHAT_RECALL_VERIFIED"
        end
      end

      IO.puts("CHAT_REVIEW_RECEIPT #{mode} #{root}")
    end
  end
end
