# Pure protocol controls. No read/effect continuation is dispatched to a host.
import ExUnit.Assertions

prefix =
  File.read!("test/support/collection_directory.exs")
  |> String.split("# Pure protocol fixture:")
  |> hd()

{_, bindings} = Code.eval_string(prefix)
fetch = fn key -> Keyword.fetch!(bindings, key) end
alias IpseKnowledge.Store.Collection, as: C
alias IpseKnowledge.Store.Collection.Generation, as: G
profile = fetch.(:profile)
job = fetch.(:job)
catalog = fetch.(:catalog)
selection = fetch.(:selection)
extraction = fetch.(:extraction)
{bundles, data} = fetch.(:inputs) |> Enum.take(8) |> Enum.unzip()
{:ok, group} = G.pack_group("notes", 0, bundles, data, selection, extraction)
json = &IO.iodata_to_binary(JSON.encode!(&1))
sha = &IpseKnowledge.Evidence.sha256/1

records = %{
  "catalog.notes" => {catalog, 500},
  "generation.notes" => {fetch.(:directory).root, 17},
  "genjob.notes" => {job, 499}
}

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
  "action" => "append",
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "group" => %{
    "plan" => group,
    "bundles" => bundles,
    "catalog_page" => hd(fetch.(:catalog_pages))
  },
  "continuation" => token
}

