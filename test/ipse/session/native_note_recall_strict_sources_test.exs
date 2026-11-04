defmodule Ipse.Session.NativeNoteStrictSourcesRecallTest do
  use ExUnit.Case, async: false

  @tag timeout: 300_000
  @tag :recall_many
  @tag :recall_strict_sources
  @tag skip:
         if(System.get_env("IPSE_TEST_RECALL_MANY") == "1",
           do: false,
           else: "opt in to the 33-original native recall control with IPSE_TEST_RECALL_MANY=1"
         )
  test "32 exact notes remain eligible when one of 33 original sources reappears before preflight" do
    run()
  end

  defp run do
    root = Path.join(System.tmp_dir!(), "ipse-native-recall-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    IO.puts("STRICT_RECALL_FRESH_ROOT=" <> root)
    operator_home = Path.join(root, "operator-home")
    File.mkdir!(operator_home)
    File.chmod!(operator_home, 0o700)
    if System.get_env("IPSE_TEST_RECALL_KEEP") != "1", do: on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.expand("../../support/operator_pty.rs", __DIR__),
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
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand(
              "../../support/native_note_recall_many.exs",
              __DIR__
            ),
            root,
            "recall-many"
          ],
        stderr_to_stdout: true,
        env: [
          {"HOME", operator_home},
          {"IPSE_TEST_RECALL_STRICT_SOURCES", "1"},
          {"IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS", "5000"},
          {"IPSE_TEST_RECALL_TIMING", "0"},
          {"IPSE_TEST_RECALL_SPARSE", "1"},
          {"IPSE_TEST_RECALL_REAPPEAR", "1"}
        ]
      )

    assert status == 0, String.slice(output, -8000, 8000)

    assert output =~ "NATIVE_NOTE_RECALL_MANY_PASSED"

    assert output =~
             "NATIVE_NOTE_RECALL_STRICT_SOURCES_PASSED originals=33 unavailable=1 reads=32 included=32 structured_parts=verified original_bytes_and_lock_identity=unchanged idle_intents=unchanged"
  end
end
