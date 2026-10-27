defmodule Ipse.Development.ManagedMetadata.AdaptiveCases do
  @moduledoc "Declared nonpublishing populations; counts are not admitted Sources or annual operations."
  alias Ipse.Development.ManagedMetadata.{Adaptive, AdaptiveLeaves, BinaryShapes, Codec, Shapes}

  def model do
    alias Ipse.Development.StorageWorkload
    initial = StorageWorkload.seed("representative")

    {_, snapshots} =
      Enum.reduce(1..365, {initial, %{}}, fn day, {rows, snapshots} ->
        actions = StorageWorkload.daily_actions(rows, day, "representative", 1)
        next = Enum.reduce(actions, rows, &StorageWorkload.apply_action(&2, &1))

        snapshots =
          if day in [30, 90, 365] do
            notes = Enum.filter(next, fn {_, r} -> Map.has_key?(r, "category") end)

            Map.put(snapshots, Integer.to_string(day), %{
              notes: length(notes),
              categories:
                Enum.frequencies_by(notes, fn {_, r} ->
                  r["category"] <>
                    if(r["previous_category"], do: ":" <> r["previous_category"], else: "")
                end)
            })
          else
            snapshots
          end

        {next, snapshots}
      end)

    true = snapshots["365"].notes == 3642

    %{
      pure_only: true,
      nominal_daily_actions: 30,
      burst_multiplier: 1,
      cycles_additional_sources_in_year_case: 8000,
      snapshots: snapshots
    }
  end

  def config(population, model) do
    case population do
      "fresh2000" -> %{days: 0, cycles: 0, notes: 2000, history: 0}
      "fresh4000" -> %{days: 0, cycles: 0, notes: 4000, history: 0}
      "days30" -> config_days(model, 30)
      "days90" -> config_days(model, 90)
      "year3642" -> %{days: 365, cycles: 10000, notes: 3642, history: 1807}
      "frozen3460" -> %{days: 365, cycles: 10000, notes: 3460, history: 1807}
    end
  end

  defp config_days(model, days) do
    snapshot = model["snapshots"][Integer.to_string(days)]

    history =
      snapshot["categories"]["history:ordinary"] + snapshot["categories"]["history:current"]

    %{days: days, cycles: 0, notes: snapshot["notes"], history: history}
  end

  def anchors(config, profile, retirement, kind) do
    ordinary = if config.days == 0, do: config.notes - 200, else: 1800 + 24 * config.days
    cycle_sources = if config.cycles > 0, do: 8000, else: 0
    forgets = 2 * config.days + if(config.cycles > 0, do: 2000, else: 0)
    retired = 4 * config.days + if(config.cycles > 0, do: 6000, else: 0)
    plain = ordinary + cycle_sources - forgets - retired

    classes = [
      {plain, nil, false, false},
      {forgets, %{"kind" => "session"}, false, false},
      {retired, nil, true, false},
      {100, nil, false, true},
      {100, %{"kind" => "pin"}, false, true},
      {4 * config.days, nil, true, true}
    ]

    {_last, rows} =
      Enum.reduce(classes, {0, []}, fn {count, policy, retired, infinite}, {offset, all} ->
        rows =
          for n <- range(count) do
            id = Shapes.lineage(offset + n)

            choice =
              cond do
                is_nil(policy) ->
                  nil

                kind == :anchor_full ->
                  put_in(Shapes.full_choice(id), ["override", "policy"], policy)

                true ->
                  BinaryShapes.capsule(id, policy)
              end

            row =
              BinaryShapes.anchor(
                choice,
                if(retired, do: BinaryShapes.retirement(id, retirement, profile), else: nil),
                profile
              )

            row = if infinite, do: put_in(row, ["clocks", Access.at(1)], nil), else: row
            {id, row}
          end

        {offset + count, rows ++ all}
      end)

    Map.new(rows)
  end

  def live(config, profile, dictionary) do
    catalog = Enum.map(1..8, &Codec.packed_hash(Shapes.hash("catalog#{&1}"))) |> Enum.sort()

    rows =
      Map.new(1..config.notes, fn n ->
        category =
          cond do
            n <= 100 -> "pin"
            n <= 150 -> "preference"
            n <= 200 -> "current"
            n <= 200 + config.history -> "history"
            true -> "ordinary"
          end

        {id, row} = BinaryShapes.live(n, n <= 200, profile, category)

        row =
          case dictionary do
            "shared" ->
              row

            "catalog4" ->
              row
              |> List.replace_at(2, Enum.at(catalog, rem(n, 4)))
              |> List.replace_at(3, Enum.at(catalog, rem(n + 1, 4)))

            "catalog8" ->
              row
              |> List.replace_at(2, Enum.at(catalog, rem(n, 8)))
              |> List.replace_at(3, Enum.at(catalog, rem(n + 1, 8)))

            "distinct" ->
              row
              |> List.replace_at(2, Codec.packed_hash(Shapes.hash("recipe#{n}")))
              |> List.replace_at(3, Codec.packed_hash(Shapes.hash("policy#{n}")))
          end

        {id, row}
      end)

    catalog =
      rows
      |> Enum.flat_map(fn {_, row} -> [Enum.at(row, 2), Enum.at(row, 3)] end)
      |> Enum.uniq()
      |> Enum.sort()

    {rows, if(dictionary == "distinct", do: :per_row, else: catalog)}
  end

  def pages(kind, rows, catalog) do
    if kind == :anchor_full do
      # The full-evidence control remains measurable, without inventing a global
      # native-capsule occupancy guarantee for its much larger legacy row.
      {chunks, current, _} =
        Enum.reduce(Enum.sort(rows), {[], [], 0}, fn {id, row} = entry,
                                                     {chunks, current, total} ->
          w = 33 + Adaptive.row_bytes(kind, id, row)
          true = w <= 4544

          if total + w > 4544 or length(current) == 128,
            do: {[Enum.reverse(current) | chunks], [entry], w},
            else: {chunks, [entry | current], total + w}
        end)

      chunks = Enum.reverse([Enum.reverse(current) | chunks])

      Enum.with_index(chunks)
      |> Enum.map(fn {chunk, i} ->
        fence = if i == 0, do: Adaptive.zero(kind), else: elem(hd(chunk), 0)
        {:ok, value} = Adaptive.encode_page(kind, fence, Map.new(chunk))
        {fence, value}
      end)
    else
      p =
        if kind == :live,
          do: AdaptiveLeaves.profile(kind, catalog),
          else: AdaptiveLeaves.profile(kind)

      {:ok, pages} = AdaptiveLeaves.initialize(p, rows)
      ^rows = AdaptiveLeaves.validate_tree!(p, pages)
      pages
    end
  end

  def measure(kind, rows, catalog, compare?) do
    pages = pages(kind, rows, catalog)

    measurements =
      Enum.with_index(pages)
      |> Enum.map(fn {{fence, value}, i} ->
        upper =
          case Enum.at(pages, i + 1) do
            nil -> nil
            {f, _} -> f
          end

        {:ok, %{entries: decoded}} = Adaptive.decode_page(kind, fence, value, upper)
        true = Enum.all?(decoded, fn {key, row} -> rows[key] == row end)

        comparison =
          if compare?,
            do:
              apply(Ipse.Development.ManagedMetadata.AdaptiveMsgpax, :compare, [
                kind,
                fence,
                decoded
              ]),
            else: nil

        %{
          rows: map_size(decoded),
          bytes: byte_size(Adaptive.bytes(value)),
          sha256: Ipse.JSON.sha256(Adaptive.bytes(value)),
          comparison: comparison
        }
      end)

    %{
      rows: map_size(rows),
      pages: length(pages),
      page_bytes: Enum.sum(Enum.map(measurements, & &1.bytes)),
      max_page_bytes: Enum.max(Enum.map(measurements, & &1.bytes)),
      page_measurements: measurements,
      full_row_and_range_roundtrip: true,
      occupancy_guarantee_for_declared_profile: kind != :anchor_full
    }
  end

  defp range(0), do: []
  defp range(n), do: 1..n
end
