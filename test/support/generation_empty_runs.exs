import ExUnit.Assertions

prefix =
  File.read!("test/support/collection_directory.exs")
  |> String.split("# Pure protocol fixture:")
  |> hd()

{_, bindings} = Code.eval_string(prefix)
fetch = fn key -> Keyword.fetch!(bindings, key) end
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection.Directory, as: D
alias IpseKnowledge.Store.Collection.Finalization, as: F
alias IpseKnowledge.Store.Collection.Generation, as: G
alias IpseKnowledge.Store.Collection.Job

profile = fetch.(:profile)
catalog = fetch.(:catalog)
catalog_pages = fetch.(:catalog_pages)
selection = fetch.(:selection)
extraction = fetch.(:extraction)
inputs = fetch.(:inputs)
json = &IO.iodata_to_binary(JSON.encode!(&1))

for mode <- [:all_empty, :first_run_empty, :second_run_empty], paged <- [false, true] do
  summaries =
    inputs
    |> Enum.chunk_every(8)
    |> Enum.with_index()
    |> Enum.map(fn {pairs, n} ->
      {bundles, data} = Enum.unzip(pairs)

      empty =
        mode == :all_empty or (mode == :first_run_empty and n < 16) or
          (mode == :second_run_empty and n == 16)

      data = if empty, do: Enum.map(data, &%{&1 | "facts" => []}), else: data
      {:ok, group} = G.pack_group("notes", n * 8, bundles, data, selection, extraction)

      {:ok, summary} =
        D.capture("notes", group, bundles, %{
          "cursor" => n * 8,
          "vector_selection" => selection,
          "fact_selection" => extraction
        })

      summary
    end)

  units = Enum.map(summaries, &D.immutable("notes", "gensum", &1))

  values =
    Map.new(units, &{&1.key, &1.value})
    |> Map.merge(Map.new(catalog_pages, &{"catalog.notes.#{&1["ordinal"]}", &1}))

  count = Enum.sum(Enum.map(summaries, & &1["header"]["facts"]))

  job =
    fetch.(:job)
    |> Map.merge(%{
      "status" => "manifests",
      "cursor" => 136,
      "summaries" => Enum.map(units, &D.reference/1),
      "facts" => count
    })

  assert Job.valid?(job, profile)

  load = fn load, current, stored, loaded ->
    case F.plan(current, loaded, paged) do
      {:need, ref} ->
        load.(load, current, stored, Map.put(loaded, ref["key"], Map.fetch!(stored, ref["key"])))

      result ->
        result
    end
  end

  reduce = fn reduce, current, stored, steps ->
    assert steps < 60
    {:ok, result} = load.(load, current, stored, %{})
    assert Job.valid?(result.job, profile)
    stored = Map.merge(stored, Map.new(result.values, &{&1.key, &1.value}))

    if result.root,
      do: {result.root, stored},
      else: reduce.(reduce, result.job, stored, steps + 1)
  end

  {root, stored} = reduce.(reduce, job, values, 0)
  {:ok, canonical} = D.pack(profile, catalog, catalog_pages, summaries, 8)

  expected =
    Map.take(
      root,
      ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
    )
    |> Map.put("root_sha256", E.sha256(json.(root)))

  old = canonical.root

  old_expected =
    Map.take(
      old,
      ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
    )
    |> Map.put("root_sha256", canonical.root_unit.sha256)

  {:ok, rows} = D.entity_rows(root, stored, expected)

  {:ok, canonical_rows} =
    D.entity_rows(old, Map.new(canonical.values, &{&1.key, &1.value}), old_expected)

  assert rows === canonical_rows
  assert root["facts"] == count
  assert root["manifests"] === old["manifests"]
  assert root["source_heads_sha256"] === old["source_heads_sha256"]
end

IO.puts(Jason.encode!(%{"cases" => 6, "groups" => 17, "native_operations" => 0}))
