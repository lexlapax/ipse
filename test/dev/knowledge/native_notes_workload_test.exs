Code.require_file("../../../dev/knowledge/native_notes_seed.ex", __DIR__)
Code.require_file("../../../dev/knowledge/native_notes_workload.ex", __DIR__)

defmodule Ipse.Development.NativeNotesWorkloadTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.NativeNotesWorkload, as: Workload

  setup_all do
    %{plan: Workload.calendar(20)}
  end

  test "the selected total is balanced across the year without replacing ordinary work", %{
    plan: plan
  } do
    assert length(plan["days"]) == 365
    actions = Enum.flat_map(plan["days"], & &1["actions"])
    churn = Enum.filter(actions, &(&1["reason"] == "additional_churn"))
    assert length(churn) == 10_000

    assert Enum.frequencies_by(churn, & &1["op"]) == %{
             "update" => 3334,
             "correct" => 3333,
             "forget" => 3333
           }

    assert plan["annual_publications_by_effect"] == %{
             "ordinary_additions" => 7320,
             "ordinary_corrections" => 1464,
             "explicit_forgets" => 732,
             "temporal_supersessions" => 1464,
             "additional_churn" => 10_000,
             "elapsed_cleanup" => 7972
           }

    assert plan["initial_plus_scheduled_publications"] == length(actions) + 2100
    assert plan["initial_plus_scheduled_publications"] == 31_052
    assert plan["main_turns"] == 14_600
    assert Enum.map(plan["days"], & &1["process_offset_day"]) == Enum.to_list(21..385)
    assert Enum.all?(plan["days"], &(&1["main_turns"] == 40))
    assert Enum.all?(plan["days"], &(&1["scheduled_publications"] <= 100))
    burst = Enum.at(plan["days"], 89)
    assert burst["ordinary_intake"] == 40
    assert Enum.count(burst["actions"], &(&1["reason"] == "ordinary_corrections")) == 8
    assert Enum.count(burst["actions"], &(&1["reason"] == "explicit_forgets")) == 4
    assert Enum.count(burst["actions"], &(&1["reason"] == "temporal_supersessions")) == 8
  end

  test "each alias is created once and removed once with the original clocks retained", %{
    plan: plan
  } do
    records = plan["final_records"]
    actions = Enum.flat_map(plan["days"], & &1["actions"])
    additions = Enum.filter(actions, &Map.has_key?(&1, "result"))
    assert length(Enum.uniq_by(additions, & &1["result"])) == length(additions)
    removals = Enum.filter(actions, &(&1["op"] in ~w(forget expire)))
    assert length(Enum.uniq_by(removals, & &1["target"])) == length(removals)
    assert map_size(records) == 18_915

    for day <- plan["days"], action <- day["actions"] do
      case action["op"] do
        "expire" ->
          target = Map.fetch!(records, action["target"])
          assert target.deadline_day == action["deadline_day"]
          assert target.deadline_day < day["process_offset_day"]
          assert target.present == false and target.status == "reclaimed"

        "forget" ->
          target = Map.fetch!(records, action["target"])
          assert target.category == "ordinary"
          assert target.deadline_day > day["process_offset_day"]
          assert target.present == false and target.status == "forgotten"

        "correct" ->
          target = Map.fetch!(records, action["target"])
          assert target.category == "history" and is_nil(target.slot)
          assert target.deadline_day <= target.admitted_day + 90
          assert target.deadline_day == action["history_deadline_day"]
          assert target.deadline_day > day["process_offset_day"]
          replacement = Map.fetch!(records, action["result"])
          assert replacement.deadline_day == target.deadline_day

        "update" ->
          target = Map.fetch!(records, action["target"])
          assert target.category == "history" and target.slot in 151..200
          assert target.present
          assert target.deadline_day == day["process_offset_day"] + 365
          assert target.deadline_day == action["history_deadline_day"]

        "capture" ->
          assert action["category"] == "ordinary"
      end
    end

    assert Enum.any?(actions, fn action ->
             action["op"] == "correct" and
               Map.fetch!(records, action["result"]).deadline_day <
                 Map.fetch!(records, action["result"]).admitted_day + 90
           end)
  end

  test "persistent slots and the first post-day-90 update survive daily churn", %{plan: plan} do
    updates =
      for day <- plan["days"],
          action <- day["actions"],
          action["target"] == "seed/200",
          do: {day, action}

    assert [{day, %{"op" => "update"}}] = updates
    assert day["day"] == 100
    assert day["process_offset_day"] > 90
    assert plan["final_records"]["seed/200"].deadline_day == 485

    for day <- plan["days"] do
      assert day["public_categories_after_day"]["pin"] == 100
      assert day["public_categories_after_day"]["preference"] == 50
      assert day["public_categories_after_day"]["current"] == 50
    end
  end

  test "retained anchors and live rows bound but do not qualify the working calendar", %{
    plan: plan
  } do
    assert plan["metadata_row_capacity_upper_bounds"] == %{"anchor" => 122, "live" => 26}
    assert plan["maximum_public_note_records"] == 6903
    assert plan["minimum_peak_collection_records"] == 7326
    assert plan["minimum_peak_collection_records"] < plan["collection_record_limit"]
    assert plan["collection_record_limit_excess_lower_bound"] == 0

    assert plan["storage_fit"] ==
             "unverified: excludes actual signed-page and retained-operation geometry"

    assert plan["maximum_value_payload_bytes_at_public_peak"] > plan["logical_record_byte_limit"]
    assert plan["actual_native_operations"] == 0
    assert plan["actual_turns"] == 0
    assert plan["qualification_passed"] == false
    assert plan["intake_ratified"] == false
    assert "compaction" in plan["unplanned_requirements"]
    assert "consent_renewal" in plan["unplanned_requirements"]
  end

  test "higher intake reports an impossible burst instead of trimming required actions" do
    plan = Workload.calendar(40)
    burst = Enum.at(plan["days"], 89)
    assert burst["ordinary_intake"] == 80
    assert burst["required_publications"] == 127
    assert burst["required_quota_excess"] == 27
    assert burst["scheduled_publications"] == 127
    assert plan["all_required_days_fit_operation_limit"] == false
    assert plan["actual_native_operations"] == 0
  end

  test "bounded segments preserve the full calendar and resolve targets only after a prior segment",
       %{
         plan: plan
       } do
    segments = Workload.segments(plan, 4)
    assert Enum.map(segments, & &1["index"]) == Enum.to_list(1..length(segments))

    assert Enum.flat_map(segments, & &1["actions"]) ==
             Enum.flat_map(plan["days"], & &1["actions"])

    known = MapSet.new(1..2000, &"seed/#{&1}")

    Enum.reduce(segments, known, fn segment, known ->
      assert length(segment["actions"]) in 1..4
      assert segment["daily_required_quota_excess"] == 0

      for action <- segment["actions"], is_binary(action["target"]) do
        assert MapSet.member?(known, action["target"])
      end

      Enum.reduce(segment["actions"], known, fn action, acc ->
        if is_binary(action["result"]), do: MapSet.put(acc, action["result"]), else: acc
      end)
    end)
  end

  test "segmentation preserves an over-quota day for the caller to refuse" do
    plan = Workload.calendar(40)
    burst = Enum.filter(Workload.segments(plan, 8), &(&1["day"] == 90))
    assert Enum.all?(burst, &(&1["daily_required_quota_excess"] == 27))
    assert burst |> Enum.flat_map(& &1["actions"]) |> length() == 127
  end

  test "a chain of newly created targets waits for separate segment closures" do
    actions = [
      %{"op" => "capture", "result" => "a"},
      %{"op" => "correct", "target" => "a", "result" => "b"},
      %{"op" => "forget", "target" => "b"}
    ]

    plan = %{
      "kind" => "native_annual_action_calendar",
      "days" => [
        %{
          "day" => 1,
          "process_offset_day" => 21,
          "required_quota_excess" => 0,
          "actions" => actions
        }
      ]
    }

    assert Enum.map(Workload.segments(plan, 8), & &1["actions"]) ==
             Enum.map(actions, &[&1])
  end

  test "fixture-clock days compensate elapsed real time and retain one offset on restart" do
    day_ms = 86_400_000
    seed = 1_800_000_000_000
    real_start = seed + 3 * 3_600_000
    previous = seed + 20 * day_ms + 2 * 3_600_000

    assert {:ok, first} = Workload.clock_day(seed, 21, real_start, previous)
    assert first["start_ms"] == seed + 21 * day_ms
    assert first["offset_ms"] == 21 * day_ms - 3 * 3_600_000

    assert {:ok, one} = Workload.clock_now(first, real_start + 3_600_000, previous)
    assert one["virtual_ms"] == first["start_ms"] + 3_600_000

    assert {:ok, resumed} =
             Workload.clock_now(first, real_start + 12 * 3_600_000, one["virtual_ms"])

    assert resumed["offset_ms"] == first["offset_ms"]
    assert resumed["virtual_ms"] == first["start_ms"] + 12 * 3_600_000

    assert {:ok, second} =
             Workload.clock_day(seed, 22, real_start + 12 * 3_600_000, resumed["virtual_ms"])

    assert second["start_ms"] == seed + 22 * day_ms
    assert second["offset_ms"] == 22 * day_ms - 15 * 3_600_000
  end

  test "fixture-clock planning refuses backward time, a day overflow and unsupported offsets" do
    day_ms = 86_400_000
    seed = 1_800_000_000_000
    real_start = seed + 3_600_000
    prior = seed + 20 * day_ms
    assert {:ok, anchor} = Workload.clock_day(seed, 21, real_start, prior)
    assert {:error, :fixture_clock_refused} = Workload.clock_now(anchor, real_start - 1, prior)

    assert {:error, :fixture_clock_refused} =
             Workload.clock_now(anchor, real_start + day_ms, prior)

    assert {:error, :fixture_clock_refused} =
             Workload.clock_now(anchor, real_start, anchor["start_ms"] + 1)

    assert {:error, :fixture_clock_refused} = Workload.clock_now(anchor, real_start, prior - 1)

    assert {:error, :fixture_clock_refused} =
             Workload.clock_now(Map.put(anchor, "offset_ms", 0), real_start, prior)

    assert {:error, :fixture_clock_refused} =
             Workload.clock_day(seed, 21, seed + 22 * day_ms, prior)

    assert {:error, :fixture_clock_refused} =
             Workload.clock_day(seed, 21, real_start, anchor["start_ms"])

    assert {:error, :fixture_clock_refused} = Workload.clock_day(seed, 501, real_start, prior)
  end

  test "out-of-contract intake cannot silently lower useful capture" do
    for value <- [nil, 0, 19, 321, 20.0, "20"] do
      assert_raise FunctionClauseError, fn -> Workload.calendar(value) end
    end

    for limit <- [0, 9, 4.0, "4"] do
      assert_raise FunctionClauseError, fn ->
        Workload.segments(%{"kind" => "native_annual_action_calendar", "days" => []}, limit)
      end
    end
  end
end
