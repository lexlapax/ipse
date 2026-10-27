defmodule Ipse.Development.ManagedMetadata.AdaptiveMsgpax do
  @moduledoc "Evaluation-only Msgpax schema arrays over identical declared facts; never a product decoder."
  alias Ipse.Development.ManagedMetadata.{Adaptive, Binary, Codec}
  @kinds [:live, :anchor_full, :anchor_native_candidate]

  def controls do
    nonminimal = <<0xCD, 0, 1>>
    {:ok, 1} = Msgpax.unpack(nonminimal)
    true = Msgpax.pack!(1, iodata: false) != nonminimal
    large = Adaptive.safe() + 1
    {:ok, ^large} = Msgpax.unpack(<<0xCF, large::64>>)
    false = Codec.uint?(large)
    {:ok, duplicate_map} = Msgpax.unpack(<<0x82, 0xA1, ?k, 1, 0xA1, ?k, 2>>)
    true = map_size(duplicate_map) == 1
    {:error, _} = Msgpax.unpack(<<0xDD, 0xFFFF_FFFF::32>>)

    %{
      schema_arrays_roundtrip_in_page_jobs: true,
      nonminimal_integer_requires_reencode_refusal: true,
      above_safe_integer_requires_schema_refusal: true,
      duplicate_map_collapses_to_one_member: duplicate_map,
      incomplete_huge_declared_array_refuses: true,
      generic_parser_is_not_closed_schema_or_authority: true
    }
  end

  def compare(kind, fence, entries) do
    {:ok, adaptive} = Adaptive.encode_page(kind, fence, entries)
    schema = schema(kind, fence, entries)
    packed = Msgpax.pack!(schema, iodata: false)
    true = byte_size(packed) <= 32768
    {:ok, ^schema} = Msgpax.unpack(packed, binary: true)
    true = Msgpax.pack!(schema, iodata: false) == packed
    ^entries = restore(kind, fence, schema)

    value = %{
      "version" => 3,
      "data" => Base.url_encode64(packed, padding: false),
      "mac" => Adaptive.synthetic_tag()
    }

    raw = Base.url_decode64!(adaptive["data"], padding: false)
    wrapped = Msgpax.pack!(bin(raw), iodata: false)

    %{
      rows: map_size(entries),
      adaptive_raw: byte_size(raw),
      adaptive_value: byte_size(Adaptive.bytes(adaptive)),
      msgpax_schema_raw: byte_size(packed),
      msgpax_schema_value: byte_size(Adaptive.bytes(value)),
      msgpax_schema_fits_6144: byte_size(Adaptive.bytes(value)) <= 6144,
      wrapped_adaptive_binary_overhead: byte_size(wrapped) - byte_size(raw),
      roundtrip_all_fields: true,
      adaptive_sha256: Ipse.JSON.sha256(Adaptive.bytes(adaptive)),
      schema_sha256: Ipse.JSON.sha256(packed)
    }
  end

  defp schema(kind, fence, entries) do
    bank =
      if kind == :live,
        do:
          entries
          |> Enum.flat_map(fn {_, row} -> [Enum.at(row, 2), Enum.at(row, 3)] end)
          |> Enum.uniq()
          |> Enum.sort(),
        else: []

    {rows, _} =
      Enum.map_reduce(Enum.sort(entries), Base.decode16!(fence, case: :lower), fn {key, row},
                                                                                  previous ->
        raw = Base.decode16!(key, case: :lower)
        prefix = common(previous, raw)

        {[
           prefix,
           bin(binary_part(raw, prefix, byte_size(raw) - prefix)),
           row(kind, key, row, bank)
         ], raw}
      end)

    [2, Enum.find_index(@kinds, &(&1 == kind)), Enum.map(bank, &binhash/1), rows]
  end

  defp restore(kind, fence, [2, tag, bank, rows]) do
    true = Enum.at(@kinds, tag) == kind
    bank = Enum.map(bank, &b64(unbin(&1)))

    {rows, _} =
      Enum.map_reduce(rows, Base.decode16!(fence, case: :lower), fn [prefix, suffix, row],
                                                                    previous ->
        raw = binary_part(previous, 0, prefix) <> unbin(suffix)
        key = Base.encode16(raw, case: :lower)
        {{key, unrow(kind, key, row, bank)}, raw}
      end)

    Map.new(rows)
  end

  defp row(
         :live,
         _,
         [lineage, value, recipe, policy, first, deadline, category, eligibility],
         bank
       ) do
    first = number(first)
    delta = if is_nil(deadline), do: nil, else: number(deadline) - first

    [
      binhash(lineage),
      binhash(value),
      Enum.find_index(bank, &(&1 == recipe)),
      Enum.find_index(bank, &(&1 == policy)),
      first,
      delta,
      category,
      eligibility
    ]
  end

  defp row(kind, key, row, _) do
    [a, b, c, d] = row["clocks"]

    [
      a,
      if(is_nil(b), do: nil, else: b - a),
      c,
      if(is_nil(d), do: nil, else: d - c),
      choice(kind, key, row["choice"]),
      retirement(row["retirement"])
    ]
  end

  defp unrow(:live, _, [lineage, value, r, p, first, delta, category, eligibility], bank) do
    [
      b64(unbin(lineage)),
      b64(unbin(value)),
      Enum.at(bank, r),
      Enum.at(bank, p),
      base36(first),
      base36(if(is_nil(delta), do: nil, else: first + delta)),
      category,
      eligibility
    ]
  end

  defp unrow(kind, key, [a, b, c, d, choice, retirement], _) do
    %{
      "clocks" => [a, if(is_nil(b), do: nil, else: a + b), c, if(is_nil(d), do: nil, else: c + d)],
      "choice" => unchoice(kind, key, choice),
      "retirement" => unretirement(retirement)
    }
  end

  defp choice(_, _, nil), do: nil

  defp choice(:anchor_native_candidate, id, value) do
    # Fixed capsule framing is checked by the frozen codec before field projection.
    _ = Binary.capsule_encode(id, value)
    {code, duration} = policy(value["policy"])

    [
      2,
      binhex(value["event_id"]),
      binhex(value["display_sha256"]),
      binhex(value["challenge"]),
      binhex(Codec.live_identity(value["target_key"])),
      binhex(value["target_value_sha256"]),
      value["observed_at_ms"],
      code,
      value["reason"],
      duration
    ]
  end

  defp choice(:anchor_full, id, value) do
    {:ok, wire} =
      Codec.encode_anchor(id, %{
        "note_first_ms" => 0,
        "note_deadline_ms" => 1,
        "pending_first_ms" => nil,
        "pending_deadline_ms" => nil,
        "choice" => value
      })

    [policy, reason, at, proof] = Enum.at(wire, 4)
    [s, o, v, k, c, a, b, q, qh, ch, rh] = proof

    policy =
      case policy do
        [code] -> [code]
        [3, d] -> [3, number(d)]
      end

    [
      1,
      policy,
      binhash(reason),
      number(at),
      [
        binhash(s),
        binhash(o),
        binhash(v),
        k,
        c,
        number(a),
        number(b) - number(a),
        binhash(q),
        binhash(qh),
        binhash(ch),
        binhash(rh)
      ]
    ]
  end

  defp unchoice(_, _, nil), do: nil

  defp unchoice(:anchor_native_candidate, id, [
         2,
         event,
         display,
         challenge,
         key,
         value,
         at,
         code,
         reason,
         duration
       ]) do
    suffix = if is_nil(duration), do: <<>>, else: <<duration::56>>

    raw =
      unbin(event) <>
        unbin(display) <>
        unbin(challenge) <>
        unbin(key) <> unbin(value) <> <<at::56, code, byte_size(reason) - 1>> <> reason <> suffix

    {value, <<>>} = Binary.capsule_decode(id, raw)
    value
  end

  defp unchoice(:anchor_full, id, [1, policy, reason, at, [s, o, v, k, c, a, b, q, qh, ch, rh]]) do
    policy =
      case policy do
        [code] -> [code]
        [3, d] -> [3, base36(d)]
      end

    proof = [
      b64(unbin(s)),
      b64(unbin(o)),
      b64(unbin(v)),
      k,
      c,
      base36(a),
      base36(a + b),
      b64(unbin(q)),
      b64(unbin(qh)),
      b64(unbin(ch)),
      b64(unbin(rh))
    ]

    {:ok, value} =
      Codec.decode_anchor(id, [
        "0",
        "1",
        nil,
        nil,
        [policy, b64(unbin(reason)), base36(at), proof]
      ])

    value["choice"]
  end

  defp retirement(nil), do: nil
  defp retirement(%{"target_kind" => "native_literal_note", "at_ms" => at}), do: [1, at]

  defp retirement(%{"record_key" => key, "record_value_sha256" => value, "at_ms" => at}),
    do: [2, at, binhex(Codec.live_identity(key)), binhex(value)]

  defp unretirement(nil), do: nil
  defp unretirement([1, at]), do: %{"target_kind" => "native_literal_note", "at_ms" => at}

  defp unretirement([2, at, key, value]),
    do: %{
      "record_key" => Codec.live_key(Base.encode16(unbin(key), case: :lower)),
      "record_value_sha256" => Base.encode16(unbin(value), case: :lower),
      "at_ms" => at
    }

  defp policy(%{"kind" => "duration", "duration_ms" => d}), do: {3, d}

  defp policy(%{"kind" => kind}),
    do: {Enum.find_index(~w(pin ordinary session), &(&1 == kind)), nil}

  defp number(value), do: String.to_integer(value, 36)
  defp base36(nil), do: nil
  defp base36(n), do: Integer.to_string(n, 36) |> String.downcase()
  defp bin(binary), do: Msgpax.Bin.new(binary)
  defp unbin(%Msgpax.Bin{data: data}), do: data
  defp binhex(hex), do: bin(Base.decode16!(hex, case: :lower))
  defp binhash(b64), do: bin(Base.url_decode64!(b64, padding: false))
  defp b64(binary), do: Base.url_encode64(binary, padding: false)
  defp common(a, b), do: common(a, b, 0)
  defp common(<<a, ar::binary>>, <<a, br::binary>>, n), do: common(ar, br, n + 1)
  defp common(_, _, n), do: n
end
