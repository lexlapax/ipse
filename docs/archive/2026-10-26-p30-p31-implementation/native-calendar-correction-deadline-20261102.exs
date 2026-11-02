Code.require_file("dev/knowledge/native_notes_seed.ex")
Code.require_file("dev/knowledge/native_notes_workload.ex")
alias Ipse.Extension.Collection.{Encoding, Blocks}
alias Ipse.JSON
plan = Ipse.Development.NativeNotesWorkload.calendar(20)
operations = plan["initial_plus_scheduled_publications"]
id = fn n -> n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0") end

operation_rows =
  Map.new(1..operations, fn n ->
    {id.(n),
     %{
       "generation" => n,
       "floor" => n,
       "request_sha256" => JSON.sha256("synthetic layout request #{n}"),
       "managed_binding_sha256" => JSON.sha256("synthetic layout binding #{n}")
     }}
  end)

states =
  for records <- [8192, plan["minimum_peak_collection_records"], 10_000] do
    rows =
      Map.new(1..records, fn n ->
        key = "note." <> JSON.sha256("synthetic layout descriptor #{n}")

        {key,
         %{
           "key" => key,
           "revision" => n,
           "operation_id" => id.(n),
           "bytes" => 6144,
           "sha256" => JSON.sha256("synthetic layout value #{n}")
         }}
      end)

    state = %{
      "version" => 3,
      "project" => JSON.sha256("synthetic layout only"),
      "generation" => operations,
      "floor" => operations,
      "floor_anchor" => id.(operations),
      "floor_lineage" => Enum.map(1..operations, id),
      "records" => rows,
      "operations" => operation_rows,
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }

    bytes = Encoding.encode(state)

    blocks =
      case Blocks.encode(state) do
        {:ok, manifest, blocks} ->
          decoded =
            Blocks.decode(Jason.decode!(manifest), fn hash, expected ->
              bytes = Map.fetch!(blocks, hash)
              true = byte_size(bytes) == expected
              {:ok, bytes}
            end)

          roundtrip =
            case decoded do
              {:ok, actual, hashes} ->
                true = actual === state and hashes === MapSet.new(Map.keys(blocks))
                "exact"

              {:error, reason} ->
                "refused:#{reason}"
            end

          %{
            "status" => "encoded",
            "manifest_bytes" => byte_size(manifest),
            "blocks" => map_size(blocks),
            "block_bytes" => Enum.sum(Enum.map(blocks, fn {_, bytes} -> byte_size(bytes) end)),
            "current_decoder_roundtrip" => roundtrip
          }

        {:error, reason} ->
          %{"status" => "refused", "reason" => Atom.to_string(reason)}
      end

    %{
      "synthetic_records" => records,
      "synthetic_managed_operations" => operations,
      "packed_bytes" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes),
      "current_8_mib_ceiling_excess" => max(byte_size(bytes) - 8 * 1024 * 1024, 0),
      "blocks" => blocks
    }
  end

root = "/tmp/ipse-native-seed-initial-20261102-first"

values =
  for index <- 1..188,
      report =
        Path.join(root, "checkpoints/report-#{index}.json") |> File.read!() |> Jason.decode!(),
      {_number, item} <- report["new_records"],
      do: item["value"]

raw = Enum.map(values, &Jason.encode!/1)

compressed =
  Enum.map(raw, fn bytes ->
    encoded = :zlib.compress(bytes)
    true = :zlib.uncompress(encoded) === bytes
    byte_size(encoded)
  end)

sample_sizes =
  Map.new(values, fn value -> {value["category"], byte_size(Jason.encode!(value))} end)

present = plan["final_records"] |> Map.values() |> Enum.filter(& &1.present)

projected_public_bytes =
  Enum.sum(
    Enum.map(present, fn record ->
      category =
        cond do
          is_integer(record.slot) -> "current"
          record.category == "preference" -> "preference"
          true -> "ordinary"
        end

      Map.fetch!(sample_sizes, category)
    end)
  )

# Current live row encoding always includes two 32-byte hashes, even before
# clocks/keys/dictionaries/wrappers. Its base64 text alone supplies this bound.
live_base64_minimum = div(length(present) * 64 * 4 + 2, 3)

report = %{
  "version" => 1,
  "scope" =>
    "Pure metadata geometry and reversible per-value compression observation; no authority, native effect or budget change",
  "calendar_commit" => "working tree after correction-deadline repair; source hash recorded separately",
  "geometry" => states,
  "observed_closed_seed_values" => length(values),
  "observed_raw_value_bytes" => Enum.sum(Enum.map(raw, &byte_size/1)),
  "observed_zlib_bytes" => Enum.sum(compressed),
  "zlib_roundtrip_exact" => true,
  "observed_native_sample_value_bytes_by_category" => sample_sizes,
  "same_shape_final_public_records" => length(present),
  "same_shape_final_public_value_bytes" => projected_public_bytes,
  "live_row_base64_only_lower_bound" => live_base64_minimum,
  "same_shape_logical_data_lower_bound" => projected_public_bytes + live_base64_minimum,
  "same_shape_24_mib_excess_lower_bound" =>
    max(projected_public_bytes + live_base64_minimum - 24 * 1024 * 1024, 0),
  "projection_scope" =>
    "Final calendar using the observed native-statement value shapes and fixed 1024-byte varied ASCII statement/quote; no new source or signed record produced; excludes all anchor/wrapper/clock/dictionary bytes",
  "logical_budget_still_counts_raw_canonical_values" => true,
  "source_journals_rewritten" => false,
  "runtime_limits_changed" => false,
  "native_operations" => 0,
  "qualification" => false
}

File.write!(
  "/tmp/ipse-notes-layout-assessment-expiry-repair-20261102.json",
  Jason.encode!(report, pretty: true) <> "\n",
  [:exclusive]
)

IO.puts(Jason.encode!(report))
