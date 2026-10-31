source = File.read!("_build/shared-projection-codec-20261029/frozen-directory-sources/test/support/collection_directory.exs")
prefix = source |> String.split("{:ok, directory} = D.pack", parts: 2) |> hd()
prefix = prefix |> String.replace("Enum.map(0..135", "Enum.map(0..9") |> String.replace("|> Enum.chunk_every(8)", "|> then(fn xs -> [Enum.take(xs, 3), Enum.drop(xs, 3)] end)") |> String.replace("\"sources\" => 136", "\"sources\" => 10") |> String.replace("\"chunks\" => 136", "\"chunks\" => 10")
probe = ~S'''
{:ok, directory} = D.pack(profile, catalog, catalog_pages, summaries, 7)
expected = Map.take(directory.root, ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)) |> Map.put("root_sha256", directory.root_unit.sha256)
values = Map.new(directory.values, &{&1.key, &1.value}) |> Map.merge(Map.new(summaries, &{&1["ref"]["key"], &1["header"]}))
key = hd(summaries)["header"]["source_keys"] |> hd()
IO.inspect(%{sources: directory.root["sources"], captured_group_sources: Enum.map(summaries, & &1["header"]["sources"]), pack: :ok, lookup: D.lookup(directory.root, values, [key], expected)}, label: "DIRECTORY_PARTIAL_GROUP_COUNTEREXAMPLE")
'''
Code.eval_string(prefix <> probe)
