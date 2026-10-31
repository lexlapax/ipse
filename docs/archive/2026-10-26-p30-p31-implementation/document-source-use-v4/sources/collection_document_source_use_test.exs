defmodule Ipse.Extension.CollectionDocumentSourceUseTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON, as: J
  alias Ipse.Extension.Collection.DocumentSourceUse

  Code.require_file("extensions/knowledge/src/evidence.ex")

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
    claim = seed["records"][seed["guard"]["claim_key"]]["value"]

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

  @tag :source_v4
  test "v4 verifies full head count and each exact ordered page while v3 remains separate", %{
    seed: seed
  } do
    first = page_v4(seed, 0)
    last = page_v4(seed, 8)

    for page <- [first, last] do
      key = page["guard"]["claim_key"]
      claim = page["records"][key]["value"]
      assert DocumentSourceUse.guard?(page["guard"])
      assert DocumentSourceUse.pending?(claim, key)
      assert {:ok, %{batch_index: 0}} = authenticate(page)
    end

    last_second =
      last |> put_in(["guard", "batch_index"], 1) |> Map.put("inputs", batch_texts(last, 1))

    assert {:ok, %{batch_index: 1, batch_count: 2}} = authenticate(last_second)

    fake_count =
      change_claim(last, fn c ->
        c |> Map.put("vector_count", 10) |> Map.update!("inputs", &Enum.take(&1, 2))
      end)

    assert DocumentSourceUse.pending?(
             fake_count["records"][fake_count["guard"]["claim_key"]]["value"],
             fake_count["guard"]["claim_key"]
           )

    assert {:error, :document_source_use_refused} = authenticate(fake_count)

    wrong_order =
      change_claim(last, &Map.update!(&1, "inputs", fn refs -> Enum.reverse(refs) end))

    assert {:error, :document_source_use_refused} = authenticate(wrong_order)
    wrong_version = put_in(last, ["guard", "version"], 1)
    refute DocumentSourceUse.guard?(wrong_version["guard"])
    assert {:error, :document_source_use_refused} = authenticate(wrong_version)

    assert {:ok, _} = authenticate(seed)

    refute DocumentSourceUse.pending?(
             seed["records"]["genproducer.notes"]["value"],
             "genproducer.notes"
           )
  end

  @tag :source_v4
  test "v4 closed pending and compact ready reject aliases, broken predecessor and receipt shapes",
       %{seed: seed} do
    page = page_v4(seed, 8)
    key = page["guard"]["claim_key"]
    pending = page["records"][key]["value"]
    ready = compact_ready(pending)
    assert DocumentSourceUse.ready?(ready, key)
    refute DocumentSourceUse.pending?(ready, key)
    refute DocumentSourceUse.ready?(pending, key)

    for invalid <- [
          Map.put(pending, "extra", true),
          Map.put(pending, "vector_cursor", 9),
          Map.put(pending, "vector_count", 257),
          put_in(pending, ["previous_ready", "key"], "genproducer4.notes.01"),
          put_in(pending, ["previous_ready", "revision"], 0),
          put_in(pending, ["source_bindings", Access.at(0), "historical"], true)
        ] do
      refute DocumentSourceUse.pending?(invalid, key)
    end

    for alias_key <- ~w(genproducer4.notes.01 genproducer4.notes.32 genproducer.notes.1) do
      refute DocumentSourceUse.guard?(Map.put(page["guard"], "claim_key", alias_key))
      refute DocumentSourceUse.pending?(pending, alias_key)
      refute DocumentSourceUse.ready?(ready, alias_key)
    end

    first = page_v4(seed, 0)
    first_claim = first["records"][first["guard"]["claim_key"]]["value"]

    maximum =
      first_claim
      |> Map.put("vector_cursor", 248)
      |> Map.put("vector_count", 256)
      |> Map.put("previous_ready", %{
        "key" => "genproducer4.notes.30",
        "revision" => 1,
        "sha256" => J.sha256("previous"),
        "byte_count" => 1
      })

    assert DocumentSourceUse.pending?(maximum, "genproducer4.notes.31")
    assert DocumentSourceUse.guard?(Map.put(page["guard"], "claim_key", "genproducer4.notes.31"))

    for invalid <- [
          Map.put(ready, "source_bindings", []),
          Map.put(ready, "input_count", 2),
          put_in(ready, ["claim", "revision"], 0),
          put_in(ready, ["page", "key"], "genvec.notes.foreign"),
          put_in(
            ready,
            ["receipts", Access.at(1), "operation_id"],
            hd(ready["receipts"])["operation_id"]
          ),
          put_in(ready, ["receipts", Access.at(1), "raw_input_sha256"], [])
        ] do
      refute DocumentSourceUse.ready?(invalid, key)
    end
  end

  defp page_v4(seed, cursor) do
    old = seed["records"]["genproducer.notes"]
    claim = old["value"]
    binding = hd(claim["source_bindings"])
    head = seed["records"]["source.notes." <> binding["source_key"]]["value"]

    bytes =
      Enum.flat_map(head["blocks"], &seed["records"][&1["key"]]["value"]["pieces"])
      |> IO.iodata_to_binary()

    {:ok, source} = J.decode_unique(bytes)
    {:ok, chunks} = IpseKnowledge.Evidence.chunks(source)

    refs =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {chunk, ci} ->
        [
          0,
          ci,
          chunk["chunk_id"],
          J.digest([chunk["text"]]),
          J.sha256(chunk["text"]),
          chunk["start_byte"],
          chunk["end_byte"]
        ]
      end)
      |> Enum.slice(cursor, 8)

    ordinal = div(cursor, 8)
    key = "genproducer4.notes.#{ordinal}"

    previous =
      if cursor == 0,
        do: nil,
        else: %{
          "key" => "genproducer4.notes.#{ordinal - 1}",
          "revision" => 1014,
          "sha256" => J.sha256("previous"),
          "byte_count" => 100
        }

    updated =
      claim
      |> Map.merge(%{
        "version" => 4,
        "recipe" => "ipse.evidence.shared_producer.pages.v4",
        "vector_cursor" => cursor,
        "vector_count" => length(chunks),
        "previous_ready" => previous,
        "inputs" => refs
      })

    row = row_value(old, fn _ -> updated end) |> Map.put("key", key)

    inputs =
      Enum.take(refs, 2)
      |> Enum.map(fn [_, _, _, _, _, start, finish] ->
        binary_part(source["text"], start, finish - start)
      end)

    seed
    |> put_in(["records", key], row)
    |> put_in(["guard", "version"], 2)
    |> put_in(["guard", "claim_key"], key)
    |> put_in(["guard", "claim_sha256"], row["sha256"])
    |> Map.put("inputs", inputs)
  end

  defp compact_ready(pending) do
    receipts =
      pending["inputs"]
      |> Enum.chunk_every(2)
      |> Enum.with_index()
      |> Enum.map(fn {rows, index} ->
        %{
          "operation_id" => String.pad_leading(Integer.to_string(index + 1), 32, "0"),
          "source_sha256" => J.sha256("source"),
          "input_sha256" => Enum.map(rows, &Enum.at(&1, 3)),
          "raw_input_sha256" => Enum.map(rows, &Enum.at(&1, 4))
        }
      end)

    hash = J.sha256("page")

    pending
    |> Map.drop(~w(source_bindings inputs))
    |> Map.merge(%{
      "status" => "ready",
      "claim" => %{
        "revision" => 1014,
        "sha256" => J.sha256("claim"),
        "operation_id" => String.duplicate("1", 32)
      },
      "input_count" => length(pending["inputs"]),
      "input_refs_sha256" => J.sha256(IO.iodata_to_binary(JSON.encode!(pending["inputs"]))),
      "page" => %{"key" => "genvec.notes." <> hash, "sha256" => hash, "byte_count" => 100},
      "receipts" => receipts
    })
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
  @tag source_relation_native: true
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
               assert witness["root"]["generation"] === 2

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
