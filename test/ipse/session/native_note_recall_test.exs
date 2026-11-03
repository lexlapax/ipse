defmodule Ipse.Session.NativeNoteRecallTest do
  use ExUnit.Case, async: false

  @tag timeout: 90_000
  test "native reviewed notes respect competing context and withdraw after forget" do
    run("save")
  end

  @tag timeout: 90_000
  test "a collection change after recall is fenced before the provider request" do
    run("save_race")
  end

  @tag timeout: 300_000
  @tag :recall_many
  @tag skip:
         if(System.get_env("IPSE_TEST_RECALL_MANY") == "1",
           do: false,
           else: "multi-page native recall remains unqualified; opt in for the diagnostic"
         )
  test "a fresh Session recalls 33 short, natively reviewed notes" do
    run("recall-many")
  end

  defp run(mode) do
    root = Path.join(System.tmp_dir!(), "ipse-native-recall-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
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
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand(
              if(mode == "recall-many",
                do: "test/support/native_note_recall_many.exs",
                else: "test/support/native_note_recall.exs"
              )
            ),
            root,
            mode
          ],
        stderr_to_stdout: true
      )

    assert status == 0, String.slice(output, -8000, 8000)

    expected =
      case mode do
        "save_race" ->
          "NATIVE_NOTE_RECALL_RACE_PASSED"

        "recall-many" ->
          if(System.get_env("IPSE_RECALL_BASELINE_CONTROL") == "1",
            do: "NATIVE_NOTE_RECALL_BASELINE_PASSED",
            else: "NATIVE_NOTE_RECALL_MANY_PASSED"
          )

        _ ->
          "NATIVE_NOTE_RECALL_PASSED"
      end

    assert output =~ expected

    if mode == "save_race" do
      [_, outcome] =
        Regex.run(~r/NATIVE_NOTE_RECALL_RACE_PASSED (provider-withheld|no-dispatch)/, output)

      IO.puts("NATIVE_NOTE_RECALL_RACE #{outcome}")
    end
  end
end
