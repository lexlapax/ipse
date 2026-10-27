[kind_name, clock_name, dictionary, retirement_name, output] = System.argv()
started = System.monotonic_time(:millisecond)
Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
peak = :atomics.new(1, [])

spawn_link(fn ->
  Enum.each(1..600, fn _ ->
    Process.sleep(50)
    memory = :erlang.memory(:total)
    :atomics.put(peak, 1, max(memory, :atomics.get(peak, 1)))

    if memory > 536_870_912 do
      File.write!(output <> ".failure.json", Jason.encode!(%{guard: "512MiB", bytes: memory}))
      System.halt(137)
    end
  end)
end)

spawn_link(fn ->
  Process.sleep(max(0, 30_000 - (System.monotonic_time(:millisecond) - started)))
  File.write!(output <> ".failure.json", Jason.encode!(%{guard: "30_seconds"}))
  System.halt(124)
end)

# Frozen development population constructors are used only by this separate
# nonpublishing measurement command, never by the host codec or local planner.
for file <-
      ~w(managed_metadata.ex managed_metadata_shapes.exs managed_metadata_binary.ex managed_metadata_binary_shapes.exs managed_metadata_adaptive.ex managed_metadata_adaptive_leaves.ex) do
  Code.require_file(file, __DIR__)
end

