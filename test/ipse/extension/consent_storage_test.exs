defmodule Ipse.Extension.ConsentStorageTest do
  use ExUnit.Case, async: false
  alias Ipse.JSON
  alias Ipse.Extension.Consent, as: C

  def state(count, actual \\ [1, 0, 131_072, 16_384, 0, 0]) do
    project = JSON.sha256("synthetic consent geometry")
    hash = JSON.sha256("synthetic request/receipt")

    rows =
      Map.new(1..count, fn sequence ->
        {Integer.to_string(sequence, 16) |> String.downcase() |> String.pad_leading(32, "0"),
         [sequence, 5, hash, 1_795_485_346_653, "settled", actual, hash]}
      end)

    %{
      "version" => 2,
      "project" => project,
      "epoch" => 5,
      "sequence" => count,
      "policy" => nil,
      "operations" => %{},
      "compacted" => rows
    }
  end

  test "v1/v2 remain readable in memory with no storage mutation" do
    state = state(1)

    for logical <- [
          state,
          %{state | "version" => 1, "sequence" => 0, "compacted" => %{}}
          |> Map.delete("compacted")
        ] do
      bytes = Jason.encode!(logical)
      assert {:ok, decoded} = C.decode_control(bytes, state["project"])
      assert decoded["version"] === 2
      assert Jason.encode!(logical) === bytes
    end
  end

  test "disk v3 is lossless and ordinary in-memory operation/public hex rows stay exact" do
    state = state(2)
    [id | _] = Map.keys(state["compacted"])
    state = put_in(state, ["compacted", id, Access.at(4)], "reconciled_overrun")
    assert {:ok, bytes} = C.encode_control(state, state["project"])
    stored = Jason.decode!(bytes)
    assert stored["version"] === 3

    assert Map.keys(stored["compacted"]) |> Enum.sort() ===
             Enum.sort(Map.keys(state["compacted"]))

    assert {:ok, ^state} = C.decode_control(bytes, state["project"])

    assert Enum.all?(stored["compacted"], fn {_, [_, _, packed, _, status, _]} ->
             byte_size(packed) === 86 and status in [0, 1]
           end)
  end

  test "reject aliases, malformed packed hashes, float discriminants and extra fields" do
    state = state(1)
    assert {:ok, bytes} = C.encode_control(state, state["project"])
    stored = Jason.decode!(bytes)
    [{id, row}] = Map.to_list(stored["compacted"])
    packed = Enum.at(row, 2)
    last = binary_part(packed, 85, 1)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    {index, 1} = :binary.match(alphabet, last)
    alias_hash = binary_part(packed, 0, 85) <> binary_part(alphabet, index + 1, 1)

    for bad <- [
          Map.put(stored, "version", 3.0),
          Map.put(stored, "extra", true),
          put_in(stored, ["compacted", id], List.replace_at(row, 2, packed <> "==")),
          put_in(stored, ["compacted", id], List.replace_at(row, 2, alias_hash)),
          put_in(stored, ["compacted", id], List.replace_at(row, 2, String.duplicate("A", 85))),
          put_in(stored, ["compacted", id], List.replace_at(row, 4, 0.0)),
          put_in(stored, ["compacted", id], List.replace_at(row, 4, 2)),
          put_in(stored, ["compacted", id], row ++ ["extra"])
        ] do
      assert {:error, :consent_unavailable} =
               C.decode_control(Jason.encode!(bad), state["project"])
    end

    assert {:error, :consent_unavailable} = C.decode_control(bytes, JSON.sha256("foreign"))

    assert {:error, :consent_unavailable} =
             C.decode_control("{\"version\":3,\"version\":3}", state["project"])
  end

  test "unknown liabilities and full recent receipts are byte-for-byte fields" do
    state = state(1)
    hash = JSON.sha256("synthetic full row")
    id = String.duplicate("f", 32)

    request = %{
      "id" => id,
      "operation" => "knowledge.capture",
      "artifact_sha256" => hash,
      "source_sha256" => hash,
      "policy_sha256" => hash,
      "request_sha256" => hash,
      "source_generation" => 1,
      "reserved" => Map.new(C.resources(), &{&1, 1}),
      "headless" => false,
      "sequence" => 2,
      "epoch" => 5,
      "created_at_ms" => 1_795_485_346_654,
      "status" => "unknown",
      "actual" => nil,
      "receipt" => nil
    }

    state = %{state | "sequence" => 2, "operations" => %{id => request}}
    assert {:ok, bytes} = C.encode_control(state, state["project"])
    assert Jason.decode!(bytes)["operations"] === state["operations"]
    assert {:ok, ^state} = C.decode_control(bytes, state["project"])
  end

  @tag timeout: 120_000
  test "specified annual geometry with64 full recent8KiB receipts retains reserved write headroom" do
    count = 31_052
    state = state(count - 64)
    hash = JSON.sha256("synthetic full row")
    actual = Map.new(Enum.zip(C.resources(), [1, 0, 131_072, 16_384, 0, 0]))
    receipt = %{"payload" => String.duplicate("x", 8_178)}
    assert byte_size(Jason.encode!(receipt)) === 8192

    recent =
      Map.new((count - 63)..count, fn seq ->
        id = Integer.to_string(seq, 16) |> String.downcase() |> String.pad_leading(32, "0")

        {id,
         %{
           "id" => id,
           "operation" => "knowledge.capture",
           "artifact_sha256" => hash,
           "source_sha256" => hash,
           "policy_sha256" => hash,
           "request_sha256" => hash,
           "source_generation" => seq,
           "reserved" => actual,
           "headless" => true,
           "sequence" => seq,
           "epoch" => 5,
           "created_at_ms" => 1_795_485_346_653,
           "status" => "settled",
           "actual" => actual,
           "receipt" => receipt
         }}
      end)

    state = %{state | "sequence" => count, "operations" => recent}
    {encode_us, {:ok, bytes}} = :timer.tc(fn -> C.encode_control(state, state["project"]) end)
    {decode_us, {:ok, ^state}} = :timer.tc(fn -> C.decode_control(bytes, state["project"]) end)
    compact_old = byte_size(Jason.encode!(state["compacted"]))
    stored = Jason.decode!(bytes)
    compact_new = byte_size(Jason.encode!(stored["compacted"]))
    assert compact_old - compact_new === 53 * (count - 64)
    receipt_bytes = 64 * 8192
    required = byte_size(bytes) - receipt_bytes - 4 + receipt_bytes + 32_768 + 16 - 1
    assert required <= 6_225_920

    geometry = %{
      "kind" => "pure_synthetic_annual_consent_geometry",
      "identities" => count,
      "compacted" => count - 64,
      "full_recent" => 64,
      "actual_vector_envelope" => [1, 0, 131_072, 16_384, 0, 0],
      "actual_vector_note" =>
        "source recipe output16384 and zero model/download/cost; input131072 is conservative envelope, not measured future actual",
      "old_compacted_object_bytes" => compact_old,
      "v3_compacted_object_bytes" => compact_new,
      "v3_encoded_state_bytes" => byte_size(bytes),
      "v3_reserved_maintenance_bytes" => required,
      "write_cap" => 6_225_920,
      "reserved_headroom_bytes" => 6_225_920 - required,
      "saved_bytes_per_settled_compacted_row" => 53,
      "encode_validation_roundtrip_us" => encode_us,
      "decode_validation_us" => decode_us,
      "receipts" => "64full8192B retained; compacted SHA unchanged",
      "app_started" => false,
      "original_accessed" => false,
      "annual_feasibility_qualified" => false
    }

    assert geometry["reserved_headroom_bytes"] > 200_000
  end

  @tag timeout: 120_000
  test "unchanged serialized budget refuses worst-size legal vectors without pruning" do
    state = state(32_768, List.duplicate(9_007_199_254_740_991, 6))
    assert {:error, :consent_capacity} = C.encode_control(state, state["project"])
    assert map_size(state["compacted"]) === 32_768
  end
end
