defmodule Ipse.Runner.OperatorProtocolTest do
  use ExUnit.Case, async: true
  alias Ipse.Runner.Operator
  @nonce String.duplicate("n", 16)
  defp frame(kind, body), do: <<kind, byte_size(body)::32, body::binary>>
  defp ready, do: frame(?g, <<@nonce::binary, 123::32, 124::32>>) <> frame(?y, @nonce)

  test "strict native transcript preserves one MiB exact bytes and requires restoration" do
    text = String.duplicate("x", 1_048_576)
    transcript = ready() <> frame(?i, @nonce <> text) <> frame(?R, @nonce)

    assert {:ok, %{phase: :input, text: ^text, restored: true, cancelled: false}} =
             Operator.validate_transcript(transcript, @nonce)

    for damaged <- [
          ready() <> frame(?i, @nonce <> text),
          transcript <> <<0>>,
          ready() <> frame(?i, @nonce <> text <> "x") <> frame(?R, @nonce),
          ready() <> frame(?R, @nonce),
          frame(?i, @nonce <> "forged") <> frame(?R, @nonce),
          ready() <> frame(?i, @nonce <> <<255>>) <> frame(?R, @nonce),
          ready() <> frame(?i, @nonce <> "ok") <> frame(?r, @nonce),
          ready() <> frame(?i, @nonce <> "ok") <> frame(?R, String.duplicate("z", 16)),
          ready() <> frame(?i, @nonce <> "ok") <> frame(?R, @nonce) <> frame(?R, @nonce)
        ] do
      assert {:error, :invalid_operator_protocol} = Operator.validate_transcript(damaged, @nonce)
    end
  end

  test "pre-display nonterminal, EOF and cancellation remain distinct from input" do
    assert {:ok, %{phase: :nonterminal, text: nil}} =
             Operator.validate_transcript(frame(?n, "nonterminal"), @nonce)

    assert {:ok, %{phase: :eof, text: nil}} =
             Operator.validate_transcript(
               ready() <> frame(?f, @nonce) <> frame(?R, @nonce),
               @nonce
             )

    assert {:ok, %{cancelled: true, text: nil}} =
             Operator.validate_transcript(
               ready() <> frame(?c, @nonce) <> frame(?R, @nonce),
               @nonce
             )

    for damaged <- [
          ready() <> frame(?n, "nonterminal"),
          frame(?y, @nonce) <> frame(?R, @nonce),
          frame(?g, <<@nonce::binary, 123::32, 123::32>>) <> frame(?y, @nonce),
          frame(?R, @nonce),
          frame(?n, "unavailable"),
          ready() <> <<?i, 1_048_593::32>>
        ] do
      assert {:error, :invalid_operator_protocol} = Operator.validate_transcript(damaged, @nonce)
    end
  end

  test "a cancellation receipt without restoration cannot remove the cleanup deadline" do
    root = Path.join(System.tmp_dir!(), "ipse-operator-protocol-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    helper = Path.join(root, "incomplete")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_protocol_probe.rs",
                 "-o",
                 helper
               ],
               stderr_to_stdout: true
             )

    before = System.monotonic_time(:millisecond)

    assert {:error, :operator_cleanup_unconfirmed} =
             Operator.run(helper, "Synthetic protocol only> ", 1000)

    assert File.read(Path.join(root, "native-c-emitted")) == {:ok, "c"}
    assert File.read(Path.join(root, "host-cancel-received")) == {:ok, "C"}
    assert System.monotonic_time(:millisecond) - before >= 1000
    assert System.monotonic_time(:millisecond) - before < 6000
  end
end
