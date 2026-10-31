defmodule IpseKnowledge.Store.Collection.Directory do
  @moduledoc """
  Catalog-bound immutable directories for shared projection groups.

  This pure codec does not select a generation or grant use authority. Capture
  validates one complete group; packing retains only its bounded summary. A
  controller must independently bind publication and current-use policy. Lookup
  authenticates directory/header bytes without hydrating vector or fact payloads.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Generation, as: G
  @recipe "ipse.evidence.shared_directory.v1"
  @bytes 48 * 1024
  @header_keys ~w(version kind recipe cursor source_set_sha256 source_keys sources vectors facts entities partial_sources vector_selection fact_selection vector_identities_sha256 fact_ids_sha256 entity_ids_sha256 source_pages vector_pages fact_pages)
  @root_keys ~w(version kind recipe partition generation catalog_sha256 catalog_generation floor sources extracted_bytes chunks vectors facts entities groups vector_selection fact_selection source_heads_sha256 entity_rows_sha256 manifests entity_pages)
  @expected ~w(root_sha256 generation catalog_sha256 catalog_generation floor vector_selection fact_selection)

  @doc false
  def valid_root?(%{"version" => 2} = root, expected),
    do: IpseKnowledge.Store.Collection.Paged.valid_root?(root, expected)

  def valid_root?(root, expected), do: root?(root, expected)

  @doc false
  def valid_summary?(partition, summary, cursor), do: summary?(partition, summary, cursor)

  @doc false
  def immutable(partition, prefix, value), do: unit(partition, prefix, value)

  @doc false
  def reference(unit), do: ref(unit)

  @doc false
  def read_reference(ref, values), do: value!(ref, values)

  def capture(partition, plan, bundles, expected) do
    with {:ok, supplied} <-
           G.unpack_group(
             partition,
             plan.header,
             Map.new(plan.values, &{&1.key, &1.value}),
             bundles,
             expected
           ),
         {:ok, canonical} <-
           G.pack_group(
             partition,
             expected["cursor"],
             bundles,
             supplied,
             expected["vector_selection"],
             expected["fact_selection"]
           ),
         true <- plan === canonical do
      {:ok,
       %{
         "header" => plan.header,
         "ref" => ref(plan.header_unit),
         "sources" =>
           Enum.map(bundles, fn bundle ->
             head = bundle["head"]

             Map.take(head, ~w(source_key ordinal text_bytes chunks bundle_sha256))
             |> Map.put("head_sha256", E.sha256(json(head)))
           end),
         "entities" => plan.entities
       }}
    else
      _ -> {:error, :invalid_generation_capture}
    end
  rescue
    _ -> {:error, :invalid_generation_capture}
  end

  def pack(profile, catalog, catalog_pages, summaries, generation) do
    partition = profile["partition"]

    with true <- C.valid_catalog?(catalog, profile) and catalog["sources"] in 1..1000,
         true <- E.safe_uint?(generation) and generation > 0,
         true <- is_list(catalog_pages) and length(catalog_pages) == length(catalog["pages"]),
         true <-
           Enum.with_index(catalog_pages)
           |> Enum.all?(fn {page, n} ->
             sha = E.sha256(json(page))

             C.valid_catalog_page?(
               %{"value" => page, "sha256" => sha},
               Enum.at(catalog["pages"], n),
               n,
               profile
             )
           end),
         rows = Enum.flat_map(catalog_pages, & &1["rows"]),
         true <-
           length(rows) == catalog["sources"] and
             length(Enum.uniq_by(rows, & &1["source_key"])) == length(rows),
         true <- is_list(summaries) and length(summaries) == div(length(rows) + 7, 8),
         true <-
           Enum.with_index(summaries)
           |> Enum.all?(fn {summary, n} ->
             summary?(partition, summary, n * 8) and
               summary["header"]["sources"] == min(8, length(rows) - n * 8)
           end),
         [first | _] = summaries,
         vector_selection = first["header"]["vector_selection"],
         fact_selection = first["header"]["fact_selection"],
         true <-
           Enum.all?(summaries, fn s ->
             s["header"]["vector_selection"] === vector_selection and
               s["header"]["fact_selection"] === fact_selection
           end),
         sources = Enum.flat_map(summaries, & &1["sources"]),
         true <- Enum.map(sources, &Map.take(&1, ~w(source_key head_sha256))) === rows,
         true <- Enum.sum(Enum.map(sources, & &1["text_bytes"])) == catalog["extracted_bytes"],
         true <- Enum.sum(Enum.map(sources, & &1["chunks"])) == catalog["chunks"],
         entities = Enum.flat_map(summaries, & &1["entities"]),
         true <-
           Enum.all?(Enum.group_by(entities, &hd/1), fn {_, group} ->
             length(Enum.uniq(group)) == 1
           end),
         unique = Enum.uniq_by(entities, &hd/1) |> Enum.sort_by(&hd/1),
         true <- length(unique) <= 5000,
         facts = Enum.sum(Enum.map(summaries, & &1["header"]["facts"])),
         true <- facts <= 20_000 do
      manifest_rows =
        Enum.map(summaries, fn s ->
          %{
            "cursor" => s["header"]["cursor"],
            "sources" => Enum.map(s["sources"], &[&1["source_key"], &1["head_sha256"]]),
            "header" => s["ref"]
          }
        end)

      entity_rows =
        Enum.map(unique, fn [id, label] ->
          groups =
            summaries
            |> Enum.with_index()
            |> Enum.filter(fn {s, _} -> [id, label] in s["entities"] end)
            |> Enum.map(&elem(&1, 1))

          [id, label, groups]
        end)

      manifests = pages(partition, "genman", "generation_manifest", manifest_rows, 16)
      entity_pages = pages(partition, "genent", "generation_entities", entity_rows, 64)

      root = %{
        "version" => 1,
        "kind" => "shared_generation_directory",
        "recipe" => @recipe,
        "partition" => partition,
        "generation" => generation,
        "catalog_sha256" => E.sha256(json(catalog)),
        "catalog_generation" => catalog["generation"],
        "floor" => catalog["floor"],
        "sources" => length(rows),
        "extracted_bytes" => catalog["extracted_bytes"],
        "chunks" => catalog["chunks"],
        "vectors" => catalog["chunks"],
        "facts" => facts,
        "entities" => length(unique),
        "groups" => length(summaries),
        "vector_selection" => vector_selection,
        "fact_selection" => fact_selection,
        "source_heads_sha256" => E.sha256(json(%{"rows" => rows})),
        "entity_rows_sha256" => E.sha256(json(%{"rows" => entity_rows})),
        "manifests" => Enum.map(manifests, &ref/1),
        "entity_pages" => Enum.map(entity_pages, &ref/1)
      }

      true = byte_size(json(root)) <= @bytes

      {:ok,
       %{
         root: root,
         root_unit: unit(partition, "genroot", root),
         values: manifests ++ entity_pages
       }}
    else
      _ -> {:error, :invalid_generation_directory}
    end
  rescue
    _ -> {:error, :invalid_generation_directory}
  end

  def lookup(root, values, source_keys, expected) do
    with true <- valid_root?(root, expected),
         true <-
           is_list(source_keys) and length(source_keys) in 1..8 and
             Enum.all?(source_keys, &E.sha256?/1) and
             length(Enum.uniq(source_keys)) == length(source_keys),
         pages =
           fetch(root["partition"], "genman", "generation_manifest", root["manifests"], values),
         true <-
           Enum.with_index(pages)
           |> Enum.all?(fn {page, n} ->
             length(page["rows"]) == min(16, root["groups"] - n * 16)
           end),
         rows = Enum.flat_map(pages, & &1["rows"]),
         true <- length(rows) == root["groups"],
         true <-
           Enum.with_index(rows) |> Enum.all?(fn {row, n} -> manifest_row?(root, row, n * 8) end),
         sources = Enum.flat_map(rows, & &1["sources"]),
         true <-
           length(sources) == root["sources"] and
             length(Enum.uniq_by(sources, &hd/1)) == length(sources),
         true <-
           E.sha256(
             json(%{
               "rows" =>
                 Enum.map(sources, fn [k, h] -> %{"source_key" => k, "head_sha256" => h} end)
             })
           ) == root["source_heads_sha256"],
         selected =
           Enum.filter(rows, fn row ->
             Enum.any?(row["sources"], fn [k, _] -> k in source_keys end)
           end),
         headers =
           Enum.map(selected, fn row ->
             header = value!(row["header"], values)
             true = header?(header, row["cursor"])
             true = header["source_keys"] === Enum.map(row["sources"], &hd/1)

             true =
               header["vector_selection"] === root["vector_selection"] and
                 header["fact_selection"] === root["fact_selection"]

             Map.put(row, "header_value", header)
           end) do
      found = Enum.map(sources, &hd/1)

      {:ok,
       %{
         "groups" => headers,
         "missing_source_keys" => Enum.reject(source_keys, &(&1 in found)),
         "coverage" => %{
           "directory_complete" => true,
           "evidence_readable" => false,
           "projection_payloads_read" => false,
           "manifest_pages" => length(pages),
           "selected_headers" => length(headers),
           "catalog_sha256" => root["catalog_sha256"],
           "floor" => root["floor"]
         }
       }}
    else
      _ -> {:error, :generation_directory_corrupt}
    end
  rescue
    _ -> {:error, :generation_directory_corrupt}
  end

  def entity_rows(%{"version" => 2} = root, values, expected),
    do: IpseKnowledge.Store.Collection.Paged.entity_rows(root, values, expected)

  def entity_rows(root, values, expected) do
    with true <- root?(root, expected),
         pages =
           fetch(root["partition"], "genent", "generation_entities", root["entity_pages"], values),
         true <-
           Enum.with_index(pages)
           |> Enum.all?(fn {page, n} ->
             length(page["rows"]) == min(64, root["entities"] - n * 64)
           end),
         rows = Enum.flat_map(pages, & &1["rows"]),
         true <-
           length(rows) == root["entities"] and
             rows === Enum.uniq_by(rows, &hd/1) |> Enum.sort_by(&hd/1),
         true <-
           Enum.all?(rows, fn
             [id, label, groups] ->
               is_binary(label) and byte_size(label) in 1..256 and
                 id === E.id("entity", [root["partition"], label]) and
                 is_list(groups) and groups != [] and groups === Enum.sort(Enum.uniq(groups)) and
                 Enum.all?(groups, &(is_integer(&1) and &1 in 0..(root["groups"] - 1)))

             _ ->
               false
           end),
         true <- E.sha256(json(%{"rows" => rows})) == root["entity_rows_sha256"] do
      {:ok, rows}
    else
      _ -> {:error, :generation_directory_corrupt}
    end
  rescue
    _ -> {:error, :generation_directory_corrupt}
  end

  defp summary?(partition, s, cursor) do
    h = s["header"]
    rows = s["sources"]
    entities = s["entities"]

    exact?(s, ~w(header ref sources entities)) and header?(h, cursor) and
      s["ref"] === ref(unit(partition, "gengrp", h)) and
      is_list(rows) and length(rows) == h["sources"] and
      Enum.all?(rows, fn row ->
        exact?(row, ~w(source_key ordinal text_bytes chunks bundle_sha256 head_sha256)) and
          Enum.all?(~w(source_key bundle_sha256 head_sha256), &E.sha256?(row[&1])) and
          Enum.all?(~w(ordinal text_bytes chunks), &E.safe_uint?(row[&1])) and
          row["ordinal"] < 1000 and row["text_bytes"] <= 65_536 and row["chunks"] in 1..32
      end) and
      Enum.map(rows, & &1["source_key"]) === h["source_keys"] and
      E.sha256(json(%{"sources" => Enum.map(rows, &[&1["source_key"], &1["bundle_sha256"]])})) ==
        h["source_set_sha256"] and
      Enum.sum(Enum.map(rows, & &1["chunks"])) == h["vectors"] and
      is_list(entities) and length(entities) == h["entities"] and
      Enum.all?(entities, fn
        [id, label] ->
          is_binary(label) and byte_size(label) in 1..256 and
            id === E.id("entity", [partition, label])

        _ ->
          false
      end) and
      entities === Enum.uniq_by(entities, &hd/1) |> Enum.sort_by(&List.last/1) and
      E.sha256(json(%{"ids" => Enum.map(entities, &hd/1)})) == h["entity_ids_sha256"]
  rescue
    _ -> false
  end

  defp header?(h, cursor) do
    exact?(h, @header_keys) and h["version"] === 1 and h["kind"] == "shared_projection_group" and
      h["recipe"] == "ipse.evidence.shared_projections.v1" and h["cursor"] === cursor and
      E.safe_uint?(cursor) and rem(cursor, 8) == 0 and h["sources"] in 1..8 and
      is_list(h["source_keys"]) and length(h["source_keys"]) == h["sources"] and
      Enum.all?(h["source_keys"], &E.sha256?/1) and
      length(Enum.uniq(h["source_keys"])) == h["sources"] and
      h["vectors"] in 1..256 and h["facts"] in 1..256 and h["entities"] in 1..512 and
      E.safe_uint?(h["partial_sources"]) and h["partial_sources"] <= h["sources"] and
      Enum.all?(
        ~w(source_set_sha256 vector_identities_sha256 fact_ids_sha256 entity_ids_sha256),
        &E.sha256?(h[&1])
      ) and
      Enum.all?(~w(source_pages vector_pages fact_pages), fn field ->
        is_list(h[field]) and length(h[field]) in 1..128 and Enum.all?(h[field], &reference?/1)
      end) and
      byte_size(json(h)) <= @bytes
  rescue
    _ -> false
  end

  defp root?(r, e) do
    exact?(r, @root_keys) and exact?(e, @expected) and r["version"] === 1 and
      r["kind"] == "shared_generation_directory" and r["recipe"] == @recipe and
      is_binary(r["partition"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, r["partition"]) and
      E.sha256?(e["root_sha256"]) and e["root_sha256"] == E.sha256(json(r)) and
      Enum.all?(@expected -- ["root_sha256"], &(r[&1] === e[&1])) and
      Enum.all?(
        ~w(generation catalog_generation floor sources extracted_bytes chunks vectors facts entities groups),
        &E.safe_uint?(r[&1])
      ) and
      r["generation"] > 0 and r["sources"] in 1..1000 and r["chunks"] in 1..10_000 and
      r["extracted_bytes"] <= 20 * 1024 * 1024 and r["vectors"] == r["chunks"] and
      r["facts"] in 1..20_000 and r["entities"] in 1..5000 and
      r["groups"] == div(r["sources"] + 7, 8) and E.sha256?(r["catalog_sha256"]) and
      E.sha256?(r["source_heads_sha256"]) and E.sha256?(r["entity_rows_sha256"]) and
      is_list(r["manifests"]) and length(r["manifests"]) == div(r["groups"] + 15, 16) and
      is_list(r["entity_pages"]) and length(r["entity_pages"]) == div(r["entities"] + 63, 64) and
      Enum.all?(r["manifests"] ++ r["entity_pages"], &reference?/1) and
      byte_size(json(r)) <= @bytes
  rescue
    _ -> false
  end

  defp manifest_row?(root, row, cursor) do
    exact?(row, ~w(cursor sources header)) and row["cursor"] === cursor and
      is_list(row["sources"]) and
      length(row["sources"]) == min(8, root["sources"] - cursor) and
      Enum.all?(row["sources"], fn
        [k, h] -> E.sha256?(k) and E.sha256?(h)
        _ -> false
      end) and
      reference?(row["header"]) and
      row["header"]["key"] == "gengrp.#{root["partition"]}." <> row["header"]["sha256"]
  end

  defp fetch(partition, prefix, kind, refs, values) do
    Enum.with_index(refs)
    |> Enum.map(fn {ref, n} ->
      true = ref["key"] == "#{prefix}.#{partition}." <> ref["sha256"]
      page = value!(ref, values)

      true =
        exact?(page, ~w(version kind recipe ordinal rows)) and page["version"] === 1 and
          page["kind"] == kind and page["recipe"] == @recipe and page["ordinal"] === n and
          is_list(page["rows"])

      page
    end)
  end

  defp pages(partition, prefix, kind, rows, limit) do
    rows
    |> Enum.chunk_every(limit)
    |> Enum.with_index()
    |> Enum.map(fn {rows, n} ->
      unit(partition, prefix, %{
        "version" => 1,
        "kind" => kind,
        "recipe" => @recipe,
        "ordinal" => n,
        "rows" => rows
      })
    end)
  end

  defp value!(ref, values) do
    true = reference?(ref)
    value = Map.fetch!(values, ref["key"])
    bytes = json(value)
    true = byte_size(bytes) == ref["byte_count"] and E.sha256(bytes) == ref["sha256"]
    value
  end

  defp unit(partition, prefix, value) do
    bytes = json(value)
    true = byte_size(bytes) <= @bytes
    sha = E.sha256(bytes)

    %{
      key: "#{prefix}.#{partition}." <> sha,
      sha256: sha,
      byte_count: byte_size(bytes),
      value: value
    }
  end

  defp ref(unit),
    do: %{"key" => unit.key, "sha256" => unit.sha256, "byte_count" => unit.byte_count}

  defp reference?(r),
    do:
      exact?(r, ~w(key sha256 byte_count)) and is_binary(r["key"]) and
        byte_size(r["key"]) in 1..96 and E.sha256?(r["sha256"]) and is_integer(r["byte_count"]) and
        r["byte_count"] in 2..@bytes

  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp json(v), do: IO.iodata_to_binary(JSON.encode!(v))
end
