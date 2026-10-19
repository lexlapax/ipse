defmodule IpseKnowledgeExample.EvaluationAuthor do
  @moduledoc "Source-only explicit-fact authoring, executed outside the harness VM."
  alias IpseKnowledge.Evidence

  @grammar ~r/([^.!?\n]+?)\s+(requires|depends on|uses|is|are|opens at|closes at|has)\s+([^.!?\n]+)[.!?]?/u

  def prepare(rows) do
    Enum.map(rows, fn row ->
      {:ok, source} = Evidence.source(row["attrs"])
      {:ok, chunks} = Evidence.chunks(source)

      facts =
        Map.new(chunks, fn chunk ->
          selected =
            Regex.scan(@grammar, chunk["text"], return: :index)
            |> Enum.flat_map(fn [{offset, length}, subject, predicate, object] ->
              attrs = %{
                "subject" => part(chunk["text"], subject),
                "predicate" => part(chunk["text"], predicate),
                "object" => part(chunk["text"], object),
                "polarity" => "positive",
                "inferred" => false,
                "valid_from_ms" => nil,
                "valid_to_ms" => nil,
                "extraction" => %{"kind" => "explicit", "profile" => nil, "version" => 1}
              }

              with true <- length <= 1024,
                   {:ok, citation} <-
                     Evidence.citation(
                       source,
                       chunk,
                       chunk["start_byte"] + offset,
                       chunk["start_byte"] + offset + length
                     ),
                   {:ok, fact} <- Evidence.fact(Map.put(attrs, "citations", [citation])) do
                [fact]
              else
                _ -> []
              end
            end)
            |> Enum.take(1)

          {chunk["chunk_id"], selected}
        end)

      %{
        "key" => row["key"],
        "source" => Map.drop(row["attrs"], ~w(partition origin)),
        "chunks" => chunks,
        "facts" => facts
      }
    end)
  end

  defp part(text, {offset, length}), do: binary_part(text, offset, length) |> String.trim()
end
