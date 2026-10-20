Code.require_file("evaluation_input.exs", __DIR__)

defmodule IpseKnowledge.EvaluationIntegrity do
  @moduledoc "Literal citation checks against hash-validated captured corpus bytes."
  @identity ~w(project source_id generation version sha256)

  def sources(bytes) do
    with {:ok, corpus} <- IpseKnowledgeExample.EvaluationInput.corpus(bytes) do
      {:ok, Map.new(corpus["documents"], &{unit(&1), &1})}
    end
  end

  def predictions(rows, sources) do
    for row <- rows, span <- row["evidence"] ++ row["context_evidence"] do
      %{
        "prediction_id" => row["prediction_id"],
        "span_id" => span["span_id"],
        "verdict" => if(literal?(span, sources, row["project"]), do: "valid", else: "invalid"),
        "reviewer_id" => "source-bytes-v1",
        "independent" => true
      }
    end
  end

  def references(labels, sources) do
    for q <- labels, {span, index} <- Enum.with_index(q["relevance"], 1) do
      %{
        "query_id" => q["query_id"],
        "reference_index" => index,
        "valid" => literal?(span, sources, q["project"])
      }
    end
  end

  defp literal?(span, sources, project) do
    case sources[unit(span["source"])] do
      %{"text" => body} ->
        first = span["start_byte"]
        last = span["end_byte"]

        span["source"]["project"] == project and first >= 0 and last <= byte_size(body) and
          last > first and binary_part(body, first, last - first) == span["quote"]

      _ ->
        false
    end
  end

  defp unit(source), do: Enum.map(@identity, &source[&1])
end
