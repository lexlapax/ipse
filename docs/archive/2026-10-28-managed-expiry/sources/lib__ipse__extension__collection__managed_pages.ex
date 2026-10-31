defmodule Ipse.Extension.Collection.ManagedPages do
  @moduledoc """
  Host-private closed managed-page syntax and scoped authentication.

  A shaped witness/record is not an attestation: callers must obtain these facts
  from the current checked Collection closure under the same native owner. Raw
  parsing and decoded native-management objects mint neither operator authority
  nor present eligibility. The compact retirement syntax addresses ONLY the
  enclosing lineage's fixed native note.<lineage> literal derivative, never
  pending/history/paraphrase/arbitrary-prefix claims. Typed minting is separate.
  """
  alias Ipse.Extension.Collection.Migration
  alias Ipse.Extension.ProjectIdentity.DomainAuth
  alias Ipse.JSON
  import Bitwise
  @safe 9_007_199_254_740_991
  @fixed_at 562_949_953_421_312
  @kinds [:live, :anchor]

  def safe, do: @safe
  def width(:live), do: 33
  def width(:anchor), do: 32
  def zero(kind), do: String.duplicate("0", width(kind) * 2)
  def bytes(value), do: Migration.encode(value)
  defp synthetic_tag, do: Base.url_encode64(<<0::256>>, padding: false)
  def fixed?(n), do: is_integer(n) and n >= @fixed_at

  def clock(n) when is_integer(n) and n in 0..@safe do
    if fixed?(n), do: <<n::56>>, else: uint(n)
  end

  def take_clock(binary, true) do
    <<n::56, rest::binary>> = binary
    true = n in @fixed_at..@safe
    {n, rest}
  end

  def take_clock(binary, false) do
    {n, rest} = take_uint(binary)
    true = n < @fixed_at
    {n, rest}
  end

  defp encode_page(kind, fence, entries, tag) do
    checked(fn ->
      true = kind in @kinds and is_map(entries) and map_size(entries) <= 128
      true = weight(kind, entries) <= profile(kind).capacity
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
        <<"IMB", 2, tag(kind)>> <>
          uint(length(rows)) <> dictionary <> IO.iodata_to_binary(pieces)

      value = %{"version" => 3, "data" => Base.url_encode64(raw, padding: false), "mac" => tag}
      true = byte_size(bytes(value)) <= 6144
      value
    end)
  end

  defp decode_page(kind, fence, value, upper) do
    checked(fn ->
      true = kind in @kinds and keys?(value, ~w(version data mac))
      true = value["version"] === 3 and byte_size(bytes(value)) <= 6144
      _ = hash(value["mac"])
      true = is_binary(value["data"]) and byte_size(value["data"]) <= 6144
      {:ok, raw} = Base.url_decode64(value["data"], padding: false)
      true = Base.url_encode64(raw, padding: false) == value["data"]
      previous = identity(kind, fence)
      upper = if is_nil(upper), do: nil, else: identity(kind, upper)
      true = is_nil(upper) or previous < upper
      <<"IMB", 2, tag, rest::binary>> = raw
      true = tag(kind) == tag
      {count, rest} = take_uint(rest)
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

  defp row_bytes(kind, key, row), do: byte_size(row_encode(kind, key, row, :inline))

  defp dictionary(:live, rows) do
    bank =
      rows
      |> Enum.flat_map(fn {_, row} -> [Enum.at(row, 2), Enum.at(row, 3)] end)
      |> Enum.uniq()
      |> Enum.sort()

    true = length(bank) <= 256
    {bank, uint(length(bank)) <> IO.iodata_to_binary(Enum.map(bank, &hash/1))}
  end

  defp dictionary(_, _), do: {[], <<>>}

  defp take_dictionary(:live, rest) do
    {count, rest} = take_uint(rest)
    true = count <= 256
    size = count * 32
    <<bank::binary-size(^size), rest::binary>> = rest
    bank = for <<item::binary-size(32) <- bank>>, do: b64(item)
    true = bank == Enum.sort(Enum.uniq(bank))
    {bank, rest}
  end

  defp take_dictionary(_, rest), do: {[], rest}

  defp row_encode(:live, key, row, bank) do
    true = valid_wire?(:live, key, row)
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
          uint(Enum.find_index(bank, &(&1 == recipe))) <>
            uint(Enum.find_index(bank, &(&1 == policy)))

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

        {:anchor, value} ->
          <<2>> <> capsule_encode(key, value)
      end

    <<flags>> <> IO.iodata_to_binary(encoded) <> choice <> retirement(row["retirement"])
  end

  defp row_decode(
         :live,
         key,
         <<lineage::binary-size(32), value::binary-size(32), rest::binary>>,
         bank
       ) do
    {r, rest} = take_uint(rest)
    {p, rest} = take_uint(rest)
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
            true = uint?(first + delta)
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

    true = valid_wire?(:live, key, row)
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

        {:anchor, 2} ->
          capsule_decode(key, rest)
      end

    {retirement, rest} = take_retirement(rest)
    row = %{"clocks" => [a, b, c, d], "choice" => choice, "retirement" => retirement}
    validate_anchor(key, row)
    {row, rest}
  end

  defp validate_anchor(key, row), do: anchor!(key, row)

  defp retirement(nil), do: <<0>>

  defp retirement(row) do
    true = uint?(row["at_ms"])
    flag = if fixed?(row["at_ms"]), do: 4, else: 0

    cond do
      keys?(row, ~w(target_kind at_ms)) ->
        true = row["target_kind"] == "native_literal_note"
        <<1 + flag>> <> clock(row["at_ms"])

      keys?(row, ~w(record_key record_value_sha256 at_ms)) ->
        key = Base.decode16!(live_identity(row["record_key"]), case: :lower)

        <<2 + flag>> <>
          clock(row["at_ms"]) <> key <> hash(packed_hash(row["record_value_sha256"]))
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
             "record_key" => live_key(hex(key)),
             "record_value_sha256" => hex(value)
           }, rest}
        )
  end

  defp identity(kind, key) do
    true = is_binary(key) and byte_size(key) == width(kind) * 2
    if kind == :live, do: live_key(key)
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

  defp number(value) do
    true = is_binary(value) and byte_size(value) in 1..11
    n = String.to_integer(value, 36)
    true = uint?(n) and base36(n) == value
    n
  end

  defp base36(nil), do: nil
  defp base36(n), do: Integer.to_string(n, 36) |> String.downcase()
  defp times(0), do: []
  defp times(n), do: 1..n

  @doc "Fixed descriptor; a format body is syntax until authenticated under admitted Identity."
  def descriptor do
    %{
      "version" => 3,
      "codec" => "IMB2",
      "auth" => "project-domain-hmac-sha256-v1",
      "page_value" => "version3-data-mac-v1",
      "integer" => "safe-u53-uleb-fixed7-v1",
      "keys" => %{
        "format" => "host.validity.format",
        "anchor_prefix" => "host.validity.a.",
        "live_prefix" => "host.validity.l.",
        "anchor_id_bytes" => 32,
        "live_id_bytes" => 33,
        "live_key_kind" => "note-pending-history-v1"
      },
      "anchor" => %{
        "tag" => 2,
        "header_max" => 7,
        "capacity" => 4544,
        "minimum" => 37,
        "maximum" => 337,
        "minimum_occupancy" => 2104,
        "row_cap" => 128
      },
      "live" => %{
        "tag" => 0,
        "header_max" => 9,
        "capacity" => 4542,
        "minimum" => 170,
        "maximum" => 183,
        "minimum_occupancy" => 2180,
        "row_cap" => 128,
        "dictionary" => "local-exact-union-per-row-charged-v1"
      },
      "management" => "native-management-v1",
      "retirement" => ["native-literal-note-v1", "exact-target-v1"]
    }
  end

  def format_body, do: Migration.encode(descriptor())
  def prefix(:anchor), do: "host.validity.a."
  def prefix(:live), do: "host.validity.l."
  def page_key(kind, fence), do: prefix(kind) <> fence
  def format_key, do: "host.validity.format"

  def profile(:anchor),
    do: %{
      kind: :anchor,
      header: 7,
      capacity: 4544,
      minimum: 37,
      maximum: 337,
      floor: 2104,
      row_cap: 128
    }

  def profile(:live),
    do: %{
      kind: :live,
      header: 9,
      capacity: 4542,
      minimum: 170,
      maximum: 183,
      floor: 2180,
      row_cap: 128
    }

  def weight(kind, rows) when is_map(rows),
    do: Enum.sum(Enum.map(rows, fn {id, row} -> row_weight(kind, id, row) end))

  def row_weight(kind, id, row) do
    n = width(kind) + 1 + row_bytes(kind, id, row) + if(kind == :live, do: 4, else: 0)
    p = profile(kind)
    true = n in p.minimum..p.maximum
    n
  end

  @doc "Raw closed syntax only; no tag, permission or current eligibility is produced."
  def pack(kind, fence, entries) do
    checked(fn ->
      {:ok, value} = encode_page(kind, fence, entries, synthetic_tag())
      Base.url_decode64!(value["data"], padding: false)
    end)
  end

  @doc "Raw parser only. Context range and later authentication remain independent requirements."
  def unpack(kind, fence, body, upper \\ nil) do
    checked(fn ->
      true = is_binary(body) and byte_size(body) <= 4551
      {:ok, page} = decode_page(kind, fence, envelope(body, synthetic_tag()), upper)
      page
    end)
  end

  def encoded_size(body) when is_binary(body),
    do: byte_size(bytes(envelope(body, synthetic_tag())))

  @doc "Seal only inside the actual checked Collection callback; shaped witness JSON is not authority."
  def seal(cap, witness, key, body) do
    checked(fn ->
      true = witness?(witness)
      generation = witness["root"]["generation"] + 1
      true = uint?(generation) and generation > 0
      {kind, fence} = identify!(key)
      syntax!(kind, fence, body)
      context = context(key, kind, witness["operation_id"], generation)
      {:ok, tag} = DomainAuth.seal(cap, context, body)
      value = envelope(body, b64(tag))
      true = byte_size(bytes(value)) <= 6144
      value
    end)
  end

  @doc "Verify the exact host-supplied read ref and selected actual neighbor range before local repair."
  def open(cap, record, observation, slot \\ "selected") do
    checked(fn ->
      range = range!(observation, slot)
      true = ref?(Map.delete(record, "value")) and Map.delete(record, "value") == range.ref
      {body, tag} = body!(record)

      true =
        DomainAuth.verify(
          cap,
          context(record["key"], range.kind, record["operation_id"], record["revision"]),
          body,
          tag
        )

      {:ok, parsed} = unpack(range.kind, range.fence, body, range.upper)
      w = weight(range.kind, parsed.entries)
      true = range.single or w >= profile(range.kind).floor
      Map.merge(parsed, %{body: body, weight: w, range: range})
    end)
  end

  def open_format(cap, record) do
    checked(fn ->
      true = ref?(Map.delete(record, "value")) and record["key"] == format_key()
      {body, tag} = body!(record)
      true = body == format_body()

      true =
        DomainAuth.verify(
          cap,
          context(record["key"], :format, record["operation_id"], record["revision"]),
          body,
          tag
        )

      descriptor()
    end)
  end

  def observation(observation), do: checked(fn -> observation!(observation) end)
  def range(observation, slot), do: checked(fn -> range!(observation, slot) end)

  defp range!(observation, slot) do
    parsed = observation!(observation)
    true = parsed.state == "initialized" and slot in ~w(predecessor selected successor)
    slots = observation["neighbors"]
    ref = Map.fetch!(slots, slot)
    true = is_map(ref)

    upper =
      case slot do
        "predecessor" -> slots["selected"]
        "selected" -> slots["successor"]
        "successor" -> slots["second_successor"]
      end

    single = slot == "selected" and is_nil(slots["predecessor"]) and is_nil(slots["successor"])
    {kind, fence} = identify!(ref["key"])

    %{
      kind: kind,
      fence: fence,
      upper: if(upper, do: elem(identify!(upper["key"]), 1)),
      single: single,
      ref: ref
    }
  end

  defp observation!(o) do
    true = keys?(o, ~w(version summary directory state neighbors witness)) and o["version"] === 1
    d = o["directory"]
    true = Ipse.Extension.Collection.Directory.neighbor_request?(d)

    kind =
      cond do
        d["prefix"] == prefix(:anchor) and d["fence_bytes"] === 32 -> :anchor
        d["prefix"] == prefix(:live) and d["fence_bytes"] === 33 -> :live
      end

    _ = identity(kind, d["needle"])
    true = keys?(o["neighbors"], ~w(predecessor selected successor second_successor))
    refs = Enum.map(~w(predecessor selected successor second_successor), &o["neighbors"][&1])
    true = Enum.all?(refs, &(is_nil(&1) or (ref?(&1) and elem(identify!(&1["key"]), 0) == kind)))
    present = Enum.reject(refs, &is_nil/1)
    true = Enum.map(present, & &1["key"]) == Enum.sort(Enum.uniq(Enum.map(present, & &1["key"])))
    w = o["witness"]

    true =
      keys?(w, ~w(version root_state root root_sha256 manifest_sha256)) and w["version"] === 2

    s = o["summary"]
    true = keys?(s, ~w(version project generation floor floor_anchor)) and s["version"] === 3
    true = JSON.sha256?(s["project"]) and uint?(s["generation"]) and uint?(s["floor"])

    true =
      (s["floor"] === 0 and is_nil(s["floor_anchor"])) or
        (s["floor"] > 0 and id?(s["floor_anchor"]))

    case o["state"] do
      "uninitialized" ->
        true = w["root_state"] == "absent" and Enum.all?(refs, &is_nil/1)
        true = is_nil(w["root"]) and is_nil(w["root_sha256"]) and is_nil(w["manifest_sha256"])
        true = s["generation"] === 0 and s["floor"] === 0 and is_nil(s["floor_anchor"])

      "initialized" ->
        true =
          w["root_state"] == "present" and is_map(w["root"]) and w["root"]["version"] in [4, 5]

        true = JSON.sha256?(w["root_sha256"]) and JSON.sha256?(w["manifest_sha256"])
        true = w["root"]["manifest"] == w["manifest_sha256"]
        true = Map.drop(w["root"], ~w(version manifest)) == Map.drop(s, ["version"])
        [previous, selected, next, second] = refs
        true = is_map(selected) and selected["key"] <= page_key(kind, d["needle"])
        true = is_nil(next) or page_key(kind, d["needle"]) < next["key"]
        true = not is_nil(next) or is_nil(second)
        true = not is_nil(previous) or selected["key"] == page_key(kind, zero(kind))
        true = is_nil(previous) or previous["key"] < selected["key"]

      _ ->
        raise ArgumentError
    end

    %{kind: kind, state: o["state"], summary: s, witness: w}
  end

  defp body!(record) do
    value = record["value"]
    true = keys?(record, ~w(key revision sha256 bytes operation_id value))
    encoded = bytes(value)
    true = byte_size(encoded) == record["bytes"] and JSON.sha256(encoded) == record["sha256"]
    true = keys?(value, ~w(version data mac)) and value["version"] === 3
    true = byte_size(encoded) <= 6144 and is_binary(value["data"])
    {:ok, body} = Base.url_decode64(value["data"], padding: false)
    true = b64(body) == value["data"] and byte_size(body) in 1..6144
    {body, hash(value["mac"])}
  end

  defp context(key, kind, id, revision),
    do: %{
      "version" => 1,
      "schema" => 3,
      "page_key" => key,
      "kind" => Atom.to_string(kind),
      "operation_id" => id,
      "revision" => revision
    }

  defp witness?(w) do
    true = is_map(w) and w["version"] === 2 and id?(w["operation_id"])
    s = w["root"]
    true = keys?(s, ~w(version project generation floor floor_anchor)) and s["version"] === 3
    true = JSON.sha256?(s["project"]) and uint?(s["generation"]) and uint?(s["floor"])

    true =
      (s["floor"] === 0 and is_nil(s["floor_anchor"])) or
        (s["floor"] > 0 and id?(s["floor_anchor"]))

    case w["root_state"] do
      "absent" ->
        is_nil(w["root_bytes"]) and is_nil(w["root_sha256"]) and
          is_nil(w["manifest_sha256"]) and s["generation"] === 0 and s["floor"] === 0

      "present" ->
        bytes = w["root_bytes"]

        true =
          is_binary(bytes) and byte_size(bytes) in 1..1024 and
            JSON.sha256(bytes) == w["root_sha256"]

        {:ok, pointer} = JSON.decode_unique(bytes)

        pointer["version"] in [4, 5] and pointer["manifest"] == w["manifest_sha256"] and
          JSON.sha256?(w["manifest_sha256"]) and
          Map.drop(pointer, ~w(version manifest)) == Map.drop(s, ["version"])
    end
  end

  defp ref?(r),
    do:
      keys?(r, ~w(key revision sha256 bytes operation_id)) and is_binary(r["key"]) and
        byte_size(r["key"]) <= 96 and uint?(r["revision"]) and r["revision"] > 0 and
        JSON.sha256?(r["sha256"]) and is_integer(r["bytes"]) and r["bytes"] in 1..6144 and
        id?(r["operation_id"])

  defp identify!(key) do
    if key == format_key() do
      {:format, nil}
    else
      kind =
        cond do
          is_binary(key) and String.starts_with?(key, prefix(:anchor)) -> :anchor
          is_binary(key) and String.starts_with?(key, prefix(:live)) -> :live
        end

      fence = String.replace_prefix(key, prefix(kind), "")
      _ = identity(kind, fence)
      {kind, fence}
    end
  end

  defp syntax!(:format, nil, body), do: true = body == format_body()

  defp syntax!(kind, fence, body) do
    {:ok, _} = unpack(kind, fence, body)
    :ok
  end

  defp envelope(body, tag), do: %{"version" => 3, "data" => b64(body), "mac" => tag}
  defp tag(:live), do: 0
  defp tag(:anchor), do: 2
  defp keys?(m, names), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(names)
  defp uint?(n), do: JSON.safe_uint?(n)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp packed_hash(v), do: b64(raw(v, 32))

  def live_identity(key) do
    [kind, id] = String.split(key, ".", parts: 2)
    true = kind in ~w(note pending history)
    raw = raw(id, 32)
    (<<Enum.find_index(~w(note pending history), &(&1 == kind))>> <> raw) |> hex()
  end

  def live_key(identity) do
    <<kind, id::binary-size(32)>> = raw(identity, 33)
    true = kind in 0..2
    Enum.at(~w(note pending history), kind) <> "." <> hex(id)
  end

  defp valid_wire?(:live, identity, row) do
    true = is_list(row) and length(row) == 8
    _ = live_key(identity)
    [lineage, value, recipe, policy, first, deadline, category, eligibility] = row
    Enum.each([lineage, value, recipe, policy], &hash/1)
    first = number(first)
    deadline = number(deadline)
    true = uint?(first) and (is_nil(deadline) or (uint?(deadline) and deadline >= first))
    true = category in 0..4 and eligibility in 0..2
    true = (category != 0 and eligibility != 1) or not is_nil(deadline)
    true
  end

  defp anchor!(key, row) do
    _ = raw(key, 32)
    true = keys?(row, ~w(clocks choice retirement))
    [a, b, c, d] = row["clocks"]
    true = (is_nil(a) or uint?(a)) and (is_nil(b) or uint?(b))
    true = not is_nil(a) or not is_nil(c)
    true = (is_nil(a) and is_nil(b)) or (uint?(a) and (is_nil(b) or b >= a))
    true = (is_nil(c) and is_nil(d)) or (uint?(c) and uint?(d) and d >= c)
    :ok
  end

  defp uint(n) do
    true = uint?(n)
    encode_uint(n)
  end

  defp encode_uint(n) when n < 128, do: <<n>>
  defp encode_uint(n), do: <<bor(band(n, 127), 128)>> <> encode_uint(bsr(n, 7))
  defp take_uint(binary), do: take_uint(binary, binary, 0, 0)

  defp take_uint(<<byte, rest::binary>>, original, n, count) when count < 8 do
    n = bor(n, bsl(band(byte, 127), count * 7))

    if byte < 128 do
      true = uint?(n) and binary_part(original, 0, count + 1) == uint(n)
      {n, rest}
    else
      take_uint(rest, original, n, count + 1)
    end
  end

  @capsule ~w(version kind event_id display_sha256 challenge target_key target_value_sha256 lineage observed_at_ms policy reason input_sha256)
  defp capsule_encode(lineage, value) do
    true =
      keys?(value, @capsule) and value["version"] === 2 and value["kind"] == "native_management"

    true = value["lineage"] == lineage
    _ = raw(lineage, 32)
    {code, verb, duration} = choice(value["policy"])
    challenge = raw(value["challenge"], 8)
    true = value["input_sha256"] == JSON.sha256(verb <> " " <> hex(challenge))
    reason = value["reason"]
    true = is_binary(reason) and String.valid?(reason) and byte_size(reason) in 1..64
    at = value["observed_at_ms"]
    true = uint?(at)

    raw(value["event_id"], 16) <>
      raw(value["display_sha256"], 32) <>
      challenge <>
      raw(live_identity(value["target_key"]), 33) <>
      raw(value["target_value_sha256"], 32) <>
      <<at::56, code, byte_size(reason) - 1>> <> reason <> duration
  end

  defp capsule_decode(
         lineage,
         <<event::binary-size(16), display::binary-size(32), challenge::binary-size(8),
           target::binary-size(33), value::binary-size(32), at::56, code, length, rest::binary>>
       ) do
    true = uint?(at) and length < 64
    size = length + 1
    <<reason::binary-size(^size), rest::binary>> = rest

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
          true = uint?(duration) and duration > 0
          {%{"kind" => "duration", "duration_ms" => duration}, rest}
      end

    {_, verb, _} = choice(policy)

    result = %{
      "version" => 2,
      "kind" => "native_management",
      "lineage" => lineage,
      "event_id" => hex(event),
      "display_sha256" => hex(display),
      "challenge" => hex(challenge),
      "target_key" => live_key(hex(target)),
      "target_value_sha256" => hex(value),
      "observed_at_ms" => at,
      "policy" => policy,
      "reason" => reason,
      "input_sha256" => JSON.sha256(verb <> " " <> hex(challenge))
    }

    _ = capsule_encode(lineage, result)
    {result, rest}
  end

  defp choice(p) do
    case p do
      %{"kind" => "pin"} when map_size(p) == 1 ->
        {0, "pin", <<>>}

      %{"kind" => "ordinary"} when map_size(p) == 1 ->
        {1, "ordinary", <<>>}

      %{"kind" => "session"} when map_size(p) == 1 ->
        {2, "forget", <<>>}

      %{"kind" => "duration", "duration_ms" => n} when map_size(p) == 2 ->
        true = uint?(n) and n > 0
        {3, "duration", <<n::56>>}
    end
  end

  defp raw(value, n) do
    true = is_binary(value) and byte_size(value) == n * 2
    decoded = Base.decode16!(value, case: :lower)
    true = hex(decoded) == value
    decoded
  end

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :managed_pages_invalid}
  end
end
