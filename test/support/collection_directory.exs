import ExUnit.Assertions
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection, as: C
alias IpseKnowledge.Store.Collection.Generation, as: G
alias IpseKnowledge.Store.Collection.Directory, as: D
alias IpseKnowledge.Store.Collection.Job
json = &IO.iodata_to_binary(JSON.encode!(&1))
profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

selection = %{
  "selection_sha256" => E.sha256("directory-shape"),
  "profile" => "fixture",
  "model" => "fixture",
  "dimensions" => 1,
  "encoding" => "float32le"
}

extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}

# Small private data exercises directory geometry, not capacity or model quality.
inputs =
  Enum.map(0..135, fn n ->
    attrs = %{
      "source_id" => "fixture:directory:#{n}",
      "partition" => "notes",
      "generation" => 1,
      "title" => "Directory fixture",
      "text" => "Directory evidence #{n}.",
      "uri" => "provided:directory",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "documents",
        "partition_or_scope" => "notes",
        "receipt" => nil,
        "historical" => false
      }
    }

    {:call, _, plan} =
      C.start(profile, :put, %{"source" => attrs, "expected_revision" => 0, "continuation" => nil})

    {:ok, head} = C.planned_source_head(plan, n)
    source = plan.source
    {:ok, [chunk]} = E.chunks(source)
    {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

    {:ok, vector} =
      E.vector(
        Map.merge(Map.delete(selection, "encoding"), %{
          "chunk_id" => chunk["chunk_id"],
          "input_sha256" => input,
          "values" => [1.0]
        })
      )

    {:ok, citation} = E.citation(source, chunk, 0, 10)

    {:ok, fact} =
      E.fact(%{
        "subject" => "Subject#{n}",
        "object" => "Object#{n}",
        "predicate" => "rel",
        "polarity" => "positive",
        "inferred" => false,
        "valid_from_ms" => nil,
        "valid_to_ms" => nil,
        "extraction" => extraction,
        "citations" => [citation]
      })

    {%{"source" => source, "head" => head},
     %{
       "source_key" => source["source_key"],
       "source_bundle_sha256" => E.sha256(json.(source)),
       "vectors" => [vector],
       "facts" => [fact]
     }}
  end)
  |> Enum.chunk_every(16)
  |> Enum.flat_map(&Enum.sort_by(&1, fn {b, _} -> b["source"]["source_key"] end))

summaries =
  inputs
  |> Enum.chunk_every(8)
  |> Enum.with_index()
  |> Enum.map(fn {pairs, n} ->
    {bundles, data} = Enum.unzip(pairs)
    {:ok, plan} = G.pack_group("notes", n * 8, bundles, data, selection, extraction)

    {:ok, summary} =
      D.capture("notes", plan, bundles, %{
        "cursor" => n * 8,
        "vector_selection" => selection,
        "fact_selection" => extraction
      })

    assert {:error, _} =
             D.capture("notes", put_in(plan, [:header_unit, :byte_count], 0), bundles, %{
               "cursor" => n * 8,
               "vector_selection" => selection,
               "fact_selection" => extraction
             })

    summary
  end)

catalog_pages =
  inputs
  |> Enum.chunk_every(16)
  |> Enum.with_index()
  |> Enum.map(fn {pairs, n} ->
    %{
      "version" => 1,
      "kind" => "catalog_page",
      "partition" => "notes",
      "ordinal" => n,
      "rows" =>
        Enum.map(pairs, fn {b, _} ->
          %{
            "source_key" => b["source"]["source_key"],
            "head_sha256" => E.sha256(json.(b["head"]))
          }
        end)
    }
  end)

catalog = %{
  "version" => 1,
  "kind" => "catalog",
  "partition" => "notes",
  "generation" => 136,
  "floor" => 3,
  "sources" => 136,
  "extracted_bytes" =>
    Enum.sum(Enum.map(inputs, fn {b, _} -> byte_size(b["source"]["text"]) end)),
  "chunks" => 136,
  "entities" => 0,
  "assertions" => 0,
  "pages" =>
    Enum.with_index(catalog_pages)
    |> Enum.map(fn {page, n} ->
      %{"key" => "catalog.notes.#{n}", "sha256" => E.sha256(json.(page))}
    end)
}

{:ok, directory} = D.pack(profile, catalog, catalog_pages, summaries, 7)

job = %{
  "version" => 1,
  "kind" => "shared_generation_job",
  "id" => String.duplicate("1", 32),
  "partition" => "notes",
  "status" => "groups",
  "catalog" => catalog,
  "catalog_sha256" => E.sha256(json.(catalog)),
  "generation" => 8,
  "root_revision" => 17,
  "root_sha256" => directory.root_unit.sha256,
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "cursor" => 0,
  "summaries" => [],
  "facts" => 0
}

