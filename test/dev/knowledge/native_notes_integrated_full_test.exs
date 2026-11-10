Code.require_file("../../../dev/knowledge/native_notes_seed.ex", __DIR__)
Code.require_file("../../../dev/knowledge/native_notes_workload.ex", __DIR__)
Code.require_file("../../../dev/knowledge/native_notes_integrated_full.ex", __DIR__)

defmodule Ipse.Development.NativeNotesIntegratedFullTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.{NativeNotesIntegratedFull, NativeNotesWorkload}

  @tag timeout: 180_000
  test "the provisional first full-cohort day has 57 one-effect segments and 40 turns" do
    Process.flag(:max_heap_size, %{size: 64_000_000, kill: true, error_logger: true})
    plan = NativeNotesWorkload.calendar(20)
    day = hd(plan["days"])
    assert plan["intake_ratified"] == false
    assert day["process_offset_day"] == 21 and day["required_quota_excess"] == 0

    assert Enum.frequencies_by(day["actions"], & &1["reason"]) == %{
             "ordinary_additions" => 20,
             "ordinary_corrections" => 4,
             "explicit_forgets" => 2,
             "temporal_supersessions" => 4,
             "additional_churn" => 27
           }

    all_segments = NativeNotesWorkload.segments(plan, 1)
    assert length(all_segments) == 28_952
    digests = Map.new(all_segments, &{Integer.to_string(&1["index"]), Ipse.JSON.digest([&1])})
    segment_bytes = byte_size(Jason.encode!(all_segments))
    digest_bytes = byte_size(Jason.encode!(digests))
    {:memory, process_bytes} = Process.info(self(), :memory)

    IO.puts(
      "INTEGRATED_FULL_PLAN_SAMPLE segments=#{length(all_segments)} segment_bytes=#{segment_bytes} digest_bytes=#{digest_bytes} process_bytes=#{process_bytes}"
    )

    segments = Enum.take_while(all_segments, &(&1["process_offset_day"] == 21))

    assert length(segments) == 57
    assert Enum.all?(segments, &(length(&1["actions"]) == 1))
    schedule = NativeNotesIntegratedFull.full_schedule(21, length(segments))
    assert Enum.map(schedule, & &1["last_effect"]) == [14, 28, 42, 57]
    effects = Enum.flat_map(schedule, &Enum.to_list(&1["first_effect"]..&1["last_effect"]))
    turns = Enum.flat_map(schedule, &Enum.to_list(&1["first_turn"]..(&1["first_turn"] + 9)))
    assert effects == Enum.to_list(1..57)
    assert turns == Enum.to_list(1..40)
  end

  test "a prior intent or result prevents restarting the integrated day" do
    dir = Path.join(System.tmp_dir!(), "ipse-full-guard-#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    assert NativeNotesIntegratedFull.new_run?(dir)

    for name <-
          ~w(run-intent.json effect-1-intent.json effect-1-result.json turn-1-intent.json turn-1-result.json complete.json) do
      File.write!(Path.join(dir, name), "{}")
      refute NativeNotesIntegratedFull.new_run?(dir)
      File.rm!(Path.join(dir, name))
    end
  end

  # This is a safety guard, not an estimate. A timeout leaves the retained run
  # interrupted/unknown; inspect process state and markers without replaying it.
  @tag timeout: 43_200_000
  @tag :native_integrated_full
  @tag skip:
         if(System.get_env("IPSE_TEST_INTEGRATED_FULL") == "1",
           do: false,
           else: "full 2,000-note native fixture is an explicit opt-in"
         )
  test "a fresh full cohort runs one provisional day and retains its evidence" do
    # Turnover requires every seed operation to precede the first quota period,
    # which begins at the first UTC midnight after the seed starts (shifted by
    # the seeded days). The seed takes over two hours, so refuse a late start
    # instead of failing after seeding.
    day = 86_400_000
    now = System.system_time(:millisecond)

    assert day - rem(now, day) >= 6 * 3_600_000,
           "start the full cohort at least six hours before the next UTC midnight"

    root = Path.join("/tmp", "ipse-native-seed-integrated-full-#{Ipse.Usage.id()}")
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    :ok = :gen_tcp.close(listener)

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    script = Path.expand("dev/knowledge/native_notes_integrated_full.exs")

    run = fn args ->
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++ paths ++ [script] ++ args,
        stderr_to_stdout: true
      )
    end

    IO.puts("NATIVE_INTEGRATED_FULL_ROOT=#{root}")
    {prepared, 0} = run.(["--prepare", root, Integer.to_string(port)])
    assert prepared =~ "NATIVE_INTEGRATED_INITIAL_PREPARED"
    {completed, 0} = run.(["--run", root])
    assert completed =~ "NATIVE_INTEGRATED_INITIAL_COMPLETED turns=40 effects=57"

    dir = Path.join(root, "integrated-full")
    complete_path = Path.join(dir, "complete.json")
    complete_bytes = File.read!(complete_path)
    complete = Jason.decode!(complete_bytes)
    assert complete["turns"] == 40 and complete["native_effects"] == 57
    assert complete["qualification"] == false and complete["fixture_provider_cost_usd"] == 0
    assert length(Path.wildcard(Path.join(dir, "effect-*-intent.json"))) == 57
    assert length(Path.wildcard(Path.join(dir, "effect-*-result.json"))) == 57
    assert length(Path.wildcard(Path.join(dir, "turn-*-result.json"))) == 40
    assert Path.wildcard(Path.join(dir, "turn-*-inflight.json")) == []
    {refused, status} = run.(["--run", root])
    assert status != 0 and refused =~ "inspect retained evidence and do not replay"
    assert File.read!(complete_path) == complete_bytes
    assert File.dir?(root)
  end
end
