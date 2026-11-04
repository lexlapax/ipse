defmodule Ipse.Development.ManagedClockLifecycleTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 180_000
  @supported match?({:unix, :linux}, :os.type()) and
               String.contains?(to_string(:erlang.system_info(:system_architecture)), "x86_64") and
               String.contains?(to_string(:erlang.system_info(:system_architecture)), "gnu")
  unless @supported, do: @moduletag(skip: "requires Linux/glibc x86-64 process-clock fixture")
  @day 86_400_000

  test "native signed retention advances across fresh processes without rewriting original sources" do
    root =
      clocked_phases("ipse-native-clock-", [
        {0, "managed_clock_seed.exs", "current", "NATIVE_CLOCK_SEED_SHA256="},
        {30, "managed_clock_day.exs", "30", "NATIVE_CLOCK_DAY_PASSED=30"},
        {91, "managed_clock_day.exs", "91", "NATIVE_CLOCK_DAY_PASSED=91"},
        {366, "managed_clock_day.exs", "366", "NATIVE_CLOCK_DAY_PASSED=366"}
      ])

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

  @tag clock_late_supersession: true
  test "first native temporal supersession after day 90 retains then reclaims original support" do
    root =
      clocked_phases(
        "ipse-native-clock-late-",
        [
          {0, "managed_clock_late_seed.exs", "current", "NATIVE_CLOCK_LATE_SEED_PASSED"},
          {100, "managed_clock_late_day.exs", "100", "NATIVE_CLOCK_LATE_DAY_PASSED=100"},
          {366, "managed_clock_late_day.exs", "366", "NATIVE_CLOCK_LATE_DAY_PASSED=366"},
          {464, "managed_clock_late_day.exs", "464", "NATIVE_CLOCK_LATE_DAY_PASSED=464"},
          {466, "managed_clock_late_day.exs", "466", "NATIVE_CLOCK_LATE_DAY_PASSED=466"}
        ],
        stdio_clock: true
      )

    reports =
      for day <- [100, 366, 464, 466],
          do: root |> Path.join("clock-late-day-#{day}.json") |> File.read!() |> Jason.decode!()

    assert Enum.map(reports, & &1["day"]) == [100, 366, 464, 466]
    assert Enum.map(reports, &length(&1["expired_operations"])) == [0, 0, 0, 1]
    assert Enum.all?(reports, &(&1["first_supersession_after_day_90"] == true))
    assert Enum.all?(reports, &(&1["controlled_stdio_clock_propagation"] == true))
    assert Enum.all?(reports, &(&1["annual_workload_qualification"] == false))
    assert length(Enum.uniq(Enum.map(reports, & &1["source_sha256"]))) == 1
    assert length(Enum.uniq(Enum.map(reports, & &1["history_deadline_ms"]))) == 1
    refute File.exists?(Path.join(root, "unexpected-model"))
  end

  @tag clock_consent_renewal: true
  test "renewed native permission permits a later capture while preserving original evidence" do
    root =
      clocked_phases(
        "ipse-native-clock-renewal-",
        [
          {0, "managed_clock_late_seed.exs", "current", "NATIVE_CLOCK_LATE_SEED_PASSED"},
          {364, "managed_clock_renewal_day.exs", "364", "NATIVE_CLOCK_RENEWAL_PASSED=364"},
          {386, "managed_clock_renewal_day.exs", "386", "NATIVE_CLOCK_RENEWAL_PASSED=386"}
        ],
        stdio_clock: true
      )

    renewal = root |> Path.join("clock-renewal-364.json") |> File.read!() |> Jason.decode!()
    later = root |> Path.join("clock-renewal-386.json") |> File.read!() |> Jason.decode!()
    assert renewal["new_epoch"] == renewal["old_epoch"] + 1
    assert renewal["new_expiry_ms"] > renewal["old_expiry_ms"]
    assert later["at_ms"] > renewal["old_expiry_ms"]
    assert later["at_ms"] < renewal["new_expiry_ms"]
    assert later["source_sha256"] == renewal["source_sha256"]
    assert later["capture_settled"] == true
    assert later["annual_workload_qualification"] == false
    refute File.exists?(Path.join(root, "unexpected-model"))
  end

  @tag clock_consent_renewal: true
  test "expired native permission refuses its old policy without renewal" do
    root =
      clocked_phases(
        "ipse-native-clock-expired-",
        [
          {0, "managed_clock_late_seed.exs", "current", "NATIVE_CLOCK_LATE_SEED_PASSED"},
          {386, "managed_clock_renewal_day.exs", "expired", "NATIVE_CLOCK_RENEWAL_PASSED=386"}
        ],
        stdio_clock: true
      )

    refute File.exists?(Path.join(root, "unexpected-model"))
  end

  @tag clock_consent_recall: true
  test "a later synthetic provider request can receive a current note saved before renewal" do
    root =
      clocked_phases(
        "ipse-native-clock-renewal-recall-",
        [
          {0, "managed_clock_late_seed.exs", "current", "NATIVE_CLOCK_LATE_SEED_PASSED"},
          {364, "managed_clock_recall_renewal.exs", "364", "NATIVE_RENEWAL_RECALL_PASSED=364"},
          {386, "managed_clock_recall_renewal.exs", "386", "NATIVE_RENEWAL_RECALL_PASSED=386"}
        ],
        stdio_clock: true
      )

    report = root |> Path.join("clock-renewal-recall.json") |> File.read!() |> Jason.decode!()
    assert report["synthetic_requests"] == 2
    assert report["old_note_in_request"] == true
    assert report["missing_source_withheld"] == true
    assert report["annual_workload_qualification"] == false
  end

  defp clocked_phases(prefix, phases, options \\ []) do
    assert is_nil(System.get_env("IPSE_RUNNER_PATH"))
    root = Path.join(System.tmp_dir!(), prefix <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    IO.puts("NATIVE_CLOCK_LIFECYCLE_ROOT=" <> root)
    frozen_fixtures = Path.expand("../native-fixtures", __DIR__)
    library = Path.join(frozen_fixtures, "clock.so")
    driver = Path.join(frozen_fixtures, "pty")

    assert Ipse.JSON.sha256(File.read!(library)) ==
             "c9e614c891fb81661cdebba4b58ada033d39360451a743cc189f037aa0e8a7f2"

    assert Ipse.JSON.sha256(File.read!(driver)) ==
             "2d0c2e2009fe602103720743dac453aab2f15810831b6941533ee0816c1d59d2"

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

    paths =
      if options[:stdio_clock] do
        frozen_runtime = Path.expand("../../clock-runtime", __DIR__)
        manifest_path = Path.join(frozen_runtime, "clock-stdio-runtime.json")
        manifest = manifest_path |> File.read!() |> Jason.decode!()

        assert manifest["runner_beam_sha256"] ==
                 "d8ae01cdca58f3bf665b777bcb9f90604109da8267ec4ecf29f84415b24dc793"

        ebin = Path.join(frozen_runtime, "stdio-runtime/ipse/ebin")

        assert Ipse.JSON.sha256(File.read!(Path.join(ebin, "Elixir.Ipse.Runner.beam"))) ==
                 manifest["runner_beam_sha256"]

        assert Ipse.JSON.sha256(
                 File.read!(Path.join(frozen_runtime, "stdio-runtime/ipse/priv/ipse-runner"))
               ) == manifest["helper_sha256"]

        File.cp!(manifest_path, Path.join(root, "clock-stdio-runtime.json"))
        IO.puts("NATIVE_CLOCK_STDIO_RUNTIME=" <> ebin)
        paths ++ ["-pa", ebin]
      else
        paths
      end

    for {day, fixture, scenario, marker} <- phases do
      fixture_path =
        if fixture == "managed_clock_recall_renewal.exs",
          do: Path.join(__DIR__, "renewal-fixtures/" <> fixture),
          else: Path.expand("test/support/" <> fixture)

      {output, status} =
        System.cmd(
          driver,
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2 +C multi_time_warp"] ++
            paths ++ [fixture_path, root, scenario],
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
      if options[:stdio_clock], do: assert(output =~ "NATIVE_CLOCK_STDIO_COHERENT")
    end

    root
  end
end
