defmodule Ipse.Development.ManagedClockLifecycleTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 180_000
  @supported match?({:unix, :linux}, :os.type()) and
               String.contains?(to_string(:erlang.system_info(:system_architecture)), "x86_64") and
               String.contains?(to_string(:erlang.system_info(:system_architecture)), "gnu")
  unless @supported, do: @moduletag(skip: "requires Linux/glibc x86-64 process-clock fixture")
  @day 86_400_000

  test "native signed retention advances across fresh processes without rewriting original sources" do
    assert is_nil(System.get_env("IPSE_RUNNER_PATH"))
    root = Path.join(System.tmp_dir!(), "ipse-native-clock-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    IO.puts("NATIVE_CLOCK_LIFECYCLE_ROOT=" <> root)
    library = Path.join(root, "clock.so")
    driver = Path.join(root, "pty")

    for {source, flags} <- [
          {"dev/fixtures/process_clock.rs", ["--crate-type=cdylib", "-o", library]},
          {"test/support/operator_pty.rs", ["-o", driver]}
        ] do
      {output, status} =
        System.cmd("rustc", ["--edition=2021", "-D", "warnings", source] ++ flags,
          stderr_to_stdout: true
        )

      assert status == 0, output
    end

    for {label, path} <- [{"LIBRARY", library}, {"DRIVER", driver}] do
      IO.puts("NATIVE_CLOCK_#{label}_SHA256=" <> Ipse.JSON.sha256(File.read!(path)))
    end

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    for {day, fixture, scenario, marker} <- [
          {0, "managed_clock_seed.exs", "current", "NATIVE_CLOCK_SEED_SHA256="},
          {30, "managed_clock_day.exs", "30", "NATIVE_CLOCK_DAY_PASSED=30"},
          {91, "managed_clock_day.exs", "91", "NATIVE_CLOCK_DAY_PASSED=91"},
          {366, "managed_clock_day.exs", "366", "NATIVE_CLOCK_DAY_PASSED=366"}
        ] do
      {output, status} =
        System.cmd(
          driver,
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2 +C multi_time_warp"] ++
            paths ++ [Path.expand("test/support/" <> fixture), root, scenario],
          env: [
            {"LD_PRELOAD", library},
            {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(day * @day)},
            {"HOME", root},
            {"IPSE_HOME", Path.join(root, "home")},
            {"TMPDIR", root}
          ],
          stderr_to_stdout: true
        )

      log = Path.join(root, "clock-process-#{day}.log")
      File.write!(log, output, [:exclusive])
      File.chmod!(log, 0o600)
      assert status == 0, output
      assert output =~ marker
    end

    reports =
      for day <- [30, 91, 366],
          do: root |> Path.join("clock-day-#{day}.json") |> File.read!() |> Jason.decode!()

    assert Enum.map(reports, & &1["day"]) == [30, 91, 366]
    assert Enum.map(reports, &length(&1["expired_operations"])) == [0, 2, 1]
    assert Enum.map(reports, &length(&1["retention_operations"])) == [1, 0, 0]
    assert length(Enum.uniq(Enum.map(reports, & &1["source_sha256"]))) == 1
    assert Enum.all?(reports, &(&1["annual_workload_qualification"] == false))
    refute File.exists?(Path.join(root, "unexpected-model"))
  end
end
