# Finite dry preflight of the current public Collection ingestion recipe.
# It performs no native storage, model inference, acquisition or publication.
{opts, [], []} = OptionParser.parse(System.argv(), strict: [sdk: :string, artifact: :string])
sdk = Path.expand(Keyword.fetch!(opts, :sdk))
Code.prepend_path(sdk)

for dep <- ~w(jason jsonschex ex_json_pointer),
    do: Code.prepend_path(Path.expand("../../#{dep}/ebin", sdk))

artifact = Path.expand(Keyword.fetch!(opts, :artifact))
manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))

for file <- manifest["files"] do
  bytes = File.read!(Path.join(artifact, file["path"]))
  true = byte_size(bytes) == file["bytes"]
  true = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == file["sha256"]
end

for path <- Path.wildcard(Path.join(artifact, "ebin/*.beam")),
    do: {:module, _} = :code.load_abs(String.to_charlist(Path.rootname(path)))

defmodule Ipse.CollectionProfileOperations do
  alias IpseKnowledge.{Evidence, Documents}
  alias IpseKnowledge.Store.Collection
  alias IpseKnowledge.Store.Collection.Projection

  def run do
    samples =
      for {size, count, suffix} <- [{2097, 252, "0000"}, {2096, 748, "0001"}] do
        source_id = "fixture:capacity:" <> suffix
        payload = document(size)
        receipt = Evidence.document_storage_receipt!(payload["document"])

        attrs = %{
          "source_id" => source_id,
          "partition" => "notes",
          "generation" => 1,
          "title" => "Capacity operation lower bound",
          "text" => payload["text"],
          "uri" => "provided:capacity.docx",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => nil,
          "origin" => %{
            "kind" => "provided",
            "store_profile" => "documents",
            "partition_or_scope" => "notes",
            "receipt" => receipt,
            "historical" => false
          }
        }

        attrs =
          if receipt["version"] == 4,
            do: Map.put(attrs, "document", payload["document"]),
            else: attrs

        profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

        {:call, _, plan} =
          Collection.start(profile, :put, %{
            "source" => attrs,
            "expected_revision" => 0,
            "continuation" => nil
          })

        source = plan.source
        {:ok, chunks} = Evidence.chunks(source)
        true = length(chunks) == 10

        selection = %{
          "selection_sha256" => Evidence.sha256("synthetic-shape-1024"),
          "profile" => "provided-shape",
          "model" => "synthetic-capacity-shape",
          "dimensions" => 1024,
          "encoding" => "float32le"
        }

        vectors =
          for {chunk, ordinal} <- Enum.with_index(chunks) do
            {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

            {:ok, vector} =
              Evidence.vector(
                Map.merge(Map.delete(selection, "encoding"), %{
                  "chunk_id" => chunk["chunk_id"],
                  "input_sha256" => input,
                  "values" => for(n <- 1..1024, do: 1.0 + rem(n + ordinal, 17) / 17)
                })
              )

            vector
          end

        {:ok, vector_pages} = Projection.pack(source, vectors, selection)
        extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}
        [first | _] = chunks

        {:ok, citation} =
          Evidence.citation(source, first, first["start_byte"], first["start_byte"] + 32)

        facts =
          for n <- 0..19 do
            {:ok, fact} =
              Evidence.fact(%{
                "subject" => "#{source_id}:Entity#{rem(n, 5)}",
                "object" => "#{source_id}:Entity#{rem(n + 1, 5)}",
                "predicate" => "relation#{n}",
                "polarity" => "positive",
                "inferred" => false,
                "valid_from_ms" => nil,
                "valid_to_ms" => nil,
                "extraction" => extraction,
                "citations" => [citation]
              })

            fact
          end

        {:ok, fact_pages} = Projection.pack_facts(source, facts, extraction)
        source_cost = Enum.map(plan.prepared, &cost/1)
        vector_cost = Enum.map(vector_pages, &cost/1)
        fact_cost = Enum.map(fact_pages, &cost/1)
        # Each selected source needs three prepared metadata values + one CAS.
        # Each source-local projection needs root + catalog preparations + one CAS.
        # These are minimums; bigger metadata can cost more than one mutation.
        costs = %{
          "source" => total(source_cost) + 4,
          "vectors" => total(vector_cost) + 3,
          "facts" => total(fact_cost) + 3
        }

        %{
          "sources" => count,
          "source_text_bytes" => byte_size(source["text"]),
          "chunks_per_source" => length(chunks),
          "vectors_per_source" => length(vectors),
          "assertions_per_source" => length(facts),
          "unique_entities_per_source" => 5,
          "source_values" => source_cost,
          "vector_values" => vector_cost,
          "fact_values" => fact_cost,
          "per_source_mutation_minimum" => costs,
          "mutation_minimum" => count * Enum.sum(Map.values(costs))
        }
      end

    text = Enum.sum(Enum.map(samples, &(&1["sources"] * &1["source_text_bytes"])))
    true = text == 20 * 1024 * 1024
    lower_bound = Enum.sum(Enum.map(samples, & &1["mutation_minimum"]))

    %{
      "version" => 1,
      "kind" => "collection_profile_operation_lower_bound",
      "samples" => samples,
      "sources" => 1000,
      "extracted_bytes" => text,
      "chunks" => 10000,
      "vectors" => 10000,
      "dimensions" => 1024,
      "entities" => 5000,
      "assertions" => 20000,
      "native_mutation_ceiling" => 32768,
      "mandatory_initial_mutation_minimum" => lower_bound,
      "preflight" => if(lower_bound > 32768, do: "refused", else: "remaining_recipe_required"),
      "excluded_work" =>
        ~w(namespace_lexical_index global_graph_catalog_and_index rebuild migration collection retention saved_notes),
      "native_operations_executed" => 0,
      "fixture_geometry_only" => true,
      "model_inference_executed" => false,
      "profile_qualified" => false
    }
  end

  defp cost(value) do
    bytes = json(value)

    base = %{
      "key" => "data.notes." <> Evidence.sha256(bytes),
      "expected_revision" => 0,
      "generation" => 32767
    }

    inline =
      Map.merge(base, %{
        "op" => "value.put_inline",
        "data" => bytes,
        "byte_count" => byte_size(bytes),
        "sha256" => Evidence.sha256(bytes)
      })

    frame = fn request ->
      %{
        "api_version" => 1,
        "kind" => "host_call",
        "request" => %{"op" => "collection.store", "scope" => "project", "request" => request}
      }
    end

    if byte_size(bytes) <= 8192 and Ipse.Extension.validate(frame.(inline)) == :ok do
      %{
        "body_bytes" => byte_size(bytes),
        "transport" => "inline",
        "native_mutations" => 1,
        "maximum_host_frame_bytes" => byte_size(json(frame.(inline)))
      }
    else
      parts =
        Stream.unfold(bytes, fn
          "" ->
            nil

          rest ->
            {part, tail} = Evidence.utf8_prefix(rest, 6144)
            {part, tail}
        end)
        |> Enum.to_list()

      frames =
        Enum.with_index(parts)
        |> Enum.map(fn {data, i} ->
          frame.(%{
            "op" => "value.append",
            "slot" => 0,
            "epoch" => String.duplicate("0", 32),
            "offset" => i * 6144,
            "data" => data,
            "generation" => 32767
          })
        end)

      true = Enum.all?(frames, &(Ipse.Extension.validate(&1) == :ok))

      %{
        "body_bytes" => byte_size(bytes),
        "transport" => "bounded_stage",
        "append_calls" => length(parts),
        "native_mutations" => length(parts) + 3,
        "maximum_host_frame_bytes" => Enum.max(Enum.map(frames, &byte_size(json(&1))))
      }
    end
  end

  defp total(costs), do: Enum.sum(Enum.map(costs, & &1["native_mutations"]))
  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))

  defp document(size) do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    body =
      Enum.map_join(1..10, fn _ ->
        "<w:p><w:r><w:t>" <> String.duplicate("a", size) <> "</w:t></w:r></w:p>"
      end)

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"capacity.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ],
        [:memory]
      )

    {:ok, extraction} = Documents.extract(bytes, "capacity.docx")
    {:ok, payload} = Documents.source_payload(extraction, 65536, 2)
    payload
  end
end

IO.puts(Jason.encode!(Ipse.CollectionProfileOperations.run(), pretty: true))
