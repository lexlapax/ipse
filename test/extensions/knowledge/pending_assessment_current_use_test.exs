defmodule IpseKnowledge.PendingAssessmentCurrentUseTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  @moduletag timeout: 180_000
  @day 86_400_000

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-pending-current-use-" <> Ipse.Usage.id())

    build =
      Path.join(File.cwd!(), "_build/verification/pending-current-use-build-" <> Ipse.Usage.id())

    File.mkdir_p!(Path.dirname(build))

    for path <- [root, build] do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    IO.puts("PENDING_CURRENT_USE_ROOT=" <> root)
    IO.puts("PENDING_CURRENT_USE_BUILD=" <> build)
    driver = Path.join(build, "pty")
    compile!("test/support/operator_pty.rs", ["-o", driver])

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    %{root: root, build: build, driver: driver, paths: paths}
  end

  @tag p30_pending_output_revocation: true
  test "revocation after settled assessment withholds advice and preserves its real charge", c do
    output = run!(c, "save_managed_approval_output_revoked", c.paths, [])
    assert output =~ "SHADOW_EXPERIMENT_SESSION_PASSED"
    refute output =~ ~r/"note_mutation"\s*:\s*"none"/
    refute output =~ ~S(\"note_mutation\":\"none\")
  end

  @tag p30_pending_own_deadline: true
  test "a fresh day-eight grant cannot release the actual proposal past its signed seven-day deadline",
       c do
    library = Path.join(c.build, "clock.so")
    compile!("dev/fixtures/process_clock.rs", ["--crate-type=cdylib", "-o", library])
    helper = Path.expand("../../support/managed_clock_lifecycle.exs", __DIR__)
    script = "Ipse.Test.ManagedClockLifecycle.prepare_stdio_clock(System.argv())"

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 1:1 +A 1"] ++
          c.paths ++
          ["-r", helper, "-e", script, c.build, Application.app_dir(:ipse, "ebin")],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
    assert output =~ "NATIVE_CLOCK_STDIO_RUNTIME="

    File.cp!(
      Path.join(c.build, "clock-stdio-runtime.json"),
      Path.join(c.root, "clock-stdio-runtime.json")
    )

    paths = c.paths ++ ["-pa", Path.join(c.build, "stdio-runtime/ipse/ebin")]

    for {day, scenario, marker} <- [
          {0, "save_managed_approval_pending_deadline_seed",
           "PENDING_PROPOSAL_OWN_DEADLINE_SEED_PASSED"},
          {8, "save_managed_approval_pending_deadline_expired",
           "PENDING_PROPOSAL_OWN_DEADLINE_EXPIRED_PASSED"}
        ] do
      output =
        run!(c, scenario, paths, [
          {"LD_PRELOAD", library},
          {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(day * @day)},
          {"HOME", c.root},
          {"IPSE_HOME", Path.join(c.root, "home")},
          {"TMPDIR", c.root}
        ])

      assert output =~ marker
      assert output =~ "NATIVE_CLOCK_STDIO_COHERENT"
    end
  end

  defp compile!(source, flags) do
    {output, status} =
      System.cmd("rustc", ["--edition=2021", "-D", "warnings", source] ++ flags,
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp run!(c, scenario, paths, env) do
    fixture = Path.expand("../../support/shadow_pending_candidate_cli.exs", __DIR__)

    {output, status} =
      System.cmd(
        c.driver,
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2 +C multi_time_warp"] ++
          paths ++ [fixture, c.root, scenario],
        env: env,
        stderr_to_stdout: true
      )

    path = Path.join(c.build, scenario <> ".private.log")
    File.write!(path, output, [:exclusive])
    File.chmod!(path, 0o600)

    assert status == 0,
           "Synthetic fixture root: #{c.root}; retained private log: #{path}; child exit: #{status}"

    output
  end
end
