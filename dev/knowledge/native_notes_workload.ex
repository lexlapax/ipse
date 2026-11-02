defmodule Ipse.Development.NativeNotesWorkload do
  @moduledoc "Pure action calendar for the native annual driver; aliases are expected fixture data, never authority."
  alias Ipse.Development.NativeNotesSeed, as: Seed
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.ManagedPages
  @days 365
  @changes 10_000
  @daily_limit 100
  @ordinary_days 90
  @history_days 365

  def calendar(intake) when is_integer(intake) and intake in 20..320 do
    seed = Seed.plan("initial")
    last_seed_day = List.last(seed)["day"]
    initial_actions = Enum.flat_map(seed, & &1["actions"])
    initial_publications = length(initial_actions)
    initial_pins = Enum.count(initial_actions, &(&1["op"] == "pin"))

    initial =
      Enum.reduce(seed, %{}, fn segment, records ->
        Enum.reduce(segment["actions"], records, fn action, records ->
          id = "seed/#{action["number"]}"

          case action["op"] do
            "capture" ->
              slot = if action["category"] == "current", do: action["number"]
              Map.put(records, id, record(id, action["category"], segment["day"], slot))

            "pin" ->
              Map.update!(records, id, &Map.merge(&1, %{category: "pin", deadline_day: nil}))
          end
        end)
      end)

    state = %{
      records: %{},
      ordinary: :gb_sets.empty(),
      expiry: :gb_sets.empty(),
      current: %{},
      temporal_cursor: 0,
      serial: 0,
      totals: %{},
      max_public: 0,
      max_collection_records: 0,
      present_count: 0
    }

    state = Enum.reduce(initial, state, fn {_, record}, state -> put(state, record) end)

    {days, state} =
      Enum.map_reduce(1..@days, state, fn day, state ->
        date = last_seed_day + day
        burst = if day == 90, do: 2, else: 1
        count = div(day * @changes, @days) - div((day - 1) * @changes, @days)
        first_change = div((day - 1) * @changes, @days)

        required =
          List.duplicate({"capture", "ordinary_additions"}, intake * burst) ++
            List.duplicate({"correct", "ordinary_corrections"}, 4 * burst) ++
            List.duplicate({"forget", "explicit_forgets"}, 2 * burst) ++
            List.duplicate({"update", "temporal_supersessions"}, 4 * burst) ++
            Enum.map((first_change + 1)..(first_change + count), fn index ->
              {Enum.at(~w(update correct forget), rem(index - 1, 3)), "additional_churn"}
            end)

        {actions, state} =
          Enum.map_reduce(required, state, fn {op, reason}, state ->
            effect(state, op, reason, day, date)
          end)

        # Reclaim only after the entire possible admission day plus 90 days.
        # The live driver must still authenticate the actual signed deadline.
        {expired_count, cleanup} =
          due(
            :gb_sets.iterator(state.expiry),
            date,
            max(@daily_limit - length(actions), 0),
            0,
            []
          )

        {cleanup_actions, state} =
          Enum.map_reduce(cleanup, state, fn id, state ->
            target = Map.fetch!(state.records, id)

            action = %{
              "op" => "expire",
              "reason" => "elapsed_cleanup",
              "target" => target.id,
              "deadline_day" => target.deadline_day
            }

            {action, remove(state, target, "reclaimed") |> count("elapsed_cleanup")}
          end)

        actions = actions ++ cleanup_actions
        present = Enum.filter(Map.values(state.records), & &1.present)

        {%{
           "day" => day,
           "process_offset_day" => date,
           "main_turns" => 40,
           "ordinary_intake" => intake * burst,
           "actions" => actions,
           "required_publications" => length(required),
           "scheduled_publications" => length(actions),
           "daily_operation_limit" => @daily_limit,
           "required_quota_excess" => max(length(required) - @daily_limit, 0),
           "eligible_cleanup_backlog" => expired_count - length(cleanup),
           "public_note_records_after_day" => length(present),
           "retained_anchor_lineages_after_day" => map_size(state.records),
           "minimum_collection_records_after_day" => minimum_records(state),
           "public_categories_after_day" => Enum.frequencies_by(present, & &1.category)
         }, state}
      end)

    %{
      "version" => 1,
      "kind" => "native_annual_action_calendar",
      "ordinary_intake_per_day" => intake,
      "intake_ratified" => false,
      "initial_publications" => initial_publications,
      "initial_pin_publications" => initial_pins,
      "initial_last_process_day" => last_seed_day,
      "additional_mixed_changes" => @changes,
      "additional_mix" => %{"update" => 3334, "correct" => 3333, "forget" => 3333},
      "additional_mix_scope" =>
        "balanced working fixture selection, not a developer-specified ratio",
      "main_turns" => @days * 40,
      "days" => days,
      "annual_publications_by_effect" => state.totals,
      "initial_plus_scheduled_publications" =>
        initial_publications + Enum.sum(Map.values(state.totals)),
      "maximum_public_note_records" => state.max_public,
      "minimum_peak_collection_records" => state.max_collection_records,
      "collection_record_limit" => Collection.limits()["records"],
      "collection_record_limit_excess_lower_bound" =>
        max(state.max_collection_records - Collection.limits()["records"], 0),
      "metadata_row_capacity_upper_bounds" => %{
        "anchor" => page_capacity(:anchor),
        "live" => page_capacity(:live)
      },
      "final_retained_anchor_lineages" => map_size(state.records),
      "maximum_value_payload_bytes_at_public_peak" =>
        state.max_public * Collection.limits()["value_bytes"],
      "payload_bound_scope" =>
        "Public record count times the profile value ceiling; no maximum-payload source or signed record produced",
      "logical_record_byte_limit" => Collection.limits()["data_bytes"],
      "final_records" => state.records,
      "all_required_days_fit_operation_limit" =>
        Enum.all?(days, &(&1["required_quota_excess"] == 0)),
      "unplanned_requirements" =>
        ~w(offline_week concurrent_owners imports compaction consent_renewal proposal_burst maximum_payload resource_peaks independent_quality),
      "storage_fit" =>
        if(state.max_collection_records > Collection.limits()["records"],
          do: "ruled_out_by_minimum_record_count_for_this_working_calendar",
          else: "unverified: excludes actual signed-page and retained-operation geometry"
        ),
      "actual_native_operations" => 0,
      "actual_turns" => 0,
      "qualification_passed" => false
    }
  end

  defp record(id, category, day, slot \\ nil) do
    %{
      id: id,
      category: category,
      admitted_day: day,
      deadline_day: if(category == "ordinary", do: day + @ordinary_days),
      present: true,
      status: "current",
      slot: slot
    }
  end

  defp effect(state, "capture", reason, day, date) do
    {id, state} = next(state, day, "capture")
    state = put(state, record(id, "ordinary", date)) |> count(reason)
    {%{"op" => "capture", "reason" => reason, "result" => id, "category" => "ordinary"}, state}
  end

  defp effect(state, "correct", reason, day, date) do
    {target, state} = ordinary(state, date)
    {id, state} = next(state, day, "correct")
    state = put(state, %{target | status: "history", category: "history"})
    state = put(state, record(id, "ordinary", date)) |> count(reason)

    {%{
       "op" => "correct",
       "reason" => reason,
       "target" => target.id,
       "result" => id,
       "history_deadline_day" => target.deadline_day
     }, state}
  end

  defp effect(state, "forget", reason, _day, date) do
    {target, state} = ordinary(state, date)

    {%{"op" => "forget", "reason" => reason, "target" => target.id},
     remove(state, target, "forgotten") |> count(reason)}
  end

  defp effect(state, "update", reason, day, date) do
    available =
      state.current
      |> Map.values()
      |> Enum.map(&Map.fetch!(state.records, &1))
      |> Enum.filter(&(day >= 100 or &1.slot != 200))
      |> Enum.sort_by(& &1.slot)

    reserved = Enum.find(available, &(&1.slot == 200 and &1.id == "seed/200"))

    target =
      if day == 100 and reserved,
        do: reserved,
        else: Enum.at(available, rem(state.temporal_cursor, length(available)))

    {id, state} = next(state, day, "update")

    history = %{
      target
      | status: "history",
        category: "history",
        deadline_day: date + @history_days
    }

    successor = record(id, "current", date, target.slot)
    state = put(state, history) |> put(successor) |> count(reason)
    state = %{state | temporal_cursor: state.temporal_cursor + 1}

    {%{
       "op" => "update",
       "reason" => reason,
       "target" => target.id,
       "result" => id,
       "history_deadline_day" => history.deadline_day
     }, state}
  end

  defp ordinary(state, date) do
    {{_, id}, remaining} = :gb_sets.take_smallest(state.ordinary)
    target = Map.fetch!(state.records, id)

    if target.deadline_day > date,
      do: {target, state},
      else: ordinary(%{state | ordinary: remaining}, date)
  end

  defp next(state, day, op),
    do: {"annual/#{day}/#{op}/#{state.serial + 1}", %{state | serial: state.serial + 1}}

  defp put(state, record) do
    previous = state.records[record.id]
    {ordinary, expiry, current} = unindex(state, previous)

    ordinary =
      if record.present and record.category == "ordinary",
        do: :gb_sets.add({record.admitted_day, record.id}, ordinary),
        else: ordinary

    expiry =
      if record.present and is_integer(record.deadline_day),
        do: :gb_sets.add({record.deadline_day, record.id}, expiry),
        else: expiry

    current =
      if record.present and record.category == "current",
        do: Map.put(current, record.slot, record.id),
        else: current

    present =
      state.present_count + if(record.present, do: 1, else: 0) -
        if(previous && previous.present, do: 1, else: 0)

    state = %{
      state
      | records: Map.put(state.records, record.id, record),
        ordinary: ordinary,
        expiry: expiry,
        current: current,
        present_count: present,
        max_public: max(state.max_public, present)
    }

    %{state | max_collection_records: max(state.max_collection_records, minimum_records(state))}
  end

  defp minimum_records(state) do
    # Every admitted lineage keeps an anchor even after removal; every present
    # literal/history also needs a live row. Packing cannot exceed either the
    # encoded row cap or capacity divided by the minimum charged row weight.
    state.present_count + 1 + ceil_div(map_size(state.records), page_capacity(:anchor)) +
      ceil_div(state.present_count, page_capacity(:live))
  end

  defp page_capacity(kind) do
    profile = ManagedPages.profile(kind)
    min(profile.row_cap, div(profile.capacity, profile.minimum))
  end

  defp ceil_div(count, size), do: div(count + size - 1, size)

  defp unindex(state, nil), do: {state.ordinary, state.expiry, state.current}

  defp unindex(state, previous) do
    ordinary = drop(state.ordinary, {previous.admitted_day, previous.id})
    expiry = drop(state.expiry, {previous.deadline_day, previous.id})

    current =
      if state.current[previous.slot] == previous.id,
        do: Map.delete(state.current, previous.slot),
        else: state.current

    {ordinary, expiry, current}
  end

  defp drop(set, item),
    do: if(:gb_sets.is_member(item, set), do: :gb_sets.delete(item, set), else: set)

  defp due(iterator, date, limit, count, selected) do
    case :gb_sets.next(iterator) do
      {{deadline, id}, next} when deadline < date ->
        selected = if count < limit, do: [id | selected], else: selected
        due(next, date, limit, count + 1, selected)

      _ ->
        {count, Enum.reverse(selected)}
    end
  end

  defp remove(state, target, status), do: put(state, %{target | present: false, status: status})
  defp count(state, reason), do: %{state | totals: Map.update(state.totals, reason, 1, &(&1 + 1))}
end
