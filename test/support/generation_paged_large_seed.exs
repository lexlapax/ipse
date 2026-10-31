input = Jason.decode!(File.read!(hd(System.argv())))

prefix =
  File.read!("test/support/generation_paged_budget.exs")
  |> String.split("{{:done, {:ok, selected}}, final}", parts: 2)
  |> hd()

{_, vars} = Code.eval_string(prefix)
get = fn key -> Keyword.fetch!(vars, key) end
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection.Job
json = &IO.iodata_to_binary(JSON.encode!(&1))
# Rebind only the maximum-width metadata fixture's partition and current
# parent. Referenced payloads are deliberately not a populated source store.
source = get.(:job)
partition = "notes"

replace_partition = fn replace_partition, value ->
  cond do
    is_map(value) ->
      Map.new(value, fn {key, item} -> {key, replace_partition.(replace_partition, item)} end)

    is_list(value) ->
      Enum.map(value, &replace_partition.(replace_partition, &1))

    is_binary(value) ->
      String.replace(value, "abcdefghijklmnop", partition)

    true ->
      value
  end
end

catalog = replace_partition.(replace_partition, get.(:catalog))

job =
  replace_partition.(replace_partition, source)
  |> Map.put("catalog", catalog)
  |> Map.put("catalog_sha256", E.sha256(json.(catalog)))
  |> Map.put("root_revision", input["revision"])
  |> Map.put("root_sha256", E.sha256(json.(input["parent"])))
  |> Map.put("generation", input["parent"]["generation"] + 1)

r = job["reduction"]

job =
  put_in(
    job,
    ["reduction", "entity_pages_sha256"],
    IpseKnowledge.Store.Collection.Paged.commitment(r["entity_pages"], r["entities"], 125)
  )

true = Job.valid?(job, %{"kind" => "collection", "scope" => "project", "partition" => partition})

IO.puts(
  Jason.encode!(%{
    "catalog" => catalog,
    "job" => job,
    "arguments" => %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => job["vector_selection"],
      "fact_selection" => job["fact_selection"]
    }
  })
)