assert Job.valid?(job, profile)

# Pure protocol fixture: feed exact bounded read envelopes, stop at the first
# proposed effect, and prove an unknown effect produces no next request/token.
begin_args = %{
  "action" => "begin",
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "continuation" => nil,
  "group" => nil
}

walk = fn walk, result, steps, change_at ->
  assert steps < 32

  case result do
    {:call, request, continuation} ->
      r = request["request"]

      if not C.read_request?(request) do
        {request, continuation}
      else
        bytes = json.(catalog)

        descriptor = %{
          "revision" => 500,
          "sha256" => E.sha256(bytes),
          "byte_count" => byte_size(bytes)
        }

        reply =
          case r["op"] do
            "snapshot" ->
              %{
                "generation" => 500,
                "floor" => 3,
                "document_store" => %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2}
              }

            "value.stat" ->
              %{
                "generation" => 500,
                "key" => r["key"],
                "record" => if(r["key"] == "catalog.notes", do: descriptor, else: nil)
              }

            "value.read" ->
              Map.merge(descriptor, %{
                "generation" => 500,
                "key" => r["key"],
                "offset" => 0,
                "next" => nil,
                "data" => bytes
              })

            "stage.list" ->
              %{"generation" => 500, "stages" => []}
          end

        reply =
          Map.put(
            reply,
            "generation",
            if(change_at != nil and steps >= change_at, do: 501, else: 500)
          )

        {:ok, sha} = Ipse.Extension.canonical_digest([request])

        outcome = %{
          "status" => "ok",
          "value" => %{
            "version" => 1,
            "operation_id" => String.duplicate("a", 32),
            "request_sha256" => sha,
            "result" => reply
          }
        }

        walk.(walk, C.resume(continuation, outcome), steps + 1, change_at)
      end

    other ->
      other
  end
end

{effect, effect_cont} = walk.(walk, C.start(profile, :generation_job, begin_args), 0, nil)
assert effect["request"]["op"] == "value.prepare_inline"
assert {:stop, :unknown_effect} = C.resume(effect_cont, %{"status" => "unknown"})

assert {:done, {:error, :document_store_deadline_unavailable, _}} =
         C.resume(effect_cont, %{
           "status" => "failed",
           "value" => %{"code" => "document_store_deadline_unavailable"}
         })

# The changed generation now fails the request-bound native read before the Job
# owner can consume it; no mutation request is returned by this walk.
assert {:done, {:error, :collection_response, _}} =
         walk.(walk, C.start(profile, :generation_job, begin_args), 0, 3)

assert {:done, {:error, :invalid_generation_job_request, _}} =
         C.start(profile, :generation_job, put_in(begin_args, ["vector_selection", "model"], nil))

{first_bundles, first_data} = Enum.take(inputs, 8) |> Enum.unzip()
{:ok, first_plan} = G.pack_group("notes", 0, first_bundles, first_data, selection, extraction)
{:ok, first_progress} = Job.append_plan(job, first_plan, first_bundles, hd(catalog_pages))

assert first_progress.job["cursor"] == 8 and first_progress.job["facts"] == 8 and
         length(first_progress.job["summaries"]) == 1

assert Job.valid?(first_progress.job, profile)

# The bound format commits the exact source group, then removes the binding
# atomically with cursor advancement. The host separately authenticates the
# selected result and owner at the native commit boundary.
source_owner = %{
  "project_id" => E.sha256("project"),
  "session_id" => String.duplicate("a", 32),
  "identity_sha256" => E.sha256("identity")
}

{:ok, group_sha} = Ipse.Extension.canonical_digest([hd(summaries)["sources"]])

input_binding = %{
  "version" => 1,
  "ref_sha256" => E.sha256("selected reference"),
  "raw_sha256" => E.sha256("selected bytes"),
  "source_set_sha256" => group_sha,
  "cursor" => 0,
  "vector_job_revision" => 1,
  "owner" => source_owner
}