walk = fn walk, result, records, stages, reads ->
  assert length(reads) < 512

  case result do
    {:call, request, continuation} ->
      r = request["request"]

      if C.read_request?(request) do
        record =
          if r["op"] == "value.stat" and r["key"] == "generation.notes" and
               Map.get(stages, :change_root_after_stage, false) and
               Enum.any?(reads, &(&1["op"] == "stage.inspect")) do
            {Map.put(fetch.(:directory).root, "generation", 999), 498}
          else
            records[r["key"]]
          end

        descriptor =
          if record,
            do:
              (fn {v, rev} ->
                 bytes = json.(v)
                 %{"revision" => rev, "sha256" => sha.(bytes), "byte_count" => byte_size(bytes)}
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
              Map.merge(descriptor, %{
                "generation" => 500,
                "key" => r["key"],
                "offset" => 0,
                "next" => nil,
                "data" => json.(elem(record, 0))
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

{:effect, ordinary, ordinary_cont, _} =
  walk.(walk, C.start(profile, :generation_job, args), records, %{}, [])

assert String.starts_with?(ordinary["request"]["key"], "gensrc.notes.")
s = ordinary_cont.generation_job
required = Enum.take(s.units, s.immutable)

refs =
  for slot <- 0..1,
      do: %{"slot" => slot, "epoch" => String.duplicate(Integer.to_string(slot + 1), 32)}

for advance <- 0..1 do
  edited =
    token
    |> Map.put("plan_sha256", s.plan_sha)
    |> Map.put("unit", s.immutable + advance)
    |> Map.put("stages", Enum.take(refs, advance))

  assert {:terminal, {:done, {:error, :generation_prerequisite_missing, _}}, reads} =
           walk.(
             walk,
             C.start(profile, :generation_job, %{args | "continuation" => edited}),
             records,
             %{},
             []
           )

  assert Enum.any?(reads, &(&1["op"] == "value.stat" and &1["key"] == hd(required).key))
  refute Enum.any?(reads, &(&1["op"] == "stage.inspect"))
end

present = Map.merge(records, Map.new(required, &{&1.key, {&1.value, 498}}))
metadata_token = token |> Map.put("plan_sha256", s.plan_sha) |> Map.put("unit", s.immutable)
metadata_args = %{args | "continuation" => metadata_token}

{:effect, metadata, _, reads} =
  walk.(walk, C.start(profile, :generation_job, metadata_args), present, %{}, [])

assert metadata["request"]["key"] == "genjob.notes"

for unit <- required,
    do: assert(Enum.count(reads, &(&1["op"] == "value.stat" and &1["key"] == unit.key)) == 1)

for altered <- [
      Map.delete(present, hd(required).key),
      Map.put(present, hd(required).key, {%{"altered" => true}, 498})
    ] do
  assert {:terminal, {:done, {:error, :generation_prerequisite_missing, _}}, _} =
           walk.(walk, C.start(profile, :generation_job, metadata_args), altered, %{}, [])
end

stages =
  Enum.zip(refs, Enum.drop(s.units, s.immutable))
  |> Map.new(fn {ref, u} ->
    bytes = json.(u.value)

    {{ref["slot"], ref["epoch"]},
     Map.merge(ref, %{
       "state" => "sealed",
       "key" => u.key,
       "expected_revision" => u.revision,
       "sha256" => sha.(bytes),
       "byte_count" => byte_size(bytes),
       "offset" => byte_size(bytes)
     })}
  end)

complete_token = metadata_token |> Map.put("unit", length(s.units)) |> Map.put("stages", refs)

assert {:terminal, {:done, {:error, :generation_job_changed, _}}, changed_reads} =
         walk.(
           walk,
           C.start(profile, :generation_job, %{args | "continuation" => complete_token}),
           present,
           Map.put(stages, :change_root_after_stage, true),
           []
         )

assert Enum.count(changed_reads, &(&1["op"] == "stage.inspect")) == 2

{:effect, commit, commit_cont, reads} =
  walk.(
    walk,
    C.start(profile, :generation_job, %{args | "continuation" => complete_token}),
    present,
    stages,
    []
  )

assert commit["request"]["op"] == "commit" and commit["request"]["generation"] == 500

checks =
  Enum.filter(
    reads,
    &(&1["op"] == "value.stat" and &1["key"] in Enum.map(required, fn u -> u.key end))
  )

assert length(checks) == length(required)
assert List.last(reads)["op"] == "value.stat"

for altered <- [
      Map.delete(present, hd(required).key),
      Map.put(present, hd(required).key, {%{"altered" => true}, 498})
    ] do
  assert {:terminal, {:done, {:error, :generation_prerequisite_missing, _}}, _} =
           walk.(
             walk,
             C.start(profile, :generation_job, %{args | "continuation" => complete_token}),
             altered,
             stages,
             []
           )
end

assert {:stop, :unknown_effect} = C.resume(commit_cont, %{"status" => "unknown"})
{:ok, digest} = Ipse.Extension.canonical_digest([commit])

wrong = %{
  "status" => "ok",
  "value" => %{
    "version" => 1,
    "operation_id" => String.duplicate("a", 32),
    "request_sha256" => digest,
    "result" => %{"generation" => 502}
  }
}

assert {:stop, :unknown_effect} = C.resume(commit_cont, wrong)
correct = put_in(wrong, ["value", "result", "generation"], 501)

assert {:done, {:ok, %{"continuation" => %{"job_revision" => 501}}}} =
         C.resume(commit_cont, correct)

# Bind the selected input before any immutable group unit. The mocked transport
# stops at each effect; the separate native tests cover the host CAS boundary.
owner = %{
  "project_id" => sha.("project"),
  "session_id" => String.duplicate("a", 32),
  "identity_sha256" => sha.("identity")
}

{:ok, sources_sha} = Ipse.Extension.canonical_digest([hd(fetch.(:summaries))["sources"]])

binding = %{
  "version" => 1,
  "ref_sha256" => sha.("reference"),
  "raw_sha256" => sha.("body"),
  "source_set_sha256" => sources_sha,
  "cursor" => 0,
  "vector_job_revision" => 499,
  "owner" => owner
}

bound_records =
  Map.put(
    records,
    "genjob.notes",
    {Map.merge(job, %{"version" => 7, "input_binding" => nil}), 499}
  )

bind_args = %{
  "action" => "bind",
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "group" => %{"input_binding" => binding, "input_owner" => owner},
  "continuation" => token
}

{:effect, bind_effect, bind_cont, _} =
  walk.(
    walk,
    IpseKnowledge.Store.Collection.Job.bind_input(profile, bind_args),
    bound_records,
    %{},
    []
  )

assert bind_effect["request"]["key"] == "genjob.notes"
bind_state = bind_cont.generation_job
assert bind_state.immutable == 0
assert bind_state.next_job["input_binding"] === binding

for altered <- [
      put_in(bind_args, ["group", "input_binding", "vector_job_revision"], 498),
      put_in(bind_args, ["group", "input_binding", "cursor"], 8),
      put_in(bind_args, ["group", "input_owner", "session_id"], String.duplicate("b", 32)),
      put_in(bind_args, ["continuation", "job_revision"], 498)
    ] do
  assert {:terminal, {:done, {:error, _, _}}, _} =
           walk.(
             walk,
             IpseKnowledge.Store.Collection.Job.bind_input(profile, altered),
             bound_records,
             %{},
             []
           )
end

bind_stages =
  Enum.zip(refs, bind_state.units)
  |> Map.new(fn {ref, unit} ->
    bytes = json.(unit.value)

    {{ref["slot"], ref["epoch"]},
     Map.merge(ref, %{
       "state" => "sealed",
       "key" => unit.key,
       "expected_revision" => unit.revision,
       "sha256" => sha.(bytes),
       "byte_count" => byte_size(bytes),
       "offset" => byte_size(bytes)
     })}
  end)

bind_token =
  token
  |> Map.put("plan_sha256", bind_state.plan_sha)
  |> Map.put("unit", 2)
  |> Map.put("stages", refs)

{:effect, bind_commit, bind_commit_cont, _} =
  walk.(
    walk,
    IpseKnowledge.Store.Collection.Job.bind_input(profile, %{
      bind_args
      | "continuation" => bind_token
    }),
    bound_records,
    bind_stages,
    []
  )

assert bind_commit["request"]["op"] == "commit"
assert bind_commit["source_guard"] == "explicit_fact_group_v1"
assert {:stop, :unknown_effect} = C.resume(bind_commit_cont, %{"status" => "unknown"})

swapped = put_in(bind_args, ["group", "input_binding", "ref_sha256"], sha.("other reference"))
swapped = %{swapped | "continuation" => bind_token}

assert {:terminal, {:done, {:error, _, _}}, _} =
         walk.(
           walk,
           IpseKnowledge.Store.Collection.Job.bind_input(profile, swapped),
           bound_records,
           bind_stages,
           []
         )

append_records = Map.put(records, "genjob.notes", {bind_state.next_job, 500})
append_token = Map.put(token, "job_revision", 500)

bound_append = %{
  args
  | "continuation" => append_token,
    "group" => Map.merge(args["group"], %{"input_binding" => binding, "input_owner" => owner})
}

{:effect, append_effect, _, _} =
  walk.(
    walk,
    IpseKnowledge.Store.Collection.Job.start(profile, bound_append, true),
    append_records,
    %{},
    []
  )

assert String.starts_with?(append_effect["request"]["key"], "gensrc.notes.")

for altered <- [
      put_in(bound_append, ["group", "input_binding", "ref_sha256"], sha.("different ref")),
      put_in(bound_append, ["group", "input_binding", "raw_sha256"], sha.("different bytes")),
      put_in(bound_append, ["group", "input_owner", "identity_sha256"], sha.("different owner")),
      put_in(bound_append, ["continuation", "job_revision"], 499)
    ] do
  assert {:terminal, {:done, {:error, _, _}}, _} =
           walk.(
             walk,
             IpseKnowledge.Store.Collection.Job.start(profile, altered, true),
             append_records,
             %{},
             []
           )
end

abort_args = %{
  "action" => "abort",
  "vector_selection" => selection,
  "fact_selection" => extraction,
  "group" => nil,
  "continuation" => token
}

abort_records = Map.put(records, "genjob.notes", {bind_state.next_job, 499})

{:effect, _, abort_cont, _} =
  walk.(
    walk,
    IpseKnowledge.Store.Collection.Job.start(profile, abort_args),
    abort_records,
    %{},
    []
  )

abort_state = abort_cont.generation_job
assert abort_state.next_job["status"] == "aborted" and abort_state.next_job["version"] == 1
refute Map.has_key?(abort_state.next_job, "input_binding")
assert abort_state.guarded == :binding

abort_stages =
  Enum.zip(refs, abort_state.units)
  |> Map.new(fn {ref, unit} ->
    bytes = json.(unit.value)

    {{ref["slot"], ref["epoch"]},
     Map.merge(ref, %{
       "state" => "sealed",
       "key" => unit.key,
       "expected_revision" => unit.revision,
       "sha256" => sha.(bytes),
       "byte_count" => byte_size(bytes),
       "offset" => byte_size(bytes)
     })}
  end)

abort_token =
  token
  |> Map.put("plan_sha256", abort_state.plan_sha)
  |> Map.put("unit", 2)
  |> Map.put("stages", refs)

{:effect, abort_commit, abort_commit_cont, _} =
  walk.(
    walk,
    IpseKnowledge.Store.Collection.Job.start(profile, %{
      abort_args
      | "continuation" => abort_token
    }),
    abort_records,
    abort_stages,
    []
  )

assert abort_commit["source_guard"] == "explicit_fact_group_v1"
assert {:stop, :unknown_effect} = C.resume(abort_commit_cont, %{"status" => "unknown"})

IO.puts(
  Jason.encode!(%{
    "edited_metadata_positions" => 2,
    "immutable_units" => length(required),
    "final_checks" => length(checks),
    "pinned_commit_generation" => 500,
    "native_operations" => 0,
    "protected_publication_demonstrated" => false
  })
)