Code.require_file("../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("storage_workload.ex", __DIR__)
Code.require_file("managed_metadata_adaptive_cases.ex", __DIR__)

defmodule Ipse.Development.ManagedPagesMeasure do
  alias Ipse.Extension.Collection.ManagedPages, as: Pages

  # Bulk partitioning is calculation scaffolding. Product lookup and repair use
  # ManagedPages.Planner and the held, budgeted Collection neighbor closure.
  def measure(kind, rows) do
    pieces = partition(kind, Enum.sort(rows))

    pages =
      pieces
      |> Enum.with_index()
      |> Enum.map(fn {entries, i} ->
        fence = if i == 0, do: Pages.zero(kind), else: elem(hd(entries), 0)
        {fence, Map.new(entries)}
      end)

    measured =
      pages
      |> Enum.with_index()
      |> Enum.map(fn {{fence, entries}, i} ->
        upper =
          case Enum.at(pages, i + 1) do
            nil -> nil
            {fence, _} -> fence
          end

        weight = Pages.weight(kind, entries)
        true = length(pages) == 1 or weight >= Pages.profile(kind).floor
        {:ok, raw} = Pages.pack(kind, fence, entries)
        {:ok, %{entries: ^entries}} = Pages.unpack(kind, fence, raw, upper)

        %{
          fence: fence,
          rows: map_size(entries),
          virtual_bytes: weight,
          raw_bytes: byte_size(raw),
          raw_sha256: Ipse.JSON.sha256(raw),
          encoded_value_bytes: Pages.encoded_size(raw)
        }
      end)

    %{
      rows: map_size(rows),
      pages: length(pages),
      profile: Pages.profile(kind),
      encoded_value_bytes: Enum.sum(Enum.map(measured, & &1.encoded_value_bytes)),
      max_value_bytes: Enum.max(Enum.map(measured, & &1.encoded_value_bytes)),
      full_inverse_and_range: true,
      page_measurements: measured
    }
  end

  defp partition(kind, rows) do
    total = Pages.weight(kind, Map.new(rows))
    p = Pages.profile(kind)

    if total <= p.capacity do
      [rows]
    else
      {sums, _} =
        Enum.map_reduce(rows, 0, fn {id, row}, n ->
          n = n + Pages.row_weight(kind, id, row)
          {n, n}
        end)

      {_, split} =
        sums
        |> Enum.drop(-1)
        |> Enum.with_index(1)
        |> Enum.min_by(fn {n, i} -> {abs(total - 2 * n), i} end)

      {a, b} = Enum.split(rows, split)
      true = Pages.weight(kind, Map.new(a)) >= p.floor
      true = Pages.weight(kind, Map.new(b)) >= p.floor
      partition(kind, a) ++ partition(kind, b)
    end
  end
end

alias Ipse.Development.ManagedMetadata.AdaptiveCases, as: Cases
alias Ipse.Extension.Collection.ManagedPages, as: Pages
clock = Map.fetch!(%{"calendar" => :calendar_2026, "safe" => :safe_width}, clock_name)

retirement =
  Map.fetch!(%{"literal" => :sticky_clock, "full_target" => :target_witness}, retirement_name)

true = dictionary in ["shared", "catalog8"]
config = Cases.config("year3642", nil)
Code.ensure_loaded!(Pages)
Code.ensure_loaded!(Ipse.Extension.Collection.ManagedPages.Planner)

files =
  Path.wildcard(Path.join(__DIR__, "managed_metadata*.ex*")) ++
    [
      __ENV__.file,
      Path.join(__DIR__, "storage_workload.ex"),
      Path.expand("../../extensions/knowledge/src/notes.ex", __DIR__),
      Path.expand("../../lib/ipse/extension/collection/managed_pages.ex", __DIR__),
      Path.expand("../../lib/ipse/extension/collection/managed_pages/planner.ex", __DIR__)
    ]

bindings = fn ->
  sources = Map.new(files, &{&1, Ipse.JSON.sha256(File.read!(&1))})

  modules =
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(fn module ->
      String.starts_with?(Atom.to_string(module), [
        "Elixir.Ipse.Development.ManagedMetadata",
        "Elixir.Ipse.Extension.Collection.ManagedPages",
        "Elixir.IpseKnowledge.Notes"
      ])
    end)
    |> Map.new(fn module ->
      {Atom.to_string(module), Base.encode16(module.module_info(:md5), case: :lower)}
    end)

  %{sources: sources, modules_md5: modules}
end

before = bindings.()
File.write!(output <> ".started.json", Jason.encode!(%{binding: before, argv: System.argv()}))
kind = Map.fetch!(%{"anchor" => :anchor, "live" => :live}, kind_name)

rows =
  case kind do
    :anchor ->
      Cases.anchors(config, clock, retirement, :anchor_native_candidate)
      |> Map.new(fn {id, row} ->
        choice = if row["choice"], do: Map.put(row["choice"], "kind", "native_management")
        {id, Map.put(row, "choice", choice)}
      end)

    :live ->
      elem(Cases.live(config, clock, dictionary), 0)
  end

true = map_size(rows) == if(kind == :anchor, do: 20220, else: 3642)
# Framed canonical rows avoid constructing a second whole-population JSON tree.
input_sha =
  Enum.sort(rows)
  |> Enum.reduce(:crypto.hash_init(:sha256), fn {id, row}, ctx ->
    raw = Pages.bytes(row)
    :crypto.hash_update(ctx, [<<byte_size(id)::32>>, id, <<byte_size(raw)::32>>, raw])
  end)
  |> :crypto.hash_final()
  |> Base.encode16(case: :lower)

:erlang.garbage_collect()
measured = Ipse.Development.ManagedPagesMeasure.measure(kind, rows)
after_binding = bindings.()
true = before == after_binding
payload = 3642 * 6144
metadata_allowance = 24 * 1024 * 1024 - payload

report = %{
  version: 1,
  pure_only: true,
  qualification_passed: false,
  native_calls: 0,
  model_calls: 0,
  gold_reads: 0,
  publication_calls: 0,
  clock: clock_name,
  dictionary: dictionary,
  retirement: retirement_name,
  kind: kind_name,
  population: "declared-year3642",
  sources: 20220,
  session_choices: 2730,
  pins: 100,
  persistent: 200,
  nominal_actions_per_day: 30,
  days: 365,
  cycles: 10000,
  actual_endurance_operations: 0,
  actual_source_admissions: 0,
  source_epoch_simulation: false,
  pending_and_arbitrary_derivative_retirement: false,
  capsule_authority: false,
  synthetic_mac_bytes: 43,
  mac_envelope_bytes: 75,
  input_sha256: input_sha,
  input_hash_encoding: "sorted length32-id length32-canonical-row stream v1",
  bindings_before: before,
  bindings_after: after_binding,
  measured: measured,
  max_payload_bytes: payload,
  metadata_allowance: metadata_allowance,
  actual_format_value_bytes: Pages.encoded_size(Pages.format_body()),
  format_reserved_bytes: 6144,
  conditional_arithmetic_fits: nil,
  allocated_files_quota_measured: false,
  lookup_or_publication_plan_measured: false,
  elapsed_ms: System.monotonic_time(:millisecond) - started,
  sampled_peak_beam_bytes: :atomics.get(peak, 1)
}

File.write!(output, Jason.encode!(report, pretty: true) <> "\n")

IO.puts(
  Jason.encode!(
    Map.take(report, [
      :clock,
      :dictionary,
      :retirement,
      :kind,
      :elapsed_ms,
      :conditional_arithmetic_fits
    ])
  )
)
