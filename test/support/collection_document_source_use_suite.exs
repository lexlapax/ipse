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

  test "projection source authentication binds the current catalog, head, complete bundle and time",
       %{seed: seed} do
    claim = seed["records"][seed["guard"]["claim_key"]]["value"]
    binding = hd(claim["source_bindings"])

    target = %{
      "partition" => claim["partition"],
      "source_key" => binding["source_key"],
      "catalog_sha256" => claim["catalog_sha256"],
      "head_revision" => binding["head_revision"],
      "head_sha256" => binding["head_sha256"],
      "source_bundle_sha256" => binding["bundle_sha256"]
    }

    assert {:ok, facts} =
             DocumentSourceUse.authenticate_projection_source(read(seed["records"]), target)

    assert facts.reads >= 4 and facts.reads <= 35
    assert DocumentSourceUse.current?(facts, binding["observed_at_ms"])

    expired =
      put_in(facts.sources, [
        %{"observed_at_ms" => 1, "expires_at_ms" => 10, "historical" => false}
      ])

    assert DocumentSourceUse.current?(expired, 9)
    refute DocumentSourceUse.current?(expired, 10)

    for changed <- [
          Map.put(target, "head_revision", target["head_revision"] + 1),
          Map.put(target, "head_sha256", String.duplicate("0", 64)),
          Map.put(target, "catalog_sha256", String.duplicate("0", 64)),
          Map.put(target, "source_bundle_sha256", String.duplicate("0", 64)),
          Map.put(target, "extra", true)
        ] do
      assert {:error, :document_source_use_refused} =
               DocumentSourceUse.authenticate_projection_source(read(seed["records"]), changed)
    end

    page = seed["records"]["catalog.notes.0"]
    forged_page = row_value(page, &Map.put(&1, "rows", []))
    records = Map.put(seed["records"], "catalog.notes.0", forged_page)

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate_projection_source(read(records), target)
  end

  test "group source authentication binds its exact catalog slice and stored source times", %{
    seed: seed
  } do
    claim = seed["records"][seed["guard"]["claim_key"]]["value"]
    binding = hd(claim["source_bindings"])
    head = seed["records"]["source.notes." <> binding["source_key"]]["value"]

    summary =
      head
      |> Map.take(~w(source_key ordinal text_bytes chunks bundle_sha256))
      |> Map.put("head_sha256", binding["head_sha256"])

    group = %{
      "partition" => "notes",
      "catalog_sha256" => claim["catalog_sha256"],
      "cursor" => 0,
      "sources" => [summary]
    }

    assert {:ok, facts} =
             DocumentSourceUse.authenticate_group_sources(read(seed["records"]), group)

    assert facts.reads == 4 and DocumentSourceUse.current?(facts, binding["observed_at_ms"])

    assert {:ok, catalog_proof} =
             DocumentSourceUse.authenticate_catalog_group(
               read(seed["records"]),
               "notes",
               claim["catalog_sha256"],
               0
             )

    assert catalog_proof.sources === facts.sources
    assert catalog_proof.reads == 7
    assert catalog_proof.catalog_rows === [Map.take(summary, ~w(source_key head_sha256))]

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate_catalog_group(
               read(seed["records"]),
               "notes",
               String.duplicate("0", 64),
               0
             )

    for bad <- [
          put_in(group, ["sources", Access.at(0), "head_sha256"], String.duplicate("0", 64)),
          put_in(group, ["sources", Access.at(0), "bundle_sha256"], String.duplicate("0", 64)),
          put_in(group, ["sources", Access.at(0), "ordinal"], 1),
          Map.put(group, "sources", []),
          Map.put(group, "cursor", 8),
          Map.put(group, "extra", true)
        ] do
      assert {:error, :document_source_use_refused} =
               DocumentSourceUse.authenticate_group_sources(read(seed["records"]), bad)
    end
  end

  @tag timeout: 120_000
  test "all 125 manifest groups authenticate 1000 current synthetic sources within each read budget" do
    {records, proof} = maximum_selection_fixture()
    reader = read(records)
    counter = make_ref()
    widths = make_ref()
    Process.put(counter, 0)
    Process.put(widths, [])

    acquire = fn callback ->
      Process.put(counter, Process.get(counter) + 1)
      read_count = make_ref()
      Process.put(read_count, 0)

      counted = fn key ->
        Process.put(read_count, Process.get(read_count) + 1)
        reader.(key)
      end

      value = callback.(%{"root" => %{"generation" => proof.generation}}, counted)
      Process.put(widths, [Process.delete(read_count) | Process.get(widths)])
      value
    end

    started = System.monotonic_time(:millisecond)
    assert {:ok, result} = DocumentSourceUse.authenticate_selection_sources_with(proof, acquire)
    elapsed = System.monotonic_time(:millisecond) - started
    assert result.sources == 1000 and result.groups == 125
    widths_used = Process.delete(widths)
    assert length(widths_used) == 125 and Enum.max(widths_used) <= 512
    assert Enum.sum(widths_used) == result.reads and Process.get(counter) == 125
    assert result.publish_before_ms == proof.publish_before_ms

    Process.put(counter, 0)

    changed = fn callback ->
      n = Process.get(counter)
      Process.put(counter, n + 1)
      generation = if n == 62, do: proof.generation + 1, else: proof.generation
      callback.(%{"root" => %{"generation" => generation}}, reader)
    end

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate_selection_sources_with(proof, changed)

    assert Process.delete(counter) == 63

    {future_records, future_proof} =
      maximum_selection_fixture(System.system_time(:millisecond) + 600_000)

    future_reader = read(future_records)
    Process.put(counter, 0)

    future = fn callback ->
      Process.put(counter, Process.get(counter) + 1)
      callback.(%{"root" => %{"generation" => future_proof.generation}}, future_reader)
    end

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate_selection_sources_with(future_proof, future)

    assert Process.delete(counter) == 125

    IO.puts(
      "SELECTION_SOURCE_MODEL " <>
        Jason.encode!(%{
          sources: 1000,
          groups: 125,
          reads: result.reads,
          maximum_group_reads: Enum.max(widths_used),
          bundle_bytes: result.bundle_bytes,
          elapsed_ms: elapsed,
          native_operations: 0
        })
    )
  end

  @doc false
  def maximum_selection_fixture(late_observed_at \\ 1, text \\ "Synthetic source.") do
    encode = fn value -> IO.iodata_to_binary(JSON.encode!(value)) end

    row = fn value ->
      %{"value" => value, "revision" => 1, "operation_id" => String.duplicate("a", 32)}
    end

    vector = %{"fixture" => "vector"}
    fact = %{"kind" => "explicit", "profile" => nil, "version" => 1}
    ids = Enum.map(1..1000, &"fixture:maximum-selection:#{&1}") |> Enum.sort_by(&J.sha256/1)

    {records, rows} =
      Enum.with_index(ids)
      |> Enum.reduce({%{}, []}, fn {id, ordinal}, {records, rows} ->
        {:ok, source} =
          IpseKnowledge.Evidence.collection_source(%{
            "source_id" => id,
            "partition" => "notes",
            "generation" => 1,
            "title" => "Synthetic",
            "text" => text,
            "uri" => "provided:synthetic",
            "observed_at_ms" => if(ordinal == 999, do: late_observed_at, else: 1),
            "event_at_ms" => nil,
            "expires_at_ms" => nil,
            "origin" => %{
              "kind" => "provided",
              "store_profile" => "local",
              "partition_or_scope" => "notes",
              "receipt" => nil,
              "historical" => false
            }
          })

        bytes = encode.(source)
        block = %{"version" => 1, "kind" => "source_data", "pieces" => source_pieces(bytes)}
        block_hash = J.sha256(encode.(block))

        head = %{
          "version" => 1,
          "kind" => "source_head",
          "source_key" => source["source_key"],
          "generation" => 1,
          "revision" => 1,
          "ordinal" => ordinal,
          "text_bytes" => byte_size(source["text"]),
          "chunks" => div(byte_size(text) + 2047, 2048),
          "byte_count" => byte_size(bytes),
          "bundle_sha256" => J.sha256(bytes),
          "blocks" => [%{"key" => "data.notes." <> block_hash, "sha256" => block_hash}]
        }

        head_hash = J.sha256(encode.(head))

        records =
          records
          |> Map.put("data.notes." <> block_hash, row.(block))
          |> Map.put("source.notes." <> source["source_key"], row.(head))

        {records, [%{"source_key" => source["source_key"], "head_sha256" => head_hash} | rows]}
      end)

    rows = Enum.reverse(rows)

    {records, refs} =
      rows
      |> Enum.chunk_every(16)
      |> Enum.with_index()
      |> Enum.reduce({records, []}, fn {page_rows, ordinal}, {records, refs} ->
        page = %{
          "version" => 1,
          "kind" => "catalog_page",
          "partition" => "notes",
          "ordinal" => ordinal,
          "rows" => page_rows
        }

        key = "catalog.notes.#{ordinal}"

        {Map.put(records, key, row.(page)),
         refs ++ [%{"key" => key, "sha256" => J.sha256(encode.(page))}]}
      end)

    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => "notes",
      "generation" => 1000,
      "floor" => 0,
      "sources" => 1000,
      "extracted_bytes" => byte_size(text) * 1000,
      "chunks" => div(byte_size(text) + 2047, 2048) * 1000,
      "entities" => 0,
      "assertions" => 0,
      "pages" => refs
    }

    catalog_hash = J.sha256(encode.(catalog))
    records = Map.put(records, "catalog.notes", row.(catalog))

    {records, entries} =
      rows
      |> Enum.chunk_every(8)
      |> Enum.with_index()
      |> Enum.reduce({records, []}, fn {group, ordinal}, {records, entries} ->
        header = %{
          "kind" => "shared_projection_group",
          "cursor" => ordinal * 8,
          "sources" => length(group),
          "vector_selection" => vector,
          "fact_selection" => fact
        }

        bytes = encode.(header)
        sha = J.sha256(bytes)

        ref = %{
          "key" => "gengrp.notes." <> sha,
          "sha256" => sha,
          "byte_count" => byte_size(bytes)
        }

        entry = %{
          "cursor" => ordinal * 8,
          "sources" => Enum.map(group, &[&1["source_key"], &1["head_sha256"]]),
          "header" => ref
        }

        {Map.put(records, ref["key"], row.(header)), entries ++ [entry]}
      end)

    {records, manifests} =
      entries
      |> Enum.chunk_every(16)
      |> Enum.with_index()
      |> Enum.reduce({records, []}, fn {entries, ordinal}, {records, refs} ->
        page = %{
          "version" => 1,
          "kind" => "generation_manifest",
          "recipe" => "ipse.evidence.shared_directory.v1",
          "ordinal" => ordinal,
          "rows" => entries
        }

        bytes = encode.(page)
        sha = J.sha256(bytes)

        ref = %{
          "key" => "genman.notes." <> sha,
          "sha256" => sha,
          "byte_count" => byte_size(bytes)
        }

        {Map.put(records, ref["key"], row.(page)), refs ++ [ref]}
      end)

    proof = %{
      generation: 55,
      partition: "notes",
      catalog_sha256: catalog_hash,
      source_count: 1000,
      manifests: manifests,
      source_heads_sha256: J.sha256(encode.(%{"rows" => rows})),
      vector_selection: vector,
      fact_selection: fact,
      publish_before_ms: System.system_time(:millisecond) + 600_000
    }

    {records, proof}
  end

  defp source_pieces(""), do: []

  defp source_pieces(bytes) do
    size = utf8_size(bytes, min(4096, byte_size(bytes)))

    [
      binary_part(bytes, 0, size)
      | source_pieces(binary_part(bytes, size, byte_size(bytes) - size))
    ]
  end

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

  test "a self-consistent truncated chunk cannot replace the canonical source range", %{
    seed: seed
  } do
    claim = seed["records"][seed["guard"]["claim_key"]]["value"]
    [si, ci, _chunk, _canonical, _raw, start, finish] = hd(claim["inputs"])
    key = Enum.at(claim["source_bindings"], si)["source_key"]
    head = seed["records"]["source.notes." <> key]["value"]

    bytes =
      Enum.flat_map(head["blocks"], fn ref -> seed["records"][ref["key"]]["value"]["pieces"] end)
      |> IO.iodata_to_binary()

    {:ok, source} = J.decode_unique(bytes)
    shortened = binary_part(hd(seed["inputs"]), 0, finish - start - 1)
    version = if source["version"] === 3, do: 2, else: 1

    chunk =
      IpseKnowledge.Evidence.id("chunk", [
        key,
        source["generation"],
        source["content_sha256"],
        version,
        start,
        finish - 1
      ])

    replacement = [si, ci, chunk, J.digest([shortened]), J.sha256(shortened), start, finish - 1]

    candidate =
      change_claim(seed, &update_in(&1, ["inputs", Access.at(0)], fn _ -> replacement end))
      |> put_in(["inputs", Access.at(0)], shortened)

    assert {:error, :document_source_use_refused} = authenticate(candidate)
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
    test "authenticates actual producer #{kind} ranges with canonical source boundaries" do
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
  alias Ipse.Extension.Collection.{DocumentSourceUse, DocumentStage, Profile}

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

  @tag :native_sandbox
  @tag :source_selection_capacity_native
  @tag timeout: 600_000
  test "native selection source reads cover 1000 small synthetic sources" do
    native_selection_capacity("Synthetic source.")
  end

  @tag :native_sandbox
  @tag :source_selection_fulltext_native
  @tag timeout: 600_000
  test "native selection source reads cover 1000 synthetic sources with 20,480,000 text bytes" do
    native_selection_capacity(String.duplicate("x", 20_480))
  end

  @tag :native_sandbox
  @tag :source_selection_switch_native
  @tag timeout: 600_000
  test "staged native selection fences a changed generation at 1000-source scale" do
    native_selection_capacity(String.duplicate("x", 20_480), true)
  end

  @tag :native_sandbox
  @tag :source_selection_rebuild_native
  @tag timeout: 600_000
  test "staged native selection preserves a populated previous root on a generation race" do
    native_selection_capacity(String.duplicate("x", 20_480), :existing_root)
  end

  defp native_selection_capacity(text, switch? \\ false) do
    {records, proof} =
      Ipse.Extension.CollectionDocumentSourceUseTest.maximum_selection_fixture(1, text)

    parent = Path.join(System.tmp_dir!(), "ipse-selection-capacity-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "collections")
    namespace = JSON.sha256("synthetic selection capacity")
    if switch?, do: Process.put({__MODULE__, :capacity}, %{})

    batches =
      records
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.chunk_every(if(byte_size(text) > 1000, do: 16, else: 64))

    started = System.monotonic_time(:millisecond)

    generation =
      Enum.reduce(batches, 0, fn batch, generation ->
        changes =
          Enum.map(batch, fn {key, record} ->
            %{"key" => key, "expected_revision" => 0, "value" => packed(record["value"])}
          end)

        assert {:ok, %{"generation" => next}} =
                 Collection.execute_profile(
                   root,
                   namespace,
                   %{
                     "op" => "commit",
                     "expected_generation" => generation,
                     "advance_floor" => false,
                     "changes" => changes
                   },
                   Usage.id(),
                   Profile.documents()
                 )

        assert next == generation + 1
        if switch?, do: observe_capacity(root, namespace)
        next
      end)

    seeded_ms = System.monotonic_time(:millisecond) - started

    proof = %{
      proof
      | generation: generation,
        publish_before_ms: System.system_time(:millisecond) + 600_000
    }

    started = System.monotonic_time(:millisecond)

    assert {:ok, result} =
             DocumentSourceUse.authenticate_selection_sources(root, namespace, proof)

    read_ms = System.monotonic_time(:millisecond) - started
    assert result.sources == 1000 and result.groups == 125 and result.reads == 3750
    assert result.bundle_bytes > byte_size(text) * 1000

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate_selection_sources(root, namespace, %{
               proof
               | generation: generation + 1
             })

    switch =
      if switch?, do: native_selection_switch(root, namespace, records, proof, switch?), else: nil

    observed = if switch?, do: Process.delete({__MODULE__, :capacity}), else: nil

    IO.puts(
      "NATIVE_SELECTION_CAPACITY " <>
        Jason.encode!(%{
          sources: result.sources,
          groups: result.groups,
          text_bytes: byte_size(text) * 1000,
          records: map_size(records),
          seed_commits: length(batches),
          reads: result.reads,
          bundle_bytes: result.bundle_bytes,
          seed_ms: seeded_ms,
          read_ms: read_ms,
          staged_switch: switch,
          observed_settled_maxima: observed
        })
    )
  end

  defp native_selection_switch(root, namespace, records, proof, switch_mode) do
    catalog = records["catalog.notes"]["value"]
    entity_hash = JSON.sha256("synthetic empty entities")

    reduction = %{
      "phase" => "select",
      "manifests" => proof.manifests,
      "entity_pages" => [],
      "heads_sha256" => proof.source_heads_sha256,
      "entity_pages_sha256" => entity_hash,
      "facts" => 0,
      "entities" => 0
    }

    old_job = %{
      "version" => 3,
      "kind" => "shared_generation_job",
      "id" => Usage.id(),
      "partition" => "notes",
      "status" => "reducing",
      "catalog" => catalog,
      "catalog_sha256" => proof.catalog_sha256,
      "generation" => 1,
      "root_revision" => 0,
      "root_sha256" => nil,
      "cursor" => 1000,
      "summaries" => [],
      "facts" => 0,
      "vector_selection" => proof.vector_selection,
      "fact_selection" => proof.fact_selection,
      "reduction" => reduction
    }

    root_value = %{
      "version" => 2,
      "kind" => "shared_generation_directory",
      "recipe" => "ipse.evidence.shared_directory.v2",
      "partition" => "notes",
      "generation" => 1,
      "catalog_sha256" => proof.catalog_sha256,
      "catalog_generation" => catalog["generation"],
      "floor" => catalog["floor"],
      "sources" => 1000,
      "extracted_bytes" => catalog["extracted_bytes"],
      "chunks" => catalog["chunks"],
      "vectors" => catalog["chunks"],
      "facts" => 0,
      "entities" => 0,
      "groups" => 125,
      "vector_selection" => proof.vector_selection,
      "fact_selection" => proof.fact_selection,
      "source_heads_sha256" => proof.source_heads_sha256,
      "entity_pages_sha256" => entity_hash,
      "entity_page_rows" => 32,
      "manifests" => proof.manifests,
      "entity_pages" => []
    }

    previous_root = if switch_mode == :existing_root, do: root_value, else: nil
    root_value = if previous_root, do: Map.put(root_value, "generation", 2), else: root_value

    old_job =
      if previous_root do
        old_job
        |> Map.put("generation", 2)
        |> Map.put("root_revision", proof.generation + 1)
        |> Map.put(
          "root_sha256",
          JSON.sha256(IO.iodata_to_binary(Elixir.JSON.encode!(previous_root)))
        )
      else
        old_job
      end

    selected_job =
      old_job |> Map.put("status", "selected") |> put_in(["reduction", "phase"], "selected")

    old_root_changes =
      if previous_root do
        [
          %{
            "key" => "generation.notes",
            "expected_revision" => 0,
            "value" => packed(previous_root)
          }
        ]
      else
        []
      end

    assert {:ok, %{"generation" => generation}} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => proof.generation,
                 "advance_floor" => false,
                 "changes" =>
                   old_root_changes ++
                     [
                       %{
                         "key" => "genjob.notes",
                         "expected_revision" => 0,
                         "value" => packed(old_job)
                       }
                     ]
               },
               Usage.id(),
               Profile.documents()
             )

    observe_capacity(root, namespace)
    previous_revision = generation

    assert {:ok, catalog_row} =
             Collection.with_document_read(root, namespace, fn _, read ->
               DocumentStage.read_value(read, "catalog.notes")
             end)

    owner = %{
      "project_id" => JSON.sha256("synthetic project"),
      "identity_sha256" => JSON.sha256("synthetic identity"),
      "session_id" => Usage.id(),
      "invocation_id" => Usage.id()
    }

    units = [
      {"genjob.notes", selected_job, generation},
      {"catalog.notes", catalog, catalog_row["revision"]},
      {"generation.notes", root_value, if(previous_root, do: previous_revision, else: 0)}
    ]

    {generation, refs} =
      Enum.with_index(units)
      |> Enum.reduce({generation, []}, fn {{key, value, revision}, slot}, {gen, refs} ->
        ref = %{"slot" => slot, "epoch" => Usage.id()}

        {next, _} =
          packed(value)["parts"]
          |> Enum.chunk_every(2)
          |> Enum.reduce({gen, 0}, fn pieces, {current, offset} ->
            bytes = IO.iodata_to_binary(Elixir.JSON.encode!(value))

            request =
              Map.merge(ref, %{
                "op" => "value.write_parts",
                "key" => key,
                "expected_revision" => revision,
                "byte_count" => byte_size(bytes),
                "sha256" => JSON.sha256(bytes),
                "offset" => offset,
                "data" => pieces,
                "publish" => false,
                "generation" => current
              })

            assert {:ok, receipt} =
                     DocumentStage.execute(root, namespace, request, Usage.id(), owner)

            observe_capacity(root, namespace)

            {receipt["generation"], offset + Enum.sum(Enum.map(pieces, &byte_size/1))}
          end)

        {next, refs ++ [ref]}
      end)

    request = %{"op" => "commit", "stages" => refs, "generation" => generation}
    started = System.monotonic_time(:millisecond)
    captured = selection_capture(root, namespace, request, owner)

    assert {:ok, sources} =
             DocumentSourceUse.authenticate_selection_sources(root, namespace, captured)

    assert sources.sources == 1000 and sources.groups == 125

    assert {:ok, %{"generation" => changed}} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => generation,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "fixture.race",
                     "expected_revision" => 0,
                     "value" => %{"version" => 1}
                   }
                 ]
               },
               Usage.id(),
               Profile.documents()
             )

    observe_capacity(root, namespace)

    assert {:error, :document_store_refused} =
             DocumentStage.execute(root, namespace, request, Usage.id(), owner,
               publish_before_ms: sources.publish_before_ms
             )

    assert {:ok, prior_row} =
             Collection.with_document_read(root, namespace, fn _, read ->
               DocumentStage.read_value(read, "generation.notes")
             end)

    if previous_root do
      assert prior_row["value"] == previous_root
      assert prior_row["revision"] == previous_revision
    else
      assert prior_row == nil
    end

    request = Map.put(request, "generation", changed)
    captured = selection_capture(root, namespace, request, owner)

    assert {:ok, sources} =
             DocumentSourceUse.authenticate_selection_sources(root, namespace, captured)

    assert {:ok, %{"generation" => final}} =
             DocumentStage.execute(root, namespace, request, Usage.id(), owner,
               publish_before_ms: sources.publish_before_ms
             )

    assert final == changed + 1
    final_status = observe_capacity(root, namespace)
    assert final_status["records"] == map_size(records) + 3

    assert {:ok, %{"stages" => []}} =
             DocumentStage.execute(root, namespace, %{"op" => "stage.list"}, Usage.id(), owner)

    assert {:ok, %{"value" => ^root_value}} =
             Collection.with_document_read(root, namespace, fn _, read ->
               DocumentStage.read_value(read, "generation.notes")
             end)

    %{
      elapsed_ms: System.monotonic_time(:millisecond) - started,
      previous_root: not is_nil(previous_root),
      retained: final_status,
      remaining_stages: 0
    }
  end

  defp selection_capture(root, namespace, request, owner) do
    assert {:ok, proof} =
             Collection.with_document_read(root, namespace, fn witness, read ->
               DocumentSourceUse.authenticate_selection_commit(
                 read,
                 witness,
                 request,
                 owner,
                 System.system_time(:millisecond)
               )
             end)

    proof
  end

  defp observe_capacity(root, namespace) do
    assert {:ok, status} =
             Collection.execute_profile(
               root,
               namespace,
               %{"op" => "status"},
               Usage.id(),
               Profile.documents()
             )

    fields =
      ~w(records operations data_bytes disk_bytes allocated_bytes accounted_allocated_bytes)

    sample = Map.take(status, fields)
    assert Enum.all?(fields, &(is_integer(sample[&1]) and sample[&1] >= 0))
    previous = Process.get({__MODULE__, :capacity}, %{})

    Process.put(
      {__MODULE__, :capacity},
      Map.merge(previous, sample, fn _, left, right -> max(left, right) end)
    )

    sample
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

    binding = hd(claim["source_bindings"])

    projection_target = %{
      "partition" => claim["partition"],
      "source_key" => binding["source_key"],
      "catalog_sha256" => claim["catalog_sha256"],
      "head_revision" => binding["head_revision"],
      "head_sha256" => binding["head_sha256"],
      "source_bundle_sha256" => binding["bundle_sha256"]
    }

    source_head = seed["records"]["source.notes." <> binding["source_key"]]["value"]

    group_source =
      source_head
      |> Map.take(~w(source_key ordinal text_bytes chunks bundle_sha256))
      |> Map.put("head_sha256", binding["head_sha256"])

    group = %{
      "partition" => "notes",
      "catalog_sha256" => claim["catalog_sha256"],
      "cursor" => 0,
      "sources" => [group_source]
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

               assert {:ok, projection_facts} =
                        DocumentSourceUse.authenticate_projection_source(read, projection_target)

               assert projection_facts.reads === 4

               assert DocumentSourceUse.current?(
                        projection_facts,
                        System.system_time(:millisecond)
                      )

               assert {:ok, group_facts} =
                        DocumentSourceUse.authenticate_group_sources(read, group)

               assert group_facts.reads === 4 and
                        DocumentSourceUse.current?(group_facts, System.system_time(:millisecond))

               {:ok, read}
             end)

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate(read, guard, seed["inputs"], seed["selection"])

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate_projection_source(read, projection_target)

    assert {:error, :document_source_use_refused} =
             DocumentSourceUse.authenticate_group_sources(read, group)

    [si, ci, _, _, _, start, finish] = hd(claim["inputs"])
    source_key = Enum.at(claim["source_bindings"], si)["source_key"]
    head = seed["records"]["source.notes." <> source_key]["value"]

    bytes =
      Enum.flat_map(head["blocks"], fn ref ->
        seed["records"][ref["key"]]["value"]["pieces"]
      end)
      |> IO.iodata_to_binary()

    {:ok, source} = JSON.decode_unique(bytes)
    shortened = binary_part(hd(seed["inputs"]), 0, finish - start - 1)
    version = if source["version"] === 3, do: 2, else: 1

    chunk =
      IpseKnowledge.Evidence.id("chunk", [
        source_key,
        source["generation"],
        source["content_sha256"],
        version,
        start,
        finish - 1
      ])

    replacement = [
      si,
      ci,
      chunk,
      JSON.digest([shortened]),
      JSON.sha256(shortened),
      start,
      finish - 1
    ]

    forged = put_in(claim, ["inputs", Access.at(0)], replacement)
    forged_inputs = put_in(seed["inputs"], [Access.at(0)], shortened)
    operation = Usage.id()

    assert {:ok, %{"generation" => 3}} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 2,
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => claim_key, "expected_revision" => 2, "value" => packed(forged)}
                 ]
               },
               operation,
               Profile.documents()
             )

    forged_guard = %{
      guard
      | "claim_revision" => 3,
        "claim_sha256" => JSON.sha256(IO.iodata_to_binary(Elixir.JSON.encode!(forged)))
    }

    assert {:ok, :refused} =
             Collection.with_document_read(root, namespace, fn witness, current_read ->
               assert witness["root"]["generation"] === 3

               assert {:error, :document_source_use_refused} =
                        DocumentSourceUse.authenticate(
                          current_read,
                          forged_guard,
                          forged_inputs,
                          seed["selection"]
                        )

               {:ok, :refused}
             end)
  end
end
