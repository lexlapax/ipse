root = Path.expand("_build/shared-projection-codec-20261029")
Path.wildcard(root <> "/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
for p <- Path.wildcard(root <> "/tested-fixture-partial-hydration-final/ebin/*.beam"), do: :code.load_abs(String.to_charlist(Path.rootname(p)))
prefix = root <> "/frozen-controller-read-sources/test/support/collection_directory.exs" |> File.read!() |> String.split("# Pure protocol fixture:") |> hd()
{_, bindings} = Code.eval_string(prefix)
fetch = fn key -> Keyword.fetch!(bindings, key) end
profile = fetch.(:profile)
job = fetch.(:job)
catalog = fetch.(:catalog)
directory = fetch.(:directory)
inputs = fetch.(:inputs)
selection = fetch.(:selection)
extraction = fetch.(:extraction)
[bundles, supplied] = inputs |> Enum.take(8) |> Enum.unzip() |> Tuple.to_list()
{:ok, group_plan} = IpseKnowledge.Store.Collection.Generation.pack_group("notes", 0, bundles, supplied, selection, extraction)
json = &IO.iodata_to_binary(JSON.encode!(&1))
sha = &IpseKnowledge.Evidence.sha256/1
records = %{
  "catalog.notes" => {catalog, 500},
  "generation.notes" => {directory.root_unit.value, 17},
  "genjob.notes" => {job, 499}
}
args = %{
  "action" => "append", "vector_selection" => selection, "fact_selection" => extraction,
  "group" => %{"plan" => group_plan, "bundles" => bundles, "catalog_page" => hd(fetch.(:catalog_pages))},
  "continuation" => %{
    "version" => 1, "id" => job["id"], "plan_sha256" => nil, "job_revision" => 499,
    "root_revision" => 17, "catalog_sha256" => job["catalog_sha256"], "unit" => 0, "write" => nil, "stages" => []
  }
}
walk = fn walk, result, reads ->
  case result do
    {:call, request, continuation} ->
      r = request["request"]
      if not IpseKnowledge.Store.Collection.read_request?(request) do
        {request, continuation, reads}
      else
        record = records[r["key"]]
        descriptor = if record, do: (fn {value, revision} -> bytes = json.(value); %{"revision" => revision, "sha256" => sha.(bytes), "byte_count" => byte_size(bytes)} end).(record)
        reply = case r["op"] do
          "snapshot" -> %{"generation" => 500, "floor" => 3, "document_store" => %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2}}
          "value.stat" -> %{"generation" => 500, "key" => r["key"], "record" => descriptor}
          "value.read" -> Map.merge(descriptor, %{"generation" => 500, "key" => r["key"], "offset" => 0, "next" => nil, "data" => json.(elem(record, 0))})
          "stage.list" -> %{"generation" => 500, "stages" => []}
        end
        {:ok, digest} = Ipse.Extension.canonical_digest([request])
        outcome = %{"status" => "ok", "value" => %{"version" => 1, "operation_id" => String.duplicate("a", 32), "request_sha256" => digest, "result" => reply}}
        walk.(walk, IpseKnowledge.Store.Collection.resume(continuation, outcome), reads ++ [r])
      end
    other -> raise "unexpected result #{inspect(other)}"
  end
end
{ordinary_effect, ordinary_cont, _} = walk.(walk, IpseKnowledge.Store.Collection.start(profile, :generation_job, args), [])
s = ordinary_cont.generation_job
true = String.starts_with?(ordinary_effect["request"]["key"], "gensrc.notes.")
forged = args["continuation"] |> Map.put("plan_sha256", s.plan_sha) |> Map.put("unit", s.immutable)
{effect, cont, reads} = walk.(walk, IpseKnowledge.Store.Collection.start(profile, :generation_job, %{args | "continuation" => forged}), [])
true = effect["request"]["key"] == "genjob.notes"
required = Enum.take(cont.generation_job.units, cont.generation_job.immutable) |> Enum.map(& &1.key)
read_keys = Enum.map(reads, & &1["key"])
true = Enum.all?(required, &(not Map.has_key?(records, &1)))
true = Enum.all?(required, &(&1 not in read_keys))
IO.inspect(%{
  ordinary_first_target: ordinary_effect["request"]["key"],
  edited_token_first_target: effect["request"]["key"],
  required_immutable_values: length(required),
  required_immutable_values_present: 0,
  required_immutable_values_read: 0,
  proposed_job_cursor: cont.generation_job.next_job["cursor"],
  proposed_job_summary_count: length(cont.generation_job.next_job["summaries"]),
  native_operations: 0,
  protected_publication_demonstrated: false
}, label: "SKIPPED_IMMUTABLES_COUNTEREXAMPLE")
