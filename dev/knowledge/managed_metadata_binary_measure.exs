Code.require_file("managed_metadata.ex", __DIR__)
Code.require_file("managed_metadata_shapes.exs", __DIR__)
Code.require_file("managed_metadata_binary.ex", __DIR__)
Code.require_file("managed_metadata_binary_shapes.exs", __DIR__)

defmodule Ipse.Development.ManagedMetadata.BinaryMeasure do
  alias Ipse.Development.ManagedMetadata.Binary, as: B
  alias Ipse.Development.ManagedMetadata.BinaryShapes, as: S
  alias Ipse.Development.ManagedMetadata.Shapes, as: F

  def binding do
    files =
      ~w(dev/knowledge/managed_metadata.ex dev/knowledge/managed_metadata_shapes.exs dev/knowledge/managed_metadata_binary.ex dev/knowledge/managed_metadata_binary_shapes.exs dev/knowledge/managed_metadata_binary_measure.exs)

    modules = [
      B,
      S,
      F,
      Ipse.Development.ManagedMetadata.Codec,
      Ipse.JSON,
      Ipse.Extension.Collection.Migration,
      Ipse.Extension.ManagedRecipe,
      Jason
    ]

    %{
      source_sha256:
        Map.new(files, fn path ->
          {path, Ipse.JSON.sha256(File.read!(Path.expand("../../" <> path, __DIR__)))}
        end),
      loaded_module_md5:
        Map.new(modules, fn module ->
          {Atom.to_string(module), Base.encode16(module.module_info(:md5), case: :lower)}
        end),
      elixir: System.version(),
      otp: System.otp_release(),
      erts: to_string(:erlang.system_info(:version))
    }
  end

  def run("live", clock, dictionary) do
    profile = select(clock, [:safe_width, :bounded_fixture, :calendar_2026])
    dictionary = select(dictionary, [:one_recipe_one_policy, :every_row_distinct_hashes])

    rows =
      Enum.map(1..3642, fn n ->
        category =
          cond do
            n <= 100 -> "pin"
            n <= 150 -> "preference"
            n <= 200 -> "current"
            n <= 200 + 1807 -> "history"
            true -> "ordinary"
          end

        {id, row} = S.live(n, n <= 200, profile, category)

        row =
          if dictionary == :every_row_distinct_hashes,
            do:
              row
              |> List.replace_at(2, packed_hash("recipe#{n}"))
              |> List.replace_at(3, packed_hash("policy#{n}")),
            else: row

        {id, row}
      end)

    Enum.map([3460, 3642], fn n ->
      measure(:live, Enum.take(rows, n), dictionary)
      |> Map.merge(%{notes: n, clock_profile: profile, dictionary_profile: dictionary})
    end)
  end

  def run(kind, clock, retirement) do
    kind = select(kind, [:anchor_full, :anchor_native_candidate])
    profile = select(clock, [:safe_width, :bounded_fixture, :calendar_2026])
    retirement = select(retirement, [:none, :sticky_clock, :target_witness])
    # Declared byte-shape fixture. Each lineage is a deterministic source-shaped
    # identity, without source admission, human observation or actual publication.
    rows =
      Enum.map(1..20220, fn n ->
        id = F.lineage(n)

        {policy, retired, infinite} =
          cond do
            n <= 8370 -> {nil, false, false}
            n <= 11100 -> {%{"kind" => "session"}, false, false}
            n <= 18560 -> {nil, true, false}
            n <= 18660 -> {nil, false, true}
            n <= 18760 -> {%{"kind" => "pin"}, false, true}
            true -> {nil, true, true}
          end

        choice =
          cond do
            is_nil(policy) -> nil
            kind == :anchor_full -> put_in(F.full_choice(id), ["override", "policy"], policy)
            true -> S.capsule(id, policy)
          end

        row =
          S.anchor(
            choice,
            if(retired, do: S.retirement(id, retirement, profile), else: nil),
            profile
          )

        row = if infinite, do: put_in(row, ["clocks", Access.at(1)], nil), else: row
        {id, row}
      end)

    [
      measure(kind, rows, :none)
      |> Map.merge(%{clock_profile: profile, retirement_profile: retirement})
    ]
  end

  defp measure(kind, rows, dictionary) do
    adjustment = if dictionary == :one_recipe_one_policy, do: -62, else: 2

    raw_header =
      cond do
        kind != :live -> 6
        dictionary == :one_recipe_one_policy -> 71
        true -> 8
      end

    outer =
      byte_size(
        B.bytes(%{
          "version" => 1,
          "kind" => Atom.to_string(kind),
          "fence" => B.zero(kind),
          "data" => ""
        })
      )

    capacity = Enum.find(4608..0//-1, &(outer + B.b64(&1 + raw_header) <= 6144))
    rows = Enum.sort(rows)

    {pages, current, _} =
      Enum.reduce(rows, {[], [], 0}, fn {key, row} = entry, {pages, current, sum} ->
        weight =
          B.row_bytes(kind, key, row) + B.width(kind) + 1 +
            if(kind == :live, do: adjustment, else: 0)

        true = weight <= capacity

        if length(current) == 64 or sum + weight > capacity,
          do: {[Enum.reverse(current) | pages], [entry], weight},
          else: {pages, [entry | current], sum + weight}
      end)

    pages = Enum.reverse([Enum.reverse(current) | pages])

    result =
      Enum.with_index(pages)
      |> Enum.map(fn {rows, index} ->
        fence = if index == 0, do: B.zero(kind), else: elem(hd(rows), 0)

        next =
          case Enum.at(pages, index + 1) do
            nil -> nil
            rows -> elem(hd(rows), 0)
          end

        entries = Map.new(rows)
        {:ok, value} = B.encode_page(kind, fence, entries)
        {:ok, %{entries: ^entries}} = B.decode_page(value, next)
        encoded = B.bytes(value)
        %{bytes: byte_size(encoded), rows: length(rows), sha256: Ipse.JSON.sha256(encoded)}
      end)

    %{
      kind: kind,
      rows: length(rows),
      pages: length(pages),
      encoded_page_bytes: Enum.sum(Enum.map(result, & &1.bytes)),
      maximum_page_bytes: result |> Enum.map(& &1.bytes) |> Enum.max(),
      minimum_page_rows: result |> Enum.map(& &1.rows) |> Enum.min(),
      every_page_roundtrip_and_next_range_checked: true,
      page_sha256: Enum.map(result, & &1.sha256),
      packing:
        "Greedy additive virtual-weight capacity; canonical real front coding/dictionaries measured after packing. Not dynamic split/merge or annual state qualification."
    }
  end

  defp packed_hash(text),
    do: text |> F.hash() |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)

  defp select(text, options),
    do: Enum.find(options, &(Atom.to_string(&1) == text)) || raise("invalid profile")
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

[output, kind, clock, other] = System.argv()
before = Ipse.Development.ManagedMetadata.BinaryMeasure.binding()
started = System.monotonic_time(:millisecond)

report = %{
  kind: "pure_declared_binary_page_measurement",
  actual_publications: 0,
  native_calls: 0,
  model_calls: 0,
  parts: Ipse.Development.ManagedMetadata.BinaryMeasure.run(kind, clock, other),
  qualification_passed: false
}

report = Map.put(report, :elapsed_ms, System.monotonic_time(:millisecond) - started)
after_binding = Ipse.Development.ManagedMetadata.BinaryMeasure.binding()
true = before == after_binding

report =
  Map.merge(report, %{
    input_job: [kind, clock, other],
    binding_before: before,
    binding_after: after_binding
  })

File.write!(output, Jason.encode!(report, pretty: true) <> "\n")

IO.puts(
  "#{kind}/#{clock}/#{other}: #{report.elapsed_ms}ms; #{inspect(Enum.map(report.parts, &Map.take(&1, [:rows, :pages, :encoded_page_bytes])))}"
)
