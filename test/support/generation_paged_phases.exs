import ExUnit.Assertions

prefix =
  File.read!("test/support/generation_paged_budget.exs")
  |> String.split("{{:done, {:ok, selected}}, final}", parts: 2)
  |> hd()

{_, bindings} = Code.eval_string(prefix)
get = fn key -> Keyword.fetch!(bindings, key) end
alias IpseTest.CollectionProtocol, as: Protocol
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection, as: C
alias IpseKnowledge.Store.Collection.{Directory, Paged, Job}
json = &IO.iodata_to_binary(JSON.encode!(&1))
partition = get.(:partition)
profile = get.(:profile)
job = get.(:job)
token = get.(:token)
args = get.(:args)
base = get.(:model)

reset = fn initial, reduction, summaries, added ->
  current = job |> Map.put("reduction", reduction) |> Map.put("summaries", summaries)
  assert Job.valid?(current, profile)

  records =
    Map.merge(
      initial.records,
      Map.new(added, &{&1.key, %{value: &1.value, revision: initial.generation - 1000}})
    )
    |> Map.put("genjob.#{partition}", %{value: current, revision: token["job_revision"]})

  %{initial | records: records} |> Protocol.reset()
end

finish = fn finish, arguments, model, metrics ->
  {result, measured} =
    Protocol.run(C.start(profile, :generation_job, arguments), Protocol.reset(model))

  assert measured.records["generation.#{partition}"].value ===
           base.records["generation.#{partition}"].value

  metrics =
    metrics ++
      [
        %{
          "reads" => measured.reads,
          "effects" => measured.effects,
          "maximum_frame_bytes" => Enum.max(measured.frames)
        }
      ]

  case result do
    {:done, {:continue, value}} ->
      finish.(finish, %{arguments | "continuation" => value["continuation"]}, measured, metrics)

    {:done, {:ok, value}} ->
      {value, measured, metrics}

    other ->
      flunk(inspect(other))
  end
end

summarize = fn metrics ->
  %{
    "invocations" => length(metrics),
    "maximum_reads" => metrics |> Enum.map(& &1["reads"]) |> Enum.max(),
    "maximum_effects" => metrics |> Enum.map(& &1["effects"]) |> Enum.max(),
    "maximum_frame_bytes" => metrics |> Enum.map(& &1["maximum_frame_bytes"]) |> Enum.max(),
    "total_effects" => Enum.sum(Enum.map(metrics, & &1["effects"]))
  }
end

# Eight sorted run directories. The first32identities occur in every run and
# each run carries only its own canonical16-group membership range.
runs =
  for index <- 0..7 do
    rows =
      get.(:rows)
      |> Enum.flat_map(fn [id, label, memberships] ->
        selected = Enum.filter(memberships, &(&1 in (index * 16)..min(index * 16 + 15, 124)))
        if selected == [], do: [], else: [[id, label, selected]]
      end)

    pages =
      rows
      |> Enum.chunk_every(32)
      |> Enum.with_index()
      |> Enum.map(fn {rows, n} ->
        Directory.immutable(partition, "genrun", %{
          "version" => 2,
          "kind" => "generation_entity_run",
          "recipe" => "ipse.evidence.shared_directory.v2",
          "ordinal" => n,
          "rows" => rows
        })
      end)

    directory =
      Directory.immutable(partition, "genruns", %{
        "version" => 2,
        "kind" => "generation_entity_run_directory",
        "recipe" => "ipse.evidence.shared_directory.v2",
        "ordinal" => index,
        "entities" => length(rows),
        "pages" => Enum.map(pages, &Directory.reference/1)
      })

    assert Enum.all?(pages ++ [directory], &Paged.native_value?(&1.value))
    {directory, pages}
  end

reduction =
  job["reduction"]
  |> Map.merge(%{
    "phase" => "entities",
    "runs" => Enum.map(runs, &Directory.reference(elem(&1, 0))),
    "positions" => List.duplicate(0, 8),
    "entity_pages" => [],
    "entities" => 0,
    "heads_sha256" => nil,
    "entity_pages_sha256" => nil,
    "digest_cursor" => 0,
    "verified_entities" => 0,
    "last_entity_id" => nil
  })

model =
  reset.(
    base,
    reduction,
    [],
    Enum.flat_map(runs, fn {directory, pages} -> pages ++ [directory] end)
  )

model = %{model | records: Map.delete(model.records, hd(get.(:entities)).key)}
{merged, _, merge_metrics} = finish.(finish, args, model, [])
assert merged["job"]["reduction"]["entities"] == 32
assert merged["job"]["reduction"]["positions"] == List.duplicate(32, 8)

# A schema-valid, native-usable upper-bound summary fixture. It deliberately
# maximizes declared header refs within48KiB/64KiB, not a claim of model/group
# production or payload hydration. Catalog/head/source totals remain exact.
heads = get.(:heads)
bytes_left = 20 * 1024 * 1024 - 128 * 65_536
width = div(bytes_left, 872)
extra = rem(bytes_left, 872)

