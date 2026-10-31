defmodule IpseKnowledge.Store.Collection.Paged do
  @moduledoc """
  Explicit directory-v2 entity pages and ordered page commitments.

  Manifest and shared projection formats remain version one. Semantic page
  verification is distinct from the page commitment and from host authority.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection.Directory, as: D
  alias IpseKnowledge.Store.Collection.Reduction, as: R
  @recipe "ipse.evidence.shared_directory.v2"
  @root ~w(version kind recipe partition generation catalog_sha256 catalog_generation floor sources extracted_bytes chunks vectors facts entities groups vector_selection fact_selection source_heads_sha256 entity_pages_sha256 entity_page_rows manifests entity_pages)
  @expected ~w(root_sha256 generation catalog_sha256 catalog_generation floor vector_selection fact_selection)

  def batch(profile, catalog, summaries, pages, ordinal, vector, fact) do
    with {:ok, batch} <- R.batch(profile, catalog, summaries, pages, ordinal, vector, fact) do
      guard(fn ->
        rows =
          batch.values
          |> Enum.filter(&(&1.value["kind"] == "generation_entity_run"))
          |> Enum.flat_map(& &1.value["rows"])

        units =
          rows
          |> Enum.chunk_every(32)
          |> Enum.with_index()
          |> Enum.map(fn {rows, n} ->
            page(profile["partition"], "genrun", "generation_entity_run", n, rows)
          end)

        run =
          immutable(profile["partition"], "genruns", %{
            "version" => 2,
            "kind" => "generation_entity_run_directory",
            "recipe" => @recipe,
            "ordinal" => ordinal,
            "entities" => length(rows),
            "pages" => Enum.map(units, &D.reference/1)
          })

        %{batch | run: run, values: [batch.manifest] ++ units ++ [run]}
      end)
    end
  end

  def merge(partition, refs, positions, values, ordinal, groups) do
    guard(fn ->
      true = is_list(refs) and length(refs) in 1..8 and length(positions) == length(refs)
      true = is_integer(ordinal) and ordinal in 0..156 and groups in 1..125

      runs =
        Enum.with_index(refs)
        |> Enum.map(fn {ref, n} ->
          run = fetch!(partition, "genruns", ref, values)

          true =
            exact?(run, ~w(version kind recipe ordinal entities pages)) and run["version"] === 2 and
              run["kind"] == "generation_entity_run_directory" and run["recipe"] == @recipe and
              run["ordinal"] === n

          true =
            run["entities"] in 1..5000 and length(run["pages"]) == div(run["entities"] + 31, 32)

          true = Enum.all?(run["pages"], &reference?(partition, "genrun", &1))
          run
        end)

      true = length(runs) == div(groups + 15, 16)

      true =
        Enum.zip(runs, positions)
        |> Enum.all?(fn {r, p} -> is_integer(p) and p in 0..r["entities"] end)

      {rows, next} = merge_rows(partition, runs, positions, values, groups, [], 32)

      %{
        unit:
          if(rows == [],
            do: nil,
            else: page(partition, "genent", "generation_entities", ordinal, rows)
          ),
        positions: next,
        entities: length(rows),
        complete: Enum.zip(runs, next) |> Enum.all?(fn {r, p} -> p == r["entities"] end)
      }
    end)
  end

  defp merge_rows(_, _, positions, _, _, rows, 0), do: {Enum.reverse(rows), positions}

  defp merge_rows(partition, runs, positions, values, groups, rows, left) do
    heads =
      Enum.zip(runs, positions)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{run, pos}, index} ->
        if pos == run["entities"] do
          []
        else
          n = div(pos, 32)
          value = fetch!(partition, "genrun", Enum.fetch!(run["pages"], n), values)
          true = page?(value, "generation_entity_run", n, min(32, run["entities"] - n * 32))
          true = rows?(value["rows"], partition, groups)

          true =
            Enum.all?(value["rows"], fn [_, _, memberships] ->
              Enum.all?(memberships, &(&1 in (index * 16)..min(index * 16 + 15, groups - 1)))
            end)

          [{Enum.at(value["rows"], rem(pos, 32)), index}]
        end
      end)

    if heads == [] do
      {Enum.reverse(rows), positions}
    else
      id = Enum.map(heads, fn {[id, _, _], _} -> id end) |> Enum.min()
      equal = Enum.filter(heads, fn {[candidate, _, _], _} -> candidate == id end)
      [label] = Enum.map(equal, fn {[_, label, _], _} -> label end) |> Enum.uniq()
      memberships = Enum.flat_map(equal, fn {[_, _, m], _} -> m end) |> Enum.uniq() |> Enum.sort()
      true = rows == [] or hd(hd(rows)) < id

      next =
        Enum.reduce(equal, positions, fn {_, n}, acc -> List.update_at(acc, n, &(&1 + 1)) end)

      merge_rows(
        partition,
        runs,
        next,
        values,
        groups,
        [[id, label, memberships] | rows],
        left - 1
      )
    end
  end

  def verify(partition, refs, values, count, groups, cursor, previous) do
    guard(fn ->
      true = count in 1..5000 and groups in 1..125 and length(refs) == div(count + 31, 32)
      true = is_integer(cursor) and cursor in 0..(length(refs) - 1)
      true = if(cursor == 0, do: previous == nil, else: E.sha256?(previous))
      value = fetch!(partition, "genent", Enum.fetch!(refs, cursor), values)
      true = page?(value, "generation_entities", cursor, min(32, count - cursor * 32))
      true = rows?(value["rows"], partition, groups)
      true = previous == nil or previous < hd(hd(value["rows"]))
      %{rows: length(value["rows"]), last: hd(List.last(value["rows"]))}
    end)
  end

  def commitment(refs, entities, groups),
    do:
      E.sha256(
        json(%{
          "version" => 2,
          "kind" => "ordered_entity_pages",
          "recipe" => @recipe,
          "entities" => entities,
          "groups" => groups,
          "page_rows" => 32,
          "pages" => refs
        })
      )

  def root(profile, catalog, generation, vector, fact, refs, counts, hashes) do
    guard(fn ->
      value = %{
        "version" => 2,
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
        "entity_pages_sha256" => hashes.entities,
        "entity_page_rows" => 32,
        "manifests" => refs.manifests,
        "entity_pages" => refs.entities
      }

      expected =
        Map.take(value, @expected -- ["root_sha256"])
        |> Map.put("root_sha256", E.sha256(json(value)))

      true = valid_root?(value, expected)
      value
    end)
  end

  def valid_root?(r, expected) do
    exact?(r, @root) and exact?(expected, @expected) and r["version"] === 2 and
      r["recipe"] == @recipe and r["kind"] == "shared_generation_directory" and
      r["entity_page_rows"] === 32 and
      is_binary(r["partition"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, r["partition"]) and
      E.sha256?(expected["root_sha256"]) and expected["root_sha256"] === E.sha256(json(r)) and
      Enum.all?(@expected -- ["root_sha256"], &(r[&1] === expected[&1])) and
      Enum.all?(
        ~w(generation catalog_generation floor sources extracted_bytes chunks vectors facts entities groups),
        &E.safe_uint?(r[&1])
      ) and r["generation"] > 0 and r["sources"] in 1..1000 and r["chunks"] in 1..10_000 and
      r["extracted_bytes"] <= 20 * 1024 * 1024 and r["vectors"] == r["chunks"] and
      r["facts"] in 1..20_000 and r["entities"] in 1..5000 and
      r["groups"] == div(r["sources"] + 7, 8) and
      Enum.all?(~w(catalog_sha256 source_heads_sha256 entity_pages_sha256), &E.sha256?(r[&1])) and
      is_list(r["manifests"]) and length(r["manifests"]) == div(r["groups"] + 15, 16) and
      Enum.all?(r["manifests"], &reference?(r["partition"], "genman", &1)) and
      is_list(r["entity_pages"]) and length(r["entity_pages"]) == div(r["entities"] + 31, 32) and
      Enum.all?(r["entity_pages"], &reference?(r["partition"], "genent", &1)) and
      length(Enum.uniq_by(r["entity_pages"], & &1["key"])) == length(r["entity_pages"]) and
      length(Enum.uniq_by(r["manifests"], & &1["key"])) == length(r["manifests"]) and
      r["entity_pages_sha256"] === commitment(r["entity_pages"], r["entities"], r["groups"]) and
      IpseKnowledge.Store.Collection.Projection.valid_selection?(r["vector_selection"]) and
      IpseKnowledge.Store.Collection.Projection.valid_extraction?(r["fact_selection"]) and
      native_value?(r)
  rescue
    _ -> false
  end

  def entity_rows(root, values, expected) do
    guard(fn ->
      true = valid_root?(root, expected)

      {rows, _} =
        Enum.with_index(root["entity_pages"])
        |> Enum.reduce({[], nil}, fn {ref, n}, {rows, previous} ->
          {:ok, check} =
            verify(
              root["partition"],
              root["entity_pages"],
              values,
              root["entities"],
              root["groups"],
              n,
              previous
            )

          value = fetch!(root["partition"], "genent", ref, values)
          {rows ++ value["rows"], check.last}
        end)

      rows
    end)
    |> case do
      {:ok, rows} -> {:ok, rows}
      _ -> {:error, :generation_directory_corrupt}
    end
  end

  def reference?(partition, prefix, ref),
    do:
      exact?(ref, ~w(key sha256 byte_count)) and E.sha256?(ref["sha256"]) and
        ref["key"] === "#{prefix}.#{partition}." <> ref["sha256"] and byte_size(ref["key"]) <= 96 and
        is_integer(ref["byte_count"]) and ref["byte_count"] in 2..49_152

  def native_value?(value) do
    bytes = json(value)

    parts =
      Stream.unfold(bytes, fn
        "" ->
          nil

        rest ->
          piece = utf8(rest, min(byte_size(rest), 6144))
          {piece, binary_part(rest, byte_size(piece), byte_size(rest) - byte_size(piece))}
      end)
      |> Enum.to_list()

    byte_size(bytes) <= 49_152 and length(parts) in 1..10 and
      byte_size(
        json(%{
          "version" => 1,
          "kind" => "document_value",
          "sha256" => E.sha256(bytes),
          "byte_count" => byte_size(bytes),
          "parts" => parts
        })
      ) <= 65_536
  rescue
    _ -> false
  end

  defp immutable(partition, prefix, value) do
    true = native_value?(value)
    D.immutable(partition, prefix, value)
  end

  defp page(partition, prefix, kind, ordinal, rows),
    do:
      immutable(partition, prefix, %{
        "version" => 2,
        "kind" => kind,
        "recipe" => @recipe,
        "ordinal" => ordinal,
        "rows" => rows
      })

  defp fetch!(partition, prefix, ref, values) do
    true = reference?(partition, prefix, ref)
    unless Map.has_key?(values, ref["key"]), do: throw({:need, ref})
    value = D.read_reference(ref, values)
    true = native_value?(value)
    value
  end

  defp page?(p, kind, n, count),
    do:
      exact?(p, ~w(version kind recipe ordinal rows)) and p["version"] === 2 and
        p["recipe"] == @recipe and p["kind"] == kind and p["ordinal"] === n and is_list(p["rows"]) and
        length(p["rows"]) == count

  defp rows?(rows, partition, groups) do
    rows === Enum.uniq_by(rows, &hd/1) |> Enum.sort_by(&hd/1) and
      Enum.all?(rows, fn
        [id, label, memberships] ->
          is_binary(label) and String.valid?(label) and byte_size(label) in 1..256 and
            not Regex.match?(~r/[\x00-\x1F\x7F]/u, label) and
            id === E.id("entity", [partition, label]) and is_list(memberships) and
            memberships != [] and memberships === Enum.sort(Enum.uniq(memberships)) and
            Enum.all?(memberships, &(is_integer(&1) and &1 in 0..(groups - 1)))

        _ ->
          false
      end)
  end

  defp utf8(bytes, n) do
    piece = binary_part(bytes, 0, n)
    if String.valid?(piece), do: piece, else: utf8(bytes, n - 1)
  end

  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))

  defp guard(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_paged_generation}
  catch
    {:need, ref} -> {:need, ref}
  end
end
