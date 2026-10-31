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
          [Path.expand("test/support/native_note_recall.exs"), root, mode],
        stderr_to_stdout: true
      )

    assert status == 0, output

    assert output =~
             if(mode == "save_race",
               do: "NATIVE_NOTE_RECALL_RACE_PASSED",
               else: "NATIVE_NOTE_RECALL_PASSED"
             )

    if mode == "save_race" do
      [_, outcome] =
        Regex.run(~r/NATIVE_NOTE_RECALL_RACE_PASSED (provider-withheld|no-dispatch)/, output)

      IO.puts("NATIVE_NOTE_RECALL_RACE #{outcome}")
    end
  end
end