summaries =
  for index <- 0..124 do
    sources =
      Enum.slice(heads, index * 8, 8)
      |> Enum.with_index(index * 8)
      |> Enum.map(fn {row, n} ->
        Map.merge(row, %{
          "ordinal" => n,
          "text_bytes" =>
            if(n < 128, do: 65_536, else: width + if(n - 128 < extra, do: 1, else: 0)),
          "chunks" => if(n < 128, do: 32, else: 6 + if(n - 128 < 672, do: 1, else: 0)),
          "bundle_sha256" => E.sha256("bundle#{n}")
        })
      end)

    labels =
      for n <- 0..39 do
        label =
          String.duplicate("\\", 251) <>
            (Integer.to_string(index * 40 + n) |> String.pad_leading(5, "0"))

        [E.id("entity", [partition, label]), label]
      end
      |> Enum.sort_by(&List.last/1)

    references = fn family, count ->
      for n <- 0..(count - 1),
          do: %{
            "key" => "#{family}.#{partition}." <> E.sha256("#{family}:#{index}:#{n}"),
            "sha256" => E.sha256("#{family}:#{index}:#{n}"),
            "byte_count" => 49_152
          }
    end

    base_header = %{
      "version" => 1,
      "kind" => "shared_projection_group",
      "recipe" => "ipse.evidence.shared_projections.v1",
      "cursor" => index * 8,
      "source_set_sha256" =>
        E.sha256(
          json.(%{"sources" => Enum.map(sources, &[&1["source_key"], &1["bundle_sha256"]])})
        ),
      "source_keys" => Enum.map(sources, & &1["source_key"]),
      "sources" => 8,
      "vectors" => Enum.sum(Enum.map(sources, & &1["chunks"])),
      "facts" =>
        cond do
          index < 16 -> 256
          index < 124 -> 146
          true -> 136
        end,
      "entities" => 40,
      "partial_sources" => 8,
      "vector_selection" => get.(:selection),
      "fact_selection" => get.(:extraction),
      "vector_identities_sha256" => E.sha256("vectors#{index}"),
      "fact_ids_sha256" => E.sha256("facts#{index}"),
      "entity_ids_sha256" => E.sha256(json.(%{"ids" => Enum.map(labels, &hd/1)})),
      "source_pages" => references.("gensrc", 1),
      "vector_pages" => [],
      "fact_pages" => references.("genfact", 1)
    }

    candidates =
      for count <- 1..128 do
        header = Map.put(base_header, "vector_pages", references.("genvec", count))
        unit = Directory.immutable(partition, "gengrp", header)

        %{
          "header" => header,
          "ref" => Directory.reference(unit),
          "sources" => sources,
          "entities" => labels
        }
      end

    summary =
      candidates
      |> Enum.filter(
        &(Directory.valid_summary?(partition, &1, index * 8) and Paged.native_value?(&1))
      )
      |> List.last()

    assert is_map(summary)
    Directory.immutable(partition, "gensum", summary)
  end

assert Enum.sum(
         Enum.map(summaries, fn s ->
           Enum.sum(Enum.map(s.value["sources"], & &1["text_bytes"]))
         end)
       ) == 20 * 1024 * 1024

assert Enum.sum(Enum.map(summaries, fn s -> s.value["header"]["vectors"] end)) == 10_000
assert Enum.sum(Enum.map(summaries, fn s -> s.value["header"]["facts"] end)) == 20_000

reduction =
  job["reduction"]
  |> Map.merge(%{
    "phase" => "manifests",
    "batch" => 0,
    "manifests" => [],
    "runs" => [],
    "positions" => [],
    "entity_pages" => [],
    "entities" => 0,
    "text_bytes" => 0,
    "chunks" => 0,
    "facts" => 0,
    "heads_sha256" => nil,
    "entity_pages_sha256" => nil,
    "digest_cursor" => 0,
    "verified_entities" => 0,
    "last_entity_id" => nil
  })

model =
  reset.(
    base,
    reduction,
    Enum.map(summaries, &Directory.reference/1),
    summaries ++
      Enum.map(get.(:catalog_pages), fn page ->
        %{key: "catalog.#{partition}.#{page["ordinal"]}", value: page}
      end)
  )

{batched, _, manifest_metrics} = finish.(finish, args, model, [])
assert batched["job"]["reduction"]["batch"] == 1
assert batched["job"]["reduction"]["text_bytes"] == 128 * 65_536

assert batched["job"]["reduction"]["chunks"] == 4096 and
         batched["job"]["reduction"]["facts"] == 4096

IO.write(
  Jason.encode!(%{
    "merge" => summarize.(merge_metrics),
    "manifest" => summarize.(manifest_metrics),
    "maximum_summary_bytes" => summaries |> Enum.map(& &1.byte_count) |> Enum.max(),
    "maximum_summary_packed_bytes" =>
      summaries |> Enum.map(&Protocol.packed_bytes(&1.value)) |> Enum.max(),
    "native_operations" => 0,
    "model_calls" => 0
  })
)
