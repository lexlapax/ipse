# Finite dry preflight of the current public Collection ingestion recipe.
# It performs no native storage, model inference, acquisition or publication.
{opts, [], []} =
  OptionParser.parse(System.argv(), strict: [sdk: :string, artifact: :string, transport: :string])

transport = Keyword.get(opts, :transport, "staged_v1")
true = transport in ~w(staged_v1 fused_v2)
sdk = Path.expand(Keyword.fetch!(opts, :sdk))
Code.prepend_path(sdk)

for dep <- ~w(jason jsonschex ex_json_pointer),
    do: Code.prepend_path(Path.expand("../../#{dep}/ebin", sdk))

artifact = Path.expand(Keyword.fetch!(opts, :artifact))
manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))

for file <- manifest["files"] do
  bytes = File.read!(Path.join(artifact, file["path"]))
  true = byte_size(bytes) == file["bytes"]
  true = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == file["sha256"]
end

for path <- Path.wildcard(Path.join(artifact, "ebin/*.beam")),
    do: {:module, _} = :code.load_abs(String.to_charlist(Path.rootname(path)))

defmodule Ipse.CollectionProfileOperations do
  alias IpseKnowledge.{Evidence, Documents}
  alias IpseKnowledge.Store.Collection
  alias IpseKnowledge.Store.Collection.Projection

  def run(transport) do
    if transport == "fused_v2" do
      true =
        Ipse.Extension.Collection.DocumentStage.request?(%{
          "op" => "value.write_parts",
          "slot" => 0,
          "epoch" => String.duplicate("0", 32),
          "key" => "probe.value",
          "expected_revision" => 0,
          "byte_count" => 2,
          "sha256" => Evidence.sha256("{}"),
          "offset" => 0,
          "data" => ["{", "}"],
          "publish" => true,
          "generation" => 0
        })
    end

    samples =
      for {size, count, suffix} <- [{2097, 252, "0000"}, {2096, 748, "0001"}] do
        source_id = "fixture:capacity:" <> suffix
        payload = document(size)
        receipt = Evidence.document_storage_receipt!(payload["document"])

        attrs = %{
          "source_id" => source_id,
          "partition" => "notes",
          "generation" => 1,
          "title" => "Capacity operation lower bound",
          "text" => payload["text"],
          "uri" => "provided:capacity.docx",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => nil,
          "origin" => %{
            "kind" => "provided",
            "store_profile" => "documents",
            "partition_or_scope" => "notes",
            "receipt" => receipt,
            "historical" => false
          }
        }

        attrs =
          if receipt["version"] == 4,
            do: Map.put(attrs, "document", payload["document"]),
            else: attrs

        profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

        {:call, _, plan} =
          Collection.start(profile, :put, %{
            "source" => attrs,
            "expected_revision" => 0,
            "continuation" => nil
          })

        source = plan.source
        {:ok, chunks} = Evidence.chunks(source)
        true = length(chunks) == 10

        selection = %{
          "selection_sha256" => Evidence.sha256("synthetic-shape-1024"),
          "profile" => "provided-shape",
          "model" => "synthetic-capacity-shape",
          "dimensions" => 1024,
          "encoding" => "float32le"
        }

        vectors =
          for {chunk, ordinal} <- Enum.with_index(chunks) do
            {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

            {:ok, vector} =
              Evidence.vector(
                Map.merge(Map.delete(selection, "encoding"), %{
                  "chunk_id" => chunk["chunk_id"],
                  "input_sha256" => input,
                  "values" => for(n <- 1..1024, do: 1.0 + rem(n + ordinal, 17) / 17)
                })
              )

            vector
          end

        {:ok, vector_pages} = Projection.pack(source, vectors, selection)
        extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}
        [first | _] = chunks

        {:ok, citation} =
          Evidence.citation(source, first, first["start_byte"], first["start_byte"] + 32)

        facts =
          for n <- 0..19 do
            {:ok, fact} =
              Evidence.fact(%{
                "subject" => "#{source_id}:Entity#{rem(n, 5)}",
                "object" => "#{source_id}:Entity#{rem(n + 1, 5)}",
                "predicate" => "relation#{n}",
                "polarity" => "positive",
                "inferred" => false,
                "valid_from_ms" => nil,
                "valid_to_ms" => nil,
                "extraction" => extraction,
                "citations" => [citation]
              })

            fact
          end

        {:ok, fact_pages} = Projection.pack_facts(source, facts, extraction)
        source_cost = Enum.map(plan.prepared, &cost(&1, transport))
        vector_cost = Enum.map(vector_pages, &cost(&1, transport))
        fact_cost = Enum.map(fact_pages, &cost(&1, transport))
        # Each selected source needs three prepared metadata values + one CAS.
        # Each source-local projection needs root + catalog preparations + one CAS.
        # These are minimums; bigger metadata can cost more than one mutation.
        costs = %{
          "source" => total(source_cost) + 4,
          "vectors" => total(vector_cost) + 3,
          "facts" => total(fact_cost) + 3
        }

        %{
          "sources" => count,
          "source_text_bytes" => byte_size(source["text"]),
          "chunks_per_source" => length(chunks),
          "vectors_per_source" => length(vectors),
          "assertions_per_source" => length(facts),
          "unique_entities_per_source" => 5,
          "source_values" => source_cost,
          "vector_values" => vector_cost,
          "fact_values" => fact_cost,
          "_source" => source,
          "per_source_mutation_minimum" => costs,
          "mutation_minimum" => count * Enum.sum(Map.values(costs))
        }
      end

    text = Enum.sum(Enum.map(samples, &(&1["sources"] * &1["source_text_bytes"])))
    true = text == 20 * 1024 * 1024
    lower_bound = Enum.sum(Enum.map(samples, & &1["mutation_minimum"]))
    lexical = lexical_plan(samples, transport)
    shared = shared_plan(lexical["_sources"], transport)
    lexical = Map.delete(lexical, "_sources")

    source_keys =
      Enum.sum(Enum.map(samples, &(&1["sources"] * (length(&1["source_values"]) + 1)))) + 64

    vector_keys =
      Enum.sum(Enum.map(samples, &(&1["sources"] * (length(&1["vector_values"]) + 1))))

    fact_keys = Enum.sum(Enum.map(samples, &(&1["sources"] * (length(&1["fact_values"]) + 1))))
    live_keys = source_keys + vector_keys + fact_keys + lexical["live_keys"]

    vector_replacement =
      Enum.sum(Enum.map(samples, &(&1["sources"] * &1["per_source_mutation_minimum"]["vectors"])))

    %{
      "version" => 1,
      "kind" => "collection_profile_operation_lower_bound",
      "samples" => Enum.map(samples, &Map.delete(&1, "_source")),
      "sources" => 1000,
      "extracted_bytes" => text,
      "chunks" => 10000,
      "vectors" => 10000,
      "dimensions" => 1024,
      "entities" => 5000,
      "assertions" => 20000,
      "native_mutation_ceiling" => 32768,
      "mandatory_initial_mutation_minimum" => lower_bound,
      "transport_recipe" => transport,
      "implemented_initial_mutation_minimum" => lower_bound + lexical["initial_mutations"],
      "one_vector_replacement_fact_reselection_and_lexical_rebuild_minimum" =>
        vector_replacement + 3000 + lexical["rebuild_mutations"],
      "lexical_index" => lexical,
      "shared_codec_plan" => shared,
      "live_key_minimum" => live_keys,
      "live_key_components" => %{
        "source" => source_keys,
        "vectors" => vector_keys,
        "facts" => fact_keys,
        "lexical_index" => lexical["live_keys"]
      },
      "old_plus_staged_vector_live_key_minimum" => live_keys + vector_keys - 1000,
      "live_key_ceiling" => 8192,
      "preflight" =>
        cond do
          lower_bound > 32768 -> "refused_mutations"
          live_keys > 8192 -> "refused_live_keys"
          true -> "remaining_recipe_required"
        end,
      "excluded_work" =>
        ~w(global_graph_catalog_and_index all_profile_atomic_generation_and_rebuild migration collection retention saved_notes),
      "complete_recipe_available" => false,
      "deadline_publication_gate" =>
        case Ipse.Extension.Collection.with_publication_deadline(
               System.system_time(:millisecond) + 60_000,
               fn -> :probe_only end
             ) do
          {:error, :collection_deadline_fence_unavailable} -> "unavailable"
          _ -> "not_qualified"
        end,
      "native_operations_executed" => 0,
      "fixture_geometry_only" => true,
      "model_inference_executed" => false,
      "profile_qualified" => false
    }
  end

  defp cost(value, transport) do
    bytes = json(value)
    true = byte_size(bytes) in 2..61_440

    parts =
      Stream.unfold(bytes, fn
        "" -> nil
        rest -> Evidence.utf8_prefix(rest, 6144)
      end)
      |> Enum.to_list()

    packed_bytes =
      byte_size(
        json(%{
          "version" => 1,
          "kind" => "document_value",
          "byte_count" => byte_size(bytes),
          "sha256" => Evidence.sha256(bytes),
          "parts" => parts
        })
      )

    true = packed_bytes <= 65_536

    base = %{
      "key" => "data.notes." <> Evidence.sha256(bytes),
      "expected_revision" => 0,
      "generation" => 32767
    }

    inline =
      Map.merge(base, %{
        "op" => "value.put_inline",
        "data" => bytes,
        "byte_count" => byte_size(bytes),
        "sha256" => Evidence.sha256(bytes)
      })

    frame = fn request ->
      %{
        "api_version" => 1,
        "kind" => "host_call",
        "request" => %{"op" => "collection.store", "scope" => "project", "request" => request}
      }
    end

    if byte_size(bytes) <= 8192 and Ipse.Extension.validate(frame.(inline)) == :ok do
      %{
        "body_bytes" => byte_size(bytes),
        "packed_document_bytes" => packed_bytes,
        "transport" => "inline",
        "native_mutations" => 1,
        "maximum_host_frame_bytes" => byte_size(json(frame.(inline)))
      }
    else
      if transport == "fused_v2" do
        frames = fused_frames(bytes, 0, base, frame)

        %{
          "body_bytes" => byte_size(bytes),
          "packed_document_bytes" => packed_bytes,
          "transport" => "fused_parts",
          "native_mutations" => length(frames),
          "parts_per_frame" => Enum.map(frames, &length(&1["request"]["request"]["data"])),
          "maximum_host_frame_bytes" => Enum.max(Enum.map(frames, &byte_size(json(&1))))
        }
      else
        parts =
          Stream.unfold(bytes, fn
            "" ->
              nil

            rest ->
              {part, tail} = Evidence.utf8_prefix(rest, 6144)
              {part, tail}
          end)
          |> Enum.to_list()

        frames =
          Enum.with_index(parts)
          |> Enum.map(fn {data, i} ->
            frame.(%{
              "op" => "value.append",
              "slot" => 0,
              "epoch" => String.duplicate("0", 32),
              "offset" => i * 6144,
              "data" => data,
              "generation" => 32767
            })
          end)

        true = Enum.all?(frames, &(Ipse.Extension.validate(&1) == :ok))

        %{
          "body_bytes" => byte_size(bytes),
          "packed_document_bytes" => packed_bytes,
          "transport" => "bounded_stage",
          "append_calls" => length(parts),
          "native_mutations" => length(parts) + 3,
          "maximum_host_frame_bytes" => Enum.max(Enum.map(frames, &byte_size(json(&1))))
        }
      end
    end
  end

  defp fused_frames(bytes, offset, _base, _frame) when offset == byte_size(bytes), do: []

  defp fused_frames(bytes, offset, base, frame) do
    tail = binary_part(bytes, offset, byte_size(bytes) - offset)
    {first, rest} = Evidence.utf8_prefix(tail, 6144)
    data = if rest == "", do: [first], else: [first, elem(Evidence.utf8_prefix(rest, 6144), 0)]

    request = fn data ->
      frame.(
        Map.merge(base, %{
          "op" => "value.write_parts",
          "slot" => 0,
          "epoch" => String.duplicate("0", 32),
          "byte_count" => byte_size(bytes),
          "sha256" => Evidence.sha256(bytes),
          "offset" => offset,
          "data" => data,
          "publish" => true
        })
      )
    end

    packet = request.(data)
    packet = if Ipse.Extension.validate(packet) == :ok, do: packet, else: request.([first])
    :ok = Ipse.Extension.validate(packet)
    true = Ipse.Extension.Collection.DocumentStage.request?(packet["request"]["request"])
    consumed = Enum.sum(Enum.map(packet["request"]["request"]["data"], &byte_size/1))
    [packet | fused_frames(bytes, offset + consumed, base, frame)]
  end

  defp total(costs), do: Enum.sum(Enum.map(costs, & &1["native_mutations"]))

  defp lexical_plan(samples, transport) do
    templates =
      Enum.flat_map(samples, fn sample -> List.duplicate(sample["_source"], sample["sources"]) end)

    sources =
      templates
      |> Enum.with_index()
      |> Enum.map(fn {source, n} ->
        id = "fixture:capacity:" <> String.pad_leading(Integer.to_string(n), 4, "0")
        source |> Map.put("source_id", id) |> Map.put("source_key", Evidence.sha256(id))
      end)
      |> Enum.chunk_every(16)
      |> Enum.flat_map(&Enum.sort_by(&1, fn source -> source["source_key"] end))

    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    groups =
      sources
      |> Enum.chunk_every(8)
      |> Enum.with_index()
      |> Enum.map(fn {sources, n} ->
        entries =
          Enum.map(sources, fn source ->
            {:ok, run} = Evidence.lexical_run(source)

            %{
              "run" => run,
              "source_bundle_sha256" => Evidence.sha256(json(source)),
              "source_revision" => 1
            }
          end)

        {:ok, plan} =
          IpseKnowledge.Store.Collection.Index.storage_plan(profile, sources, entries, n * 8)

        plan
      end)

    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => "notes",
      "generation" => 1000,
      "floor" => 0,
      "sources" => 1000,
      "extracted_bytes" => 20_971_520,
      "chunks" => 10000,
      "entities" => 0,
      "assertions" => 0,
      "pages" =>
        for(
          n <- 0..62,
          do: %{"key" => "catalog.notes.#{n}", "sha256" => String.duplicate("0", 64)}
        )
    }

    job = %{
      "version" => 1,
      "kind" => "lexical_job",
      "id" => String.duplicate("0", 32),
      "status" => "building",
      "catalog" => catalog,
      "catalog_sha256" => Evidence.sha256(json(catalog)),
      "cursor" => 0,
      "unit" => 0,
      "groups" => [],
      "root_revision" => 0,
      "index_generation" => 1
    }

    {jobs, _} =
      Enum.map_reduce(groups, job, fn group, job ->
        next =
          job
          |> Map.update!("cursor", &(&1 + 8))
          |> Map.update!("groups", &(&1 ++ [group.header]))

        {next, next}
      end)

    last = List.last(jobs)

    root = %{
      "version" => 1,
      "kind" => "lexical_index",
      "recipe" => Evidence.lexical_recipe(),
      "job_id" => job["id"],
      "generation" => 1,
      "catalog_sha256" => job["catalog_sha256"],
      "catalog_generation" => 1000,
      "floor" => 0,
      "sources" => 1000,
      "chunks" => 10000,
      "groups" => last["groups"]
    }

    immutable = for group <- groups, unit <- group.values, do: cost(unit.value, transport)
    job_costs = Enum.map([job | jobs], &cost(&1, transport))
    # Metadata target names are shorter than the conservative data-key frame.
    publication = total([cost(root, transport), cost(catalog, transport)]) + 1

    rebuilt_jobs =
      Enum.map([job | jobs], fn value ->
        value
        |> Map.put("id", String.duplicate("1", 32))
        |> Map.put("index_generation", 2)
        |> Map.put("root_revision", 32767)
        |> cost(transport)
      end)

    %{
      "_sources" => sources,
      "groups" => length(groups),
      "immutable_values" => length(immutable),
      "live_keys" => length(immutable) + 2,
      "initial_mutations" => total(immutable) + total(job_costs) + publication,
      "rebuild_mutations" => total(rebuilt_jobs) + publication,
      "rebuild_immutable_values_reused" => length(immutable),
      "job_rewrites" => length(job_costs),
      "maximum_host_frame_bytes" =>
        Enum.max(Enum.map(immutable ++ job_costs, & &1["maximum_host_frame_bytes"])),
      "initial_fresh_group_mutations" => total(immutable),
      "initial_job_mutations" => total(job_costs),
      "publication_mutations" => publication
    }
  end

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))

  defp shared_plan(sources, transport) do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    selection = %{
      "selection_sha256" => Evidence.sha256("synthetic-shape-1024"),
      "profile" => "provided-shape",
      "model" => "synthetic-capacity-shape",
      "dimensions" => 1024,
      "encoding" => "float32le"
    }

    extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}

    groups =
      sources
      |> Enum.chunk_every(8)
      |> Enum.with_index()
      |> Enum.map(fn {sources, group} ->
        bundles =
          Enum.with_index(sources, group * 8)
          |> Enum.map(fn {source, _n} ->
            {:call, _, plan} =
              Collection.start(profile, :put, %{
                "source" => source,
                "expected_revision" => 0,
                "continuation" => nil
              })

            ordinal =
              source["source_id"] |> String.split(":") |> List.last() |> String.to_integer()

            {:ok, head} = Collection.planned_source_head(plan, ordinal)
            %{"source" => source, "head" => head}
          end)

        supplied =
          Enum.map(sources, fn source ->
            {:ok, chunks} = Evidence.chunks(source)

            vectors =
              Enum.with_index(chunks)
              |> Enum.map(fn {chunk, n} ->
                {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

                {:ok, vector} =
                  Evidence.vector(
                    Map.merge(Map.delete(selection, "encoding"), %{
                      "chunk_id" => chunk["chunk_id"],
                      "input_sha256" => input,
                      "values" => for(i <- 1..1024, do: 1.0 + rem(i + n, 17) / 17)
                    })
                  )

                vector
              end)

            [chunk | _] = chunks

            {:ok, citation} =
              Evidence.citation(source, chunk, chunk["start_byte"], chunk["start_byte"] + 32)

            facts =
              for n <- 0..19 do
                {:ok, fact} =
                  Evidence.fact(%{
                    "subject" => "#{source["source_id"]}:Entity#{rem(n, 5)}",
                    "object" => "#{source["source_id"]}:Entity#{rem(n + 1, 5)}",
                    "predicate" => "relation#{n}",
                    "polarity" => "positive",
                    "inferred" => false,
                    "valid_from_ms" => nil,
                    "valid_to_ms" => nil,
                    "extraction" => extraction,
                    "citations" => [citation]
                  })

                fact
              end

            %{
              "source_key" => source["source_key"],
              "source_bundle_sha256" => Evidence.sha256(json(source)),
              "vectors" => vectors,
              "facts" => facts
            }
          end)

        {:ok, plan} =
          IpseKnowledge.Store.Collection.Generation.pack_group(
            "notes",
            group * 8,
            bundles,
            supplied,
            selection,
            extraction
          )

        values = plan.values ++ [plan.header_unit]
        %{plan: plan, costs: Enum.map(values, &cost(&1.value, transport))}
      end)

    entity_rows =
      groups |> Enum.flat_map(& &1.plan.entities) |> Enum.uniq_by(&hd/1) |> Enum.sort_by(&hd/1)

    group_entries =
      groups
      |> Enum.map(fn group ->
        header = group.plan.header
        unit = group.plan.header_unit

        %{
          "cursor" => header["cursor"],
          "source_keys" => header["source_keys"],
          "ref" => %{"key" => unit.key, "sha256" => unit.sha256, "byte_count" => unit.byte_count}
        }
      end)

    manifest_pages =
      group_entries
      |> Enum.chunk_every(16)
      |> Enum.with_index()
      |> Enum.map(fn {rows, n} ->
        %{"version" => 1, "kind" => "planned_generation_manifest", "ordinal" => n, "rows" => rows}
      end)

    entity_pages =
      entity_rows
      |> Enum.chunk_every(64)
      |> Enum.with_index()
      |> Enum.map(fn {rows, n} ->
        %{"version" => 1, "kind" => "planned_generation_entities", "ordinal" => n, "rows" => rows}
      end)

    costs =
      Enum.flat_map(groups, & &1.costs) ++
        Enum.map(manifest_pages ++ entity_pages, &cost(&1, transport))

    leaves = Enum.sum(Enum.map(groups, &(length(&1.plan.values) + 1)))
    live = 3064 + 252 + leaves + length(manifest_pages) + length(entity_pages) + 2
    vector_pages = Enum.sum(Enum.map(groups, &length(&1.plan.header["vector_pages"])))

    %{
      "codec_groups" => length(groups),
      "sources" => 1000,
      "vectors" => 10000,
      "facts" => 20000,
      "unique_entities" => length(entity_rows),
      "group_values" => leaves,
      "manifest_pages" => length(manifest_pages),
      "entity_pages" => length(entity_pages),
      "planned_initial_live_keys" => live,
      "planned_old_plus_staged_vector_live_keys" =>
        live + vector_pages + length(groups) + length(manifest_pages) + 1,
      "fresh_value_mutations" => total(costs),
      "group_packed_document_bytes" =>
        Enum.sum(for g <- groups, c <- g.costs, do: c["packed_document_bytes"]),
      "planned_directory_packed_document_bytes" =>
        Enum.sum(
          for p <- manifest_pages ++ entity_pages, do: cost(p, transport)["packed_document_bytes"]
        ),
      "staged_vector_and_group_header_packed_document_bytes" =>
        Enum.sum(
          for g <- groups,
              u <- g.plan.values ++ [g.plan.header_unit],
              u.value["kind"] in ["shared_vectors", "shared_projection_group"],
              do: cost(u.value, transport)["packed_document_bytes"]
        ),
      "byte_totals_exclude_source_lexical_native_metadata_and_journal" => true,
      "maximum_host_frame_bytes" => Enum.max(Enum.map(costs, & &1["maximum_host_frame_bytes"])),
      "largest_group_header_bytes" =>
        Enum.max(Enum.map(groups, & &1.plan.header_unit.byte_count)),
      "largest_value_bytes" =>
        Enum.max(Enum.flat_map(groups, fn g -> Enum.map(g.plan.values, & &1.byte_count) end)),
      "generation_publication_implemented" => false,
      "gc_migration_implemented" => false,
      "capacity_qualified" => false,
      "index_entity_directory_pages_are_plans" => true
    }
  end

  defp document(size) do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    body =
      Enum.map_join(1..10, fn _ ->
        "<w:p><w:r><w:t>" <> String.duplicate("a", size) <> "</w:t></w:r></w:p>"
      end)

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"capacity.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ],
        [:memory]
      )

    {:ok, extraction} = Documents.extract(bytes, "capacity.docx")
    {:ok, payload} = Documents.source_payload(extraction, 65536, 2)
    payload
  end
end

IO.puts(Jason.encode!(Ipse.CollectionProfileOperations.run(transport), pretty: true))
