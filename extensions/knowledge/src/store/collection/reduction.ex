defmodule IpseKnowledge.Store.Collection.Reduction do
  @moduledoc """
  Bounded reductions producing the existing shared-directory representation.

  A manifest batch authenticates at most sixteen captured groups against their
  captured catalog pages. Its entity run is sorted by entity identity. Merge
  consumes at most eight runs and emits one canonical sixty-four-row entity
  page. Missing inputs are returned as exact immutable references, never treated
  as empty. Callers must pin reads and publication to their job/catalog epoch.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Directory, as: D
  @recipe "ipse.evidence.shared_directory.v1"

  def batch(profile, catalog, summaries, catalog_pages, ordinal, vector, fact) do
    guard(fn ->
      true = C.valid_catalog?(catalog, profile) and catalog["sources"] in 1..1000
      true = is_integer(ordinal) and ordinal in 0..7
      start = ordinal * 16
      count = min(16, div(catalog["sources"] + 7, 8) - start)
      true = count > 0 and length(summaries) == count

      rows =
        Enum.with_index(summaries, start)
        |> Enum.flat_map(fn {summary, n} ->
          true = D.valid_summary?(profile["partition"], summary, n * 8)
          h = summary["header"]
          true = h["sources"] == min(8, catalog["sources"] - n * 8)
          true = h["vector_selection"] === vector and h["fact_selection"] === fact

          Enum.with_index(summary["sources"], n * 8)
          |> Enum.map(fn {source, index} ->
            page_no = div(index, 16)
            page = Map.fetch!(catalog_pages, page_no)
            ref = Enum.fetch!(catalog["pages"], page_no)

            true =
              C.valid_catalog_page?(
                %{"value" => page, "sha256" => E.sha256(json(page))},
                ref,
                page_no,
                profile
              )

            true =
              Map.take(source, ~w(source_key head_sha256)) ===
                Enum.at(page["rows"], rem(index, 16))

            source
          end)
        end)

      true = length(Enum.uniq_by(rows, & &1["source_key"])) == length(rows)

      manifests =
        Enum.map(summaries, fn s ->
          %{
            "cursor" => s["header"]["cursor"],
            "sources" => Enum.map(s["sources"], &[&1["source_key"], &1["head_sha256"]]),
            "header" => s["ref"]
          }
        end)

      entities =
        Enum.with_index(summaries, start)
        |> Enum.flat_map(fn {s, n} ->
          Enum.map(s["entities"], fn [id, label] -> [id, label, n] end)
        end)
        |> Enum.group_by(&hd/1)
        |> Enum.map(fn {id, entries} ->
          [label] = Enum.map(entries, &Enum.at(&1, 1)) |> Enum.uniq()
          [id, label, Enum.map(entries, &List.last/1) |> Enum.uniq() |> Enum.sort()]
        end)
        |> Enum.sort_by(&hd/1)

      true = length(entities) in 0..5000
      partition = profile["partition"]
      manifest = page(partition, "genman", "generation_manifest", ordinal, manifests)

      pages =
        entities
        |> Enum.chunk_every(64)
        |> Enum.with_index()
        |> Enum.map(fn {r, n} -> page(partition, "genrun", "generation_entity_run", n, r) end)

      run =
        D.immutable(partition, "genruns", %{
          "version" => 1,
          "kind" => "generation_entity_run_directory",
          "recipe" => @recipe,
          "ordinal" => ordinal,
          "entities" => length(entities),
          "pages" => Enum.map(pages, &D.reference/1)
        })

      %{
        manifest: manifest,
        run: run,
        values: [manifest] ++ pages ++ [run],
        sources: length(rows),
        text_bytes: Enum.sum(Enum.map(rows, & &1["text_bytes"])),
        chunks: Enum.sum(Enum.map(rows, & &1["chunks"])),
        facts: Enum.sum(Enum.map(summaries, & &1["header"]["facts"]))
      }
    end)
  end

  def merge(partition, run_refs, positions, values, ordinal) do
    guard(fn ->
      true = is_list(run_refs) and length(run_refs) in 1..8
      true = length(positions) == length(run_refs)
      true = is_integer(ordinal) and ordinal in 0..78

      runs =
        Enum.with_index(run_refs)
        |> Enum.map(fn {ref, n} ->
          run = fetch!(ref, values)
          true = ref["key"] == "genruns.#{partition}." <> ref["sha256"]

          true =
            exact?(run, ~w(version kind recipe ordinal entities pages)) and run["version"] === 1 and
              run["kind"] == "generation_entity_run_directory" and run["recipe"] == @recipe and
              run["ordinal"] === n

          true =
            run["entities"] in 0..5000 and length(run["pages"]) == div(run["entities"] + 63, 64)

          run
        end)

      true =
        Enum.zip(runs, positions)
        |> Enum.all?(fn {r, p} -> is_integer(p) and p in 0..r["entities"] end)

      {rows, next} = merge_rows(partition, runs, positions, values, [], 64)

      %{
        unit:
          if(rows == [],
            do: nil,
            else: page(partition, "genent", "generation_entities", ordinal, rows)
          ),
        positions: next,
        complete: Enum.zip(runs, next) |> Enum.all?(fn {r, p} -> r["entities"] == p end),
        entities: length(rows)
      }
    end)
  end

  defp merge_rows(_, _, positions, _, rows, 0), do: {Enum.reverse(rows), positions}

  defp merge_rows(partition, runs, positions, values, rows, left) do
    heads =
      Enum.zip(runs, positions)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{run, pos}, index} ->
        if pos == run["entities"] do
          []
        else
          n = div(pos, 64)
          ref = Enum.fetch!(run["pages"], n)
          p = fetch!(ref, values)
          true = ref["key"] == "genrun.#{partition}." <> ref["sha256"]
          true = valid_page?(p, "generation_entity_run", n, min(64, run["entities"] - n * 64))
          true = valid_rows?(p["rows"], partition, 128)
          [{Enum.at(p["rows"], rem(pos, 64)), index}]
        end
      end)

    if heads == [] do
      {Enum.reverse(rows), positions}
    else
      id = heads |> Enum.map(fn {[id, _, _], _} -> id end) |> Enum.min()
      equal = Enum.filter(heads, fn {[candidate, _, _], _} -> candidate == id end)
      [label] = equal |> Enum.map(fn {[_, label, _], _} -> label end) |> Enum.uniq()

      groups =
        equal |> Enum.flat_map(fn {[_, _, groups], _} -> groups end) |> Enum.uniq() |> Enum.sort()

      true = rows == [] or hd(hd(rows)) < id

      next =
        Enum.reduce(equal, positions, fn {_, index}, acc ->
          List.update_at(acc, index, &(&1 + 1))
        end)

      merge_rows(partition, runs, next, values, [[id, label, groups] | rows], left - 1)
    end
  end

  def manifests(profile, catalog, refs, values, vector, fact) do
    guard(fn ->
      true = C.valid_catalog?(catalog, profile)
      groups = div(catalog["sources"] + 7, 8)
      true = length(refs) == div(groups + 15, 16)

      rows =
        Enum.with_index(refs)
        |> Enum.flat_map(fn {ref, n} ->
          true = ref["key"] == "genman.#{profile["partition"]}." <> ref["sha256"]
          p = fetch!(ref, values)
          true = valid_page?(p, "generation_manifest", n, min(16, groups - n * 16))
          p["rows"]
        end)

      heads =
        Enum.with_index(rows)
        |> Enum.flat_map(fn {r, n} ->
          true = exact?(r, ~w(cursor sources header)) and r["cursor"] === n * 8
          true = length(r["sources"]) == min(8, catalog["sources"] - n * 8)
          true = r["header"]["key"] == "gengrp.#{profile["partition"]}." <> r["header"]["sha256"]

          Enum.map(r["sources"], fn [key, sha] ->
            true = E.sha256?(key) and E.sha256?(sha)
            %{"source_key" => key, "head_sha256" => sha}
          end)
        end)

      true = length(Enum.uniq_by(heads, & &1["source_key"])) == length(heads)

      %{
        sha256: E.sha256(json(%{"rows" => heads})),
        vector_selection: vector,
        fact_selection: fact
      }
    end)
  end

  def entities(partition, refs, values, count, groups) do
    guard(fn ->
      true = count in 0..5000 and groups in 1..125
      true = length(refs) == div(count + 63, 64)

      rows =
        Enum.with_index(refs)
        |> Enum.flat_map(fn {ref, n} ->
          true = ref["key"] == "genent.#{partition}." <> ref["sha256"]
          p = fetch!(ref, values)
          true = valid_page?(p, "generation_entities", n, min(64, count - n * 64))
          p["rows"]
        end)

      true = valid_rows?(rows, partition, groups)
      %{sha256: E.sha256(json(%{"rows" => rows})), count: length(rows)}
    end)
  end

  def root(profile, catalog, generation, vector, fact, refs, counts, hashes) do
    guard(fn ->
      root = %{
        "version" => 1,
        "kind" => "shared_generation_directory",
        "recipe" => @recipe,
        "partition" => profile["partition"],
        "generation" => generation,
        "catalog_sha256" => E.sha256(json(catalog)),
        "catalog_generation" => catalog["generation"],
        "floor" => catalog["floor"],
        "sources" => catalog["sources"],
        "extracted_bytes" => catalog["extracted_bytes"],
        "chunks" => catalog["chunks"],
        "vectors" => catalog["chunks"],
        "facts" => counts.facts,
        "entities" => counts.entities,
        "groups" => div(catalog["sources"] + 7, 8),
        "vector_selection" => vector,
        "fact_selection" => fact,
        "source_heads_sha256" => hashes.heads,
        "entity_rows_sha256" => hashes.entities,
        "manifests" => refs.manifests,
        "entity_pages" => refs.entities
      }

      expected =
        Map.take(
          root,
          ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
        )
        |> Map.put("root_sha256", E.sha256(json(root)))

      true = D.valid_root?(root, expected)
      root
    end)
  end

  defp valid_rows?(rows, partition, groups) do
    rows === Enum.uniq_by(rows, &hd/1) |> Enum.sort_by(&hd/1) and
      Enum.all?(rows, fn
        [id, label, memberships] ->
          is_binary(label) and byte_size(label) in 1..256 and
            id === E.id("entity", [partition, label]) and is_list(memberships) and
            memberships != [] and memberships === Enum.sort(Enum.uniq(memberships)) and
            Enum.all?(memberships, &(is_integer(&1) and &1 in 0..(groups - 1)))

        _ ->
          false
      end)
  end

  defp page(p, prefix, kind, ordinal, rows),
    do:
      D.immutable(p, prefix, %{
        "version" => 1,
        "kind" => kind,
        "recipe" => @recipe,
        "ordinal" => ordinal,
        "rows" => rows
      })

  defp valid_page?(p, kind, n, count),
    do:
      exact?(p, ~w(version kind recipe ordinal rows)) and p["version"] === 1 and p["kind"] == kind and
        p["recipe"] == @recipe and p["ordinal"] === n and is_list(p["rows"]) and
        length(p["rows"]) == count

  defp fetch!(ref, values) do
    if Map.has_key?(values, ref["key"]),
      do: D.read_reference(ref, values),
      else: throw({:need, ref})
  end

  defp guard(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_generation_reduction}
  catch
    {:need, ref} -> {:need, ref}
  end

  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp json(v), do: IO.iodata_to_binary(JSON.encode!(v))
end
