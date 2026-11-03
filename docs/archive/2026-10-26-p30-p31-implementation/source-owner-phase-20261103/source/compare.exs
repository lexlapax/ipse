defmodule SourcePhaseComparison do
  @source_stages ~w(source_lock source_scan source_index source_validate source_resolve source_origin_final source_unchanged source_lock_final source_live_final source_file_close source_unlock)
  @stages ~w(egress observe_first observe_second) ++ @source_stages

  def run([single, split]) do
    one = read_run(single, 1)
    eight = read_run(split, 8)
    same!(Map.drop(one.shape, ~w(source_sessions key_revision_sha256)), Map.drop(eight.shape, ~w(source_sessions key_revision_sha256)), "actual egress shape")
    same!(Map.drop(one.fixture, ~w(source_sessions key_revision_sha256)), Map.drop(eight.fixture, ~w(source_sessions key_revision_sha256)), "verified note shape")
    IO.puts(Jason.encode!(%{
      "status" => "directional_comparison",
      "limitations" => "One instrumented run per case; different source journals and cache state. Not a 33-note result, a production timing, or proof of cause.",
      "same_egress_shape" => Map.drop(one.shape, ~w(source_sessions key_revision_sha256)),
      "same_note_shape" => Map.drop(one.fixture, ~w(source_sessions key_revision_sha256)),
      "one_source" => one.measurements,
      "eight_sources" => eight.measurements
    }))
  end
  def run(_), do: raise("expected two fresh fixture directories")

  defp read_run(dir, source_count) do
    regular!(Path.join(dir, "phase-sources-unchanged"))
    same!(File.read!(Path.join(dir, "phase-sources-unchanged")), "confirmed\n", "source preservation")
    fixture = dir |> Path.join("phase-fixture-shape.json") |> read_json()
    same!(fixture["record_count"], 8, "verified records")
    same!(fixture["source_sessions"], source_count, "fixture sources")
    sizes = fixture["text_byte_sizes"]
    require!(is_list(sizes) and length(sizes) == 8 and Enum.all?(sizes, &(is_integer(&1) and &1 > 0)), "note size shape")

    path = Path.join(dir, "source-timing.jsonl")
    regular!(path)
    require!(File.stat!(path).size <= 2_000_000, "timing size")
    entries = path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    {events, [summary]} = Enum.split(entries, -1)
    same!(summary["kind"], "summary", "summary")
    same!(summary["closure"], "stop_received", "sink closure")
    same!(summary["dropped"], 0, "dropped events")
    same!(summary["events"], length(events), "event count")
    scopes = events |> Enum.map(&{&1["pid"], &1["token"]}) |> Enum.uniq()
    require!(length(scopes) == 1, "unique egress process and token")
    same!(List.last(events)["kind"], "barrier", "producer barrier")
    same!(Enum.count(events, &(&1["kind"] == "barrier")), 1, "barrier count")
    shapes = Enum.filter(events, &(&1["kind"] == "shape"))
    require!(length(shapes) == 1, "one egress shape")
    shape = hd(shapes) |> Map.take(~w(dependencies versions v4_records proofs source_sessions key_revision_sha256))
    same!(shape["v4_records"], 8, "distinct v4 records")
    same!(shape["proofs"], 8, "proof count")
    same!(shape["source_sessions"], source_count, "proof owners")
    same!(shape["key_revision_sha256"], fixture["key_revision_sha256"], "egress-to-provider record binding")
    require!(is_binary(shape["key_revision_sha256"]) and byte_size(shape["key_revision_sha256"]) == 64, "record digest")
    versions = shape["versions"]
    require!(is_map(versions) and Enum.sort(Map.keys(versions)) == ~w(3 4 5 6 7) and Enum.all?(Map.values(versions), &(is_integer(&1) and &1 >= 0)), "version counts")
    same!(Enum.sum(Map.values(versions)), shape["dependencies"], "complete dependency count")
    require!(Enum.all?(events, &(&1["kind"] in ~w(start finish shape journal cache barrier))), "event kinds")
    require!(Enum.all?(Enum.filter(events, &(&1["kind"] in ~w(start finish))), &(&1["stage"] in @stages)), "known stages")
    totals = Map.new(@stages, fn stage ->
      count = if stage in @source_stages, do: source_count, else: 1
      {stage, spans!(events, stage, count)}
    end)
    order!(events, hd(shapes), source_count)
    journals = Enum.filter(events, &(&1["kind"] == "journal"))
    same!(length(journals), source_count, "journal count")
    require!(Enum.all?(journals, &(is_integer(&1["bytes"]) and &1["bytes"] >= 0 and is_integer(&1["events"]) and &1["events"] > 0)), "journal sizes")
    caches = Enum.filter(events, &(&1["kind"] == "cache"))
    same!(length(caches), source_count, "cache observation count")
    require!(Enum.all?(caches, &(&1["mode"] in ~w(none scoped unavailable))), "cache mode")
    %{shape: shape, fixture: fixture, measurements: %{
      "source_count" => source_count,
      "stage_total_microseconds" => totals,
      "journal_bytes" => Enum.map(journals, & &1["bytes"]),
      "journal_event_counts" => Enum.map(journals, & &1["events"]),
      "cache_modes" => Enum.frequencies(Enum.map(caches, & &1["mode"]))
    }}
  end

  defp order!(events, shape, source_count) do
    get = fn stage, kind -> Enum.filter(events, &(&1["stage"] == stage and &1["kind"] == kind)) |> Enum.map(& &1["at_us"]) end
    [outer_start] = get.("egress", "start")
    [outer_finish] = get.("egress", "finish")
    [first_finish] = get.("observe_first", "finish")
    [second_start] = get.("observe_second", "start")
    [second_finish] = get.("observe_second", "finish")
    require!(is_integer(shape["at_us"]) and outer_start <= first_finish and first_finish <= shape["at_us"] and shape["at_us"] <= second_start and second_start <= second_finish and second_finish <= outer_finish, "observation order")
    for event <- Enum.filter(events, &(&1["kind"] in ~w(start finish))) do
      require!(event["at_us"] >= outer_start and event["at_us"] <= outer_finish, "stage contained in egress")
    end
    acquisitions = for stage <- ~w(source_lock source_scan source_index source_validate source_resolve), do: {stage, get.(stage, "start"), get.(stage, "finish")}
    for index <- 0..(source_count - 1) do
      [{_, lock_s, lock_e}, {_, scan_s, scan_e}, {_, index_s, index_e}, {_, valid_s, valid_e}, {_, resolve_s, resolve_e}] = acquisitions
      require!(shape["at_us"] <= Enum.at(lock_s, index) and Enum.at(lock_e, index) <= Enum.at(scan_s, index) and Enum.at(scan_e, index) <= Enum.at(index_s, index) and Enum.at(index_e, index) <= Enum.at(valid_s, index) and Enum.at(valid_e, index) <= Enum.at(resolve_s, index) and Enum.at(resolve_e, index) <= second_start, "source acquisition order")
    end
    for stage <- ~w(source_origin_final source_unchanged source_lock_final source_live_final source_file_close source_unlock), time <- get.(stage, "start") do
      require!(time >= second_finish, "source release order")
    end
  end

  defp spans!(events, stage, count) do

    spans = Enum.filter(events, &(&1["stage"] == stage))
    same!(length(spans), count * 2, stage <> " span count")
    spans |> Enum.chunk_every(2) |> Enum.map(fn [start, finish] ->
      same!(start["kind"], "start", stage <> " start")
      same!(finish["kind"], "finish", stage <> " finish")
      same!(finish["class"], "ok", stage <> " result")
      require!(is_integer(start["at_us"]) and is_integer(finish["at_us"]) and finish["at_us"] >= start["at_us"], stage <> " timing")
      finish["at_us"] - start["at_us"]
    end) |> Enum.sum()
  end
  defp read_json(path) do
    regular!(path)
    path |> File.read!() |> Jason.decode!()
  end
  defp regular!(path), do: require!(File.lstat!(path).type == :regular, "regular evidence path")
  defp require!(true, _), do: :ok
  defp require!(_, what), do: raise("inconclusive: " <> what)
  defp same!(left, right, what), do: require!(left === right, what)
end
SourcePhaseComparison.run(System.argv())
