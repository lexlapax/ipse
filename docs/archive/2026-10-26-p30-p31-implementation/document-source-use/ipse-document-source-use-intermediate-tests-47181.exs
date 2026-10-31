defmodule Ipse.Extension.CollectionDocumentSourceUseTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON, as: J
  alias Ipse.Extension.Collection.DocumentSourceUse

  @seed "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-host-seed/pending-v3-model.exs"

  setup do
    {seed, _} = Code.eval_file(@seed)
    %{seed: seed}
  end

  # This is an explicitly synthetic storage relation, not a native read owner or
  # an authenticated Session. The native held-reader tests own that boundary.
  defp read(records) do
    fn key ->
      case records[key] do
        nil ->
          {:ok, nil}

        row ->
          bytes = IO.iodata_to_binary(JSON.encode!(row["value"]))

          packed = %{
            "version" => 1,
            "kind" => "document_value",
            "parts" => parts(bytes),
            "sha256" => J.sha256(bytes),
            "byte_count" => byte_size(bytes)
          }

          {:ok, Map.put(row, "value", packed)}
      end
    end
  end

  defp parts(""), do: []

  defp parts(bytes) do
    size = utf8_size(bytes, min(6144, byte_size(bytes)))
    [binary_part(bytes, 0, size) | parts(binary_part(bytes, size, byte_size(bytes) - size))]
  end

  defp utf8_size(bytes, size),
    do: if(String.valid?(binary_part(bytes, 0, size)), do: size, else: utf8_size(bytes, size - 1))

  defp authenticate(seed),
    do:
      DocumentSourceUse.authenticate(
        read(seed["records"]),
        seed["guard"],
        seed["inputs"],
        seed["selection"]
      )

  defp row_value(row, fun) do
    value = fun.(row["value"])
    bytes = IO.iodata_to_binary(JSON.encode!(value))

    Map.merge(row, %{
      "value" => value,
      "sha256" => J.sha256(bytes),
      "byte_count" => byte_size(bytes)
    })
  end

  defp change_claim(seed, fun) do
    key = seed["guard"]["claim_key"]
    row = row_value(seed["records"][key], fun)
    seed |> put_in(["records", key], row) |> put_in(["guard", "claim_sha256"], row["sha256"])
  end

  defp batch_texts(seed, index) do
    claim = seed["records"]["genproducer.notes"]["value"]

    Enum.slice(claim["inputs"], index * 2, 2)
    |> Enum.map(fn [si, _, _, _, _, start, finish] ->
      key = Enum.at(claim["source_bindings"], si)["source_key"]
      head = seed["records"]["source.notes." <> key]["value"]

      bytes =
        Enum.flat_map(head["blocks"], fn ref -> seed["records"][ref["key"]]["value"]["pieces"] end)
        |> IO.iodata_to_binary()

      {:ok, source} = J.decode_unique(bytes)
      binary_part(source["text"], start, finish - start)
    end)
  end

  @tag source_relation_repair: true
  test "authenticates the actual private producer seed, all four exact batches and original modeled operation",
       %{seed: seed} do
    assert {:ok, facts} = authenticate(seed)

    assert facts.claim_operation_id ===
             seed["claim_commit_action"]["outcome"]["value"]["operation_id"]

    assert facts.claim_revision === seed["guard"]["claim_revision"]
    assert facts.batch_count === 4 and facts.reads === 7
    assert facts.logical_bytes < 100_000 and facts.bundle_bytes > 40_000
    assert DocumentSourceUse.current?(facts, 100)

    for index <- 1..3 do
      inputs = batch_texts(seed, index)
      next = seed |> put_in(["guard", "batch_index"], index) |> Map.put("inputs", inputs)
      assert {:ok, %{batch_index: ^index}} = authenticate(next)
    end
  end

  @tag source_relation_repair: true
  test "rejects stale anchors, changed source transport and mismatched prepared inputs", %{
    seed: seed
  } do
    for key <- ~w(genjob.notes genproducer.notes) do
      candidate = update_in(seed, ["records", key, "revision"], &(&1 + 1))
      assert {:error, :document_source_use_refused} = authenticate(candidate)
    end

    candidate = put_in(seed, ["records", "genproducer.notes", "operation_id"], nil)
    assert {:error, :document_source_use_refused} = authenticate(candidate)

    for {key, change} <- [
          {"catalog.notes", &Map.update!(&1, "floor", fn n -> n + 1 end)},
          {"genjob.notes", &Map.put(&1, "id", String.duplicate("0", 32))}
        ] do
      candidate = update_in(seed, ["records", key], &row_value(&1, change))
      assert {:error, :document_source_use_refused} = authenticate(candidate)
    end

    for {key, row} <- seed["records"],
        String.starts_with?(key, "source.") or String.starts_with?(key, "data.") do
      candidate = put_in(seed, ["records", key], row_value(row, &Map.put(&1, "kind", "foreign")))
      assert {:error, :document_source_use_refused} = authenticate(candidate)
    end

    assert {:error, :document_source_use_refused} =
             authenticate(Map.put(seed, "inputs", ["unrelated bytes"]))

    assert {:error, :document_source_use_refused} =
             authenticate(put_in(seed, ["selection", "selection_sha256"], J.sha256("foreign")))

    assert {:error, :document_source_use_refused} =
             authenticate(
               put_in(seed, ["records", "generation.notes"], %{"revision" => 1, "value" => %{}})
             )
  end

  test "even a newly matching claim hash cannot authorize foreign, truncated or malformed ranges",
       %{seed: seed} do
    changes = [
      &Map.put(&1, "version", 2),
      &Map.put(&1, "status", "ready"),
      &Map.update!(&1, "inputs", fn refs -> Enum.take(refs, 2) end),
      &Map.update!(&1, "inputs", fn refs -> Enum.reverse(refs) end),
      &update_in(&1, ["inputs", Access.at(0), Access.at(0)], fn _ -> 7 end),
      &update_in(&1, ["inputs", Access.at(0), Access.at(2)], fn _ -> J.sha256("foreign chunk") end),
      &update_in(&1, ["inputs", Access.at(0), Access.at(5)], fn _ -> 0.0 end),
      &update_in(&1, ["inputs", Access.at(0), Access.at(6)], fn _ -> 65_537 end),
      &update_in(&1, ["source_bindings", Access.at(0), "observed_at_ms"], fn _ -> 11 end)
    ]

    for change <- changes,
        do:
          assert(
            {:error, :document_source_use_refused} = authenticate(change_claim(seed, change))
          )
  end

  test "host time decision is exclusive, checks every source and is separate from stored authentication",
       %{seed: seed} do
    assert {:ok, facts} = authenticate(seed)

    facts = %{
      facts
      | sources: [%{"observed_at_ms" => 10, "expires_at_ms" => 100, "historical" => false}]
    }

    assert DocumentSourceUse.current?(facts, 10)
    assert DocumentSourceUse.current?(facts, 99)
    refute DocumentSourceUse.current?(facts, 100)
    refute DocumentSourceUse.current?(facts, 9)

    refute DocumentSourceUse.current?(
             %{
               facts
               | sources:
                   facts.sources ++
                     [%{"observed_at_ms" => 10, "expires_at_ms" => nil, "historical" => true}]
             },
             99
           )

    refute DocumentSourceUse.current?(%{sources: []}, 99)
  end

  test "malformed guards and escaped/unavailable readers do not yield authenticated facts", %{
    seed: seed
  } do
    for guard <- [
          nil,
          %{},
          Map.put(seed["guard"], "batch_index", 4),
          Map.put(seed["guard"], "extra", true)
        ] do
      refute DocumentSourceUse.guard?(guard)
      assert {:error, :document_source_use_refused} = authenticate(Map.put(seed, "guard", guard))
    end

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate(
               fn _ -> {:error, :collection_unavailable} end,
               seed["guard"],
               seed["inputs"],
               seed["selection"]
             )
  end
end

