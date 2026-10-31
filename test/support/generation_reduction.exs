import ExUnit.Assertions

prefix =
  File.read!("test/support/collection_directory.exs")
  |> String.split("# Pure protocol fixture:")
  |> hd()

{_, bindings} = Code.eval_string(prefix)
fetch = fn key -> Keyword.fetch!(bindings, key) end
alias IpseKnowledge.Store.Collection.Directory, as: D
alias IpseKnowledge.Store.Collection.Reduction, as: R
profile = fetch.(:profile)
catalog = fetch.(:catalog)
selection = fetch.(:selection)
extraction = fetch.(:extraction)
summaries = fetch.(:summaries)
pages = fetch.(:catalog_pages) |> Enum.with_index() |> Map.new(fn {p, n} -> {n, p} end)

batches =
  summaries
  |> Enum.chunk_every(16)
  |> Enum.with_index()
  |> Enum.map(fn {s, n} ->
    {:ok, batch} = R.batch(profile, catalog, s, pages, n, selection, extraction)
    batch
  end)

values = batches |> Enum.flat_map(& &1.values) |> Map.new(&{&1.key, &1.value})
runs = Enum.map(batches, &D.reference(&1.run))
assert {:need, _} = R.merge("notes", runs, [0, 0], %{}, 0)

merge = fn merge, positions, units ->
  {:ok, result} = R.merge("notes", runs, positions, values, length(units))
  units = if result.unit, do: units ++ [result.unit], else: units
  if result.complete, do: units, else: merge.(merge, result.positions, units)
end

entity_units = merge.(merge, [0, 0], [])
entity_refs = Enum.map(entity_units, &D.reference/1)
manifests = Enum.map(batches, &D.reference(&1.manifest))
values = Map.merge(values, Map.new(entity_units, &{&1.key, &1.value}))
{:ok, heads} = R.manifests(profile, catalog, manifests, values, selection, extraction)
{:ok, entities} = R.entities("notes", entity_refs, values, 272, 17)

{:ok, root} =
  R.root(
    profile,
    catalog,
    7,
    selection,
    extraction,
    %{manifests: manifests, entities: entity_refs},
    %{facts: 136, entities: 272},
    %{heads: heads.sha256, entities: entities.sha256}
  )

assert root === fetch.(:directory).root

assert Map.take(values, Enum.map(fetch.(:directory).values, & &1.key)) ===
         Map.new(fetch.(:directory).values, &{&1.key, &1.value})

# Noncanonical batch geometry, missing pages, foreign catalog and selectors refuse.
assert {:error, _} =
         R.batch(profile, catalog, Enum.take(summaries, 15), pages, 0, selection, extraction)

assert {:error, _} =
         R.batch(profile, catalog, Enum.take(summaries, 16), %{}, 0, selection, extraction)

assert {:error, _} =
         R.batch(
           profile,
           catalog,
           Enum.take(summaries, 16),
           pages,
           0,
           %{selection | "model" => "foreign"},
           extraction
         )

assert {:error, _} = R.merge("notes", runs, [1_000, 0], values, 0)
assert {:error, _} = R.merge("notes", Enum.reverse(runs), [0, 0], values, 0)
bad = put_in(values, [hd(runs)["key"], "entities"], 1)
assert {:error, _} = R.merge("notes", runs, [0, 0], bad, 0)

assert {:need, _} =
         R.entities("notes", entity_refs, Map.delete(values, hd(entity_refs)["key"]), 272, 17)

assert {:error, _} = R.entities("notes", Enum.reverse(entity_refs), values, 272, 17)

IO.write(
  Jason.encode!(%{
    "manifest_batches" => length(batches),
    "entity_pages" => length(entity_units),
    "canonical_equal" => root === fetch.(:directory).root,
    "native_operations" => 0,
    "protected_publication_demonstrated" => false
  })
)
