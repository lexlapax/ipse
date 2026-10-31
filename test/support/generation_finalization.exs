import ExUnit.Assertions
paged = Keyword.get(binding(), :paged, false)

prefix =
  File.read!("test/support/collection_directory.exs")
  |> String.split("# Pure protocol fixture:")
  |> hd()

{_, bindings} = Code.eval_string(prefix)
fetch = fn key -> Keyword.fetch!(bindings, key) end
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection, as: C
alias IpseKnowledge.Store.Collection.Directory, as: D
alias IpseKnowledge.Store.Collection.Finalization, as: F
alias IpseKnowledge.Store.Collection.Job
json = &IO.iodata_to_binary(JSON.encode!(&1))
profile = fetch.(:profile)
catalog = fetch.(:catalog)
summaries = Enum.map(fetch.(:summaries), &D.immutable("notes", "gensum", &1))

values =
  Map.new(summaries, &{&1.key, &1.value})
  |> Map.merge(Map.new(fetch.(:catalog_pages), &{"catalog.notes.#{&1["ordinal"]}", &1}))

job =
  fetch.(:job)
  |> Map.put("status", "manifests")
  |> Map.put("cursor", 136)
  |> Map.put("summaries", Enum.map(summaries, &D.reference/1))
  |> Map.put("facts", 136)

assert Job.valid?(job, profile)

# The durable job and immutable inputs are reconstructed at every pure step.
# Proposed values are recorded only in this private test map, never sent to Core.
load = fn load, current, stored, loaded, reads ->
  case F.plan(current, loaded, paged) do
    {:need, ref} ->
      value = Map.fetch!(stored, ref["key"])

      load.(
        load,
        current,
        stored,
        Map.put(loaded, ref["key"], value),
        reads + div(byte_size(json.(value)) + 6143, 6144) + 2
      )

    result ->
      {result, reads}
  end
end

reduce = fn reduce, current, stored, phases, max_reads, max_bytes, inputs ->
  inputs = inputs ++ [{current, stored}]
  {{:ok, planned}, reads} = load.(load, current, stored, %{}, 0)
  assert reads < 512
  assert Job.valid?(planned.job, profile)
  max_bytes = max(max_bytes, byte_size(json.(planned.job)))
  stored = Map.merge(stored, Map.new(planned.values, &{&1.key, &1.value}))

  if planned.root do
    {planned, stored, phases + 1, max(max_reads, reads), max_bytes, current, inputs}
  else
    reduce.(reduce, planned.job, stored, phases + 1, max(max_reads, reads), max_bytes, inputs)
  end
end

{final, stored, phases, max_reads, max_bytes, preselection, phase_inputs} =
  reduce.(reduce, job, values, 0, 0, 0, [])

{:ok, canonical} = D.pack(profile, catalog, fetch.(:catalog_pages), fetch.(:summaries), 8)

expected_root =
  if paged do
    expected =
      Map.take(
        final.root,
        ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
      )
      |> Map.put("root_sha256", E.sha256(json.(final.root)))

    {:ok, actual_rows} = D.entity_rows(final.root, stored, expected)
    old_values = Map.new(canonical.values, &{&1.key, &1.value})

    old_expected =
      Map.take(
        canonical.root,
        ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
      )
      |> Map.put("root_sha256", canonical.root_unit.sha256)

    {:ok, old_rows} = D.entity_rows(canonical.root, old_values, old_expected)
    assert actual_rows === old_rows
    assert final.root["manifests"] === canonical.root["manifests"]
    assert final.root["source_heads_sha256"] === canonical.root["source_heads_sha256"]
    refute Map.has_key?(final.root, "entity_rows_sha256")
    final.root
  else
    assert final.root === canonical.root
    canonical.root
  end

assert final.job["status"] == "selected"
assert length(final.prerequisites) == if(paged, do: 11, else: 7)
assert {:error, _} = F.plan(final.job, stored)

assert {:error, _} =
         F.plan(
           %{
             preselection
             | "reduction" => %{preselection["reduction"] | "heads_sha256" => "bad"}
           },
           stored
         )

records =
  Map.new(stored, fn {k, v} -> {k, {v, 498}} end)
  |> Map.merge(%{
    "catalog.notes" => {catalog, 500},
    "generation.notes" => {fetch.(:directory).root, 17},
    "genjob.notes" => {preselection, 499}
  })

