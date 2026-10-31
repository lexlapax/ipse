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
  @tag source_relation_anchors: true
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

    referenced =
      seed["records"]
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "source.") end)
      |> Enum.flat_map(fn {key, row} -> [key | Enum.map(row["value"]["blocks"], & &1["key"])] end)

    for key <- referenced do
      row = seed["records"][key]
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

  for kind <- ~w(reverse-order segmented-document) do
    @tag source_relation_additive: true
    test "authenticates actual producer #{kind} ranges without imposing a host chunk splitter" do
      kind = unquote(kind)

      path =
        "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-relation-seeds/pending-v3-#{kind}.exs"

      {seed, _} = Code.eval_file(path)
      key = seed["guard"]["claim_key"]
      # The developer model uses uppercase hexadecimal. Adapt that model-only
      # field to Core's lowercase native ID syntax; this is no native receipt.
      seed = update_in(seed, ["records", key, "operation_id"], &String.downcase/1)
      assert {:ok, facts} = authenticate(seed)
      assert DocumentSourceUse.current?(facts, 100)

      if kind == "reverse-order" do
        claim = seed["records"][key]["value"]

        ordinals =
          Enum.map(claim["source_bindings"], fn b ->
            seed["records"]["source.notes." <> b["source_key"]]["value"]["ordinal"]
          end)

        assert ordinals === [1, 0]
      else
        refs = seed["records"][key]["value"]["inputs"]
        assert length(refs) === 3
        assert Enum.at(Enum.at(refs, 1), 5) > Enum.at(hd(refs), 6)
      end
    end
  end
end

defmodule Ipse.Extension.CollectionDocumentSourceUseNativeTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.{DocumentSourceUse, Profile}

  defp packed(value) do
    body = IO.iodata_to_binary(Elixir.JSON.encode!(value))

    parts =
      Stream.unfold(body, fn
        "" ->
          nil

        rest ->
          n = min(6144, byte_size(rest))
          {binary_part(rest, 0, n), binary_part(rest, n, byte_size(rest) - n)}
      end)
      |> Enum.to_list()

    %{
      "version" => 1,
      "kind" => "document_value",
      "parts" => parts,
      "sha256" => JSON.sha256(body),
      "byte_count" => byte_size(body)
    }
  end

  @tag source_relation_additive: true
  test "actual retained native reads preserve the real claim commit and refuse escaped reuse" do
    {seed, _} =
      Code.eval_file(
        "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-host-seed/pending-v3-model.exs"
      )

    parent = Path.join(System.tmp_dir!(), "ipse-document-source-use-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = parent <> "/collections"
    namespace = JSON.sha256("document-source-use synthetic native fixture")
    claim_key = seed["guard"]["claim_key"]
    values = Map.delete(seed["records"], claim_key)
    seed_operation = Usage.id()

    assert {:ok, %{"generation" => 1}} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" =>
                   Enum.map(values, fn {key, row} ->
                     %{"key" => key, "expected_revision" => 0, "value" => packed(row["value"])}
                   end)
               },
               seed_operation,
               Profile.documents()
             )

    claim =
      seed["records"][claim_key]["value"]
      |> Map.put("job_revision", 1)
      |> Map.update!("source_bindings", &Enum.map(&1, fn b -> Map.put(b, "head_revision", 1) end))

    claim_operation = Usage.id()

    assert {:ok, %{"generation" => 2}} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => claim_key, "expected_revision" => 0, "value" => packed(claim)}
                 ]
               },
               claim_operation,
               Profile.documents()
             )

    guard = %{
      seed["guard"]
      | "claim_revision" => 2,
        "claim_sha256" => JSON.sha256(IO.iodata_to_binary(Elixir.JSON.encode!(claim)))
    }

    assert {:ok, read} =
             Collection.with_document_read(root, namespace, fn witness, read ->
               assert witness["generation"] === 2

               assert {:ok, facts} =
                        DocumentSourceUse.authenticate(
                          read,
                          guard,
                          seed["inputs"],
                          seed["selection"]
                        )

               assert facts.claim_operation_id === claim_operation
               assert facts.claim_revision === 2 and facts.reads === 7
               assert DocumentSourceUse.current?(facts, System.system_time(:millisecond))
               {:ok, read}
             end)

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate(read, guard, seed["inputs"], seed["selection"])
  end
end

