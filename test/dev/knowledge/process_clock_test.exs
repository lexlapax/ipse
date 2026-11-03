Code.require_file("../../../dev/knowledge/native_notes_seed.ex", __DIR__)
Code.require_file("../../../dev/knowledge/native_notes_workload.ex", __DIR__)

defmodule Ipse.Development.ProcessClockTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 120_000
  @supported match?({:unix, :linux}, :os.type()) and
               String.contains?(to_string(:erlang.system_info(:system_architecture)), "x86_64") and
               String.contains?(to_string(:erlang.system_info(:system_architecture)), "gnu")
  unless @supported, do: @moduletag(skip: "requires Linux/glibc x86-64 process-clock fixture")
  @day 86_400_000

  setup_all do
    id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    root = Path.join(System.tmp_dir!(), "ipse-process-clock-" <> id)
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    library = Path.join(root, "clock.so")
    probe = Path.join(root, "probe")

    for {source, arguments} <- [
          {"dev/fixtures/process_clock.rs", ["--crate-type=cdylib", "-o", library]},
          {"test/support/process_clock_probe.rs", ["-o", probe]}
        ] do
      {output, status} =
        System.cmd("rustc", ["--edition=2021", "-D", "warnings", source] ++ arguments,
          stderr_to_stdout: true
        )

      assert status == 0, output
    end

    for {label, path} <- [{"LIBRARY", library}, {"PROBE", probe}] do
      digest = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
      IO.puts("PROCESS_CLOCK_#{label}_SHA256=#{digest}")
    end

    %{root: root, library: library, probe: probe}
  end

  test "fresh host and Rust child share day-zero and day-365 wall offsets with real timers",
       context do
    original_wall = System.system_time(:millisecond)

    for offset <- [
          0,
          999,
          1001,
          30 * @day,
          90 * @day,
          365 * @day,
          400 * @day,
          466 * @day,
          500 * @day
        ] do
      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            "--erl",
            "+S 2:2 +C multi_time_warp",
            Path.expand("dev/fixtures/process_clock_probe.exs"),
            context.probe
          ],
          env: environment(context, Integer.to_string(offset)),
          cd: context.root,
          stderr_to_stdout: true
        )

      assert status == 0, output

      values =
        output
        |> String.split("\n", trim: true)
        |> Map.new(fn line ->
          [key, value] = String.split(line, "=", parts: 2)
          {key, String.to_integer(value)}
        end)

      for key <- ~w(beam_wall_ms os_wall_ms) do
        # The BEAM observes its startup offset before the Rust child starts.
        assert values[key] <= values["raw_wall_after_ms"] + offset
        assert values[key] >= original_wall + offset
        assert values["raw_wall_before_ms"] + offset - values[key] < 10_000
      end

      assert values["beam_sleep_ms"] >= 60
      assert values["monotonic_sleep_ms"] >= 60
    end

    assert System.system_time(:millisecond) - original_wall < @day
  end

  test "absent, malformed, negative and excessive offsets refuse wall reads", context do
    for value <- [nil, "", "-1", "1x", "1.5", "99999999999999999999", "43200000001"] do
      {output, status} =
        System.cmd(context.probe, ["--invalid"],
          env: environment(context, value),
          cd: context.root,
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output == "invalid_offset_refused=1\n"
    end
  end

  test "a compensated day offset works in fresh BEAM and Rust processes", context do
    alias Ipse.Development.NativeNotesWorkload, as: Workload
    real_start = System.system_time(:millisecond)
    seed = real_start - 27 * 3_600_000
    previous = seed + 20 * @day
    assert {:ok, anchor} = Workload.clock_day(seed, 21, real_start, previous)
    assert anchor["offset_ms"] == 21 * @day - 27 * 3_600_000

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "--erl",
          "+S 2:2 +C multi_time_warp",
          Path.expand("dev/fixtures/process_clock_probe.exs"),
          context.probe
        ],
        env: environment(context, Integer.to_string(anchor["offset_ms"])),
        cd: context.root,
        stderr_to_stdout: true
      )

    assert status == 0, output

    values =
      output
      |> String.split("\n", trim: true)
      |> Map.new(fn line ->
        [key, value] = String.split(line, "=", parts: 2)
        {key, String.to_integer(value)}
      end)

    assert {:ok, after_probe} =
             Workload.clock_now(anchor, System.system_time(:millisecond), previous)

    for key <- ~w(beam_wall_ms os_wall_ms) do
      assert values[key] >= anchor["start_ms"]
      assert values[key] <= after_probe["virtual_ms"]
      assert after_probe["virtual_ms"] - values[key] < 10_000
    end
  end

  defp environment(context, offset) do
    [
      {"LD_PRELOAD", context.library},
      {"IPSE_TEST_CLOCK_OFFSET_MS", offset},
      {"HOME", context.root},
      {"IPSE_HOME", Path.join(context.root, "ipse")},
      {"TMPDIR", context.root}
    ]
  end
end
