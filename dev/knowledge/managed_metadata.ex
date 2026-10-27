defmodule Ipse.Development.ManagedMetadata.Codec do
  @moduledoc "Nonpublishing proposed metadata codec; neither proof JSON nor candidate capsules grant authority."
  alias Ipse.Extension.Collection.Migration
  alias Ipse.JSON
  @safe 9_007_199_254_740_991
  @live ~w(version record_key lineage first_admitted_ms valid_until_ms category eligibility recipe_sha256 policy_sha256 record_value_sha256 sources)
  @source ~w(session_id occurrence_id version_id kind origin content_sha256 receipt_sha256)
  @proof ~w(version session_id occurrence_id version_id kind origin coverage path start_byte end_byte quote quote_sha256 content_sha256 receipt_sha256)
  @anchor ~w(note_first_ms note_deadline_ms pending_first_ms pending_deadline_ms choice)
  @categories ~w(ordinary preference current pin history)
  @eligibilities ~w(current never_current history)
  @capsule ~w(version kind event_id display_sha256 input_sha256 target_key target_value_sha256 lineage policy reason observed_at_ms authority_ref)

  def bytes(value), do: Migration.encode(value)
  def uint?(n), do: is_integer(n) and n in 0..@safe
  def sha?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{64}\z/, v)
  def keys?(m, ks), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(ks)
  def packed_hash(hex), do: pack(hex, 32)
  def unpacked_hash(value), do: unpack(value, 32)

  def live_identity(key) do
    case String.split(key, ".", parts: 2) do
      [kind, id] when kind in ~w(note pending history) ->
        true = sha?(id)

        Integer.to_string(Enum.find_index(~w(note pending history), &(&1 == kind)), 16)
        |> String.pad_leading(2, "0")
        |> Kernel.<>(id)
    end
  end

  def live_key(identity) do
    <<kind::binary-size(2), id::binary-size(64)>> = identity
    true = sha?(id)
    prefix = Enum.fetch!(~w(note pending history), String.to_integer(kind, 16))
    true = String.pad_leading(Integer.to_string(String.to_integer(kind, 16), 16), 2, "0") == kind
    prefix <> "." <> id
  end

  def encode_live(row, record) do
    checked(fn ->
      true = keys?(row, @live) and row["version"] === 3

      true =
        keys?(record, ~w(key revision value)) and uint?(record["revision"]) and
          record["revision"] > 0

      identity = live_identity(record["key"])
      true = row["record_key"] == record["key"] and row["lineage"] == record["value"]["lineage"]
      true = byte_size(bytes(record["value"])) <= 6144
      true = row["record_value_sha256"] == JSON.sha256(bytes(record["value"]))
      [proof] = record["value"]["evidence"]["sources"]
      true = valid_record_proof?(proof)
      {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(proof)
      true = lineage == row["lineage"] and record["value"]["category"] == row["category"]
      true = row["sources"] == [Map.take(proof, @source)]
      true = valid_sources?(row["sources"])

      wire = [
        pack(row["lineage"], 32),
        pack(row["record_value_sha256"], 32),
        pack(row["recipe_sha256"], 32),
        pack(row["policy_sha256"], 32),
        clock(row["first_admitted_ms"]),
        clock(row["valid_until_ms"]),
        enum(row["category"], @categories),
        enum(row["eligibility"], @eligibilities)
      ]

      true = valid_wire?(:live, identity, wire)
      {identity, wire}
    end)
  end

  def decode_live(identity, wire, record) do
    checked(fn ->
      true = valid_wire?(:live, identity, wire)
      [lineage, value_hash, recipe, policy, first, deadline, category, eligibility] = wire
      [proof] = record["value"]["evidence"]["sources"]

      row = %{
        "version" => 3,
        "record_key" => live_key(identity),
        "lineage" => unpack(lineage, 32),
        "record_value_sha256" => unpack(value_hash, 32),
        "recipe_sha256" => unpack(recipe, 32),
        "policy_sha256" => unpack(policy, 32),
        "first_admitted_ms" => unclock(first),
        "valid_until_ms" => unclock(deadline),
        "category" => Enum.fetch!(@categories, category),
        "eligibility" => Enum.fetch!(@eligibilities, eligibility),
        "sources" => [Map.take(proof, @source)]
      }

      {:ok, {^identity, ^wire}} = encode_live(row, record)
      row
    end)
  end

  def encode_anchor(identity, row, mode \\ :anchor_full) do
    checked(fn ->
      true = sha?(identity) and keys?(row, @anchor)

      wire =
        Enum.map(
          ~w(note_first_ms note_deadline_ms pending_first_ms pending_deadline_ms),
          &clock(row[&1])
        ) ++
          [encode_choice(mode, identity, row["choice"])]

      true = valid_wire?(mode, identity, wire)
      wire
    end)
  end

  def decode_anchor(identity, wire, mode \\ :anchor_full) do
    checked(fn ->
      true = valid_wire?(mode, identity, wire)
      [a, b, c, d, choice] = wire

      %{
        "note_first_ms" => unclock(a),
        "note_deadline_ms" => unclock(b),
        "pending_first_ms" => unclock(c),
        "pending_deadline_ms" => unclock(d),
        "choice" => decode_choice(mode, identity, choice)
      }
    end)
  end

  def valid_wire?(kind, identity, wire) do
    case checked(fn ->
           validate_wire(kind, identity, wire)
           true
         end) do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp validate_wire(:live, identity, [
         lineage,
         value,
         recipe,
         policy,
         first,
         deadline,
         category,
         eligibility
       ]) do
    _ = live_key(identity)
    Enum.each([lineage, value, recipe, policy], &unpack(&1, 32))
    first = unclock(first)
    deadline = unclock(deadline)
    true = uint?(first) and (is_nil(deadline) or deadline >= first)
    true = category in 0..4 and eligibility in 0..2
    true = (category != 0 and eligibility != 1) or is_integer(deadline)
  end

  defp validate_wire(mode, identity, [a, b, c, d, choice])
       when mode in [:anchor_full, :anchor_candidate] do
    true = sha?(identity)
    [a, b, c, d] = Enum.map([a, b, c, d], &unclock/1)
    true = not is_nil(a) or not is_nil(c)
    true = not is_nil(a) or is_nil(b)
    true = is_nil(b) or b >= a
    true = (is_nil(c) and is_nil(d)) or (uint?(c) and uint?(d) and d >= c)
    value = decode_choice(mode, identity, choice)
    true = encode_choice(mode, identity, value) === choice
  end

  defp encode_choice(_, _, nil), do: nil

  defp encode_choice(:anchor_full, lineage, value) do
    true = byte_size(bytes(value)) <= 4096
    true = keys?(value, ~w(version kind lineage override evidence))

    true =
      value["version"] === 1 and value["kind"] == "retention_override" and
        value["lineage"] == lineage

    override = value["override"]
    true = byte_size(bytes(override)) <= 1024
    true = keys?(override, ~w(version lineage policy reason updated_at_ms))
    true = override["version"] === 1 and override["lineage"] == lineage
    true = keys?(value["evidence"], ["sources"])
    [proof] = value["evidence"]["sources"]

    [
      policy(override["policy"]),
      text64(override["reason"], 256),
      clock_required(override["updated_at_ms"]),
      encode_proof(proof)
    ]
  end

  defp encode_choice(:anchor_candidate, lineage, value) do
    true = keys?(value, @capsule) and value["version"] === 1
    true = value["kind"] == "candidate_native_retention_choice" and value["lineage"] == lineage
    ref = value["authority_ref"]
    true = keys?(ref, ~w(session_id event_id sha256))

    [
      pack(value["event_id"], 16),
      pack(value["display_sha256"], 32),
      pack(value["input_sha256"], 32),
      pack(live_identity(value["target_key"]), 33),
      pack(value["target_value_sha256"], 32),
      policy(value["policy"]),
      text64(value["reason"], 256),
      clock_required(value["observed_at_ms"]),
      [pack(ref["session_id"], 16), pack(ref["event_id"], 16), pack(ref["sha256"], 32)]
    ]
  end

  defp decode_choice(_, _, nil), do: nil

  defp decode_choice(:anchor_full, lineage, [policy, reason, at, proof]) do
    %{
      "version" => 1,
      "kind" => "retention_override",
      "lineage" => lineage,
      "override" => %{
        "version" => 1,
        "lineage" => lineage,
        "policy" => unpolicy(policy),
        "reason" => untext(reason, 256),
        "updated_at_ms" => unclock_required(at)
      },
      "evidence" => %{"sources" => [decode_proof(proof)]}
    }
  end

  defp decode_choice(:anchor_candidate, lineage, [
         event,
         display,
         input,
         target,
         value,
         policy,
         reason,
         at,
         [session, ref_event, ref_hash]
       ]) do
    %{
      "version" => 1,
      "kind" => "candidate_native_retention_choice",
      "lineage" => lineage,
      "event_id" => unpack(event, 16),
      "display_sha256" => unpack(display, 32),
      "input_sha256" => unpack(input, 32),
      "target_key" => live_key(unpack(target, 33)),
      "target_value_sha256" => unpack(value, 32),
      "policy" => unpolicy(policy),
      "reason" => untext(reason, 256),
      "observed_at_ms" => unclock_required(at),
      "authority_ref" => %{
        "session_id" => unpack(session, 16),
        "event_id" => unpack(ref_event, 16),
        "sha256" => unpack(ref_hash, 32)
      }
    }
  end

  defp encode_proof(p) do
    true = byte_size(bytes(p)) <= 2048
    true = keys?(p, @proof) and p["version"] === 1 and is_nil(p["path"])

    kind =
      enum({p["kind"], p["origin"]}, [
        {"input.original", "interactive_operator"},
        {"input.operator_answer", "native_operator_answer"}
      ])

    true = uint?(p["start_byte"]) and uint?(p["end_byte"])
    true = p["end_byte"] - p["start_byte"] == byte_size(p["quote"])
    true = p["quote_sha256"] == JSON.sha256(p["quote"])

    [
      pack(p["session_id"], 16),
      pack(p["occurrence_id"], 16),
      pack(p["version_id"], 16),
      kind,
      enum(p["coverage"], ~w(available partial)),
      clock_required(p["start_byte"]),
      clock_required(p["end_byte"]),
      text64(p["quote"], 1024),
      pack(p["quote_sha256"], 32),
      pack(p["content_sha256"], 32),
      pack(p["receipt_sha256"], 32)
    ]
  end

  defp decode_proof([
         session,
         occurrence,
         version,
         kind,
         coverage,
         start,
         finish,
         quote,
         quote_hash,
         content,
         receipt
       ]) do
    {kind, origin} =
      Enum.fetch!(
        [
          {"input.original", "interactive_operator"},
          {"input.operator_answer", "native_operator_answer"}
        ],
        kind
      )

    p = %{
      "version" => 1,
      "session_id" => unpack(session, 16),
      "occurrence_id" => unpack(occurrence, 16),
      "version_id" => unpack(version, 16),
      "kind" => kind,
      "origin" => origin,
      "coverage" => Enum.fetch!(~w(available partial), coverage),
      "path" => nil,
      "start_byte" => unclock_required(start),
      "end_byte" => unclock_required(finish),
      "quote" => untext(quote, 1024),
      "quote_sha256" => unpack(quote_hash, 32),
      "content_sha256" => unpack(content, 32),
      "receipt_sha256" => unpack(receipt, 32)
    }

    _ = encode_proof(p)
    p
  end

  defp policy(p) do
    kind = enum(p["kind"], ~w(pin ordinary session duration))
    true = keys?(p, if(kind == 3, do: ~w(kind duration_ms), else: ["kind"]))

    if kind == 3 do
      true = uint?(p["duration_ms"]) and p["duration_ms"] > 0
      [kind, clock_required(p["duration_ms"])]
    else
      [kind]
    end
  end

  defp unpolicy([3, n]), do: %{"kind" => "duration", "duration_ms" => unclock_required(n)}
  defp unpolicy([n]) when n in 0..2, do: %{"kind" => Enum.fetch!(~w(pin ordinary session), n)}

  defp enum(value, choices) do
    n = Enum.find_index(choices, &(&1 === value))
    true = is_integer(n)
    n
  end

  defp clock(nil), do: nil
  defp clock(n), do: clock_required(n)

  defp clock_required(n) do
    true = uint?(n)
    Integer.to_string(n, 36) |> String.downcase()
  end

  defp unclock(nil), do: nil
  defp unclock(n), do: unclock_required(n)

  defp unclock_required(n) do
    true = is_binary(n) and byte_size(n) in 1..11
    v = String.to_integer(n, 36)
    true = uint?(v) and clock_required(v) == n
    v
  end

  defp pack(hex, n) do
    true = is_binary(hex) and byte_size(hex) == n * 2
    {:ok, raw} = Base.decode16(hex, case: :lower)
    Base.url_encode64(raw, padding: false)
  end

  defp unpack(value, n) do
    true = is_binary(value) and byte_size(value) == div(n * 8 + 5, 6)
    {:ok, raw} = Base.url_decode64(value, padding: false)
    true = byte_size(raw) == n and Base.url_encode64(raw, padding: false) === value
    Base.encode16(raw, case: :lower)
  end

  defp text64(value, n) do
    true = is_binary(value) and String.valid?(value) and byte_size(value) in 1..n
    Base.url_encode64(value, padding: false)
  end

  defp untext(value, n) do
    true = is_binary(value) and byte_size(value) <= div(n * 8 + 5, 6)
    {:ok, raw} = Base.url_decode64(value, padding: false)

    true =
      byte_size(raw) in 1..n and String.valid?(raw) and
        Base.url_encode64(raw, padding: false) === value

    raw
  end

  defp valid_record_proof?(p) do
    keys?(p, @proof) and p["version"] === 1 and is_nil(p["path"]) and
      p["coverage"] in ~w(available partial) and uint?(p["start_byte"]) and
      uint?(p["end_byte"]) and is_binary(p["quote"]) and String.valid?(p["quote"]) and
      byte_size(p["quote"]) in 1..1024 and
      p["end_byte"] - p["start_byte"] == byte_size(p["quote"]) and
      p["quote_sha256"] == JSON.sha256(p["quote"]) and
      byte_size(bytes(p)) <= 2048 and valid_sources?([Map.take(p, @source)])
  end

  defp valid_sources?([s]) do
    keys?(s, @source) and
      Enum.all?(~w(session_id occurrence_id version_id), fn k ->
        is_binary(s[k]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, s[k])
      end) and
      sha?(s["content_sha256"]) and sha?(s["receipt_sha256"]) and
      {s["kind"], s["origin"]} in [
        {"input.original", "interactive_operator"},
        {"input.original", "unattended_input"},
        {"input.operator_answer", "native_operator_answer"},
        {"answer.original", "assistant_proposal"},
        {"tool.outcome", "typed_host_outcome"}
      ]
  end

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_managed_metadata}
  end
