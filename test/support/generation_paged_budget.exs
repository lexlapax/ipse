import ExUnit.Assertions
Code.require_file("test/support/collection_protocol.exs")
alias IpseTest.CollectionProtocol, as: Protocol
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection, as: C
alias IpseKnowledge.Store.Collection.{Directory, Paged, Finalization, Job}
json = &IO.iodata_to_binary(JSON.encode!(&1))
partition = "abcdefghijklmnop"
profile = %{"kind" => "collection", "scope" => "project", "partition" => partition}
maximum = 9_007_199_254_740_991
epoch = maximum - 991

selection = %{
  "selection_sha256" => E.sha256("budget"),
  "profile" => String.duplicate(<<0>>, 128),
  "model" => String.duplicate(<<0>>, 128),
  "dimensions" => 1024,
  "encoding" => "float32le"
}

extraction = %{
  "kind" => "model_complete",
  "profile" => String.duplicate(<<0>>, 128),
  "version" => 1
}

heads =
  for n <- 0..999,
      do: %{"source_key" => E.sha256("source#{n}"), "head_sha256" => E.sha256("head#{n}")}

catalog_pages =
  heads
  |> Enum.chunk_every(16)
  |> Enum.with_index()
  |> Enum.map(fn {rows, n} ->
    %{
      "version" => 1,
      "kind" => "catalog_page",
      "partition" => partition,
      "ordinal" => n,
      "rows" => Enum.sort_by(rows, & &1["source_key"])
    }
  end)

heads = Enum.flat_map(catalog_pages, & &1["rows"])

catalog = %{
  "version" => 1,
  "kind" => "catalog",
  "partition" => partition,
  "generation" => maximum,
  "floor" => maximum,
  "sources" => 1000,
  "extracted_bytes" => 20 * 1024 * 1024,
  "chunks" => 10_000,
  "entities" => 5000,
  "assertions" => 20_000,
  "pages" =>
    Enum.map(
      catalog_pages,
      &%{"key" => "catalog.#{partition}.#{&1["ordinal"]}", "sha256" => E.sha256(json.(&1))}
    )
}

assert C.valid_catalog?(catalog, profile)

manifests =
  heads
  |> Enum.chunk_every(8)
  |> Enum.with_index()
  |> Enum.map(fn {sources, n} ->
    %{
      "cursor" => n * 8,
      "sources" => Enum.map(sources, &[&1["source_key"], &1["head_sha256"]]),
      "header" => %{
        "key" => "gengrp.#{partition}." <> E.sha256("header#{n}"),
        "sha256" => E.sha256("header#{n}"),
        "byte_count" => 49_152
      }
    }
  end)
  |> Enum.chunk_every(16)
  |> Enum.with_index()
  |> Enum.map(fn {rows, n} ->
    Directory.immutable(partition, "genman", %{
      "version" => 1,
      "kind" => "generation_manifest",
      "recipe" => "ipse.evidence.shared_directory.v1",
      "ordinal" => n,
      "rows" => rows
    })
  end)

rows =
  for n <- 0..4999 do
    label = String.duplicate("\\", 251) <> (Integer.to_string(n) |> String.pad_leading(5, "0"))
    [E.id("entity", [partition, label]), label, [rem(n, 125)]]
  end
  |> Enum.sort_by(&hd/1)
  |> Enum.with_index()
  |> Enum.map(fn {[id, label, groups], n} ->
    [id, label, if(n < 32, do: Enum.to_list(0..124), else: groups)]
  end)

entities =
  rows
  |> Enum.chunk_every(32)
  |> Enum.with_index()
  |> Enum.map(fn {rows, n} ->
    Directory.immutable(partition, "genent", %{
      "version" => 2,
      "kind" => "generation_entities",
      "recipe" => "ipse.evidence.shared_directory.v2",
      "ordinal" => n,
      "rows" => rows
    })
  end)

assert Enum.all?(entities ++ manifests, &Paged.native_value?(&1.value))
values = Map.new(entities ++ manifests, &{&1.key, &1.value})
refs = Enum.map(entities, &Directory.reference/1)

Enum.reduce(0..156, nil, fn n, previous ->
  {:ok, checked} = Paged.verify(partition, refs, values, 5000, 125, n, previous)
  checked.last
end)

manifest_refs = Enum.map(manifests, &Directory.reference/1)

