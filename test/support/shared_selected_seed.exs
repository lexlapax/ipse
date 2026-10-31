# Trusted private fixture seeding only. The actual worker reads via the host SDK.
input = Jason.decode!(File.read!(hd(System.argv())))
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection.{Generation, Directory}
json = &IO.iodata_to_binary(JSON.encode!(&1))
selection = input["selection"]
extraction = input["extraction"]
bundles = Enum.sort_by(input["bundles"], & &1["source"]["source_key"])

data =
  Enum.map(bundles, fn bundle ->
    source = bundle["source"]
    {:ok, chunks} = E.chunks(source)

    vectors =
      Enum.map(chunks, fn chunk ->
        {:ok, sha} = Ipse.Extension.canonical_digest([chunk["text"]])

        {:ok, vector} =
          E.vector(
            Map.merge(Map.delete(selection, "encoding"), %{
              "chunk_id" => chunk["chunk_id"],
              "input_sha256" => sha,
              "values" => List.duplicate(1.0, selection["dimensions"])
            })
          )

        vector
      end)

    [chunk | _] = chunks

    {:ok, citation} =
      E.citation(
        source,
        chunk,
        chunk["start_byte"],
        min(chunk["start_byte"] + 32, chunk["end_byte"])
      )

    {:ok, fact} =
      E.fact(%{
        "subject" => source["source_id"],
        "predicate" => "quotes",
        "object" => citation["quote"],
        "polarity" => "positive",
        "inferred" => false,
        "valid_from_ms" => nil,
        "valid_to_ms" => nil,
        "extraction" => extraction,
        "citations" => [citation]
      })

    {:ok, expired} = E.fact(Map.drop(fact, ~w(version fact_id)) |> Map.put("valid_to_ms", 15))

    %{
      "source_key" => source["source_key"],
      "source_bundle_sha256" => E.sha256(json.(source)),
      "vectors" => vectors,
      "facts" => [fact, expired]
    }
  end)

{:ok, group} = Generation.pack_group("notes", 0, bundles, data, selection, extraction)

{:ok, summary} =
  Directory.capture("notes", group, bundles, %{
    "cursor" => 0,
    "vector_selection" => selection,
    "fact_selection" => extraction
  })

{:ok, directory} =
  Directory.pack(
    %{"kind" => "collection", "scope" => "project", "partition" => "notes"},
    input["catalog"],
    input["pages"],
    [summary],
    1
  )

values =
  Enum.map(group.values ++ [group.header_unit] ++ directory.values, fn u ->
    %{"key" => u.key, "value" => u.value}
  end) ++ [%{"key" => "generation.notes", "value" => directory.root}]

result = %{
  "values" => values,
  "source_keys" => Enum.map(bundles, & &1["source"]["source_key"]),
  "vectors" => Enum.sum(Enum.map(data, &length(&1["vectors"])))
}

result =
  if input["finalization"] == true do
    captured = Directory.immutable("notes", "gensum", summary)

    {expected, expected_values} =
      if input["paged_finalization"] do
        alias IpseKnowledge.Store.Collection.Paged
        profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

        {:ok, batch} =
          Paged.batch(
            profile,
            input["catalog"],
            [summary],
            Map.new(input["pages"], &{&1["ordinal"], &1}),
            0,
            selection,
            extraction
          )

        stored = Map.new(batch.values, &{&1.key, &1.value})
        {:ok, merged} = Paged.merge("notes", [Directory.reference(batch.run)], [0], stored, 0, 1)
        entity_refs = [Directory.reference(merged.unit)]

        {:ok, root} =
          Paged.root(
            profile,
            input["catalog"],
            2,
            selection,
            extraction,
            %{manifests: [Directory.reference(batch.manifest)], entities: entity_refs},
            %{facts: directory.root["facts"], entities: directory.root["entities"]},
            %{
              heads: directory.root["source_heads_sha256"],
              entities: Paged.commitment(entity_refs, directory.root["entities"], 1)
            }
          )

        {root,
         Enum.map(batch.values ++ [merged.unit], fn u -> %{"key" => u.key, "value" => u.value} end)}
      else
        {Map.put(directory.root, "generation", 2), []}
      end

    Map.merge(result, %{
      "summary" => %{"key" => captured.key, "value" => captured.value},
      "summary_ref" => Directory.reference(captured),
      "expected_root" => expected,
      "expected_root_values" => expected_values,
      "facts" => Enum.sum(Enum.map(data, &length(&1["facts"])))
    })
  else
    result
  end

IO.puts(Jason.encode!(result))