for {version, epoch} <- [{7, nil}, {8, 1}] do
  bound = Map.merge(job, %{"version" => version, "input_binding" => input_binding})
  bound = if epoch, do: Map.put(bound, "maintenance_epoch", epoch), else: bound
  assert Job.valid?(bound, profile)
  assert {:ok, progressed} = Job.append_plan(bound, first_plan, first_bundles, hd(catalog_pages))
  assert progressed.job["version"] == version and progressed.job["input_binding"] == nil
  assert progressed.job["cursor"] == 8

  assert {:error, _} =
           Job.append_plan(progressed.job, first_plan, first_bundles, hd(catalog_pages))

  wrong_sources = put_in(bound, ["input_binding", "source_set_sha256"], E.sha256("other"))

  assert {:error, _} =
           Job.append_plan(wrong_sources, first_plan, first_bundles, hd(catalog_pages))

  {last_bundles, last_data} = inputs |> Enum.drop(128) |> Enum.unzip()
  {:ok, last_plan} = G.pack_group("notes", 128, last_bundles, last_data, selection, extraction)
  {:ok, last_sha} = Ipse.Extension.canonical_digest([List.last(summaries)["sources"]])

  last_job =
    bound
    |> Map.merge(%{
      "cursor" => 128,
      "facts" => 128,
      "summaries" => Enum.map(Enum.take(summaries, 16), & &1["ref"]),
      "input_binding" =>
        Map.merge(input_binding, %{"cursor" => 128, "source_set_sha256" => last_sha})
    })

  assert {:ok, completed} =
           Job.append_plan(last_job, last_plan, last_bundles, Enum.at(catalog_pages, 8))

  assert completed.job["version"] == if(version == 7, do: 1, else: 4)
  assert completed.job["status"] == "manifests"
  refute Map.has_key?(completed.job, "input_binding")
  assert Job.valid?(completed.job, profile)
end

assert {:error, _} =
         Job.append_plan(first_progress.job, first_plan, first_bundles, hd(catalog_pages))

assert {:error, _} =
         Job.append_plan(
           Map.put(job, "status", "aborted"),
           first_plan,
           first_bundles,
           hd(catalog_pages)
         )

assert {:error, _} =
         Job.append_plan(
           put_in(job, ["vector_selection", "model"], "different-model"),
           first_plan,
           first_bundles,
           hd(catalog_pages)
         )

assert {:error, _} =
         Job.append_plan(
           job,
           first_plan,
           first_bundles,
           put_in(
             hd(catalog_pages),
             ["rows", Access.at(0), "head_sha256"],
             String.duplicate("0", 64)
           )
         )

# A numeric alias inside opaque citation origin is accepted by legacy span
# validation but cannot enter a new lossless shared projection.
opaque_attrs =
  first_bundles
  |> hd()
  |> Map.fetch!("source")
  |> Map.drop(~w(version source_key content_sha256 chunking))
  |> put_in(["origin", "receipt"], %{"version" => 1})

{:call, _, opaque_plan} =
  C.start(profile, :put, %{
    "source" => opaque_attrs,
    "expected_revision" => 0,
    "continuation" => nil
  })

{:ok, opaque_head} = C.planned_source_head(opaque_plan, 0)
opaque_source = opaque_plan.source
{:ok, [opaque_chunk]} = E.chunks(opaque_source)
{:ok, opaque_citation} = E.citation(opaque_source, opaque_chunk, 0, 10)

{:ok, opaque_fact} =
  E.fact(
    hd(hd(first_data)["facts"])
    |> Map.drop(~w(version fact_id))
    |> Map.put("citations", [opaque_citation])
  )

opaque_data = %{
  "source_key" => opaque_source["source_key"],
  "source_bundle_sha256" => E.sha256(json.(opaque_source)),
  "vectors" => hd(first_data)["vectors"],
  "facts" => [opaque_fact]
}

opaque_bundle = %{"source" => opaque_source, "head" => opaque_head}

{:ok, opaque_group} =
  G.pack_group("notes", 0, [opaque_bundle], [opaque_data], selection, extraction)

assert {:ok, [^opaque_data]} =
         G.unpack_group(
           "notes",
           opaque_group.header,
           Map.new(opaque_group.values, &{&1.key, &1.value}),
           [opaque_bundle],
           %{"cursor" => 0, "vector_selection" => selection, "fact_selection" => extraction}
         )

aliased = put_in(opaque_fact, ["citations", Access.at(0), "origin", "receipt", "version"], 1.0)
assert E.valid_fact?(aliased) and E.valid_span?(opaque_source, hd(aliased["citations"]))
assert aliased["fact_id"] === opaque_fact["fact_id"]

assert {:ok, _} =
         IpseKnowledge.Store.Collection.Projection.pack_facts(
           opaque_source,
           [aliased],
           extraction
         )

assert {:error, :invalid_shared_projection_group} =
         G.pack_group(
           "notes",
           0,
           [opaque_bundle],
           [%{opaque_data | "facts" => [aliased]}],
           selection,
           extraction
         )

ten = Enum.take(inputs, 10)
ten_page = put_in(hd(catalog_pages), ["rows"], Enum.take(hd(catalog_pages)["rows"], 10))

ten_catalog =
  catalog
  |> Map.merge(%{
    "generation" => 10,
    "sources" => 10,
    "chunks" => 10,
    "extracted_bytes" => Enum.sum(Enum.map(ten, fn {b, _} -> byte_size(b["source"]["text"]) end)),
    "pages" => [%{"key" => "catalog.notes.0", "sha256" => E.sha256(json.(ten_page))}]
  })

