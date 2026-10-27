Code.require_file("managed_metadata.ex", __DIR__)
Code.require_file("managed_metadata_shapes.exs", __DIR__)
Code.require_file("../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("storage_workload.ex", __DIR__)

defmodule Ipse.Development.ManagedMetadata.Proof do
  alias Ipse.Development.ManagedMetadata.{Codec, Leaves, Shapes}
  alias Ipse.Development.StorageWorkload

  def geometry(kind, minimum, maximum) do
    id = Leaves.zero(kind)
    true = Codec.valid_wire?(kind, id, minimum) and Codec.valid_wire?(kind, id, maximum)
    header = byte_size(Codec.bytes(Leaves.page(kind, id, %{})))
    [small] = Leaves.weights(kind, [{id, minimum}])
    [large] = Leaves.weights(kind, [{id, maximum}])
    trigger = min(6146 - header, 65 * small)
    lower = div(trigger - large, 2)
    true = lower > 0 and large + header - 1 <= 6144

    %{
      empty_page_bytes: header,
      minimum_entry_weight: small,
      maximum_entry_weight: large,
      minimum_trigger_weight: trigger,
      proved_split_leaf_weight_floor: lower,
      maximum_single_entry_page_bytes: header + large - 1
    }
  end

  def run do
    {:ok, simple} = Codec.encode_anchor(Shapes.hash(1), Shapes.anchor())
    minimal = ["0", "1", "0", "1", nil]
    full = Shapes.anchor(Shapes.full_choice(Shapes.hash(1)))
    candidate = Shapes.anchor(Shapes.candidate_choice(Shapes.hash(1)))
    {:ok, full_wire} = Codec.encode_anchor(Shapes.hash(1), full, :anchor_full)
    {:ok, candidate_wire} = Codec.encode_anchor(Shapes.hash(1), candidate, :anchor_candidate)
    {live, record} = Shapes.live()
    {:ok, {live_id, live_wire}} = Codec.encode_live(live, record)
    live_min = live_wire |> List.replace_at(4, "0") |> List.replace_at(5, "1")

    geometries = %{
      anchor_full: geometry(:anchor_full, minimal, full_wire),
      anchor_candidate: geometry(:anchor_candidate, minimal, candidate_wire),
      live: geometry(:live, live_min, live_wire)
    }

    lineage_model = annual_notes()
    identities = lineage_model.distinct_sources + 8000
    choices = 365 * 2 + 2000
    note_only = simple |> List.replace_at(2, nil) |> List.replace_at(3, nil)
    full_note_only = full_wire |> List.replace_at(2, nil) |> List.replace_at(3, nil)
    candidate_note_only = candidate_wire |> List.replace_at(2, nil) |> List.replace_at(3, nil)
    [normal_weight] = Leaves.weights(:anchor_full, [{Shapes.hash(1), note_only}])
    [full_weight] = Leaves.weights(:anchor_full, [{Shapes.hash(1), full_note_only}])

    [candidate_weight] =
      Leaves.weights(:anchor_candidate, [{Shapes.hash(1), candidate_note_only}])

    [live_weight] = Leaves.weights(:live, [{live_id, live_wire}])

    class_weights =
      for {kind, make} <- [
            anchor_full: &Shapes.full_choice/1,
            anchor_candidate: &Shapes.candidate_choice/1
          ],
          {class, policy} <- [pin: %{"kind" => "pin"}, forget: %{"kind" => "session"}],
          into: %{} do
        choice = make.(Shapes.hash(1))

        choice =
          if kind == :anchor_full,
            do: put_in(choice, ["override", "policy"], policy),
            else: Map.put(choice, "policy", policy)

        {:ok, wire} = Codec.encode_anchor(Shapes.hash(1), Shapes.anchor(choice), kind)
        wire = wire |> List.replace_at(2, nil) |> List.replace_at(3, nil)
        [weight] = Leaves.weights(kind, [{Shapes.hash(1), wire}])
        {{kind, class}, weight}
      end

    cases =
      for {label, notes} <- [
            frozen_arithmetic: 3460,
            pure_existing_notes_model: lineage_model.peak_notes
          ],
          {kind, maximum_weight} <- [anchor_full: full_weight, anchor_candidate: candidate_weight],
          choice_profile <- [:all_duration_maximum_control, :pin_and_session_classes] do
        pins = if choice_profile == :pin_and_session_classes, do: 100, else: 0

        anchor_sum =
          if choice_profile == :all_duration_maximum_control do
            (identities - choices) * normal_weight + choices * maximum_weight
          else
            (identities - choices - pins) * normal_weight +
              choices * class_weights[{kind, :forget}] + pins * class_weights[{kind, :pin}]
          end

        live_sum = notes * live_weight
        anchor_pages = max(1, div(anchor_sum, geometries[kind].proved_split_leaf_weight_floor))
        live_pages = max(1, div(live_sum, geometries.live.proved_split_leaf_weight_floor))
        metadata_lower = anchor_sum + live_sum

        metadata_upper =
          metadata_lower + anchor_pages * (geometries[kind].empty_page_bytes - 1) +
            live_pages * (geometries.live.empty_page_bytes - 1)

        %{
          population_model: label,
          choice_model: kind,
          choice_profile: choice_profile,
          note_records: notes,
          source_anchors: identities,
          forget_choices: choices,
          initial_pin_choices: pins,
          raw_record_bytes_at_6144: notes * 6144,
          metadata_member_bytes: metadata_lower,
          metadata_bytes_upper_including_leaf_headers: metadata_upper,
          record_slots_upper: notes + anchor_pages + live_pages + 1,
          byte_limit: 24 * 1024 * 1024,
          record_limit: 8192,
          exceeds_24mib_even_before_page_headers:
            notes * 6144 + metadata_lower > 24 * 1024 * 1024,
          unsupported_additional_costs: [
            "automatic correction retirement markers",
            "additional accepted proposals",
            "management authenticator or retained authority-journal cost"
          ]
        }
      end

    %{
      kind: "nonpublishing_managed_metadata_proof",
      actual_publications: 0,
      native_calls: 0,
      model_calls: 0,
      qualification_passed: false,
      candidate_capsule_is_authority: false,
      mutation_count_without_bootstrap_or_expiry_maintenance: 20_950,
      initial_records_require_separate_actual_publications: 2000,
      initial_typed_pin_choices_require_separate_actual_publications: 100,
      cycle_source_scenario: %{
        cycles: 10_000,
        forget_choices: 2000,
        nonforget_updates_each_assumed_to_introduce_one_distinct_source: 8000,
        actual_domain_cycle_history_implemented: false
      },
      resource_gates: %{
        new_or_nonshrinking_capture_sidecars_upper: 4,
        shrinking_or_delete_with_other_tree_split_sidecars_upper: 5,
        all_typed_journeys_within_four_sidecars_proved: false,
        host_neighbors_adapter_implemented: false,
        native_read_budget_qualified: false
      },
      geometry: geometries,
      annual_pure_model: lineage_model,
      row_bytes: %{
        plain_anchor_wire: byte_size(Codec.bytes(simple)),
        full_evidence_anchor_wire: byte_size(Codec.bytes(full_wire)),
        candidate_capsule_anchor_wire: byte_size(Codec.bytes(candidate_wire)),
        live_wire: byte_size(Codec.bytes(live_wire)),
        note_only_anchor_entry: normal_weight,
        note_only_full_evidence_anchor_entry: full_weight,
        note_only_candidate_capsule_anchor_entry: candidate_weight,
        live_entry: live_weight
      },
      class_specific_anchor_entry_weights: %{
        full_pin: class_weights[{:anchor_full, :pin}],
        full_session_forget: class_weights[{:anchor_full, :forget}],
        candidate_pin: class_weights[{:anchor_candidate, :pin}],
        candidate_session_forget: class_weights[{:anchor_candidate, :forget}]
      },
      cases: cases,
      scope:
        "Structural codec/occupancy bounds only; full evidence and proposed native-capsule maxima are separate, not substituted qualification."
    }
  end

  defp annual_notes do
    initial = StorageWorkload.seed("representative")
    lineages = MapSet.new(Enum.map(initial, fn {_, n} -> n["lineage"] end))

    {rows, lineages, peak, expired} =
      Enum.reduce(1..365, {initial, lineages, 2000, 0}, fn day, {rows, sources, peak, expired} ->
        [expiry | _] = actions = StorageWorkload.daily_actions(rows, day, "representative", 1)

        rows =
          Enum.reduce(actions, rows, fn action, all ->
            StorageWorkload.apply_action(all, action)
          end)

        notes = Enum.filter(rows, fn {_, row} -> Map.has_key?(row, "category") end)

        sources =
          Enum.reduce(notes, sources, fn {_, row}, all -> MapSet.put(all, row["lineage"]) end)

        {rows, sources, max(peak, length(notes)), expired + length(expiry)}
      end)

    %{
      days: 365,
      burst_multiplier: 1,
      pure_only: true,
      distinct_sources: MapSet.size(lineages),
      peak_notes: peak,
      expiry_record_deletions: expired,
      persistent: %{pin: 100, preference: 50, current: 50},
      final_categories:
        Enum.reduce(rows, %{}, fn {_, row}, all ->
          if row["category"],
            do:
              Map.update(
                all,
                Enum.join([row["category"], row["previous_category"]], ":"),
                1,
                &(&1 + 1)
              ),
            else: all
        end)
    }
  end
end

owner = self()
Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})

spawn_link(fn ->
  Enum.reduce_while(1..300, nil, fn _, _ ->
    Process.sleep(100)
    if :erlang.memory(:total) > 536_870_912, do: Process.exit(owner, :kill)
    {:cont, nil}
  end)

  Process.exit(owner, :kill)
end)

[output] = System.argv()
report = Ipse.Development.ManagedMetadata.Proof.run()
File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
IO.puts(Jason.encode!(report, pretty: true))
