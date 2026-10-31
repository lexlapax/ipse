defmodule Ipse.Session.NativeNoteRecallTest do
  use ExUnit.Case, async: false

  @tag timeout: 90_000
  test "native reviewed notes reach the first registered inference body and withdraw after forget" do
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
          [Path.expand("test/support/native_note_recall.exs"), root, "save"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "NATIVE_NOTE_RECALL_PASSED"
  end
end
