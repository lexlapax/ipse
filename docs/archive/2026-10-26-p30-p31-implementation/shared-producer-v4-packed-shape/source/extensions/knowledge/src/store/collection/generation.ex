defmodule IpseKnowledge.Store.Collection.Generation do
  @moduledoc """
  Lossless shared projection pages for a captured group of document sources.

  This codec grants no authority and performs no storage or inference. Its input
  bundles come from the Collection client's authenticated private bundle read.
  A generation controller must bind their captured catalog and select all groups
  atomically. Building pages is not publication or capacity qualification.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection.Paged
  alias IpseKnowledge.Store.Collection.Projection, as: P
  alias IpseKnowledge.Store.Collection, as: C
  @bytes 48 * 1024
  @recipe "ipse.evidence.shared_projections.v1"

  def pack_group(partition, cursor, bundles, supplied, selection, extraction) do
    with true <- is_binary(partition) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, partition),
         true <- E.safe_uint?(cursor) and rem(cursor, 8) == 0,
         true <- is_list(bundles) and length(bundles) in 1..8,
         true <- is_list(supplied) and length(supplied) == length(bundles),
         true <- length(Enum.uniq_by(bundles, & &1["source"]["source_key"])) == length(bundles),
         true <- Enum.all?(bundles, &bundle?(&1, partition)),
         true <-
           Enum.zip(bundles, supplied)
           |> Enum.all?(fn {bundle, data} ->
             source = bundle["source"]

             exact?(data, ~w(source_key source_bundle_sha256 vectors facts)) and
               data["source_key"] == source["source_key"] and
               data["source_bundle_sha256"] == E.sha256(json(source)) and
               match?({:ok, _}, P.pack(source, data["vectors"], selection)) and
               canonical_facts?(source, data["facts"]) and
               match?({:ok, _}, P.pack_facts(source, data["facts"], extraction))
           end) do
      identities = Enum.map(bundles, &[&1["source"]["source_key"], E.sha256(json(&1["source"]))])
      set_hash = E.sha256(json(%{"sources" => identities}))

      source_rows =
        Enum.map(bundles, fn bundle ->
          source = bundle["source"]
          receipt = E.document_receipt(source)
          warnings = if is_map(receipt), do: receipt["warnings"], else: []

          %{
            "source_key" => source["source_key"],
            "source_id" => source["source_id"],
            "head" => bundle["head"],
            "observed_at_ms" => source["observed_at_ms"],
            "expires_at_ms" => source["expires_at_ms"],
            "historical" => source["origin"]["historical"],
            "document_status" => if(is_map(receipt), do: receipt["status"], else: nil),
            "warning_count" => length(warnings),
            "warnings_sha256" => E.sha256(json(%{"warnings" => warnings}))
          }
        end)

      vector_rows =
        supplied
        |> Enum.with_index()
        |> Enum.flat_map(fn {data, source_i} ->
          Enum.with_index(data["vectors"])
          |> Enum.map(fn {vector, chunk_i} ->
            vector_row(vector, source_i, chunk_i)
          end)
        end)

      fact_rows =
        Enum.zip(bundles, supplied)
        |> Enum.with_index()
        |> Enum.flat_map(fn {{bundle, data}, source_i} ->
          {:ok, chunks} = E.chunks(bundle["source"])

          positions =
            chunks |> Enum.with_index() |> Map.new(fn {chunk, i} -> {chunk["chunk_id"], i} end)

          Enum.map(data["facts"], fn fact ->
            [
              source_i,
              fact["subject"],
              fact["predicate"],
              fact["object"],
              fact["polarity"],
              fact["inferred"],
              fact["valid_from_ms"],
              fact["valid_to_ms"],
              Enum.map(fact["citations"], fn c ->
                [positions[c["chunk_id"]], c["start_byte"], c["end_byte"], c["quote_sha256"]]
              end)
            ]
          end)
        end)

      with {:ok, source_pages} <- pages(source_rows, &page("sources", set_hash, &1, &2)),
           {:ok, vector_pages} <- pages(vector_rows, &page("vectors", set_hash, &1, &2)),
           {:ok, fact_pages} <- pages(fact_rows, &fact_page(set_hash, &1, &2)) do
        source_units = units(partition, "gensrc", source_pages)
        vector_units = units(partition, "genvec", vector_pages)
        fact_units = units(partition, "genfact", fact_pages)

        vector_ids =
          for data <- supplied, v <- data["vectors"], do: [v["chunk_id"], v["vector_sha256"]]

        fact_ids = for data <- supplied, f <- data["facts"], do: f["fact_id"]
        true = length(Enum.uniq(fact_ids)) == length(fact_ids)

        entities =
          fact_rows
          |> Enum.flat_map(fn [_, subject, _, object | _] -> [subject, object] end)
          |> Enum.uniq()
          |> Enum.sort()

        entity_ids = Enum.map(entities, &E.id("entity", [partition, &1]))

        header = %{
          "version" => 1,
          "kind" => "shared_projection_group",
          "recipe" => @recipe,
          "cursor" => cursor,
          "source_set_sha256" => set_hash,
          "source_keys" => Enum.map(identities, &hd/1),
          "sources" => length(bundles),
          "vectors" => length(vector_ids),
          "facts" => length(fact_ids),
          "entities" => length(entities),
          "partial_sources" => Enum.count(source_rows, &(&1["document_status"] == "partial")),
          "vector_selection" => selection,
          "fact_selection" => extraction,
          "vector_identities_sha256" => E.sha256(json(%{"ids" => vector_ids})),
          "fact_ids_sha256" => E.sha256(json(%{"ids" => fact_ids})),
          "entity_ids_sha256" => E.sha256(json(%{"ids" => entity_ids})),
          "source_pages" => Enum.map(source_units, &ref/1),
          "vector_pages" => Enum.map(vector_units, &ref/1),
          "fact_pages" => Enum.map(fact_units, &ref/1)
        }

        if Paged.native_value?(header) do
          {:ok,
           %{
             header: header,
             header_unit: unit(partition, "gengrp", header),
             values: source_units ++ vector_units ++ fact_units,
             entities:
               Enum.zip(entity_ids, entities) |> Enum.map(fn {id, label} -> [id, label] end)
           }}
        else
          {:error, :shared_projection_directory_bound}
        end
      end
    else
      _ -> {:error, :invalid_shared_projection_group}
    end
  rescue
    _ -> {:error, :invalid_shared_projection_group}
  end

  @doc "One canonical 1024D shared page at an eight-aligned chunk offset."
  def vector_page(partition, cursor, bundles, vectors, selection, start) do
    with true <- is_integer(start) and start in 0..248 and rem(start, 8) == 0,
         true <- selection["dimensions"] === 1024,
         true <- P.valid_selection?(selection),
         true <- is_binary(partition) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, partition),
         true <- E.safe_uint?(cursor) and rem(cursor, 8) == 0,
         true <- is_list(bundles) and length(bundles) in 1..8,
         true <- Enum.all?(bundles, &bundle?(&1, partition)),
         true <- length(Enum.uniq_by(bundles, & &1["source"]["source_key"])) == length(bundles),
         chunks =
           bundles
           |> Enum.with_index()
           |> Enum.flat_map(fn {bundle, source_i} ->
             {:ok, chunks} = E.chunks(bundle["source"])

             Enum.with_index(chunks)
             |> Enum.map(fn {chunk, chunk_i} -> {source_i, chunk_i, chunk} end)
           end),
         expected = Enum.slice(chunks, start, 8),
         true <- is_list(vectors) and length(vectors) == length(expected) and expected != [],
         true <-
           Enum.zip(vectors, expected)
           |> Enum.all?(fn {v, {_, _, chunk}} ->
             E.current_vector?(v) and
               Map.take(v, ~w(selection_sha256 profile model dimensions encoding)) === selection and
               E.vector_input_matches_chunk?(v, chunk)
           end),
         rows =
           Enum.zip(vectors, expected)
           |> Enum.map(fn {v, {si, ci, _}} -> vector_row(v, si, ci) end),
         identities =
           Enum.map(bundles, &[&1["source"]["source_key"], E.sha256(json(&1["source"]))]),
         set = E.sha256(json(%{"sources" => identities})),
         value = page("vectors", set, rows, div(start, 8)),
         true <- Paged.native_value?(value) do
      {:ok, unit(partition, "genvec", value)}
    else
      _ -> {:error, :invalid_shared_vector_page}
    end
  rescue
    _ -> {:error, :invalid_shared_vector_page}
  end

  @doc "Decode complete ordered shared vector pages against their original group chunks."
  def unpack_vector_pages(partition, cursor, bundles, values, selection) do
    with true <- is_list(bundles) and length(bundles) in 1..8,
         true <- Enum.all?(bundles, &bundle?(&1, partition)),
         true <- P.valid_selection?(selection) and selection["dimensions"] === 1024,
         chunks =
           Enum.map(bundles, fn b ->
             {:ok, chunks} = E.chunks(b["source"])
             chunks
           end),
         total = Enum.sum(Enum.map(chunks, &length/1)),
         true <- is_list(values) and length(values) == div(total + 7, 8),
         decoded =
           Enum.map(values, fn p ->
             Enum.map(p["rows"], &decode_vector_row(&1, chunks, selection))
           end),
         true <-
           Enum.with_index(values)
           |> Enum.all?(fn {p, n} ->
             {:ok, canonical} =
               vector_page(partition, cursor, bundles, Enum.at(decoded, n), selection, n * 8)

             canonical.value === p
           end) do
      {:ok, Enum.concat(decoded)}
    else
      _ -> {:error, :shared_projection_corrupt}
    end
  rescue
    _ -> {:error, :shared_projection_corrupt}
  end

  @doc "Decode one exact canonical page without claiming complete group coverage."
  def unpack_vector_page(partition, cursor, bundles, value, selection, start) do
    with true <- is_list(bundles) and length(bundles) in 1..8,
         true <- Enum.all?(bundles, &bundle?(&1, partition)),
         chunks =
           Enum.map(bundles, fn b ->
             {:ok, chunks} = E.chunks(b["source"])
             chunks
           end),
         vectors = Enum.map(value["rows"], &decode_vector_row(&1, chunks, selection)),
         {:ok, canonical} <- vector_page(partition, cursor, bundles, vectors, selection, start),
         true <- canonical.value === value do
      {:ok, vectors}
    else
      _ -> {:error, :shared_projection_corrupt}
    end
  rescue
    _ -> {:error, :shared_projection_corrupt}
  end

  defp decode_vector_row([si, ci, input, sha, encoded], chunks, selection) do
    true = is_list(encoded) and length(encoded) in 1..4

    bytes =
      Enum.map_join(encoded, fn part ->
        true = is_binary(part) and byte_size(part) <= 5464
        {:ok, bytes} = Base.decode64(part)
        true = Base.encode64(bytes) === part
        bytes
      end)

    true = byte_size(bytes) === selection["dimensions"] * 4 and E.sha256(bytes) === sha
    chunk = at!(at!(chunks, si), ci)

    vector =
      selection
      |> Map.merge(%{
        "version" => 2,
        "chunk_id" => chunk["chunk_id"],
        "input_sha256" => input,
        "vector_sha256" => sha,
        "values" => for(<<n::float-little-32 <- bytes>>, do: n)
      })

    true = E.current_vector?(vector) and E.vector_input_matches_chunk?(vector, chunk)
    vector
  end

  defp vector_row(vector, source_i, chunk_i) do
    bytes = for n <- vector["values"], into: <<>>, do: <<n::float-little-32>>
    [source_i, chunk_i, vector["input_sha256"], vector["vector_sha256"], pieces(bytes)]
  end

  def unpack_group(partition, header, values, bundles, expected) do
    with true <-
           is_map(header) and is_map(values) and is_list(bundles) and length(bundles) in 1..8,
         true <-
           exact?(expected, ~w(cursor vector_selection fact_selection)) and
             Map.take(header, ~w(cursor vector_selection fact_selection)) === expected,
         source_pages = fetch_pages(header["source_pages"], values),
         vector_pages = fetch_pages(header["vector_pages"], values),
         fact_pages = fetch_pages(header["fact_pages"], values),
         sources = Enum.map(bundles, & &1["source"]),
         chunks =
           Enum.map(sources, fn source ->
             {:ok, chunks} = E.chunks(source)
             chunks
           end),
         vectors = Enum.flat_map(vector_pages, & &1["rows"]),
         facts =
           Enum.flat_map(fact_pages, fn page ->
             Enum.map(page["rows"], fn [
                                         source_i,
                                         subject,
                                         predicate,
                                         object,
                                         polarity,
                                         inferred,
                                         from,
                                         to,
                                         spans
                                       ] ->
               source = at!(sources, source_i)
               source_chunks = at!(chunks, source_i)

               citations =
                 Enum.map(spans, fn [chunk, start, finish, sha] ->
                   {:ok, citation} = E.citation(source, at!(source_chunks, chunk), start, finish)
                   true = citation["quote_sha256"] == sha
                   citation
                 end)

               {:ok, fact} =
                 E.fact(%{
                   "subject" => at!(page["entities"], subject),
                   "predicate" => predicate,
                   "object" => at!(page["entities"], object),
                   "polarity" => polarity,
                   "inferred" => inferred,
                   "valid_from_ms" => from,
                   "valid_to_ms" => to,
                   "extraction" => header["fact_selection"],
                   "citations" => citations
                 })

               {source_i, fact}
             end)
           end),
         decoded_vectors =
           Enum.map(vectors, fn [source_i, chunk_i, input, sha, encoded] ->
             true = is_list(encoded) and length(encoded) in 1..4

             bytes =
               Enum.map_join(encoded, fn part ->
                 true = is_binary(part) and byte_size(part) <= 5464
                 {:ok, bytes} = Base.decode64(part)
                 true = Base.encode64(bytes) == part
                 bytes
               end)

             true =
               byte_size(bytes) == header["vector_selection"]["dimensions"] * 4 and
                 E.sha256(bytes) == sha

             chunk = at!(at!(chunks, source_i), chunk_i)

             vector =
               header["vector_selection"]
               |> Map.merge(%{
                 "version" => 2,
                 "chunk_id" => chunk["chunk_id"],
                 "input_sha256" => input,
                 "vector_sha256" => sha,
                 "values" => for(<<n::float-little-32 <- bytes>>, do: n)
               })

             {source_i, vector}
           end),
         supplied =
           Enum.with_index(bundles)
           |> Enum.map(fn {bundle, i} ->
             %{
               "source_key" => bundle["source"]["source_key"],
               "source_bundle_sha256" => E.sha256(json(bundle["source"])),
               "vectors" => for({^i, v} <- decoded_vectors, do: v),
               "facts" => for({^i, f} <- facts, do: f)
             }
           end),
         {:ok, plan} <-
           pack_group(
             partition,
             header["cursor"],
             bundles,
             supplied,
             header["vector_selection"],
             header["fact_selection"]
           ),
         true <- header === plan.header,
         true <-
           Enum.all?(plan.values, fn unit -> Map.fetch!(values, unit.key) === unit.value end),
         true <-
           source_pages ===
             Enum.map(
               Enum.filter(plan.values, &(&1.value["kind"] == "shared_sources")),
               & &1.value
             ) do
      {:ok, supplied}
    else
      _ -> {:error, :shared_projection_corrupt}
    end
  rescue
    _ -> {:error, :shared_projection_corrupt}
  end

  defp canonical_facts?(source, facts) do
    with true <- is_list(facts) and length(facts) in 1..32,
         {:ok, chunks} <- E.chunks(source),
         by_id = Map.new(chunks, &{&1["chunk_id"], &1}) do
      Enum.all?(facts, fn fact ->
        fact["version"] === 1 and is_list(fact["citations"]) and length(fact["citations"]) in 1..8 and
          Enum.all?(fact["citations"], fn citation ->
            case E.citation(
                   source,
                   Map.fetch!(by_id, citation["chunk_id"]),
                   citation["start_byte"],
                   citation["end_byte"]
                 ) do
              {:ok, canonical} -> canonical === citation
              _ -> false
            end
          end)
      end)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp fetch_pages(refs, values) do
    true = is_list(refs) and length(refs) in 1..128

    Enum.map(refs, fn ref ->
      true = exact?(ref, ~w(key sha256 byte_count))
      value = Map.fetch!(values, ref["key"])
      bytes = json(value)

      true =
        byte_size(bytes) <= @bytes and byte_size(bytes) == ref["byte_count"] and
          E.sha256(bytes) == ref["sha256"]

      value
    end)
  end

  defp at!(values, i) do
    true = is_list(values) and values != [] and is_integer(i) and i in 0..(length(values) - 1)
    Enum.fetch!(values, i)
  end

  defp bundle?(bundle, partition) do
    source = bundle["source"]
    head = bundle["head"]

    with true <-
           exact?(bundle, ~w(source head)) and E.valid_source?(source) and
             source["partition"] == partition,
         {:ok, chunks} <- E.chunks(source),
         true <- C.valid_source_head?(head, source["source_key"]),
         true <-
           head["source_key"] == source["source_key"] and
             head["generation"] == source["generation"],
         true <-
           head["bundle_sha256"] == E.sha256(json(source)) and
             head["byte_count"] == byte_size(json(source)),
         true <-
           head["text_bytes"] == byte_size(source["text"]) and head["chunks"] == length(chunks) do
      true
    else
      _ -> false
    end
  end

  defp pages(rows, make) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, pages} ->
      fresh = make.([row], length(pages))

      case List.last(pages) do
        nil ->
          if Paged.native_value?(fresh),
            do: {:cont, {:ok, [{[row], fresh}]}},
            else: {:halt, {:error, :shared_projection_row_bound}}

        {raw, _} ->
          candidate = make.(raw ++ [row], length(pages) - 1)

          cond do
            Paged.native_value?(candidate) ->
              {:cont, {:ok, List.replace_at(pages, -1, {raw ++ [row], candidate})}}

            Paged.native_value?(fresh) ->
              {:cont, {:ok, pages ++ [{[row], fresh}]}}

            true ->
              {:halt, {:error, :shared_projection_row_bound}}
          end
      end
    end)
    |> case do
      {:ok, pages} -> {:ok, Enum.map(pages, &elem(&1, 1))}
      other -> other
    end
  end

  defp page(kind, set, rows, ordinal),
    do: %{
      "version" => 1,
      "kind" => "shared_" <> kind,
      "recipe" => @recipe,
      "source_set_sha256" => set,
      "ordinal" => ordinal,
      "rows" => rows
    }

  defp fact_page(set, rows, ordinal) do
    entities =
      rows |> Enum.flat_map(fn [_, s, _, o | _] -> [s, o] end) |> Enum.uniq() |> Enum.sort()

    indexed =
      Enum.map(rows, fn [source, subject, predicate, object | tail] ->
        [
          source,
          Enum.find_index(entities, &(&1 == subject)),
          predicate,
          Enum.find_index(entities, &(&1 == object)) | tail
        ]
      end)

    page("facts", set, indexed, ordinal) |> Map.put("entities", entities)
  end

  defp units(partition, prefix, pages), do: Enum.map(pages, &unit(partition, prefix, &1))

  defp unit(partition, prefix, value) do
    bytes = json(value)
    sha = E.sha256(bytes)

    %{
      key: prefix <> "." <> partition <> "." <> sha,
      sha256: sha,
      byte_count: byte_size(bytes),
      value: value
    }
  end

  defp ref(unit),
    do:
      Map.take(unit, [:key, :sha256, :byte_count])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

  defp pieces(""), do: []

  defp pieces(bytes) do
    n = min(byte_size(bytes), 4096)

    [
      Base.encode64(binary_part(bytes, 0, n))
      | pieces(binary_part(bytes, n, byte_size(bytes) - n))
    ]
  end

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
end
