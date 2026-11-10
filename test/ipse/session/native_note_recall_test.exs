defmodule Ipse.Session.NativeNoteRecallTest do
  use ExUnit.Case, async: false

  @tag timeout: 90_000
  @tag :native_storage
  test "native reviewed notes respect competing context and withdraw after forget" do
    run("save")
  end

  @tag timeout: 90_000
  @tag :native_storage
  test "a collection change after recall is fenced before the provider request" do
    run("save_race")
  end

  @tag timeout: 90_000
  @tag :native_storage
  test "worker input reuses native record results only at an identical root" do
    run("save_reuse")
  end

  # The second runtime starts with its wall clock twenty seconds before the
  # only note deadline; dev/fixtures/process_clock.rs fixes that offset
  # before the runtime starts.
  @tag timeout: 180_000
  @tag :native_storage
  test "a remembered record that expires at an unchanged root withholds worker input" do
    {root, paths} = run("save_reuse_seed")
    library = Path.join(root, "clock.so")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "dev/fixtures/process_clock.rs"] ++
                 ["--crate-type=cdylib", "-o", library],
               stderr_to_stdout: true
             )

    %{"dependencies" => dependencies} =
      root |> Path.join("reuse-expiry.json") |> File.read!() |> Jason.decode!()

    assert [deadline] =
             for(
               dependency <- dependencies,
               value = get_in(dependency, ["subject", "validity", "valid_until_ms"]),
               is_integer(value),
               do: value
             )

    offset = deadline - System.system_time(:millisecond) - 20_000
    assert offset > 0

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++
          paths ++ [Path.expand("test/support/native_recall_reuse_expiry.exs"), root],
        stderr_to_stdout: true,
        env: [{"LD_PRELOAD", library}, {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(offset)}]
      )

    assert status == 0, String.slice(output, -8000, 8000)
    assert output =~ "NATIVE_NOTE_RECALL_REUSE_EXPIRY_PASSED"
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

  @tag timeout: 300_000
  @tag :recall_many
  @tag skip:
         if(System.get_env("IPSE_TEST_RECALL_MANY") == "1",
           do: false,
           else: "multi-page native recall remains unqualified; opt in for the diagnostic"
         )
  test "a fresh Session reaches an eligible note after unavailable indexed sources" do
    run("recall-many", sparse: true)
  end

  @tag timeout: 300_000
  @tag :recall_many
  @tag skip:
         if(System.get_env("IPSE_TEST_RECALL_MANY") == "1",
           do: false,
           else: "multi-page native recall remains unqualified; opt in for the diagnostic"
         )
  test "a source reappearing before model preflight leaves coverage explicitly partial" do
    run("recall-many", sparse: true, reappear: true)
  end

  @tag timeout: 600_000
  @tag :recall_many
  @tag skip:
         if(System.get_env("IPSE_TEST_RECALL_MANY") == "1",
           do: false,
           else: "multi-page native recall remains unqualified; opt in for the diagnostic"
         )
  test "one turn over 64 distinct literals completes on every path that reads them all" do
    run("recall-many", notes: 64)
  end

  defp run(mode, opts \\ []) do
    root = Path.join(System.tmp_dir!(), "ipse-native-recall-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    if System.get_env("IPSE_TEST_NOTE_RECALL_KEEP") == "1",
      do: IO.puts("NATIVE_NOTE_RECALL_FIXTURE #{root}"),
      else: on_exit(fn -> File.rm_rf!(root) end)

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
        stderr_to_stdout: true,
        env: [
          {"IPSE_TEST_RECALL_SPARSE", if(opts[:sparse], do: "1", else: "0")},
          {"IPSE_TEST_RECALL_REAPPEAR", if(opts[:reappear], do: "1", else: "0")},
          {"IPSE_TEST_RECALL_NOTES", Integer.to_string(opts[:notes] || 33)}
        ]
      )

    assert status == 0, String.slice(output, -8000, 8000)

    expected =
      case mode do
        "save_race" ->
          "NATIVE_NOTE_RECALL_RACE_PASSED"

        "save_reuse" ->
          "NATIVE_NOTE_RECALL_REUSE_PASSED"

        "save_reuse_seed" ->
          "NATIVE_NOTE_RECALL_REUSE_SEEDED"

        "recall-many" ->
          "NATIVE_NOTE_RECALL_MANY_PASSED"

        _ ->
          "NATIVE_NOTE_RECALL_PASSED"
      end

    assert output =~ expected

    if mode == "save_race" do
      [_, outcome] =
        Regex.run(~r/NATIVE_NOTE_RECALL_RACE_PASSED (provider-withheld|no-dispatch)/, output)

      IO.puts("NATIVE_NOTE_RECALL_RACE #{outcome}")
    end

    {root, paths}
  end
end
