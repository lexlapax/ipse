[evidence_path, projection_path] = System.argv()
Code.compiler_options(no_warn_undefined: :all)
Code.compile_file(evidence_path)
Code.compile_file(projection_path)
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection.Projection, as: P

attrs = %{
  "source_id" => "benchmark:synthetic", "partition" => "notes", "generation" => 1,
  "title" => "Synthetic benchmark", "text" => String.duplicate("alpha beta ", 4000),
  "uri" => "local:synthetic", "observed_at_ms" => 10, "event_at_ms" => nil,
  "expires_at_ms" => nil,
  "origin" => %{"kind" => "provided", "store_profile" => "local",
                "partition_or_scope" => "notes", "receipt" => nil, "historical" => false}
}
{:ok, source} = E.collection_source(attrs)
{:ok, chunks} = E.chunks(source)
selection = %{"kind" => "explicit", "profile" => nil, "version" => 1}
citations = for chunk <- Enum.take(chunks, 8) do
  {:ok, c} = E.citation(source, chunk, chunk["start_byte"], chunk["start_byte"] + 10)
  c
end
facts = for n <- 1..32 do
  {:ok, fact} = E.fact(%{"subject" => "subject #{n}", "predicate" => "quotes",
    "object" => "synthetic", "polarity" => "positive", "inferred" => false,
    "valid_from_ms" => nil, "valid_to_ms" => nil, "extraction" => selection,
    "citations" => citations})
  fact
end
{:ok, pages} = P.pack_facts(source, facts, selection)
{:ok, ^facts} = P.unpack_facts(source, pages, selection)
{us, _} = :timer.tc(fn -> for _ <- 1..5, do: ({:ok, ^facts} = P.unpack_facts(source, pages, selection)) end)
IO.puts(Jason.encode!(%{"elapsed_us" => us, "iterations" => 5, "facts" => length(facts),
  "citations" => Enum.sum(Enum.map(facts, &length(&1["citations"]))),
  "source_sha256" => E.sha256(Jason.encode!(source)), "pages_sha256" => E.sha256(Jason.encode!(pages))}))
