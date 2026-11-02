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
             "elapsed_cleanup" => 6859
           }

    assert plan["initial_plus_scheduled_publications"] == length(actions) + 2100
    assert plan["initial_plus_scheduled_publications"] == 29_939
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
          assert target.deadline_day == target.admitted_day + 90
          assert target.deadline_day == action["history_deadline_day"]
          assert target.deadline_day > day["process_offset_day"]

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

  test "retained anchors and live rows rule out this working calendar before native execution", %{
    plan: plan
  } do
    assert plan["metadata_row_capacity_upper_bounds"] == %{"anchor" => 122, "live" => 26}
    assert plan["maximum_public_note_records"] == 8012
    assert plan["minimum_peak_collection_records"] > plan["collection_record_limit"]
    assert plan["collection_record_limit_excess_lower_bound"] > 0
    assert plan["storage_fit"] == "ruled_out_by_minimum_record_count_for_this_working_calendar"
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

  test "out-of-contract intake cannot silently lower useful capture" do
    for value <- [nil, 0, 19, 321, 20.0, "20"] do
      assert_raise FunctionClauseError, fn -> Workload.calendar(value) end
    end
  end
end
