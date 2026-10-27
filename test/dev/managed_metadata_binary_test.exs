Code.require_file("../../dev/knowledge/managed_metadata.ex", __DIR__)
Code.require_file("../../dev/knowledge/managed_metadata_shapes.exs", __DIR__)
Code.require_file("../../dev/knowledge/managed_metadata_binary.ex", __DIR__)
Code.require_file("../../dev/knowledge/managed_metadata_binary_shapes.exs", __DIR__)

defmodule Ipse.Development.ManagedMetadataBinaryTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.ManagedMetadata.Binary, as: B
  alias Ipse.Development.ManagedMetadata.BinaryShapes, as: S
  alias Ipse.Development.ManagedMetadata.Shapes, as: F

  test "safe integer varints are minimal exact and bounded" do
    for n <- [0, 1, 127, 128, 16383, 16384, Bitwise.bsl(1, 49), B.safe()] do
      assert {^n, <<42>>} = B.take_uint(B.uint(n) <> <<42>>)
      assert byte_size(B.uint(n)) <= 8
    end

    for bad <- [
          <<128, 0>>,
          <<255, 255, 255, 255, 255, 255, 255, 255, 0>>,
          <<128>>,
          <<255, 255, 255, 255, 255, 255, 255, 127>>
        ] do
      assert catch_error(B.take_uint(bad))
    end
  end

  test "candidate v2 preserves all proposed fields and checks exact no-LF input hash" do
    for policy <- [
          %{"kind" => "pin"},
          %{"kind" => "session"},
          %{"kind" => "ordinary"},
          %{"kind" => "duration", "duration_ms" => B.safe()}
        ] do
      id = F.hash(1)
      capsule = S.capsule(id, policy)
      encoded = B.capsule_encode(id, capsule)
      assert byte_size(encoded) == if(policy["kind"] == "duration", do: 201, else: 194)
      assert {^capsule, <<77>>} = B.capsule_decode(id, encoded <> <<77>>)
      assert_raise MatchError, fn -> B.capsule_encode(F.hash(2), capsule) end

      assert_raise MatchError, fn ->
        B.capsule_encode(
          id,
          Map.put(capsule, "input_sha256", F.hash("forget 0123456789abcdef\n"))
        )
      end

      assert_raise MatchError, fn ->
        B.capsule_encode(id, Map.put(capsule, "reason", String.duplicate("r", 65)))
      end
    end
  end

  test "legacy full evidence and candidate pages roundtrip independently with all retirement models" do
    for {kind, make} <- [anchor_full: &F.full_choice/1, anchor_native_candidate: &S.capsule/1],
        retirement <- [:none, :sticky_clock, :target_witness] do
      id = F.hash(7)
      entries = %{id => S.anchor(make.(id), S.retirement(id, retirement))}
      assert {:ok, value} = B.encode_page(kind, B.zero(kind), entries)
      assert byte_size(B.bytes(value)) <= 6144
      assert {:ok, %{entries: ^entries}} = B.decode_page(value)
    end
  end

  test "live shared dictionaries preserve all hashes and refuse unused or malformed bytes" do
    entries = Map.new(1..24, &S.live(&1))
    assert {:ok, value} = B.encode_page(:live, B.zero(:live), entries)
    assert {:ok, %{entries: ^entries}} = B.decode_page(value)
    assert {:error, _} = B.decode_page(Map.put(value, "data", value["data"] <> "="))
    assert {:error, _} = B.decode_page(Map.put(value, "extra", true))
    raw = Base.url_decode64!(value["data"], padding: false)

    <<header::binary-size(6), count, hashes::binary-size(64), rest::binary>> = raw
    unused = header <> <<count + 1>> <> hashes <> :binary.copy(<<255>>, 32) <> rest

    assert {:error, _} =
             B.decode_page(Map.put(value, "data", Base.url_encode64(unused, padding: false)))

    assert {:error, _} = B.decode_page(Map.put(value, "data", String.duplicate("x", 6145)))

    assert {:error, _} =
             B.decode_page(
               Map.put(value, "data", Base.url_encode64(raw <> <<0>>, padding: false))
             )
  end

  test "front coding is exact for same-prefix IDs and rejects aliases duplicates and reversed rows" do
    ids =
      for n <- 1..33,
          do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

    entries = Map.new(ids, &{&1, S.anchor()})
    assert {:ok, value} = B.encode_page(:anchor_full, B.zero(:anchor_full), entries)
    assert {:ok, %{entries: ^entries}} = B.decode_page(value)
    assert {:error, _} = B.decode_page(value, Enum.at(ids, 10))
    raw = Base.url_decode64!(value["data"], padding: false)
    # First identity is encoded relative to the all-zero lower fence with LCP31.
    <<header::binary-size(6), 31, suffix, rest::binary>> = raw
    noncanonical = header <> <<30, 0, suffix>> <> rest

    assert {:error, _} =
             B.decode_page(
               Map.put(value, "data", Base.url_encode64(noncanonical, padding: false))
             )

    <<"IMB", 1, 1, 33, rest::binary>> = raw

    assert {:error, _} =
             B.decode_page(
               Map.put(
                 value,
                 "data",
                 Base.url_encode64(<<"IMB", 1, 1, 34, rest::binary>>, padding: false)
               )
             )

    assert {:error, _} =
             B.encode_page(:anchor_full, hd(ids), %{B.zero(:anchor_full) => S.anchor()})

    assert {:error, _} = B.encode_page(:anchor_full, hd(ids), %{})
  end

  test "closed framing rejects unsupported versions unsafe clocks and truncation" do
    id = F.hash(1)
    row = S.anchor(S.capsule(id))

    assert {:ok, value} =
             B.encode_page(:anchor_native_candidate, B.zero(:anchor_native_candidate), %{
               id => row
             })

    raw = Base.url_decode64!(value["data"], padding: false)

    for length <- 0..(byte_size(raw) - 1) do
      cut = binary_part(raw, 0, length)

      assert {:error, _} =
               B.decode_page(Map.put(value, "data", Base.url_encode64(cut, padding: false)))
    end

    <<"IMB", 1, kind, rest::binary>> = raw

    for bad <- [<<"IMB", 2, kind, rest::binary>>, <<"IMB", 1, 255, rest::binary>>] do
      assert {:error, _} =
               B.decode_page(Map.put(value, "data", Base.url_encode64(bad, padding: false)))
    end

    capsule = B.capsule_encode(id, S.capsule(id))
    <<prefix::binary-size(121), _at::56, rest::binary>> = capsule

    assert_raise MatchError, fn ->
      B.capsule_decode(id, prefix <> <<B.safe() + 1::56>> <> rest)
    end

    assert {:error, _} = B.decode_page(Map.put(value, "version", 2))
  end

  test "calendar sizing keeps exact clocks and distinguishes the synthetic epoch" do
    id = F.hash(1)
    calendar = S.anchor(nil, S.retirement(id, :sticky_clock, :calendar_2026), :calendar_2026)
    fixture = S.anchor(nil, nil, :bounded_fixture)
    [first, deadline, nil, nil] = calendar["clocks"]
    assert byte_size(B.uint(first)) == 6
    assert byte_size(B.uint(hd(fixture["clocks"]))) == 5
    assert deadline - first == 90 * 86_400_000
    assert calendar["retirement"]["at_ms"] - first == 365 * 86_400_000

    assert {:ok, page} =
             B.encode_page(:anchor_native_candidate, B.zero(:anchor_native_candidate), %{
               id => calendar
             })

    assert {:ok, %{entries: %{^id => ^calendar}}} = B.decode_page(page)
  end
end
