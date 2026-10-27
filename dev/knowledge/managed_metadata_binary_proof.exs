Code.require_file("managed_metadata.ex", __DIR__)
Code.require_file("managed_metadata_shapes.exs", __DIR__)
Code.require_file("managed_metadata_binary.ex", __DIR__)
Code.require_file("managed_metadata_binary_shapes.exs", __DIR__)

defmodule Ipse.Development.ManagedMetadata.BinaryProof do
  alias Ipse.Development.ManagedMetadata.Binary, as: B
  alias Ipse.Development.ManagedMetadata.BinaryShapes, as: S
  alias Ipse.Development.ManagedMetadata.Shapes, as: F

  def run do
    id = F.hash(1)
    pin = %{"kind" => "pin"}
    session = %{"kind" => "session"}
    nil_anchor = fn row -> put_in(row, ["clocks", Access.at(1)], nil) end

    cases =
      for notes <- [3460, 3642],
          kind <- [:anchor_full, :anchor_native_candidate],
          clocks <- [:safe_width, :bounded_fixture, :calendar_2026],
          retirement <- [:none, :sticky_clock, :target_witness],
          dictionary <- [:one_recipe_one_policy, :every_row_distinct_hashes] do
        choice = fn policy ->
          if kind == :anchor_full,
            do: put_in(F.full_choice(id), ["override", "policy"], policy),
            else: S.capsule(id, policy)
        end

        plain = S.anchor(nil, nil, clocks)
        retired = S.anchor(nil, S.retirement(id, retirement, clocks), clocks)
        # Exact source classes of the DECLARED new-source cycle scenario:
        # 10560 ordinary annual sources +8000 ordinary cycle sources;
        # 200 initial persistent +1460 temporal current source versions.
        classes = [
          {8370, plain},
          {2730, S.anchor(choice.(session), nil, clocks)},
          {7460, retired},
          {100, nil_anchor.(plain)},
          {100, nil_anchor.(S.anchor(choice.(pin), nil, clocks))},
          {1460, nil_anchor.(retired)}
        ]

        anchor_costs =
          Enum.map(classes, fn {count, row} -> {count, 33 + B.row_bytes(kind, id, row)} end)

        anchor_sum = Enum.sum(Enum.map(anchor_costs, fn {n, cost} -> n * cost end))
        {live_id, finite} = S.live(1, false, clocks)
        {_, infinite} = S.live(1, true, clocks)
        # Count each fixed hash exactly. Shared dictionary has two hashes/leaf;
        # worst dictionary charges both32Bhashes plus2indexbytes per row.
        adjustment = if dictionary == :one_recipe_one_policy, do: -62, else: 2
        live_weight = 34 + B.row_bytes(:live, live_id, finite) + adjustment
        infinite_weight = 34 + B.row_bytes(:live, live_id, infinite) + adjustment
        live_sum = (notes - 200) * live_weight + 200 * infinite_weight
        anchor_max = anchor_costs |> Enum.map(&elem(&1, 1)) |> Enum.max()
        anchor_min = anchor_costs |> Enum.map(&elem(&1, 1)) |> Enum.min()
        ag = geometry(kind, 6, anchor_min, anchor_max)
        live_header = if dictionary == :one_recipe_one_policy, do: 71, else: 8
        lg = geometry(:live, live_header, infinite_weight, live_weight)
        ap = max(1, div(anchor_sum, ag.weight_floor) + 1)
        lp = max(1, div(live_sum, lg.weight_floor) + 1)
        upper = total_upper(anchor_sum, ap, ag) + total_upper(live_sum, lp, lg)
        # Optimistic comparison for THESE declared fields: first-code every ID
        # with zero common prefix, then subtract the full maximum32/33bytes per
        # row to avoid claiming incompressibility. Actual front coding is below.
        raw_fields_only = anchor_sum - 20220 * 33 + live_sum - notes * 34
        lower_fields_only = B.b64(raw_fields_only)

        %{
          notes: notes,
          choice_format: kind,
          clock_profile: clocks,
          retirement_profile: retirement,
          dictionary_profile: dictionary,
          source_anchors: 20220,
          session_choices: 2730,
          pin_choices: 100,
          retirement_witnesses: if(retirement == :none, do: 0, else: 8920),
          unfrontcoded_virtual_anchor_weights: anchor_sum,
          unfrontcoded_virtual_live_weights: live_sum,
          optimistic_field_bytes_without_any_ID_or_page_header: lower_fields_only,
          metadata_allowance: 24 * 1024 * 1024 - notes * 6144,
          fields_alone_exceed_allowance: lower_fields_only > 24 * 1024 * 1024 - notes * 6144,
          virtual_weight_packing_upper_page_values: upper,
          upper_within_allowance: upper <= 24 * 1024 * 1024 - notes * 6144,
          future_format_record_reservation: 6144,
          upper_page_values_plus_format_reservation: upper + 6144,
          upper_with_format_reservation_within_allowance:
            upper + 6144 <= 24 * 1024 * 1024 - notes * 6144,
          anchor_geometry: ag,
          live_geometry: lg,
          upper_leaf_count: ap + lp,
          upper_record_count: notes + ap + lp + 1,
          authority_or_actual_annual_claim: false
        }
      end

    %{
      kind: "pure_binary_metadata_proof",
      actual_publications: 0,
      native_calls: 0,
      model_calls: 0,
      qualification_passed: false,
      candidate_is_authority: false,
      full_legacy_JSON_failure_control:
        "managed-metadata-calculation-final.json at19f377c; immutable",
      proposed_candidate: %{
        pin_session_raw: byte_size(B.capsule_encode(id, S.capsule(id))),
        duration_raw:
          byte_size(
            B.capsule_encode(
              id,
              S.capsule(id, %{"kind" => "duration", "duration_ms" => B.safe()})
            )
          )
      },
      four_clock_control: %{
        plain_anchor_raw_fields:
          B.row_bytes(:anchor_native_candidate, id, S.anchor(nil, nil, :four_safe_clocks)),
        candidate_anchor_raw_fields:
          B.row_bytes(
            :anchor_native_candidate,
            id,
            S.anchor(S.capsule(id), nil, :four_safe_clocks)
          ),
        scope:
          "Separate maximum four-clock shape; annual literal-only scenario has no pending clocks. Pending population is not silently included in literal-year acceptance."
      },
      counts: %{
        annual_sources_before_cycles: 12220,
        ordinary_sources_after_cycles: 18560,
        current_preference_pin_source_versions: 1660,
        cycle_nonforget_sources: 8000,
        cycle_existing_record_replacements: 6000,
        ordinary_retirements: 1460,
        temporal_retirements: 1460,
        total_retirements: 8920,
        initial_pin_choices: 100,
        session_forget_choices: 2730
      },
      cases: cases,
      gates: %{
        binary_split_merge_planner_implemented: false,
        actual_host_neighbors_and_32_reads_qualified: false,
        all_lifecycle_sidecars_within_four: false,
        retirement_semantics_ratified: false,
        native_choice_host_mint_implemented: false
      },
      scope:
        "Bounded pure codecs and conditional conservative virtual-weight packing calculation. No product or store effects. Sticky retirement is explicitly unratified; full target/key/value/time control is separate."
    }
  end

  defp geometry(kind, raw_header, minimum, maximum) do
    outer =
      byte_size(
        B.bytes(%{
          "version" => 1,
          "kind" => Atom.to_string(kind),
          "fence" => B.zero(kind),
          "data" => ""
        })
      )

    capacity = Enum.find(4608..0//-1, fn n -> outer + B.b64(n + raw_header) <= 6144 end)
    trigger = min(capacity + 1, 65 * minimum)
    floor = div(trigger - maximum, 2)
    true = floor > 0 and maximum <= capacity

    %{
      outer_JSON_bytes: outer,
      raw_header_bound: raw_header,
      virtual_weight_capacity: capacity,
      minimum_weight: minimum,
      maximum_weight: maximum,
      weight_floor: floor,
      assumption:
        "Future planner splits/merges by additive conservative virtual weights; no such binary planner implemented."
    }
  end

  defp total_upper(weight, pages, g),
    do: B.b64(weight + pages * g.raw_header_bound) + pages * (g.outer_JSON_bytes + 2)
end

owner = self()
Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})

spawn_link(fn ->
  Enum.each(1..300, fn _ ->
    Process.sleep(100)
    if :erlang.memory(:total) > 536_870_912, do: Process.exit(owner, :kill)
  end)

  Process.exit(owner, :kill)
end)

[output] = System.argv()
report = Ipse.Development.ManagedMetadata.BinaryProof.run()
File.write!(output, Jason.encode!(report, pretty: true) <> "\n")

IO.puts(
  "Computed #{length(report.cases)} explicit binary sizing controls; no publications/native/model calls"
)
