defmodule Ipse.Development.ManagedMetadata.Binary do
  @moduledoc "Nonpublishing binary metadata experiment; candidate bytes establish no authority."
  alias Ipse.Development.ManagedMetadata.Codec, as: C
  import Bitwise
  @safe 9_007_199_254_740_991
  @kinds [:live, :anchor_full, :anchor_native_candidate]
  @capsule ~w(version kind event_id display_sha256 challenge target_key target_value_sha256 lineage observed_at_ms policy reason input_sha256)

  def safe, do: @safe
  def width(:live), do: 33
  def width(k) when k in [:anchor_full, :anchor_native_candidate], do: 32
  def zero(kind), do: String.duplicate("0", width(kind) * 2)
  def bytes(v), do: C.bytes(v)
  def b64(n), do: div(n * 8 + 5, 6)

  def uint(n) when is_integer(n) and n in 0..@safe do
    if n < 128, do: <<n>>, else: <<bor(band(n, 127), 128)>> <> uint(bsr(n, 7))
  end

  def take_uint(binary), do: take_uint(binary, 0, 0, <<>>)

  defp take_uint(<<byte, rest::binary>>, shift, acc, seen) when shift <= 49 do
    value = acc + bsl(band(byte, 127), shift)
    seen = seen <> <<byte>>
    true = value <= @safe

    if byte < 128 do
      true = uint(value) == seen
      {value, rest}
    else
      take_uint(rest, shift + 7, value, seen)
    end
  end

  def encode_page(kind, fence, entries) do
    checked(fn ->
      true = kind in @kinds and is_map(entries) and map_size(entries) <= 64
      _ = id(kind, fence)
      true = map_size(entries) > 0 or fence == zero(kind)
      ordered = Enum.sort(entries)
      true = Enum.all?(ordered, fn {key, _} -> key >= fence end)
      {bank, bank_bytes} = bank(kind, ordered)

      {parts, _} =
        Enum.map_reduce(ordered, id(kind, fence), fn {key, row}, previous ->
          raw = id(kind, key)
          prefix = common(previous, raw)
          suffix = binary_part(raw, prefix, byte_size(raw) - prefix)
          {<<prefix>> <> suffix <> row_encode(kind, key, row, bank), raw}
        end)

      raw =
        <<"IMB", 1, Enum.find_index(@kinds, &(&1 == kind))>> <>
          uint(length(ordered)) <> bank_bytes <> IO.iodata_to_binary(parts)

      value = %{
        "version" => 1,
        "kind" => Atom.to_string(kind),
        "fence" => fence,
        "data" => Base.url_encode64(raw, padding: false)
      }

      true = byte_size(bytes(value)) <= 6144
      value
    end)
  end

  def decode_page(value, next_fence \\ nil) do
    checked(fn ->
      true = C.keys?(value, ~w(version kind fence data)) and value["version"] === 1
      true = is_binary(value["kind"]) and byte_size(value["kind"]) <= 32
      true = is_binary(value["fence"]) and byte_size(value["fence"]) in [64, 66]
      true = is_binary(value["data"]) and byte_size(value["data"]) <= 6144
      true = byte_size(bytes(value)) <= 6144
      kind = Enum.find(@kinds, &(Atom.to_string(&1) == value["kind"]))
      true = kind in @kinds
      fence = id(kind, value["fence"])
      upper = if is_nil(next_fence), do: nil, else: id(kind, next_fence)
      true = is_nil(upper) or fence < upper
      encoded = value["data"]
      true = is_binary(encoded) and byte_size(encoded) <= 6144
      {:ok, raw} = Base.url_decode64(encoded, padding: false)
      true = Base.url_encode64(raw, padding: false) == encoded
      <<"IMB", 1, tag, rest::binary>> = raw
      true = Enum.at(@kinds, tag) == kind
      {count, rest} = take_uint(rest)
      true = count <= 64
      {bank, rest} = take_bank(kind, rest)

      {entries, <<>>, _} =
        Enum.reduce(times(count), {%{}, rest, fence}, fn _, {rows, binary, previous} ->
          <<prefix, rest::binary>> = binary
          true = prefix <= width(kind)
          n = width(kind) - prefix
          <<suffix::binary-size(^n), rest::binary>> = rest
          key = binary_part(previous, 0, prefix) <> suffix
          true = common(previous, key) == prefix

          true =
            key >= fence and (is_nil(upper) or key < upper) and
              (map_size(rows) == 0 or key > previous)

          hex = hex(key)
          _ = id(kind, hex)
          {row, rest} = row_decode(kind, hex, rest, bank)
          {Map.put(rows, hex, row), rest, key}
        end)

      {:ok, ^value} = encode_page(kind, value["fence"], entries)
      %{kind: kind, fence: value["fence"], entries: entries}
    end)
  end

  def row_bytes(kind, key, row), do: byte_size(row_encode(kind, key, row, :inline))

  def capsule_encode(lineage, capsule) do
    true = C.keys?(capsule, @capsule)
    true = capsule["version"] === 2 and capsule["kind"] == "candidate_native_management"
    true = capsule["lineage"] == lineage and C.sha?(lineage)
    {code, verb, duration} = choice(capsule["policy"])
    challenge = raw(capsule["challenge"], 8)
    input = verb <> " " <> hex(challenge)
    true = capsule["input_sha256"] == Ipse.JSON.sha256(input)
    reason = capsule["reason"]
    true = is_binary(reason) and String.valid?(reason) and byte_size(reason) in 1..64
    key = raw(C.live_identity(capsule["target_key"]), 33)
    at = capsule["observed_at_ms"]
    true = C.uint?(at)

    raw(capsule["event_id"], 16) <>
      raw(capsule["display_sha256"], 32) <>
      challenge <>
      key <>
      raw(capsule["target_value_sha256"], 32) <>
      <<at::56, code, byte_size(reason) - 1>> <>
      reason <> duration
  end

  def capsule_decode(lineage, binary) do
    <<event::binary-size(16), display::binary-size(32), challenge::binary-size(8),
      target::binary-size(33), value::binary-size(32), at::56, code, reason_minus_one,
      rest::binary>> = binary

    true = C.uint?(at) and reason_minus_one < 64
    length = reason_minus_one + 1
    <<reason::binary-size(^length), rest::binary>> = rest

    {policy, rest} =
      case code do
        0 ->
          {%{"kind" => "pin"}, rest}

        1 ->
          {%{"kind" => "ordinary"}, rest}

        2 ->
          {%{"kind" => "session"}, rest}

        3 ->
          <<duration::56, rest::binary>> = rest
          true = C.uint?(duration) and duration > 0
          {%{"kind" => "duration", "duration_ms" => duration}, rest}
      end

    {_, verb, _} = choice(policy)

    result = %{
      "version" => 2,
      "kind" => "candidate_native_management",
      "lineage" => lineage,
      "event_id" => hex(event),
      "display_sha256" => hex(display),
      "challenge" => hex(challenge),
      "target_key" => C.live_key(hex(target)),
      "target_value_sha256" => hex(value),
      "observed_at_ms" => at,
      "policy" => policy,
      "reason" => reason,
      "input_sha256" => Ipse.JSON.sha256(verb <> " " <> hex(challenge))
    }

    _ = capsule_encode(lineage, result)
    {result, rest}
  end

  defp choice(policy) do
    true = is_map(policy)

    case policy["kind"] do
      kind when kind in ~w(pin ordinary session) ->
        true = C.keys?(policy, ["kind"])
        code = Enum.find_index(~w(pin ordinary session), &(&1 == kind))
        verb = Enum.at(~w(pin ordinary forget), code)
        {code, verb, <<>>}

      "duration" ->
        true = C.keys?(policy, ~w(kind duration_ms))
        n = policy["duration_ms"]
        true = C.uint?(n) and n > 0
        {3, "duration", <<n::56>>}
    end
  end

  defp bank(:live, rows) do
    hashes =
      rows
      |> Enum.flat_map(fn {key, wire} ->
        true = C.valid_wire?(:live, key, wire)
        [Enum.at(wire, 2), Enum.at(wire, 3)]
      end)
      |> Enum.uniq()
      |> Enum.sort()

    raw = Enum.map(hashes, &unb64(&1, 32)) |> IO.iodata_to_binary()
    {hashes, uint(length(hashes)) <> raw}
  end

  defp bank(_, _), do: {[], <<>>}

  defp take_bank(:live, binary) do
    {count, rest} = take_uint(binary)
    true = count <= 128
    size = count * 32
    <<hashes::binary-size(^size), rest::binary>> = rest
    bank = for <<hash::binary-size(32) <- hashes>>, do: b64raw(hash)
    true = bank == Enum.sort(Enum.uniq(bank))
    {bank, rest}
  end

  defp take_bank(_, binary), do: {[], binary}

  defp row_encode(:live, key, wire, bank) do
    true = C.valid_wire?(:live, key, wire)
    [lineage, value, recipe, policy, first, deadline, category, eligibility] = wire
    first = number(first)
    deadline = number(deadline)

    hashes =
      if bank == :inline,
        do: unb64(recipe, 32) <> unb64(policy, 32),
        else:
          uint(Enum.find_index(bank, &(&1 == recipe))) <>
            uint(Enum.find_index(bank, &(&1 == policy)))

    unb64(lineage, 32) <>
      unb64(value, 32) <>
      hashes <>
      <<if(is_nil(deadline), do: 0, else: 1)>> <>
      uint(first) <>
      if(is_nil(deadline), do: <<>>, else: uint(deadline - first)) <> <<category, eligibility>>
  end

  defp row_encode(kind, key, row, _), do: anchor_encode(kind, key, row)

  defp row_decode(
         :live,
         key,
         <<lineage::binary-size(32), value::binary-size(32), rest::binary>>,
         bank
       ) do
    {r, rest} = take_uint(rest)
    {p, rest} = take_uint(rest)
    true = r < length(bank) and p < length(bank)
    <<flag, rest::binary>> = rest
    true = flag in 0..1
    {first, rest} = take_uint(rest)

    {deadline, rest} =
      if flag == 0,
        do: {nil, rest},
        else:
          (fn ->
             {delta, rest} = take_uint(rest)
             true = C.uint?(first + delta)
             {first + delta, rest}
           end).()

    <<category, eligibility, rest::binary>> = rest

    wire = [
      b64raw(lineage),
      b64raw(value),
      Enum.at(bank, r),
      Enum.at(bank, p),
      base36(first),
      base36(deadline),
      category,
      eligibility
    ]

    true = C.valid_wire?(:live, key, wire)
    {wire, rest}
  end

  defp row_decode(kind, key, binary, _), do: anchor_decode(kind, key, binary)

  defp anchor_encode(kind, key, row) when kind in [:anchor_full, :anchor_native_candidate] do
    true = C.keys?(row, ~w(clocks choice retirement))
    [a, b, c, d] = row["clocks"]

    {:ok, _} =
      C.encode_anchor(key, %{
        "note_first_ms" => a,
        "note_deadline_ms" => b,
        "pending_first_ms" => c,
        "pending_deadline_ms" => d,
        "choice" => nil
      })

    clocks = [a, if(is_nil(b), do: nil, else: b - a), c, if(is_nil(d), do: nil, else: d - c)]

    flags =
      clocks
      |> Enum.with_index()
      |> Enum.reduce(0, fn {clock, index}, flags ->
        if is_nil(clock), do: flags, else: bor(flags, bsl(1, index))
      end)

    encoded = Enum.map(clocks, fn n -> if is_nil(n), do: <<>>, else: uint(n) end)

    choice =
      case {kind, row["choice"]} do
        {_, nil} -> <<0>>
        {:anchor_full, choice} -> <<1>> <> legacy_encode(key, choice)
        {:anchor_native_candidate, choice} -> <<1>> <> capsule_encode(key, choice)
      end

    <<flags>> <> IO.iodata_to_binary(encoded) <> choice <> retirement_encode(row["retirement"])
  end

  defp anchor_decode(kind, key, <<flags, rest::binary>>) do
    true = flags < 16

    {clocks, rest} =
      Enum.map_reduce(0..3, rest, fn index, rest ->
        if band(flags, bsl(1, index)) == 0, do: {nil, rest}, else: take_uint(rest)
      end)

    [a, b, c, d] = clocks
    b = if is_nil(b), do: nil, else: a + b
    d = if is_nil(d), do: nil, else: c + d
    <<present, rest::binary>> = rest

    {choice, rest} =
      case {present, kind} do
        {0, _} -> {nil, rest}
        {1, :anchor_full} -> legacy_decode(key, rest)
        {1, :anchor_native_candidate} -> capsule_decode(key, rest)
      end

    {retirement, rest} = retirement_decode(rest)
    row = %{"clocks" => [a, b, c, d], "choice" => choice, "retirement" => retirement}
    _ = row_encode(kind, key, row, [])
    {row, rest}
  end

  defp retirement_encode(nil), do: <<0>>

  defp retirement_encode(row) do
    true = C.uint?(row["at_ms"])

    case Enum.sort(Map.keys(row)) do
      ["at_ms", "target_kind"] ->
        true = row["target_kind"] == "native_literal_note"
        <<1>> <> uint(row["at_ms"])

      ["at_ms", "record_key", "record_value_sha256"] ->
        <<2>> <>
          uint(row["at_ms"]) <>
          raw(C.live_identity(row["record_key"]), 33) <> raw(row["record_value_sha256"], 32)
    end
  end

  defp retirement_decode(<<0, rest::binary>>), do: {nil, rest}

  defp retirement_decode(<<tag, rest::binary>>) when tag in 1..2 do
    {at, rest} = take_uint(rest)

    if tag == 1 do
      {%{"target_kind" => "native_literal_note", "at_ms" => at}, rest}
    else
      <<key::binary-size(33), value::binary-size(32), rest::binary>> = rest

      {%{
         "at_ms" => at,
         "record_key" => C.live_key(hex(key)),
         "record_value_sha256" => hex(value)
       }, rest}
    end
  end

  defp legacy_encode(key, choice) do
    {:ok, wire} =
      C.encode_anchor(key, %{
        "note_first_ms" => 0,
        "note_deadline_ms" => 1,
        "pending_first_ms" => nil,
        "pending_deadline_ms" => nil,
        "choice" => choice
      })

    [policy, reason, at, proof] = Enum.at(wire, 4)

    [session, occurrence, version, kind, coverage, start, finish, quote, qhash, content, receipt] =
      proof

    policy_bytes =
      case policy do
        [n] -> <<n>>
        [3, duration] -> <<3>> <> uint(number(duration))
      end

    reason = Base.url_decode64!(reason, padding: false)
    quote = Base.url_decode64!(quote, padding: false)

    policy_bytes <>
      uint(byte_size(reason)) <>
      reason <>
      uint(number(at)) <>
      unb64(session, 16) <>
      unb64(occurrence, 16) <>
      unb64(version, 16) <>
      <<kind, coverage>> <>
      uint(number(start)) <>
      uint(number(finish) - number(start)) <>
      uint(byte_size(quote)) <>
      quote <>
      unb64(qhash, 32) <> unb64(content, 32) <> unb64(receipt, 32)
  end

  defp legacy_decode(key, <<code, rest::binary>>) do
    {policy, rest} =
      if code == 3,
        do:
          (fn ->
             {duration, rest} = take_uint(rest)
             {[3, base36(duration)], rest}
           end).(),
        else:
          (
            true = code in 0..2
            {[code], rest}
          )

    {reason, rest} = take_text(rest, 256)
    {at, rest} = take_uint(rest)

    <<session::binary-size(16), occurrence::binary-size(16), version::binary-size(16), kind,
      coverage, rest::binary>> = rest

    {start, rest} = take_uint(rest)
    {delta, rest} = take_uint(rest)
    true = C.uint?(start + delta)
    {quote, rest} = take_text(rest, 1024)

    <<qhash::binary-size(32), content::binary-size(32), receipt::binary-size(32), rest::binary>> =
      rest

    proof = [
      b64raw(session),
      b64raw(occurrence),
      b64raw(version),
      kind,
      coverage,
      base36(start),
      base36(start + delta),
      b64raw(quote),
      b64raw(qhash),
      b64raw(content),
      b64raw(receipt)
    ]

    wire = ["0", "1", nil, nil, [policy, b64raw(reason), base36(at), proof]]
    {:ok, semantic} = C.decode_anchor(key, wire)
    {semantic["choice"], rest}
  end

  defp take_text(binary, maximum) do
    {length, rest} = take_uint(binary)
    true = length in 1..maximum
    <<text::binary-size(^length), rest::binary>> = rest
    true = String.valid?(text)
    {text, rest}
  end

  defp number(nil), do: nil
  defp number(n), do: String.to_integer(n, 36)
  defp base36(nil), do: nil
  defp base36(n), do: Integer.to_string(n, 36) |> String.downcase()

  defp raw(hex, n) do
    true = is_binary(hex) and byte_size(hex) == n * 2
    Base.decode16!(hex, case: :lower)
  end

  defp hex(binary), do: Base.encode16(binary, case: :lower)

  defp unb64(value, n) do
    {:ok, raw} = Base.url_decode64(value, padding: false)
    true = byte_size(raw) == n and b64raw(raw) == value
    raw
  end

  defp b64raw(raw), do: Base.url_encode64(raw, padding: false)

  defp id(kind, hex) do
    result = raw(hex, width(kind))
    if kind == :live, do: C.live_key(hex)
    result
  end

  defp common(a, b), do: common(a, b, 0)
  defp common(<<a, ar::binary>>, <<a, br::binary>>, n), do: common(ar, br, n + 1)
  defp common(_, _, n), do: n
  defp times(0), do: []
  defp times(n), do: 1..n

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_binary_metadata}
  end
end
