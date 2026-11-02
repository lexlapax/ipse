defmodule Ipse.Development.NativeReceiptGeometry do
  @moduledoc false
  alias Ipse.Extension.Collection.{Blocks, Encoding}
  @counts [22_980, 32_768, 42_980]
  @decoded_bytes 8 * 1024 * 1024
  @sources ~w(
    lib/ipse/extension/collection/blocks.ex
    lib/ipse/extension/collection/encoding.ex
    lib/ipse/extension/collection/migration.ex
    dev/knowledge/native_receipt_geometry.exs
  )

  def run(args) do
    {options, [], []} = OptionParser.parse(args, strict: [output: :string])
    output = Keyword.fetch!(options, :output)

    rows =
      for count <- @counts,
          managed <- [false, true],
          live <- [0, 2000],
          do: measure(count, managed, live)

    report = %{
      "kind" => "synthetic_retained_receipt_geometry",
      "version" => 1,
      "current_limits_unchanged" => true,
      "qualification" => false,
      "scope" =>
        "Synthetic receipt rows, destructive-floor lineage and zero/2000 public record descriptors; no value objects, authenticated sidecars, domain publication, native allocation, migration, peak or performance acceptance",
      "source_sha256" => Map.new(@sources, &{&1, sha(File.read!(&1))}),
      "rows" => rows
    }

    File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
    Enum.each(rows, &IO.puts(Jason.encode!(&1)))
  end

  defp measure(count, managed, live) do
    operations =
      Map.new(1..count, fn n ->
        receipt = %{
          "generation" => n,
          "floor" => n,
          "request_sha256" => sha("synthetic receipt geometry #{n}")
        }

        receipt =
          if managed,
            do: Map.put(receipt, "managed_binding_sha256", sha("synthetic binding #{n}")),
            else: receipt

        {id(n), receipt}
      end)

    records =
      if live == 0 do
        %{}
      else
        Map.new(1..live, fn n ->
          key = "note." <> sha("synthetic selected lineage #{n}")

          {key,
           %{
             "key" => key,
             "revision" => n,
             "operation_id" => id(n),
             "bytes" => 6144,
             "sha256" => sha("synthetic selected value #{n}")
           }}
        end)
      end

    state = %{
      "version" => 3,
      "project" => sha("receipt geometry only"),
      "generation" => count,
      "floor" => count,
      "floor_anchor" => id(count),
      "floor_lineage" => Enum.map(1..count, &id/1),
      "records" => records,
      "operations" => operations,
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }

    packed = Encoding.encode(state)

    blocks =
      case Blocks.encode(state) do
        {:ok, manifest, blocks} ->
          %{
            "status" => "encoded",
            "manifest_bytes" => byte_size(manifest),
            "blocks" => map_size(blocks),
            "block_bytes" => Enum.sum(Enum.map(blocks, fn {_, bytes} -> byte_size(bytes) end))
          }

        {:error, reason} ->
          %{"status" => "refused", "reason" => Atom.to_string(reason)}
      end

    %{
      "synthetic_receipts" => count,
      "all_receipts_managed" => managed,
      "all_operations_advance_floor" => true,
      "live_record_descriptors" => live,
      "canonical_packed_state_bytes" => byte_size(packed),
      "packed_state_sha256" => sha(packed),
      "decoded_byte_ceiling" => @decoded_bytes,
      "above_decoded_byte_ceiling" => byte_size(packed) > @decoded_bytes,
      "current_blocks_encode" => blocks,
      "actual_native_operations" => 0,
      "qualification" => false
    }
  end

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end

Ipse.Development.NativeReceiptGeometry.run(System.argv())
