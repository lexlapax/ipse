defmodule Ipse.CLITerminalTest do
  use ExUnit.Case, async: true
  alias Ipse.CLI.Terminal

  test "plain Unicode, newlines and tabs remain readable while terminal controls are inert" do
    assert Terminal.escape("日本語 café 😀\n\tordinary") == "日本語 café 😀\n\tordinary"

    assert Terminal.escape("\e]52;c;data\a\r\b\u009B\u202E\u2066\u200B\u034F\u2028") ==
             "\\u001b]52;c;data\\u0007\\u000d\\u0008\\u009b\\u202e\\u2066\\u200b\\u034f\\u2028"
  end

  test "split escape sequences and malformed binary output cannot execute controls" do
    assert Terminal.escape("\e") <> Terminal.escape("[8m") == "\\u001b[8m"
    assert Terminal.escape(<<0xFF, 0x9B, 0xE2, 0x80>>) == "\\xff\\x9b\\xe2\\x80"
    assert Terminal.escape("before" <> <<0xFF>> <> "after\e") == "before\\xffafter\\u001b"
  end

  test "UTF-8 output remains exact for Unicode and latin1 IO devices" do
    for encoding <- [:unicode, :latin1] do
      {:ok, device} = StringIO.open("", encoding: encoding)

      try do
        original = %{"text" => "雪 😀\u202E\u{E0001}"}
        assert :ok = Terminal.puts(device, Jason.encode!(original))
        assert :ok = Terminal.write(device, "雪\e")
        {_, output} = StringIO.contents(device)
        [json, text] = String.split(output, "\n", parts: 2)
        assert Jason.decode!(json) == original
        assert text == "雪\\u001b"

        previous = Process.group_leader()

        try do
          true = Process.group_leader(self(), device)
          assert :ok = Terminal.write("alias 雪")
          assert :ok = Terminal.puts("\e")
        after
          Process.group_leader(self(), previous)
        end

        assert {"", output <> "alias 雪\\u001b\n"} == StringIO.contents(device)
      after
        StringIO.close(device)
      end
    end
  end

  test "rendered JSON retains exact values including supplementary format characters" do
    original = %{"text\u202E" => "\e\n\t\u2028\u200B\u{E0001} 😀"}
    rendered = original |> Jason.encode!(pretty: true) |> Terminal.escape()
    assert Jason.decode!(rendered) == original
    refute rendered =~ "\u202E"
    refute rendered =~ "\u200B"
    refute rendered =~ "\u{E0001}"
    assert rendered =~ "\\udb40\\udc01"
  end

  test "complete worst-case native edit arguments fit the explicit display bound" do
    text = String.duplicate(<<1>>, 1_048_576)
    args = %{"path" => String.duplicate("p", 4096), "old" => text, "new" => text}

    assert {:ok, display} =
             Terminal.approval_display("edit", args, nil, "fresh", String.duplicate("c", 4096))

    assert byte_size(display) > 12 * 1_048_576
    assert byte_size(display) < 16 * 1_048_576
    assert display =~ Jason.encode!(args, pretty: true)
    assert display =~ "Type allow fresh"
  end

  test "exact escaped display limit is accepted and one further byte is refused whole" do
    assert {:ok, empty} =
             Terminal.approval_display("shell", %{"command" => ""}, nil, "fresh", "/tmp")

    count = Ipse.Runner.Operator.display_limit() - byte_size(empty)

    assert {:ok, display} =
             Terminal.approval_display(
               "shell",
               %{"command" => String.duplicate("x", count)},
               nil,
               "fresh",
               "/tmp"
             )

    assert byte_size(display) == Ipse.Runner.Operator.display_limit()

    assert {:error, :display_too_large} =
             Terminal.approval_display(
               "shell",
               %{"command" => String.duplicate("x", count + 1)},
               nil,
               "fresh",
               "/tmp"
             )
  end
end