end

defmodule Ipse.Development.ManagedMetadata.Leaves do
  @moduledoc "Nonpublishing fence-leaf planner over supplied verified manifest references."
  alias Ipse.Development.ManagedMetadata.Codec, as: C
  @limit 6144
  @count 64
  @refs 8192

  def prefix(:live), do: "host.validity.live3."
  def prefix(:anchor_full), do: "host.validity.anchor3f."
  def prefix(:anchor_candidate), do: "host.validity.anchor3c."
  def width(:live), do: 66
  def width(kind) when kind in [:anchor_full, :anchor_candidate], do: 64
  def zero(kind), do: String.duplicate("0", width(kind))
  def key(kind, fence), do: prefix(kind) <> fence

  def page(kind, fence, entries),
    do: %{"version" => 3, "kind" => Atom.to_string(kind), "fence" => fence, "entries" => entries}

  def entry_id(hex), do: hex |> Base.decode16!(case: :lower) |> Base.url_encode64(padding: false)

  def identity(kind, encoded) do
    true = is_binary(encoded) and byte_size(encoded) == div(div(width(kind), 2) * 8 + 5, 6)
    {:ok, raw} = Base.url_decode64(encoded, padding: false)

    true =
      byte_size(raw) * 2 == width(kind) and Base.url_encode64(raw, padding: false) === encoded

    Base.encode16(raw, case: :lower)
  end

  def directory(kind, refs) do
    checked(fn ->
      true = is_list(refs) and length(refs) <= @refs

      pairs =
        Enum.map(refs, fn ref ->
          true =
            C.keys?(ref, ~w(key revision)) and C.uint?(ref["revision"]) and ref["revision"] > 0

          true = String.starts_with?(ref["key"], prefix(kind))
          fence = String.replace_prefix(ref["key"], prefix(kind), "")
          true = fence?(kind, fence)
          {fence, ref}
        end)

      true = length(Enum.uniq_by(pairs, &elem(&1, 0))) == length(pairs)
      pairs = Enum.sort(pairs)
      true = pairs == [] or elem(hd(pairs), 0) == zero(kind)
      pairs
    end)
  end

  def neighbors(kind, refs, id) do
    checked(fn ->
      true = fence?(kind, id)
      {:ok, pairs} = directory(kind, refs)
      {before, after_rows} = Enum.split_while(pairs, fn {f, _} -> f <= id end)

      %{
        "previous" => if(before == [], do: nil, else: elem(List.last(before), 1)),
        "next" => if(after_rows == [], do: nil, else: elem(hd(after_rows), 1))
      }
    end)
  end

  def valid_page?(kind, ref, next, value) do
    case checked(fn ->
           true = C.keys?(value, ~w(version kind fence entries)) and value["version"] === 3
           true = value["kind"] == Atom.to_string(kind) and fence?(kind, value["fence"])

           true =
             C.keys?(ref, ~w(key revision)) and C.uint?(ref["revision"]) and ref["revision"] > 0

           true = ref["key"] == key(kind, value["fence"])
           upper = if is_nil(next), do: nil, else: ref_fence(kind, next)
           true = is_nil(upper) or value["fence"] < upper
           entries = value["entries"]
           true = is_map(entries) and map_size(entries) <= @count
           true = map_size(entries) > 0 or value["fence"] == zero(kind)
           true = byte_size(C.bytes(value)) <= @limit

           true =
             Enum.all?(entries, fn {packed, row} ->
               id = identity(kind, packed)

               id >= value["fence"] and (is_nil(upper) or id < upper) and
                 C.valid_wire?(kind, id, row)
             end)

           true
         end) do
      {:ok, true} -> true
      _ -> false
    end
  end

  def put(kind, refs, selected, id, row) do
    checked(fn ->
      true = C.valid_wire?(kind, id, row)
      {:ok, n} = neighbors(kind, refs, id)
      ref = n["previous"]

      value =
        if is_nil(ref) do
          true = refs == [] and is_nil(selected)
          page(kind, zero(kind), %{})
        else
          true = valid_page?(kind, ref, n["next"], selected)
          selected
        end

      packed = entry_id(id)

      if old = value["entries"][packed] do
        true = byte_size(C.bytes(row)) >= byte_size(C.bytes(old))
      end

      entries = Map.put(value["entries"], packed, row)
      emit(kind, value["fence"], entries, ref, n["next"])
    end)
  end

  def deletion_neighbor(kind, refs, id) do
    checked(fn ->
      {:ok, pairs} = directory(kind, refs)
      {:ok, n} = neighbors(kind, refs, id)
      selected = n["previous"]
      true = not is_nil(selected)
      index = Enum.find_index(pairs, fn {_, r} -> r == selected end)
      neighbor = if index > 0, do: Enum.at(pairs, index - 1), else: Enum.at(pairs, index + 1)
      if neighbor, do: elem(neighbor, 1), else: nil
    end)
  end

  def delete(kind, refs, selected, neighbor, id),
    do: edit(kind, refs, selected, neighbor, id, nil)

  def replace(kind, refs, selected, neighbor, id, row) do
    checked(fn ->
      true = C.valid_wire?(kind, id, row)
      old = Map.fetch!(selected["entries"], entry_id(id))

      if byte_size(C.bytes(row)) >= byte_size(C.bytes(old)) do
        {:ok, plan} = put(kind, refs, selected, id, row)
        plan
      else
        {:ok, plan} = edit(kind, refs, selected, neighbor, id, row)
        plan
      end
    end)
  end

  defp edit(kind, refs, selected, neighbor, id, row) do
    checked(fn ->
      {:ok, n} = neighbors(kind, refs, id)
      ref = n["previous"]
      true = not is_nil(ref) and valid_page?(kind, ref, n["next"], selected)
      true = Map.has_key?(selected["entries"], entry_id(id))
      remaining = Map.delete(selected["entries"], entry_id(id))

      remaining =
        if is_nil(row) do
          remaining
        else
          true = C.valid_wire?(kind, id, row)
          Map.put(remaining, entry_id(id), row)
        end

      {:ok, sibling} = deletion_neighbor(kind, refs, id)

      if is_nil(sibling) do
        true = is_nil(neighbor)
        [change(ref, page(kind, selected["fence"], remaining))]
      else
        sibling_fence = ref_fence(kind, sibling)
        {:ok, sn} = neighbors(kind, refs, sibling_fence)
        true = valid_page?(kind, sibling, sn["next"], neighbor)

        true =
          MapSet.disjoint?(
            MapSet.new(Map.keys(remaining)),
            MapSet.new(Map.keys(neighbor["entries"]))
          )

        {left_ref, right_ref, lower, upper} =
          if sibling_fence < selected["fence"],
            do: {sibling, ref, sibling_fence, n["next"]},
            else: {ref, sibling, selected["fence"], sn["next"]}

        combined = Map.merge(remaining, neighbor["entries"])
        proposed = emit(kind, lower, combined, left_ref, upper)
        old_right = right_ref["key"]

        case Enum.find(proposed, &(&1["key"] == old_right)) do
          nil ->
            proposed ++ [change(right_ref, nil)]

          _ ->
            Enum.map(proposed, fn c ->
              if c["key"] == old_right,
                do: Map.put(c, "expected_revision", right_ref["revision"]),
                else: c
            end)
        end
      end
    end)
  end

  def weights(kind, entries) do
    Enum.map(entries, fn {id, row} ->
      true = fence?(kind, id) and C.valid_wire?(kind, id, row)
      byte_size(C.bytes(%{entry_id(id) => row})) - 1
    end)
  end

  defp emit(kind, fence, entries, ref, upper) do
    value = page(kind, fence, entries)

    if fits?(value) do
      [change(ref || %{"key" => key(kind, fence), "revision" => 0}, value)]
    else
      ordered = Enum.sort_by(entries, fn {packed, _} -> identity(kind, packed) end)
      true = length(ordered) in 2..128

      best =
        Enum.map(1..(length(ordered) - 1), fn cut ->
          {a, b} = Enum.split(ordered, cut)
          next_fence = identity(kind, elem(hd(b), 0))
          left = page(kind, fence, Map.new(a))
          right = page(kind, next_fence, Map.new(b))
          {max(byte_size(C.bytes(left)), byte_size(C.bytes(right))), cut, left, right}
        end)
        |> Enum.filter(fn {_, _, a, b} -> fits?(a) and fits?(b) end)
        |> Enum.min_by(fn {size, cut, _, _} -> {size, cut} end)

      {_, _, left, right} = best
      true = is_nil(upper) or right["fence"] < ref_fence(kind, upper)

      [
        change(ref || %{"key" => key(kind, fence), "revision" => 0}, left),
        change(%{"key" => key(kind, right["fence"]), "revision" => 0}, right)
      ]
    end
  end

  defp fits?(v), do: map_size(v["entries"]) <= @count and byte_size(C.bytes(v)) <= @limit

  defp change(ref, v),
    do: %{"key" => ref["key"], "expected_revision" => ref["revision"], "value" => v}

  defp ref_fence(kind, ref) do
    true = C.keys?(ref, ~w(key revision)) and C.uint?(ref["revision"]) and ref["revision"] > 0
    true = String.starts_with?(ref["key"], prefix(kind))
    f = String.replace_prefix(ref["key"], prefix(kind), "")
    true = fence?(kind, f)
    f
  end

  defp fence?(kind, id),
    do:
      is_binary(id) and byte_size(id) == width(kind) and Regex.match?(~r/\A[0-9a-f]+\z/, id) and
        (kind != :live or binary_part(id, 0, 2) in ~w(00 01 02))

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_managed_leaf}
  end
end
