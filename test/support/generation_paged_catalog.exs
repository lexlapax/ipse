import ExUnit.Assertions

prefix =
  File.read!("test/support/generation_paged_budget.exs")
  |> String.split("{{:done, {:ok, selected}}, final}", parts: 2)
  |> hd()

{_, bindings} = Code.eval_string(prefix)
get = fn key -> Keyword.fetch!(bindings, key) end
alias IpseTest.CollectionProtocol, as: Protocol
alias IpseKnowledge.Store.Collection, as: C
alias IpseKnowledge.Store.Collection.{Directory, Job}
partition = get.(:partition)
profile = get.(:profile)
args = get.(:args)
model = get.(:model)

job =
  get.(:job)
  |> put_in(["reduction", "phase"], "heads")
  |> put_in(["reduction", "heads_sha256"], nil)
  |> put_in(["reduction", "entity_pages_sha256"], nil)
  |> put_in(["reduction", "digest_cursor"], 0)
  |> put_in(["reduction", "verified_entities"], 0)
  |> put_in(["reduction", "last_entity_id"], nil)

assert Job.valid?(job, profile)
model = %{model | records: Map.update!(model.records, "genjob.#{partition}", &%{&1 | value: job})}

{{:done, {:ok, progressed}}, measured} =
  Protocol.run(C.start(profile, :generation_job, args), model)

assert progressed["job"]["reduction"]["phase"] == "entity_digest"
assert progressed["job"]["reduction"]["heads_sha256"] === get.(:old)["source_heads_sha256"]
assert length(progressed["job"]["catalog"]["pages"]) == 63

assert measured.records["generation.#{partition}"].value ===
         model.records["generation.#{partition}"].value

manifests = get.(:manifests)
first = hd(manifests).value |> Map.fetch!("rows") |> hd() |> Map.fetch!("sources") |> hd()
second = Enum.at(manifests, 1)
duplicate = put_in(second.value, ["rows", Access.at(0), "sources", Access.at(0)], first)
last = List.last(manifests)

reordered =
  put_in(
    last.value,
    ["rows"],
    [Enum.at(last.value["rows"], 1), hd(last.value["rows"])] ++ Enum.drop(last.value["rows"], 2)
  )

missing_row = Map.update!(last.value, "rows", &Enum.drop(&1, -1))

for {n, value} <- [{1, duplicate}, {7, reordered}, {7, missing_row}] do
  bad = Directory.immutable(partition, "genman", value)
  altered = put_in(job, ["reduction", "manifests", Access.at(n)], Directory.reference(bad))
  assert Job.valid?(altered, profile)

  records =
    model.records
    |> Map.update!("genjob.#{partition}", &%{&1 | value: altered})
    |> Map.put(bad.key, %{value: bad.value, revision: get.(:epoch) - 1000})

  {{:done, {:error, :invalid_generation_finalization, _}}, refused} =
    Protocol.run(C.start(profile, :generation_job, args), %{model | records: records})

  assert refused.effects == 0
end

missing = %{model | records: Map.delete(model.records, last.key)}

{{:done, {:error, :generation_job_changed, _}}, refused} =
  Protocol.run(C.start(profile, :generation_job, args), missing)

assert refused.effects == 0

IO.write(
  Jason.encode!(%{
    "sources" => 1000,
    "groups" => 125,
    "catalog_pages" => 63,
    "manifest_pages" => 8,
    "reads" => measured.reads,
    "effects" => measured.effects,
    "negative_effects" => 0,
    "native_operations" => 0,
    "model_calls" => 0
  })
)