capture = fn pairs, cursor ->
  {bundles, data} = Enum.unzip(pairs)
  {:ok, plan} = G.pack_group("notes", cursor, bundles, data, selection, extraction)

  {:ok, summary} =
    D.capture("notes", plan, bundles, %{
      "cursor" => cursor,
      "vector_selection" => selection,
      "fact_selection" => extraction
    })

  summary
end

noncanonical_groups = [capture.(Enum.take(ten, 3), 0), capture.(Enum.drop(ten, 3), 8)]

assert {:error, :invalid_generation_directory} =
         D.pack(profile, ten_catalog, [ten_page], noncanonical_groups, 7)

canonical_groups = [capture.(Enum.take(ten, 8), 0), capture.(Enum.drop(ten, 8), 8)]
{:ok, ten_directory} = D.pack(profile, ten_catalog, [ten_page], canonical_groups, 7)

ten_expected =
  Map.take(
    ten_directory.root,
    ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
  )
  |> Map.put("root_sha256", ten_directory.root_unit.sha256)

ten_values =
  Map.new(ten_directory.values, &{&1.key, &1.value})
  |> Map.merge(Map.new(canonical_groups, &{&1["ref"]["key"], &1["header"]}))

{:ok, ten_lookup} =
  D.lookup(
    ten_directory.root,
    ten_values,
    [List.last(ten) |> elem(0) |> get_in(["source", "source_key"])],
    ten_expected
  )

assert length(ten_lookup["groups"]) == 1

expected =
  Map.take(
    directory.root,
    ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
  )
  |> Map.put("root_sha256", directory.root_unit.sha256)

values =
  Map.new(directory.values, &{&1.key, &1.value})
  |> Map.merge(Map.new(summaries, &{&1["ref"]["key"], &1["header"]}))

keys = [
  hd(summaries)["header"]["source_keys"] |> hd(),
  List.last(summaries)["header"]["source_keys"] |> List.last()
]

{:ok, lookup} = D.lookup(directory.root, values, keys, expected)
assert Enum.map(lookup["groups"], & &1["cursor"]) == [0, 128]
assert lookup["coverage"]["manifest_pages"] == 2
assert lookup["missing_source_keys"] == []
{:ok, entities} = D.entity_rows(directory.root, values, expected)
assert length(entities) == 272
assert {:error, _} = D.lookup(directory.root, values, keys, Map.put(expected, "floor", 4))
assert {:error, _} = D.pack(profile, catalog, Enum.reverse(catalog_pages), summaries, 7)
assert {:error, _} = D.pack(profile, catalog, catalog_pages, Enum.reverse(summaries), 7)
[manifest | _] = directory.root["manifests"]
assert {:error, _} = D.lookup(directory.root, Map.delete(values, manifest["key"]), keys, expected)
[entity | _] = directory.root["entity_pages"]
assert {:error, _} = D.entity_rows(directory.root, Map.delete(values, entity["key"]), expected)
reversed = Map.update!(directory.root, "manifests", &Enum.reverse/1)

assert {:error, _} =
         D.lookup(
           reversed,
           values,
           keys,
           Map.put(expected, "root_sha256", E.sha256(json.(reversed)))
         )

reversed = Map.update!(directory.root, "entity_pages", &Enum.reverse/1)

assert {:error, _} =
         D.entity_rows(
           reversed,
           values,
           Map.put(expected, "root_sha256", E.sha256(json.(reversed)))
         )

# Rehash both the altered manifest and root: canonical group order still refuses.
page = Map.fetch!(values, manifest["key"])
[first, second | tail] = page["rows"]
page = Map.put(page, "rows", [second, first | tail])
sha = E.sha256(json.(page))
key = "genman.notes." <> sha
ref = %{"key" => key, "sha256" => sha, "byte_count" => byte_size(json.(page))}
forged = put_in(directory.root, ["manifests", Access.at(0)], ref)

assert {:error, _} =
         D.lookup(
           forged,
           Map.put(values, key, page),
           keys,
           Map.put(expected, "root_sha256", E.sha256(json.(forged)))
         )

# Unknown keys remain explicit; no other group's payload is fetched.
{:ok, missing} = D.lookup(directory.root, values, [E.sha256("absent")], expected)
assert missing["groups"] == [] and missing["missing_source_keys"] == [E.sha256("absent")]
refute lookup["coverage"]["evidence_readable"]
refute lookup["coverage"]["projection_payloads_read"]

IO.puts(
  Jason.encode!(%{
    "groups" => 17,
    "sources" => 136,
    "manifest_pages" => 2,
    "entity_pages" => length(directory.root["entity_pages"]),
    "selected_headers" => 2,
    "entities" => 272,
    "directory_root_bytes" => directory.root_unit.byte_count,
    "native_operations" => 0,
    "publication_attempted" => false
  })
)
