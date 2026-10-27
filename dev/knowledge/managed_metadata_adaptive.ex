defmodule Ipse.Development.ManagedMetadata.Adaptive do
  @moduledoc "Pure IMB2 experiment: synthetic MAC syntax is not authentication or publication authority."
  alias Ipse.Development.ManagedMetadata.{Binary, Codec}
  import Bitwise
  @safe 9_007_199_254_740_991
  @fixed_at 562_949_953_421_312
  @kinds [:live, :anchor_full, :anchor_native_candidate]

  def safe, do: @safe
  def width(kind), do: Binary.width(kind)
  def zero(kind), do: Binary.zero(kind)
  def bytes(value), do: Codec.bytes(value)
  def synthetic_tag, do: Base.url_encode64(<<0::256>>, padding: false)
  def fixed?(n), do: is_integer(n) and n >= @fixed_at

  def clock(n) when is_integer(n) and n in 0..@safe do
    if fixed?(n), do: <<n::56>>, else: Binary.uint(n)
  end

  def take_clock(binary, true) do
    <<n::56, rest::binary>> = binary
    true = n in @fixed_at..@safe
    {n, rest}
  end

  def take_clock(binary, false) do
    {n, rest} = Binary.take_uint(binary)
    true = n < @fixed_at
    {n, rest}
  end

  def encode_page(kind, fence, entries, tag \\ synthetic_tag()) do
    checked(fn ->
      true = kind in @kinds and is_map(entries) and map_size(entries) <= 128
      previous = identity(kind, fence)
      true = map_size(entries) > 0 or fence == zero(kind)
      _ = hash(tag)
      rows = Enum.sort(entries)
      true = Enum.all?(rows, fn {key, _} -> key >= fence end)
      {bank, dictionary} = dictionary(kind, rows)

      {pieces, _} =
        Enum.map_reduce(rows, previous, fn {key, row}, previous ->
          key = identity(kind, key)
          prefix = common(previous, key)
          piece = <<prefix>> <> binary_part(key, prefix, byte_size(key) - prefix)
          {piece <> row_encode(kind, hex(key), row, bank), key}
        end)

      raw =
        <<"IMB", 2, Enum.find_index(@kinds, &(&1 == kind))>> <>
          Binary.uint(length(rows)) <> dictionary <> IO.iodata_to_binary(pieces)

      value = %{"version" => 3, "data" => Base.url_encode64(raw, padding: false), "mac" => tag}
      true = byte_size(bytes(value)) <= 6144
      value
    end)
  end

  def decode_page(kind, fence, value, upper \\ nil) do
    checked(fn ->
      true = kind in @kinds and Codec.keys?(value, ~w(version data mac))
      true = value["version"] === 3 and byte_size(bytes(value)) <= 6144
      _ = hash(value["mac"])
      true = is_binary(value["data"]) and byte_size(value["data"]) <= 6144
      {:ok, raw} = Base.url_decode64(value["data"], padding: false)
      true = Base.url_encode64(raw, padding: false) == value["data"]
      previous = identity(kind, fence)
      upper = if is_nil(upper), do: nil, else: identity(kind, upper)
      true = is_nil(upper) or previous < upper
      <<"IMB", 2, tag, rest::binary>> = raw
      true = Enum.at(@kinds, tag) == kind
      {count, rest} = Binary.take_uint(rest)
      true = count <= 128
      true = count > 0 or (fence == zero(kind) and is_nil(upper))
      {bank, rest} = take_dictionary(kind, rest)

      {rows, <<>>, _} =
        Enum.reduce(times(count), {%{}, rest, previous}, fn _, {rows, rest, previous} ->
          <<prefix, rest::binary>> = rest
          true = prefix <= width(kind)
          suffix_size = width(kind) - prefix
          <<suffix::binary-size(^suffix_size), rest::binary>> = rest
          key = binary_part(previous, 0, prefix) <> suffix
          true = common(previous, key) == prefix
          true = key >= identity(kind, fence) and (is_nil(upper) or key < upper)
          true = map_size(rows) == 0 or key > previous
          {row, rest} = row_decode(kind, hex(key), rest, bank)
          {Map.put(rows, hex(key), row), rest, key}
        end)

      {:ok, ^value} = encode_page(kind, fence, rows, value["mac"])
      %{kind: kind, fence: fence, entries: rows}
    end)
  end

  def row_bytes(kind, key, row), do: byte_size(row_encode(kind, key, row, :inline))

  defp dictionary(:live, rows) do
    bank =
      rows
      |> Enum.flat_map(fn {_, row} -> [Enum.at(row, 2), Enum.at(row, 3)] end)
      |> Enum.uniq()
      |> Enum.sort()

    true = length(bank) <= 256
    {bank, Binary.uint(length(bank)) <> IO.iodata_to_binary(Enum.map(bank, &hash/1))}
  end

  defp dictionary(_, _), do: {[], <<>>}

  defp take_dictionary(:live, rest) do
    {count, rest} = Binary.take_uint(rest)
    true = count <= 256
    size = count * 32
    <<bank::binary-size(^size), rest::binary>> = rest
    bank = for <<item::binary-size(32) <- bank>>, do: b64(item)
    true = bank == Enum.sort(Enum.uniq(bank))
    {bank, rest}
  end

  defp take_dictionary(_, rest), do: {[], rest}

  defp row_encode(:live, key, row, bank) do
    true = Codec.valid_wire?(:live, key, row)
    [lineage, value, recipe, policy, first, deadline, category, eligibility] = row
    first = number(first)
    delta = if is_nil(deadline), do: nil, else: number(deadline) - first

    flags =
      if(is_nil(delta), do: 0, else: 1) +
        if(fixed?(first), do: 2, else: 0) + if fixed?(delta), do: 4, else: 0

    hashes =
      if bank == :inline,
        do: hash(recipe) <> hash(policy),
        else:
          Binary.uint(Enum.find_index(bank, &(&1 == recipe))) <>
            Binary.uint(Enum.find_index(bank, &(&1 == policy)))

    hash(lineage) <>
      hash(value) <>
      hashes <>
      <<flags>> <>
      clock(first) <>
      if(is_nil(delta), do: <<>>, else: clock(delta)) <> <<category, eligibility>>
  end

  defp row_encode(kind, key, row, _) do
    validate_anchor(key, row)
    [a, b, c, d] = row["clocks"]
    clocks = [a, if(is_nil(b), do: nil, else: b - a), c, if(is_nil(d), do: nil, else: d - c)]

    flags =
      Enum.with_index(clocks)
      |> Enum.reduce(0, fn {n, i}, acc ->
        if is_nil(n),
          do: acc,
          else: bor(acc, bsl(1, i) + if(fixed?(n), do: bsl(1, i + 4), else: 0))
      end)

    encoded = Enum.map(clocks, fn n -> if is_nil(n), do: <<>>, else: clock(n) end)

    choice =
      case {kind, row["choice"]} do
        {_, nil} ->
          <<0>>

        {:anchor_native_candidate, value} ->
          <<2>> <> Binary.capsule_encode(key, value)

        {:anchor_full, value} ->
          encoded = legacy_encode(key, value)
          <<1>> <> Binary.uint(byte_size(encoded)) <> encoded
      end

    <<flags>> <> IO.iodata_to_binary(encoded) <> choice <> retirement(row["retirement"])
  end

  defp row_decode(
         :live,
         key,
         <<lineage::binary-size(32), value::binary-size(32), rest::binary>>,
         bank
       ) do
    {r, rest} = Binary.take_uint(rest)
    {p, rest} = Binary.take_uint(rest)
    true = r < length(bank) and p < length(bank)
    <<flags, rest::binary>> = rest
    true = flags in 0..7 and (band(flags, 1) != 0 or band(flags, 4) == 0)
    {first, rest} = take_clock(rest, band(flags, 2) != 0)

    {deadline, rest} =
      if band(flags, 1) == 0,
        do: {nil, rest},
        else:
          (
            {delta, rest} = take_clock(rest, band(flags, 4) != 0)
            true = Codec.uint?(first + delta)
            {first + delta, rest}
          )

    <<category, eligibility, rest::binary>> = rest

    row = [
      b64(lineage),
      b64(value),
      Enum.at(bank, r),
      Enum.at(bank, p),
      base36(first),
      base36(deadline),
      category,
      eligibility
    ]

    true = Codec.valid_wire?(:live, key, row)
    {row, rest}
  end

  defp row_decode(kind, key, <<flags, rest::binary>>, _) do
    {clocks, rest} =
      Enum.map_reduce(0..3, rest, fn i, rest ->
        present = band(flags, bsl(1, i)) != 0
        fixed = band(flags, bsl(1, i + 4)) != 0
        true = present or not fixed
        if present, do: take_clock(rest, fixed), else: {nil, rest}
      end)

    [a, b, c, d] = clocks
    b = if is_nil(b), do: nil, else: a + b
    d = if is_nil(d), do: nil, else: c + d
    <<tag, rest::binary>> = rest

    {choice, rest} =
      case {kind, tag} do
        {_, 0} ->
          {nil, rest}

        {:anchor_native_candidate, 2} ->
          Binary.capsule_decode(key, rest)

        {:anchor_full, 1} ->
          {length, rest} = Binary.take_uint(rest)
          true = length in 1..4096
          <<encoded::binary-size(^length), rest::binary>> = rest
          {legacy_decode(key, encoded), rest}
      end

    {retirement, rest} = take_retirement(rest)
    row = %{"clocks" => [a, b, c, d], "choice" => choice, "retirement" => retirement}
    validate_anchor(key, row)
    {row, rest}
  end

  defp validate_anchor(key, row) do
    true = Codec.keys?(row, ~w(clocks choice retirement))
    [a, b, c, d] = row["clocks"]

    {:ok, _} =
      Codec.encode_anchor(key, %{
        "note_first_ms" => a,
        "note_deadline_ms" => b,
        "pending_first_ms" => c,
        "pending_deadline_ms" => d,
        "choice" => nil
      })
  end

  defp retirement(nil), do: <<0>>

  defp retirement(row) do
    true = Codec.uint?(row["at_ms"])
    flag = if fixed?(row["at_ms"]), do: 4, else: 0

    cond do
      Codec.keys?(row, ~w(target_kind at_ms)) ->
        true = row["target_kind"] == "native_literal_note"
        <<1 + flag>> <> clock(row["at_ms"])

      Codec.keys?(row, ~w(record_key record_value_sha256 at_ms)) ->
        key = Base.decode16!(Codec.live_identity(row["record_key"]), case: :lower)

        <<2 + flag>> <>
          clock(row["at_ms"]) <> key <> hash(Codec.packed_hash(row["record_value_sha256"]))
    end
  end

  defp take_retirement(<<0, rest::binary>>), do: {nil, rest}

  defp take_retirement(<<tag, rest::binary>>) when tag in [1, 2, 5, 6] do
    {at, rest} = take_clock(rest, tag >= 4)

    if rem(tag, 4) == 1,
      do: {%{"target_kind" => "native_literal_note", "at_ms" => at}, rest},
      else:
        (
          <<key::binary-size(33), value::binary-size(32), rest::binary>> = rest

          {%{
             "at_ms" => at,
             "record_key" => Codec.live_key(hex(key)),
             "record_value_sha256" => hex(value)
           }, rest}
        )
  end

  # The immutable IMB1 choice codec remains the single legacy field definition.
  defp legacy_encode(key, choice) do
    row = %{"clocks" => [0, 1, nil, nil], "choice" => choice, "retirement" => nil}
    {:ok, value} = Binary.encode_page(:anchor_full, Binary.zero(:anchor_full), %{key => row})
    <<"IMB", 1, 1, 1, prefix, rest::binary>> = Base.url_decode64!(value["data"], padding: false)
    n = 32 - prefix
    <<_suffix::binary-size(^n), 3, 0, 1, 1, rest::binary>> = rest
    n = byte_size(rest) - 1
    <<choice::binary-size(^n), 0>> = rest
    choice
  end

  defp legacy_decode(key, choice) do
    id = identity(:anchor_full, key)
    prefix = common(<<0::256>>, id)
    suffix = binary_part(id, prefix, 32 - prefix)
    raw = <<"IMB", 1, 1, 1, prefix>> <> suffix <> <<3, 0, 1, 1>> <> choice <> <<0>>

    old = %{
      "version" => 1,
      "kind" => "anchor_full",
      "fence" => Binary.zero(:anchor_full),
      "data" => b64(raw)
    }

    {:ok, %{entries: entries}} = Binary.decode_page(old)
    entries[key]["choice"]
  end

  defp identity(kind, key) do
    true = is_binary(key) and byte_size(key) == width(kind) * 2
    if kind == :live, do: Codec.live_key(key)
    Base.decode16!(key, case: :lower)
  end

  defp hash(value) do
    true = is_binary(value) and byte_size(value) == 43
    {:ok, raw} = Base.url_decode64(value, padding: false)
    true = byte_size(raw) == 32 and b64(raw) == value
    raw
  end

  defp common(a, b), do: common(a, b, 0)
  defp common(<<a, ar::binary>>, <<a, br::binary>>, n), do: common(ar, br, n + 1)
  defp common(_, _, n), do: n
  defp b64(binary), do: Base.url_encode64(binary, padding: false)
  defp hex(binary), do: Base.encode16(binary, case: :lower)
  defp number(nil), do: nil
  defp number(value), do: String.to_integer(value, 36)
  defp base36(nil), do: nil
  defp base36(n), do: Integer.to_string(n, 36) |> String.downcase()
  defp times(0), do: []
  defp times(n), do: 1..n

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_adaptive_metadata}
  end
end