token = %{
  "version" => 1,
  "id" => job["id"],
  "plan_sha256" => nil,
  "job_revision" => 499,
  "root_revision" => 17,
  "catalog_sha256" => job["catalog_sha256"],
  "unit" => 0,
  "write" => nil,
  "stages" => []
}

args = %{
  "action" => if(paged, do: "finalize_paged", else: "finalize"),
  "vector_selection" => job["vector_selection"],
  "fact_selection" => job["fact_selection"],
  "continuation" => token,
  "group" => nil
}

walk = fn walk, result, records, stages, reads ->
  assert length(reads) < 512

  case result do
    {:call, request, continuation} ->
      r = request["request"]

      if C.read_request?(request) do
        record = records[r["key"]]

        descriptor =
          if record,
            do:
              (fn {v, rev} ->
                 %{
                   "revision" => rev,
                   "sha256" => E.sha256(json.(v)),
                   "byte_count" => byte_size(json.(v))
                 }
               end).(record)

        reply =
          case r["op"] do
            "snapshot" ->
              %{
                "generation" => 500,
                "floor" => 3,
                "document_store" => %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2}
              }

            "value.stat" ->
              %{"generation" => 500, "key" => r["key"], "record" => descriptor}

            "value.read" ->
              bytes = json.(elem(record, 0))
              offset = r["offset"]
              data = binary_part(bytes, offset, min(6144, byte_size(bytes) - offset))
              next = offset + byte_size(data)

              Map.merge(descriptor, %{
                "generation" => 500,
                "key" => r["key"],
                "offset" => offset,
                "next" => if(next < byte_size(bytes), do: next),
                "data" => data
              })

            "stage.list" ->
              %{"generation" => 500, "stages" => []}

            "stage.inspect" ->
              %{"generation" => 500, "stage" => Map.fetch!(stages, {r["slot"], r["epoch"]})}
          end

        {:ok, digest} = Ipse.Extension.canonical_digest([request])

        outcome = %{
          "status" => "ok",
          "value" => %{
            "version" => 1,
            "operation_id" => String.duplicate("a", 32),
            "request_sha256" => digest,
            "result" => reply
          }
        }

        walk.(walk, C.resume(continuation, outcome), records, stages, reads ++ [r])
      else
        {:effect, request, continuation, reads}
      end

    other ->
      {:terminal, other, reads}
  end
end

phase_reads =
  Enum.map(phase_inputs, fn {current, supplied} ->
    supplied =
      Map.new(supplied, fn {k, v} -> {k, {v, 498}} end)
      |> Map.merge(%{
        "catalog.notes" => {catalog, 500},
        "generation.notes" => {fetch.(:directory).root, 17},
        "genjob.notes" => {current, 499}
      })

    {:effect, _, continuation, reads} =
      walk.(walk, C.start(profile, :generation_job, args), supplied, %{}, [])

    assert C.resume(continuation, %{"status" => "unknown"}) == {:stop, :unknown_effect}
    assert continuation.generation_job.next_job["status"] in ~w(reducing selected)
    length(reads)
  end)

{:effect, first, first_cont, first_reads} =
  walk.(walk, C.start(profile, :generation_job, args), records, %{}, [])

assert first["request"]["key"] == "genjob.notes"
assert C.resume(first_cont, %{"status" => "unknown"}) == {:stop, :unknown_effect}

assert {:done, {:error, :document_store_deadline_unavailable, _}} =
         C.resume(first_cont, %{
           "status" => "failed",
           "value" => %{"code" => "document_store_deadline_unavailable"}
         })

s = first_cont.generation_job
assert s.metadata_count == 3 and s.immutable == 0

refs =
  for slot <- 0..2,
      do: %{"slot" => slot, "epoch" => String.duplicate(Integer.to_string(slot + 1), 32)}

stages =
  Enum.zip(refs, s.units)
  |> Map.new(fn {r, u} ->
    bytes = json.(u.value)

    {{r["slot"], r["epoch"]},
     Map.merge(r, %{
       "state" => "sealed",
       "key" => u.key,
       "sha256" => E.sha256(bytes),
       "byte_count" => byte_size(bytes),
       "offset" => byte_size(bytes),
       "expected_revision" => u.revision
     })}
  end)