old = %{
  "version" => 1,
  "kind" => "shared_generation_directory",
  "recipe" => "ipse.evidence.shared_directory.v1",
  "partition" => partition,
  "generation" => maximum - 1,
  "catalog_sha256" => E.sha256(json.(catalog)),
  "catalog_generation" => maximum,
  "floor" => maximum,
  "sources" => 1000,
  "extracted_bytes" => 20 * 1024 * 1024,
  "chunks" => 10_000,
  "vectors" => 10_000,
  "facts" => 20_000,
  "entities" => 5000,
  "groups" => 125,
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "source_heads_sha256" => E.sha256(json.(%{"rows" => heads})),
  "entity_rows_sha256" => E.sha256("trusted-old-row-digest"),
  "manifests" => manifest_refs,
  "entity_pages" => Enum.take(refs, 79)
}

reduction = %{
  "phase" => "select",
  "recipe" => "ipse.evidence.shared_directory.v2",
  "batch" => 8,
  "manifests" => manifest_refs,
  "runs" => [],
  "positions" => [],
  "entity_pages" => refs,
  "entities" => 5000,
  "text_bytes" => catalog["extracted_bytes"],
  "chunks" => 10_000,
  "facts" => 20_000,
  "heads_sha256" => old["source_heads_sha256"],
  "entity_pages_sha256" => Paged.commitment(refs, 5000, 125),
  "digest_cursor" => 157,
  "verified_entities" => 5000,
  "last_entity_id" => hd(List.last(rows))
}

job = %{
  "version" => 3,
  "kind" => "shared_generation_job",
  "id" => String.duplicate("f", 32),
  "partition" => partition,
  "status" => "reducing",
  "catalog" => catalog,
  "catalog_sha256" => E.sha256(json.(catalog)),
  "generation" => maximum,
  "root_revision" => epoch - 1000,
  "root_sha256" => E.sha256(json.(old)),
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "cursor" => 1000,
  "summaries" => [],
  "facts" => 20_000,
  "reduction" => reduction
}

assert Job.valid?(job, profile)
{:ok, expected} = Finalization.selected_root(job)

records =
  Map.merge(values, %{
    "catalog.#{partition}" => catalog,
    "generation.#{partition}" => old,
    "genjob.#{partition}" => job
  })

model = Protocol.new(records, epoch)

token = %{
  "version" => 1,
  "id" => job["id"],
  "plan_sha256" => nil,
  "job_revision" => epoch - 1000,
  "root_revision" => epoch - 1000,
  "catalog_sha256" => job["catalog_sha256"],
  "unit" => 0,
  "write" => nil,
  "stages" => []
}

args = %{
  "action" => "finalize_paged",
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "continuation" => token,
  "group" => nil
}

{{:done, {:ok, selected}}, final} = Protocol.run(C.start(profile, :generation_job, args), model)
assert selected["job"]["status"] == "selected" and selected["coverage"]["selected_changed"]
assert final.records["generation.#{partition}"].value === expected
assert final.records["catalog.#{partition}"].value === catalog
assert final.records["genjob.#{partition}"].value === selected["job"]

proof_reads =
  Enum.count(
    final.requests,
    &(get_in(&1, ["request", "op"]) == "value.stat" and
        get_in(&1, ["request", "key"]) in Enum.map(manifest_refs ++ refs, fn r -> r["key"] end))
  )

assert proof_reads == 330
assert List.last(final.requests)["request"]["op"] == "commit"
assert Enum.at(final.requests, -2)["request"]["op"] == "value.stat"
assert List.last(final.requests)["request"]["generation"] == final.generation - 1

# A known fully prepared set lets each explicit metadata position be resumed.
# These are new invocations; counters reset, physical row revisions do not.
stop = fn request, _ ->
  if get_in(request, ["request", "op"]) == "commit" and
       length(get_in(request, ["request", "stages"])) == 3,
     do: :stop,
     else: :continue
end

{{:call, _, before_commit}, prepared} =
  Protocol.run(C.start(profile, :generation_job, args), model, stop)

state = before_commit.generation_job
assert prepared.records["generation.#{partition}"].value === old

resumes =
  for unit <- 0..3 do
    resume =
      token
      |> Map.put("plan_sha256", state.plan_sha)
      |> Map.put("unit", unit)
      |> Map.put("stages", Enum.take(state.stages, unit))

    {{:done, {:ok, resumed}}, measured} =
      Protocol.run(
        C.start(profile, :generation_job, %{args | "continuation" => resume}),
        Protocol.reset(prepared)
      )

    assert resumed["status"] == "selected" and
             measured.records["generation.#{partition}"].value === expected

    assert measured.reads <= 512 and measured.effects <= 16

    missing =
      %{prepared | records: Map.delete(prepared.records, List.last(refs)["key"])}
      |> Protocol.reset()

    {{:done, {:error, :generation_prerequisite_missing, _}}, denied} =
      Protocol.run(C.start(profile, :generation_job, %{args | "continuation" => resume}), missing)

    assert denied.effects == 0

    %{
      "unit" => unit,
      "reads" => measured.reads,
      "effects" => measured.effects,
      "maximum_frame_bytes" => Enum.max(measured.frames)
    }
  end

