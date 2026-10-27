for path <-
      ~w(managed_metadata.ex managed_metadata_shapes.exs managed_metadata_binary.ex managed_metadata_binary_shapes.exs managed_metadata_adaptive.ex managed_metadata_adaptive_leaves.ex) do
  Code.require_file("../../dev/knowledge/" <> path, __DIR__)
end

defmodule Ipse.Development.ManagedMetadataAdaptiveTest do
  use ExUnit.Case, async: true

  alias Ipse.Development.ManagedMetadata.{
    Adaptive,
    AdaptiveLeaves,
    Binary,
    BinaryShapes,
    Codec,
    Shapes
  }

  setup do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    :ok
  end

  test "adaptive clocks use one canonical selector and preserve safe boundary integers" do
    for n <- [
          0,
          1,
          127,
          128,
          Bitwise.bsl(1, 42),
          Bitwise.bsl(1, 49) - 1,
          Bitwise.bsl(1, 49),
          Adaptive.safe()
        ] do
      assert byte_size(Adaptive.clock(n)) <= 7
      assert {^n, <<23>>} = Adaptive.take_clock(Adaptive.clock(n) <> <<23>>, Adaptive.fixed?(n))
    end

    assert byte_size(Adaptive.clock(Bitwise.bsl(1, 49) - 1)) == 7
    assert catch_error(Adaptive.take_clock(<<0::56>>, true))
    assert catch_error(Adaptive.take_clock(Binary.uint(Bitwise.bsl(1, 49)), false))
    assert catch_error(Adaptive.take_clock(<<Adaptive.safe() + 1::56>>, true))

    for bad <- [<<128, 0>>, <<128>>, <<255, 255, 255, 255, 255, 255, 255, 127>>] do
      assert catch_error(Adaptive.take_clock(bad, false))
    end
  end

  test "exact synthetic tag envelope and version separation carry no authentication" do
    assert byte_size(
             Adaptive.bytes(%{"version" => 3, "data" => "", "mac" => Adaptive.synthetic_tag()})
           ) == 75

    id = Shapes.hash(1)
    row = BinaryShapes.anchor()

    assert {:ok, page} =
             Adaptive.encode_page(
               :anchor_native_candidate,
               Adaptive.zero(:anchor_native_candidate),
               %{id => row}
             )

    assert {:error, _} = Binary.decode_page(page)

    assert {:ok, old} =
             Binary.encode_page(
               :anchor_native_candidate,
               Binary.zero(:anchor_native_candidate),
               %{id => row}
             )

    assert {:error, _} =
             Adaptive.decode_page(
               :anchor_native_candidate,
               Adaptive.zero(:anchor_native_candidate),
               old
             )

    # Another syntactically canonical synthetic tag is allowed: no MAC check exists here.
    tag = Base.url_encode64(<<1::256>>, padding: false)

    assert {:ok, _} =
             Adaptive.decode_page(
               :anchor_native_candidate,
               Adaptive.zero(:anchor_native_candidate),
               Map.put(page, "mac", tag)
             )

    for bad <- [
          Map.put(page, "mac", page["mac"] <> "="),
          Map.put(page, "extra", 1),
          Map.put(page, "version", 2)
        ] do
      assert {:error, _} =
               Adaptive.decode_page(
                 :anchor_native_candidate,
                 Adaptive.zero(:anchor_native_candidate),
                 bad
               )
    end
  end

  test "legacy and native facts roundtrip separately through all clock and retirement controls" do
    for {kind, make} <- [
          anchor_full: &Shapes.full_choice/1,
          anchor_native_candidate: &BinaryShapes.capsule/1
        ],
        profile <- [:calendar_2026, :safe_width, :bounded_fixture, :four_safe_clocks],
        ret <- [:none, :sticky_clock, :target_witness] do
      id = Shapes.hash(4)
      row = BinaryShapes.anchor(make.(id), BinaryShapes.retirement(id, ret, profile), profile)
      assert {:ok, page} = Adaptive.encode_page(kind, Adaptive.zero(kind), %{id => row})

      assert {:ok, %{entries: %{^id => ^row}}} =
               Adaptive.decode_page(kind, Adaptive.zero(kind), page)
    end
  end

  test "canonical flags front coding dictionaries ranges and all truncations refuse" do
    id = Shapes.hash(5)

    row =
      BinaryShapes.anchor(
        BinaryShapes.capsule(id),
        BinaryShapes.retirement(id, :target_witness),
        :four_safe_clocks
      )

    kind = :anchor_native_candidate
    assert {:ok, page} = Adaptive.encode_page(kind, Adaptive.zero(kind), %{id => row})
    raw = Base.url_decode64!(page["data"], padding: false)

    for n <- 0..(byte_size(raw) - 1) do
      assert {:error, _} =
               Adaptive.decode_page(
                 kind,
                 Adaptive.zero(kind),
                 raw_page(page, binary_part(raw, 0, n))
               )
    end

    assert {:error, _} =
             Adaptive.decode_page(kind, Adaptive.zero(kind), raw_page(page, raw <> <<0>>))

    assert {:error, _} = Adaptive.decode_page(kind, Adaptive.zero(kind), page, id)
    assert {:error, _} = Adaptive.decode_page(:anchor_full, Adaptive.zero(:anchor_full), page)

    ids =
      for n <- 1..128,
          do: Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(64, "0")

    small = %{"clocks" => [0, nil, nil, nil], "choice" => nil, "retirement" => nil}

    assert {:ok, compressed} =
             Adaptive.encode_page(kind, Adaptive.zero(kind), Map.new(ids, &{&1, small}))

    assert {:ok, %{entries: entries}} =
             Adaptive.decode_page(kind, Adaptive.zero(kind), compressed)

    assert map_size(entries) == 128

    assert {:error, _} =
             Adaptive.encode_page(
               kind,
               Adaptive.zero(kind),
               Map.put(entries, Shapes.hash(999), small)
             )

    assert {:error, _} = Adaptive.encode_page(kind, hd(ids), %{})
    raw = Base.url_decode64!(compressed["data"], padding: false)
    <<header::binary-size(7), 31, last, rest::binary>> = raw

    assert {:error, _} =
             Adaptive.decode_page(
               kind,
               Adaptive.zero(kind),
               raw_page(compressed, header <> <<30, 0, last>> <> rest)
             )

    # A fixed selector without its presence bit is forbidden, even with spare bytes.
    {:ok, one} = Adaptive.encode_page(kind, Adaptive.zero(kind), %{hd(ids) => small})

    <<header::binary-size(8), _flags, rest::binary>> =
      Base.url_decode64!(one["data"], padding: false)

    assert {:error, _} =
             Adaptive.decode_page(
               kind,
               Adaptive.zero(kind),
               raw_page(one, header <> <<16>> <> rest)
             )

    rows = Map.new(1..20, &BinaryShapes.live(&1))
    {:ok, live} = Adaptive.encode_page(:live, Adaptive.zero(:live), rows)
    assert {:ok, %{entries: ^rows}} = Adaptive.decode_page(:live, Adaptive.zero(:live), live)

    <<head::binary-size(6), count, hashes::binary-size(64), rest::binary>> =
      Base.url_decode64!(live["data"], padding: false)

    poison = head <> <<count + 1>> <> hashes <> <<255::256>> <> rest
    assert {:error, _} = Adaptive.decode_page(:live, Adaptive.zero(:live), raw_page(live, poison))
  end

  test "global weights prove byte-before-count and both single and double edit repair bounds" do
    p = AdaptiveLeaves.profile(:anchor_native_candidate)
    id = Shapes.hash(8)
    choice = BinaryShapes.capsule(id, %{"kind" => "duration", "duration_ms" => Adaptive.safe()})

    row = %{
      "clocks" => [Bitwise.bsl(1, 49), Bitwise.bsl(1, 50), Bitwise.bsl(1, 49), Bitwise.bsl(1, 50)],
      "choice" => choice,
      "retirement" => BinaryShapes.retirement(id, :target_witness)
    }

    assert AdaptiveLeaves.weight(p, id, row) == 337

    assert AdaptiveLeaves.weight(p, id, %{
             "clocks" => [0, nil, nil, nil],
             "choice" => nil,
             "retirement" => nil
           }) == 37

    for profile <- [
          p,
          AdaptiveLeaves.profile(:live, :per_row),
          AdaptiveLeaves.profile(:live, catalog())
        ] do
      assert profile.capacity >= 5 * profile.maximum
      assert profile.floor >= 2 * profile.maximum
      assert 128 * profile.minimum > profile.capacity
    end

    {live_id, live_maximum} = BinaryShapes.live(99)

    assert AdaptiveLeaves.weight(AdaptiveLeaves.profile(:live, :per_row), live_id, live_maximum) ==
             183

    rows =
      Map.new(1..128, fn n ->
        {Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(64, "0"),
         %{"clocks" => [0, nil, nil, nil], "choice" => nil, "retirement" => nil}}
      end)

    assert {:ok, pages} = AdaptiveLeaves.initialize(p, rows)
    assert length(pages) > 1
    assert AdaptiveLeaves.validate_tree!(p, pages) == rows
    # Full legacy evidence is still encodable, but has no admitted native-only global weight.
    legacy = BinaryShapes.anchor(Shapes.full_choice(id))
    assert Adaptive.row_bytes(:anchor_full, id, legacy) > 337
  end

  test "two disjoint adjacent repairs retain boundaries and local plans match a pure oracle" do
    p = AdaptiveLeaves.profile(:anchor_native_candidate)
    initial = Map.new(1..180, fn n -> {Shapes.hash(n), anchor(n, true)} end)
    {:ok, pages} = AdaptiveLeaves.initialize(p, initial)

    {pages, oracle} =
      Enum.reduce(1..180, {pages, initial}, fn n, {pages, oracle} ->
        id = Shapes.hash(rem(n, 180) + 1)
        second = Shapes.hash(1000 + n)
        replacement = if rem(n, 3) == 0, do: nil, else: anchor(rem(n, 180) + 1, rem(n, 2) == 0)
        edits = [{id, replacement}, {second, anchor(1000 + n, rem(n, 2) == 1)}]
        refs = AdaptiveLeaves.refs(p, pages)
        values = Map.new(pages, fn {f, v} -> {AdaptiveLeaves.key(p.kind, f), v} end)
        assert {:ok, needed} = AdaptiveLeaves.required(p, refs, values, edits)
        assert length(needed) <= 4
        assert {:ok, plan} = AdaptiveLeaves.plan(p, refs, Map.take(values, needed), edits)
        assert length(plan.changes) <= 6
        assert plan.old_pages <= 4
        pages = AdaptiveLeaves.apply_plan(p, pages, plan)

        oracle =
          Enum.reduce(edits, oracle, fn {key, value}, acc ->
            if is_nil(value), do: Map.delete(acc, key), else: Map.put(acc, key, value)
          end)

        assert AdaptiveLeaves.validate_tree!(p, pages) == oracle
        {pages, oracle}
      end)

    assert map_size(oracle) > 0 and length(pages) > 1
  end

  test "dictionary union is charged by a global catalog or inline per-row allowance" do
    catalog = catalog()

    rows =
      Map.new(1..120, fn n ->
        {id, row} = BinaryShapes.live(n, false, :calendar_2026)

        {id,
         row
         |> List.replace_at(2, Enum.at(catalog, rem(n, 4)))
         |> List.replace_at(3, Enum.at(catalog, rem(n + 1, 4)))}
      end)

    for p <- [AdaptiveLeaves.profile(:live, catalog), AdaptiveLeaves.profile(:live, :per_row)] do
      assert {:ok, pages} = AdaptiveLeaves.initialize(p, rows)
      assert AdaptiveLeaves.validate_tree!(p, pages) == rows
      edits = rows |> Enum.sort() |> Enum.take(2) |> Enum.map(fn {id, _} -> {id, nil} end)
      refs = AdaptiveLeaves.refs(p, pages)
      values = Map.new(pages, fn {f, v} -> {AdaptiveLeaves.key(p.kind, f), v} end)
      assert {:ok, needed} = AdaptiveLeaves.required(p, refs, values, edits)
      assert {:ok, plan} = AdaptiveLeaves.plan(p, refs, Map.take(values, needed), edits)
      next = AdaptiveLeaves.apply_plan(p, pages, plan)

      assert AdaptiveLeaves.validate_tree!(p, next) ==
               Map.drop(rows, Enum.map(edits, &elem(&1, 0)))
    end

    {id, row} = hd(Enum.sort(rows))

    assert catch_error(
             AdaptiveLeaves.weight(AdaptiveLeaves.profile(:live, Enum.take(catalog, 1)), id, row)
           )

    distinct =
      Map.new(rows, fn {id, row} ->
        {id,
         row
         |> List.replace_at(2, Codec.packed_hash(Shapes.hash(id)))
         |> List.replace_at(3, Codec.packed_hash(Shapes.hash(id <> "policy")))}
      end)

    assert {:ok, pages} =
             AdaptiveLeaves.initialize(AdaptiveLeaves.profile(:live, :per_row), distinct)

    assert AdaptiveLeaves.validate_tree!(AdaptiveLeaves.profile(:live, :per_row), pages) ==
             distinct
  end

  test "poisoned directories selected ranges duplicate edits and absent deletions fail closed" do
    p = AdaptiveLeaves.profile(:anchor_native_candidate)
    rows = Map.new(1..200, fn n -> {Shapes.hash(n), anchor(n, false)} end)
    {:ok, pages} = AdaptiveLeaves.initialize(p, rows)
    refs = AdaptiveLeaves.refs(p, pages)
    values = Map.new(pages, fn {f, v} -> {AdaptiveLeaves.key(p.kind, f), v} end)
    id = hd(Map.keys(rows))
    edits = [{id, nil}]
    assert {:error, _} = AdaptiveLeaves.required(p, tl(refs), values, edits)
    assert {:error, _} = AdaptiveLeaves.required(p, [hd(refs) | refs], values, edits)
    assert {:error, _} = AdaptiveLeaves.required(p, Enum.reverse(refs), values, edits)

    assert {:error, _} =
             AdaptiveLeaves.required(p, refs, values, [{id, nil}, {id, anchor(1, false)}])

    assert {:error, _} = AdaptiveLeaves.required(p, refs, values, [{Shapes.hash("absent"), nil}])
    {:ok, needed} = AdaptiveLeaves.required(p, refs, values, edits)
    selected = Map.take(values, needed)
    poison = Map.update!(selected, hd(needed), &Map.put(&1, "data", &1["data"] <> "="))
    assert {:error, _} = AdaptiveLeaves.plan(p, refs, poison, edits)
    assert {:error, _} = AdaptiveLeaves.plan(p, refs, Map.put(selected, "unselected", %{}), edits)
    assert AdaptiveLeaves.validate_tree!(p, pages) == rows
    assert {:ok, [{zero, empty}]} = AdaptiveLeaves.initialize(p, %{})
    assert zero == Adaptive.zero(p.kind)
    assert {:ok, %{entries: %{}}} = Adaptive.decode_page(p.kind, zero, empty)
    assert {:error, _} = Adaptive.decode_page(p.kind, zero, empty, Shapes.hash("upper"))
  end

  defp anchor(n, large) do
    id = Shapes.hash(n)
    BinaryShapes.anchor(if(large, do: BinaryShapes.capsule(id), else: nil), nil, :calendar_2026)
  end

  defp catalog, do: Enum.map(1..4, &Codec.packed_hash(Shapes.hash("hash#{&1}"))) |> Enum.sort()
  defp raw_page(page, raw), do: Map.put(page, "data", Base.url_encode64(raw, padding: false))
end