complete =
  token |> Map.put("plan_sha256", s.plan_sha) |> Map.put("unit", 3) |> Map.put("stages", refs)

complete_args = %{args | "continuation" => complete}

{:effect, commit, committed, reads} =
  walk.(walk, C.start(profile, :generation_job, complete_args), records, stages, [])

assert commit["request"] == %{"op" => "commit", "generation" => 500, "stages" => refs}

assert Enum.count(
         reads,
         &(&1["op"] == "value.stat" and
             &1["key"] in Enum.map(final.prerequisites, fn r -> r["key"] end))
       ) == length(final.prerequisites) * 2

assert List.last(reads)["op"] == "value.stat"
assert C.resume(committed, %{"status" => "unknown"}) == {:stop, :unknown_effect}
{:ok, digest} = Ipse.Extension.canonical_digest([commit])

outcome = %{
  "status" => "ok",
  "value" => %{
    "version" => 1,
    "operation_id" => String.duplicate("b", 32),
    "request_sha256" => digest,
    "result" => %{"generation" => 501}
  }
}

assert {:done, {:ok, selected}} = C.resume(committed, outcome)
assert selected["status"] == "selected" and selected["coverage"]["selected_changed"]
assert selected["continuation"]["job_revision"] == 501

current =
  records
  |> Map.put("generation.notes", {final.root, 500})
  |> Map.put("genjob.notes", {final.job, 500})

assert {:terminal, {:done, {:ok, inspected}}, _} =
         walk.(
           walk,
           C.start(profile, :generation_job, %{
             args
             | "action" => "inspect",
               "continuation" => nil
           }),
           current,
           %{},
           []
         )

refute inspected["stale"]
missing = Map.delete(records, hd(final.prerequisites)["key"])

assert {:terminal, {:done, {:error, :generation_prerequisite_missing, _}}, _} =
         walk.(walk, C.start(profile, :generation_job, complete_args), missing, stages, [])

changed = put_in(records, ["catalog.notes"], {Map.put(catalog, "floor", 4), 500})

assert {:terminal, {:done, {:error, :generation_job_changed, _}}, _} =
         walk.(walk, C.start(profile, :generation_job, args), changed, %{}, [])