# One worst-width semantic page is fully loaded and checked before either
# metadata value is prepared. It is a bounded durable step, not a flat digest.
checking =
  job
  |> put_in(["reduction", "phase"], "entity_digest")
  |> put_in(["reduction", "digest_cursor"], 0)
  |> put_in(["reduction", "verified_entities"], 0)
  |> put_in(["reduction", "last_entity_id"], nil)
  |> put_in(["reduction", "entity_pages_sha256"], nil)

assert Job.valid?(checking, profile)

page_model = %{
  model
  | records:
      Map.put(model.records, "genjob.#{partition}", %{value: checking, revision: epoch - 1000})
}

{{:done, {:ok, verified}}, page_budget} =
  Protocol.run(C.start(profile, :generation_job, args), page_model)

assert verified["job"]["reduction"]["digest_cursor"] == 1
assert verified["job"]["reduction"]["verified_entities"] == 32
assert verified["job"]["reduction"]["last_entity_id"] == hd(List.last(hd(entities).value["rows"]))
assert page_budget.records["generation.#{partition}"].value === old
assert page_budget.reads <= 512 and page_budget.effects <= 16

# Produce an actual client checkpoint after one known packet, with a declared
# fifteen earlier effects in that fixture invocation. The shared job must
# recompute its semantic input before resuming those exact remaining bytes.
first_effect = fn request, _ -> if C.read_request?(request), do: :continue, else: :stop end

{{:call, _, page_continuation}, _} =
  Protocol.run(C.start(profile, :generation_job, args), page_model, first_effect)

page_plan = page_continuation.generation_job
unit = hd(page_plan.units)
prior_budget = %{page_model | effects: 15}

{{:done, {:continue, partial}}, partial_model} =
  Protocol.run(
    C.start(profile, :value_prepare, %{
      "key" => unit.key,
      "value" => unit.value,
      "expected_revision" => unit.revision,
      "reuse" => false,
      "continuation" => nil,
      "effects_used" => 15
    }),
    prior_budget
  )

assert partial["continuation"]["active"]["offset"] > 0

resume =
  token |> Map.put("plan_sha256", page_plan.plan_sha) |> Map.put("write", partial["continuation"])

{{:done, {:ok, recovered}}, recovered_model} =
  Protocol.run(
    C.start(profile, :generation_job, %{args | "continuation" => resume}),
    Protocol.reset(partial_model)
  )

assert recovered["job"] === verified["job"]
assert recovered_model.records["generation.#{partition}"].value === old

missing_page =
  %{partial_model | records: Map.delete(partial_model.records, hd(refs)["key"])}
  |> Protocol.reset()

{{:done, {:error, :generation_job_changed, _}}, refused_partial} =
  Protocol.run(
    C.start(profile, :generation_job, %{args | "continuation" => resume}),
    missing_page
  )

assert refused_partial.effects == 0
job_native = Protocol.packed_bytes(selected["job"])
root_native = Protocol.packed_bytes(expected)
assert job_native <= 65_536 and root_native <= 65_536

IO.write(
  Jason.encode!(%{
    "references" => 165,
    "proof_reads" => proof_reads,
    "reads" => final.reads,
    "effects" => final.effects,
    "maximum_frame_bytes" => Enum.max(final.frames),
    "maximum_parts" => Enum.max(final.part_counts),
    "root_bytes" => byte_size(json.(expected)),
    "job_bytes" => byte_size(json.(selected["job"])),
    "catalog_bytes" => byte_size(json.(catalog)),
    "maximum_counter" => maximum,
    "root_native_packed_bytes" => root_native,
    "job_native_packed_bytes" => job_native,
    "metadata_resumes" => resumes,
    "per_page_reads" => page_budget.reads,
    "per_page_effects" => page_budget.effects,
    "known_partial_offset" => partial["continuation"]["active"]["offset"],
    "known_partial_resume_reads" => recovered_model.reads,
    "known_partial_resume_effects" => recovered_model.effects,
    "native_operations" => 0,
    "model_calls" => 0
  })
)
