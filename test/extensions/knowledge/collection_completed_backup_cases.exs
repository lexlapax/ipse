defmodule IpseKnowledge.CollectionCompletedBackupCases do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.{Directory, Generation, Index, Projection}
  @profile %{"kind" => "collection", "scope" => "project", "partition" => "docs"}
  @extraction %{"kind" => "explicit", "profile" => nil, "version" => 1}

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp hash(value), do: E.sha256(json(value))
  defp id, do: String.duplicate("a", 32)

  defp ref(key, value),
    do: %{"key" => key, "sha256" => hash(value), "byte_count" => byte_size(json(value))}

  defp envelope(key, value) do
    body = json(value)

    parts =
      Stream.unfold(body, fn
        "" ->
          nil

        bytes ->
          {part, rest} = E.utf8_prefix(bytes, 6144)
          {part, rest}
      end)
      |> Enum.to_list()

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => E.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => parts
    }

    {:ok, physical} = Ipse.Extension.ResultDocument.encode(packed, %{"type" => "object"})

    %{
      "key" => key,
      "revision" => 1,
      "operation_id" => id(),
      "sha256" => E.sha256(physical),
      "bytes" => byte_size(physical),
      "value" => packed
    }
  end

  defp source_plan(generation, receipt \\ nil, times \\ %{}) do
    attrs = %{
      "source_id" => "backup:one",
      "partition" => "docs",
      "generation" => generation,
      "title" => "Backup source",
      "text" => "Ada knows Bea. Café evidence.",
      "uri" => "provided:backup",
      "observed_at_ms" => Map.get(times, :observed, 10),
      "event_at_ms" => nil,
      "expires_at_ms" => Map.get(times, :expires),
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "documents",
        "partition_or_scope" => "docs",
        "receipt" => receipt,
        "historical" => false
      }
    }

    {:call, _, plan} =
      C.start(@profile, :put, %{
        "source" => attrs,
        "expected_revision" => 0,
        "continuation" => nil
      })

    plan
  end

  defp base(generation \\ 2, receipt \\ nil, times \\ %{}) do
    plan = source_plan(generation, receipt, times)
    {:ok, head} = C.planned_source_head(plan, 0)
    source = plan.source

    page = %{
      "version" => 1,
      "kind" => "catalog_page",
      "partition" => "docs",
      "ordinal" => 0,
      "rows" => [%{"source_key" => source["source_key"], "head_sha256" => hash(head)}]
    }

    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => "docs",
      "generation" => 1,
      "floor" => 0,
      "sources" => 1,
      "extracted_bytes" => byte_size(source["text"]),
      "chunks" => plan.chunks,
      "entities" => 0,
      "assertions" => 0,
      "pages" => [Map.take(ref("catalog.docs.0", page), ~w(key sha256))]
    }

    values =
      Map.new(plan.prepared, &{"data.docs." <> hash(&1), &1})
      |> Map.put("source.docs." <> source["source_key"], head)
      |> Map.put("catalog.docs.0", page)
      |> Map.put("catalog.docs", catalog)

    %{values: values, source: source, head: head, catalog: catalog, page: page}
  end

  defp records(values),
    do: values |> Enum.sort() |> Enum.map(fn {key, value} -> envelope(key, value) end)

  defp valid?(values), do: Projection.completed_backup?(@profile, records(values))

  def completed_source_fixture do
    c = base()
    %{profile: @profile, records: records(c.values), source: c.source, catalog: c.catalog}
  end

  def temporal_fixture(receipt \\ nil) do
    times = %{observed: Process.get(:observed, 10), expires: Process.get(:expires)}
    base(2, receipt, times) |> indexed()
  end

  defp indexed(c) do
    {:ok, run} = E.lexical_run(c.source)

    entry = %{
      "run" => run,
      "source_bundle_sha256" => hash(c.source),
      "source_revision" => c.head["revision"]
    }

    {:ok, plan} = Index.storage_plan(@profile, [c.source], [entry], 0)

    root = %{
      "version" => 1,
      "kind" => "lexical_index",
      "recipe" => E.lexical_recipe(),
      "job_id" => id(),
      "generation" => 1,
      "catalog_sha256" => hash(c.catalog),
      "catalog_generation" => 1,
      "floor" => 0,
      "sources" => 1,
      "chunks" => c.catalog["chunks"],
      "groups" => [plan.header]
    }

    job = %{
      "version" => 1,
      "kind" => "lexical_job",
      "id" => id(),
      "status" => "building",
      "catalog" => c.catalog,
      "catalog_sha256" => hash(c.catalog),
      "cursor" => 1,
      "unit" => 0,
      "groups" => [plan.header],
      "root_revision" => 0,
      "index_generation" => 1
    }

    values =
      Enum.reduce(plan.values, c.values, &Map.put(&2, &1.key, &1.value))
      |> Map.put("lexical.docs", root)
      |> Map.put("lexjob.docs", job)

    %{c | values: values}
  end

  defp projections(c, dimensions \\ 1) do
    selection = %{
      "selection_sha256" => E.sha256("selection"),
      "profile" => "fixture",
      "model" => "fixture",
      "dimensions" => dimensions,
      "encoding" => "float32le"
    }

    {:ok, [chunk]} = E.chunks(c.source)
    {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

    {:ok, vector} =
      E.vector(
        Map.merge(Map.delete(selection, "encoding"), %{
          "chunk_id" => chunk["chunk_id"],
          "input_sha256" => input,
          "values" => List.duplicate(1.0, dimensions)
        })
      )

    {:ok, facts} =
      Projection.facts_from_spans(c.source, [
        %{
          "subject" => "Ada",
          "predicate" => "knows",
          "object" => "Bea",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "spans" => [[0, 0, 13]]
        }
      ])

    {:ok, vector_pages} = Projection.pack(c.source, [vector], selection)
    {:ok, fact_pages} = Projection.pack_facts(c.source, facts, @extraction)

    make = fn kind, prefix, pages, selected, count ->
      refs = Enum.map(pages, &ref(prefix <> ".docs." <> hash(&1), &1))

      root = %{
        "version" => 1,
        "kind" => kind <> "_projection",
        "recipe" =>
          if(kind == "fact",
            do: "ipse.evidence.fact_spans.v1",
            else: "ipse.evidence.float32le.base64.v1"
          ),
        "revision" => 1,
        "source_key" => c.source["source_key"],
        "source_generation" => c.source["generation"],
        "content_sha256" => c.source["content_sha256"],
        "source_bundle_sha256" => hash(c.source),
        "selection" => selected,
        "catalog_sha256" => hash(c.catalog),
        "catalog_generation" => 1,
        "floor" => 0,
        "pages" => refs,
        if(kind == "fact", do: "facts", else: "vectors") => count
      }

      root =
        if kind == "fact",
          do: Map.put(root, "entities", Enum.map(["Ada", "Bea"], &E.id("entity", ["docs", &1]))),
          else: root

      {root, Enum.zip(refs, pages) |> Map.new(fn {r, p} -> {r["key"], p} end)}
    end

    {vector_root, vp} = make.("vector", "vecp", vector_pages, selection, 1)
    {fact_root, fp} = make.("fact", "factp", fact_pages, @extraction, 1)

    values =
      c.values
      |> Map.merge(vp)
      |> Map.merge(fp)
      |> Map.put("vector.docs." <> c.source["source_key"], vector_root)
      |> Map.put("facts.docs." <> c.source["source_key"], fact_root)

    Map.merge(c, %{values: values, vectors: [vector], facts: facts, selection: selection})
  end

  defp shared(c) do
    bundles = [%{"source" => c.source, "head" => c.head}]

    supplied = [
      %{
        "source_key" => c.source["source_key"],
        "source_bundle_sha256" => hash(c.source),
        "vectors" => c.vectors,
        "facts" => c.facts
      }
    ]

    {:ok, group} = Generation.pack_group("docs", 0, bundles, supplied, c.selection, @extraction)

    {:ok, summary} =
      Directory.capture("docs", group, bundles, %{
        "cursor" => 0,
        "vector_selection" => c.selection,
        "fact_selection" => @extraction
      })

    {:ok, directory} = Directory.pack(@profile, c.catalog, [c.page], [summary], 1)

    values =
      Enum.reduce(
        group.values ++ [group.header_unit] ++ directory.values,
        c.values,
        &Map.put(&2, &1.key, &1.value)
      )
      |> Map.put("generation.docs", directory.root)

    job = %{
      "version" => 1,
      "kind" => "shared_generation_job",
      "id" => id(),
      "partition" => "docs",
      "status" => "selected",
      "catalog" => c.catalog,
      "catalog_sha256" => hash(c.catalog),
      "generation" => 1,
      "root_revision" => 0,
      "root_sha256" => nil,
      "vector_selection" => c.selection,
      "fact_selection" => @extraction,
      "cursor" => 1,
      "summaries" => [summary["ref"]],
      "facts" => 1
    }

    c |> Map.put(:values, Map.put(values, "genjob.docs", job)) |> Map.put(:summary, summary)
  end

  test "complete actual Source plans, lexical jobs, vectors and cited facts join without rewriting parts" do
    c = base() |> indexed() |> projections()
    rows = records(c.values)
    before = :erlang.term_to_binary(rows)
    assert Projection.completed_backup?(@profile, rows)
    assert :erlang.term_to_binary(rows) === before
    assert length(rows) <= 32
  end

  test "physical and logical envelopes, namespace and complete membership fail closed" do
    c = base()
    rows = records(c.values)
    assert Projection.completed_backup?(@profile, rows)
    [first | rest] = rows

    for changed <- [
          Map.put(first, "extra", true),
          Map.put(first, "sha256", E.sha256("wrong")),
          put_in(first, ["value", "parts"], ["{}"]),
          Map.put(first, "revision", 1.0)
        ] do
      refute Projection.completed_backup?(@profile, [changed | rest])
    end

    refute Projection.completed_backup?(%{@profile | "partition" => "other"}, rows)
    refute Projection.completed_backup?(@profile, tl(rows))
    refute Projection.completed_backup?(@profile, rows ++ rows)
    refute valid?(Map.put(c.values, "unknown", %{"version" => 1, "kind" => "unknown"}))
    refute valid?(Map.put(c.values, "host.stage.0", %{"version" => 1, "kind" => "catalog"}))
  end

  test "a selected lexical job must be complete and canonical postings must match actual source bytes" do
    c = base() |> indexed()
    assert valid?(c.values)
    refute valid?(put_in(c.values, ["lexjob.docs", "unit"], 1))
    refute valid?(put_in(c.values, ["lexical.docs", "job_id"], String.duplicate("b", 32)))
    [ref] = c.values["lexical.docs"]["groups"]
    header = c.values[ref["key"]]
    changed = put_in(header, ["sources", Access.at(0), Access.at(1)], "forged:source")
    new_ref = ref("lexr.docs." <> hash(changed), changed)

    bad =
      c.values
      |> Map.delete(ref["key"])
      |> Map.put(new_ref["key"], changed)
      |> put_in(["lexical.docs", "groups"], [new_ref])
      |> put_in(["lexjob.docs", "groups"], [new_ref])

    refute valid?(bad)
  end

  test "a lexical selection must retain the actual Source lexical manifest used by query hydration" do
    c = base() |> indexed()
    head = c.head |> Map.delete("lexical") |> Map.put("version", 1)
    page = put_in(c.page, ["rows", Access.at(0), "head_sha256"], hash(head))
    catalog = put_in(c.catalog, ["pages", Access.at(0), "sha256"], hash(page))

    values =
      c.values
      |> Map.put("source.docs." <> c.source["source_key"], head)
      |> Map.put("catalog.docs.0", page)
      |> Map.put("catalog.docs", catalog)
      |> put_in(["lexical.docs", "catalog_sha256"], hash(catalog))
      |> put_in(["lexjob.docs", "catalog_sha256"], hash(catalog))
      |> put_in(["lexjob.docs", "catalog"], catalog)

    refute valid?(values)
  end

  defp index_walk({:call, request, continuation}, values, epoch, reads) do
    if C.read_request?(request) do
      r = request["request"]

      result =
        case r["op"] do
          "stage.list" ->
            %{"generation" => 20, "stages" => []}

          "stage.available" ->
            %{"generation" => 20, "stages" => [], "available_slots" => Enum.to_list(0..15)}

          "snapshot" ->
            %{
              "generation" => 20,
              "floor" => 0,
              "document_store" =>
                if(epoch === 0,
                  do: %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2},
                  else: %{
                    "version" => 4,
                    "inline_bytes" => 8192,
                    "write_parts" => 2,
                    "maintenance_epoch" => epoch,
                    "maintenance_status" => "idle",
                    "progress" => 1
                  }
                )
            }

          "value.stat" ->
            value = Map.fetch!(values, r["key"])

            %{
              "generation" => 20,
              "key" => r["key"],
              "record" => %{
                "revision" => 10,
                "sha256" => hash(value),
                "byte_count" => byte_size(json(value))
              }
            }

          "value.read" ->
            bytes = json(Map.fetch!(values, r["key"]))
            offset = r["offset"]
            count = min(6144, byte_size(bytes) - offset)

            %{
              "generation" => 20,
              "key" => r["key"],
              "revision" => 10,
              "offset" => offset,
              "sha256" => E.sha256(bytes),
              "byte_count" => byte_size(bytes),
              "data" => binary_part(bytes, offset, count),
              "next" => if(offset + count < byte_size(bytes), do: offset + count)
            }
        end

      {:ok, digest} = Ipse.Extension.canonical_digest([request])

      outcome = %{
        "status" => "ok",
        "value" => %{
          "version" => 1,
          "operation_id" => id(),
          "request_sha256" => digest,
          "result" => result
        }
      }

      index_walk(Index.resume(continuation, outcome), values, epoch, reads + 1)
    else
      {:effect, request}
    end
  end

  defp index_walk(result, _, _, reads), do: {result, reads}

  test "a completed Index cannot resume or abort through recomputed rebased native stamps" do
    c = base() |> indexed()

    for epoch <- [0, 1], action <- ~w(next abort) do
      job = c.values["lexjob.docs"] |> Map.put("root_revision", 10)

      job =
        if epoch === 0,
          do: job,
          else: Map.merge(job, %{"version" => 2, "maintenance_epoch" => epoch})

      values = Map.put(c.values, "lexjob.docs", job)
      assert Index.completed_job?(job, values["lexical.docs"], @profile)

      token = %{
        "version" => 2,
        "job_id" => id(),
        "job_revision" => 10,
        "work" => "job",
        "write" => nil,
        "stages" => %{},
        "unit" => 0
      }

      token =
        if epoch === 0,
          do: token,
          else: Map.merge(token, %{"version" => 3, "maintenance_epoch" => epoch})

      # The imported native root/job stamps deliberately equal the old stored
      # root_revision; token editing alone must still return no next effect.
      result =
        Index.start(@profile, :lexical_build, %{"action" => action, "continuation" => token})

      assert {{:done, {:error, :lexical_continuation_conflict, _}}, reads} =
               index_walk(result, values, epoch, 0)

      assert reads > 0
    end
  end

  test "Source history is retained but missing old blocks or altered source totals refuse" do
    c = base()
    old = source_plan(1)
    history = Enum.reduce(old.prepared, c.values, &Map.put(&2, "data.docs." <> hash(&1), &1))
    assert valid?(history)
    refute valid?(put_in(history, ["catalog.docs", "chunks"], 2))
    refute valid?(Map.delete(history, "data.docs." <> hash(hd(old.prepared))))
  end

  test "source-bound projection pages require the exact complete pages and citation reconstruction" do
    c = base() |> projections()
    assert valid?(c.values)
    key = "facts.docs." <> c.source["source_key"]
    [page_ref] = c.values[key]["pages"]
    refute valid?(Map.delete(c.values, page_ref["key"]))
    refute valid?(put_in(c.values, [key, "source_generation"], 99))
    refute valid?(put_in(c.values, [key, "entities"], [E.sha256("forged")]))
  end

  test "a historical projection cannot acquire a current catalog binding by changing catalog metadata" do
    current = base()
    old = base(1) |> projections()
    # Keep the old immutable bodies as genuine history, while publishing the
    # newer Source head/catalog. Only projection catalog fields are relabeled.
    values = Map.merge(old.values, current.values)

    values =
      Enum.reduce(~w(vector facts), values, fn prefix, values ->
        key = prefix <> ".docs." <> current.source["source_key"]
        Map.update!(values, key, &Map.put(&1, "catalog_sha256", hash(current.catalog)))
      end)

    refute valid?(values)

    assert valid?(
             Map.merge(
               current.values,
               Map.take(
                 old.values,
                 Enum.filter(Map.keys(old.values), &String.starts_with?(&1, "data."))
               )
             )
           )
  end

  test "selected shared generations reconstruct Source heads, vectors, facts and entity pages" do
    c = base() |> projections() |> shared()
    assert valid?(c.values)
    refute valid?(put_in(c.values, ["genjob.docs", "status"], "groups"))
    refute valid?(put_in(c.values, ["generation.docs", "facts"], 0))
    [manifest] = c.values["generation.docs"]["manifests"]
    refute valid?(Map.delete(c.values, manifest["key"]))

    refute valid?(
             Map.delete(c.values, "genjob.docs")
             |> Map.put("genproducer.docs", %{
               "kind" => "shared_projection_producer",
               "status" => "pending"
             })
           )
  end

  test "actual paged finalization fragments and selected Job3 retain complete semantic joins" do
    alias IpseKnowledge.Store.Collection.Paged
    c = base() |> projections() |> shared()

    {:ok, batch} =
      Paged.batch(@profile, c.catalog, [c.summary], %{0 => c.page}, 0, c.selection, @extraction)

    source_values = Map.new(batch.values, &{&1.key, &1.value})
    {:ok, merge} = Paged.merge("docs", [Directory.reference(batch.run)], [0], source_values, 0, 1)
    assert merge.complete
    entities = merge.unit
    entity_refs = [Directory.reference(entities)]
    heads = c.values["generation.docs"]["source_heads_sha256"]

    {:ok, root} =
      Paged.root(
        @profile,
        c.catalog,
        1,
        c.selection,
        @extraction,
        %{manifests: [Directory.reference(batch.manifest)], entities: entity_refs},
        %{facts: 1, entities: 2},
        %{heads: heads, entities: Paged.commitment(entity_refs, 2, 1)}
      )

    reduction = %{
      "phase" => "selected",
      "batch" => 1,
      "manifests" => root["manifests"],
      "runs" => [],
      "positions" => [],
      "entity_pages" => entity_refs,
      "entities" => 2,
      "text_bytes" => c.catalog["extracted_bytes"],
      "chunks" => 1,
      "facts" => 1,
      "heads_sha256" => heads,
      "recipe" => "ipse.evidence.shared_directory.v2",
      "entity_pages_sha256" => root["entity_pages_sha256"],
      "digest_cursor" => 1,
      "verified_entities" => 2,
      "last_entity_id" => entities.value["rows"] |> List.last() |> hd()
    }

    job =
      c.values["genjob.docs"]
      |> Map.put("version", 3)
      |> Map.put("summaries", [])
      |> Map.put("reduction", reduction)

    values =
      Enum.reduce(batch.values ++ [entities], c.values, &Map.put(&2, &1.key, &1.value))
      |> Map.put("generation.docs", root)
      |> Map.put("genjob.docs", job)

    assert length(records(values)) <= 32
    assert valid?(values)
    # The selected root no longer references completed reduction runs. Native
    # plan membership preserves their presence; semantic validation requires its
    # actual selected entity pages, not hypothetical unreferenced history.
    assert valid?(Map.delete(values, batch.run.key))
    refute valid?(Map.delete(values, entities.key))
    forged = Map.put(batch.run.value, "entities", 1)
    refute valid?(Map.put(values, batch.run.key, forged))
    refute valid?(put_in(values, ["genjob.docs", "reduction", "phase"], "entities"))
  end

  test "ready producer history joins terminal Job, exact chunk inputs and real vector page; pending refuses" do
    c = base() |> projections(1024) |> shared()
    {:ok, [chunk]} = E.chunks(c.source)
    {:ok, canonical} = Ipse.Extension.canonical_digest([chunk["text"]])

    inputs = [
      [0, 0, chunk["chunk_id"], canonical, E.sha256(chunk["text"]), 0, byte_size(chunk["text"])]
    ]

    [page] = c.summary["header"]["vector_pages"]

    record = %{
      "version" => 4,
      "kind" => "shared_projection_producer",
      "recipe" => "ipse.evidence.shared_producer.pages.v4",
      "partition" => "docs",
      "job_id" => id(),
      "job_revision" => 1,
      "catalog_sha256" => hash(c.catalog),
      "catalog_floor" => 0,
      "root_revision" => 0,
      "root_sha256" => nil,
      "cursor" => 0,
      "embedding" => "fixture",
      "vector_selection" => c.selection,
      "fact_selection" => @extraction,
      "source_set_sha256" => hash(%{"sources" => [[c.source["source_key"], hash(c.source)]]}),
      "vector_cursor" => 0,
      "vector_count" => 1,
      "previous_ready" => nil,
      "status" => "ready",
      "page" => page,
      "receipts" => [
        %{
          "operation_id" => id(),
          "source_sha256" => E.sha256("source"),
          "input_sha256" => [canonical],
          "raw_input_sha256" => [E.sha256(chunk["text"])]
        }
      ],
      "claim" => %{"revision" => 1, "sha256" => E.sha256("claim"), "operation_id" => id()},
      "input_count" => 1,
      "input_refs_sha256" => hash(inputs)
    }

    key = "genproducer4.docs.0"
    values = Map.put(c.values, key, record)
    assert valid?(values)
    refute valid?(put_in(values, [key, "status"], "pending"))
    refute valid?(put_in(values, [key, "input_refs_sha256"], E.sha256("forged")))

    refute valid?(
             put_in(values, [key, "receipts", Access.at(0), "raw_input_sha256"], [
               E.sha256("wrong")
             ])
           )

    refute valid?(Map.delete(values, page["key"]))
  end

  test "recognized stored Job and Index epochs cannot exceed the actual exported source epoch" do
    c = base() |> indexed() |> projections() |> shared()

    values =
      c.values
      |> Map.update!("genjob.docs", &Map.merge(&1, %{"version" => 4, "maintenance_epoch" => 1}))
      |> Map.update!("lexjob.docs", &Map.merge(&1, %{"version" => 2, "maintenance_epoch" => 1}))

    assert Projection.completed_backup?(@profile, records(values), 1)
    refute Projection.completed_backup?(@profile, records(values))
    refute Projection.completed_backup?(@profile, records(values), 0)

    for key <- ~w(genjob.docs lexjob.docs) do
      future = put_in(values, [key, "maintenance_epoch"], 2)
      refute Projection.completed_backup?(@profile, records(future), 1)
      malformed = put_in(values, [key, "maintenance_epoch"], 1.0)
      refute Projection.completed_backup?(@profile, records(malformed), 1)
    end

    for epoch <- [1.0, -1, nil, "1"] do
      refute Projection.completed_backup?(@profile, records(values), epoch)
    end
  end

  test "arbitrary Source receipt JSON is data and is neither recursively fenced nor rewritten" do
    receipt = %{
      "kind" => "provided_metadata",
      "maintenance_epoch" => 999,
      "nested" => %{"kind" => "shared_generation_job", "maintenance_epoch" => 1000}
    }

    c = base(2, receipt)
    rows = records(c.values)
    before = :erlang.term_to_binary(rows)
    assert Projection.completed_backup?(@profile, rows, 0)
    assert Projection.completed_backup?(@profile, rows, 1)
    assert :erlang.term_to_binary(rows) === before
    assert c.source["origin"]["receipt"] === receipt
  end
end