if paged do
  root_expected = fn root ->
    Map.take(
      root,
      ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
    )
    |> Map.put("root_sha256", E.sha256(json.(root)))
  end

  reroot = fn pages ->
    final.root
    |> Map.put("entity_pages", pages)
    |> Map.put(
      "entity_pages_sha256",
      IpseKnowledge.Store.Collection.Paged.commitment(
        pages,
        final.root["entities"],
        final.root["groups"]
      )
    )
  end

  headers = Map.new(fetch.(:summaries), &{&1["ref"]["key"], &1["header"]})

  {:ok, lookup} =
    D.lookup(
      final.root,
      Map.merge(stored, headers),
      [hd(hd(fetch.(:catalog_pages))["rows"])["source_key"]],
      root_expected.(final.root)
    )

  assert lookup["coverage"]["directory_complete"] and length(lookup["groups"]) == 1
  reversed = reroot.(Enum.reverse(final.root["entity_pages"]))
  assert D.valid_root?(reversed, root_expected.(reversed))

  assert {:error, :generation_directory_corrupt} =
           D.entity_rows(reversed, stored, root_expected.(reversed))

  duplicated =
    reroot.(List.replace_at(final.root["entity_pages"], 1, hd(final.root["entity_pages"])))

  refute D.valid_root?(duplicated, root_expected.(duplicated))
  page_refs = final.root["entity_pages"]
  first_page = stored[hd(page_refs)["key"]]
  second_ref = Enum.at(page_refs, 1)
  second_page = stored[second_ref["key"]]

  cross_duplicate =
    Map.put(
      second_page,
      "rows",
      List.replace_at(second_page["rows"], 0, List.last(first_page["rows"]))
    )

  for bad_page <- [
        cross_duplicate,
        Map.put(second_page, "version", 2.0),
        put_in(second_page, ["rows", Access.at(0), Access.at(2)], [final.root["groups"]])
      ] do
    bad = D.immutable("notes", "genent", bad_page)
    bad_root = reroot.(List.replace_at(page_refs, 1, D.reference(bad)))
    assert D.valid_root?(bad_root, root_expected.(bad_root))

    assert {:error, :generation_directory_corrupt} =
             D.entity_rows(
               bad_root,
               Map.put(stored, bad.key, bad.value),
               root_expected.(bad_root)
             )
  end

  assert {:error, :generation_directory_corrupt} =
           D.entity_rows(
             final.root,
             Map.delete(stored, hd(page_refs)["key"]),
             root_expected.(final.root)
           )

  {checking, supplied} =
    Enum.find(phase_inputs, fn {j, _} ->
      j["version"] == 3 and j["reduction"]["phase"] == "entity_digest"
    end)

  for altered <- [
        Map.put(checking["reduction"], "digest_cursor", 1),
        Map.put(checking["reduction"], "verified_entities", 32),
        Map.put(checking["reduction"], "last_entity_id", String.duplicate("a", 64))
      ] do
    refute Job.valid?(Map.put(checking, "reduction", altered), profile)
  end

  assert {:error, :invalid_generation_finalization} = F.plan(checking, supplied, false)
  {initial, initial_values} = hd(phase_inputs)
  {:ok, old_phase} = F.plan(initial, initial_values, false)
  assert old_phase.job["version"] == 2
  assert {:error, :invalid_generation_finalization} = F.plan(old_phase.job, initial_values, true)

  supplied =
    Map.new(supplied, fn {k, v} -> {k, {v, 498}} end)
    |> Map.merge(%{
      "catalog.notes" => {catalog, 500},
      "generation.notes" => {fetch.(:directory).root, 17},
      "genjob.notes" => {checking, 499}
    })

  {:effect, _, semantic_continuation, _} =
    walk.(walk, C.start(profile, :generation_job, args), supplied, %{}, [])

  semantic = semantic_continuation.generation_job
  missing = Map.delete(supplied, hd(checking["reduction"]["entity_pages"])["key"])

  for unit <- 0..2 do
    edited =
      token
      |> Map.put("plan_sha256", semantic.plan_sha)
      |> Map.put("unit", unit)
      |> Map.put("stages", Enum.take(refs, unit))

    assert {:terminal, {:done, {:error, :generation_job_changed, _}}, _} =
             walk.(
               walk,
               C.start(profile, :generation_job, %{args | "continuation" => edited}),
               missing,
               %{},
               []
             )
  end

  assert {:done, {:error, :invalid_generation_job_request, _}} =
           C.start(profile, :generation_job, %{
             args
             | "continuation" => Map.put(token, "digest_cursor", 9)
           })

  path =
    Path.join(System.tmp_dir!(), "ipse-retained-root2-#{System.unique_integer([:positive])}.json")

  File.write!(
    path,
    Jason.encode!(%{"root" => final.root, "expected" => root_expected.(final.root)})
  )

  try do
    # This source matches the executable checksum of the historical module
    # recorded in shared-job-prerequisites/manifest.json. Compile it in a fresh
    # VM so the compatibility check does not depend on a local build cache.
    old = Path.expand("test/support/legacy_directory_v1.ex")
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {"old_root2_refused", 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          [
            "-e",
            "Code.compiler_options(no_warn_undefined: :all); Code.compile_file(\"extensions/knowledge/src/evidence.ex\"); Code.compile_file(Enum.at(System.argv(), 0)); i=Jason.decode!(File.read!(Enum.at(System.argv(), 1))); false=IpseKnowledge.Store.Collection.Directory.valid_root?(i[\"root\"],i[\"expected\"]); {:error,:generation_directory_corrupt}=IpseKnowledge.Store.Collection.Directory.lookup(i[\"root\"],%{},[String.duplicate(\"a\",64)],i[\"expected\"]); IO.write(\"old_root2_refused\")",
            old,
            path
          ],
        stderr_to_stdout: true
      )
  after
    File.rm!(path)
  end
end

IO.write(
  Jason.encode!(%{
    "phases" => phases,
    "selection_stages" => 3,
    "canonical_equal" => final.root === expected_root,
    "root_version" => final.root["version"],
    "max_reduction_reads" => max_reads,
    "max_job_bytes" => max_bytes,
    "selection_reads" => length(reads),
    "initial_selection_reads" => length(first_reads),
    "phase_protocol_reads" => phase_reads,
    "native_operations" => 0,
    "protected_publication_demonstrated" => false
  })
)
