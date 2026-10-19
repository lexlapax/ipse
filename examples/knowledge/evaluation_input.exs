defmodule IpseKnowledgeExample.EvaluationInput do
  @moduledoc """
  Bounded projections of the version-one evaluation dataset.

  Query projection returns only query ID, project and query text. It never returns
  relevance, expected answers or expected classes. Labels are a separate API for
  the scoring phase after prediction hashes have been verified. Both are pure;
  the orchestrator owns file access and the freeze-before-input boundary.

  Each JSON member is at most 1 MiB, using the host's duplicate-rejecting decoder.
  Larger workloads refuse visibly rather than dropping documents or questions.
  """
  alias Ipse.Extensions.Manifest

  @document_fields ~w(document_id project source_id generation version title text created_at observed_at state sha256 byte_length media_type)
  @query_fields ~w(query_id project query)
  @safe 9_007_199_254_740_991

  def queries(bytes, split) do
    project(bytes, fn data ->
      require!(is_map(data) and data["schema_version"] === 1, :dataset_version)
      rows = data["queries"]
      require!(list?(rows, 1, 1024), :query_limit)
      require!(text?(split, 64), :invalid_split)

      projected =
        Enum.map(rows, fn row ->
          require!(is_map(row) and row["split"] == split, :query_split)
          require!(text?(row["query_id"], 256) and name?(row["project"]), :query_identity)
          require!(text?(row["query"], 1024), :query_text)
          Map.take(row, @query_fields)
        end)

      require!(unique?(projected, & &1["query_id"]), :duplicate_query)

      %{
        "version" => 1,
        "queries" => projected,
        "excluded_fields" => excluded(rows, @query_fields)
      }
    end)
  end

  def corpus(bytes) do
    project(bytes, fn data ->
      require!(is_map(data) and data["schema_version"] === 1, :dataset_version)
      rows = data["documents"]
      require!(list?(rows, 0, 256), :document_limit)

      documents =
        Enum.map(rows, fn row ->
          require!(is_map(row), :invalid_document)
          require!(text?(row["document_id"], 128) and name?(row["project"]), :document_identity)
          require!(text?(row["source_id"], 256), :document_identity)
          require!(uint?(row["generation"]) and row["generation"] > 0, :document_generation)
          require!(version?(row["version"]), :document_version)
          require!(text?(row["title"], 128) and text?(row["text"], 65_536), :document_text)
          require!(row["byte_length"] === byte_size(row["text"]), :document_length)
          require!(hash?(row["sha256"]) and sha(row["text"]) == row["sha256"], :document_hash)

          require!(
            timestamp?(row["created_at"]) and timestamp?(row["observed_at"]),
            :document_time
          )

          require!(text?(row["state"], 64) and text?(row["media_type"], 128), :document_metadata)
          Map.take(row, @document_fields)
        end)

      require!(
        unique?(documents, &Map.take(&1, ~w(project source_id generation version))),
        :duplicate_source_generation
      )

      %{
        "version" => 1,
        "documents" => documents,
        "excluded_fields" => excluded(rows, @document_fields)
      }
    end)
  end

  def labels(bytes, split) do
    with {:ok, _projection} <- queries(bytes, split) do
      project(bytes, fn data ->
        rows =
          Enum.map(data["queries"], fn row ->
            require!(row["expected_class"] in ~w(answer conflict open abstain), :label_class)
            refusal = Map.get(row, "expected_refusal", false)
            require!(is_boolean(refusal), :label_refusal)
            relevance = row["relevance"]
            require!(list?(relevance, 0, 1024), :relevance_limit)

            %{
              "query_id" => row["query_id"],
              "project" => row["project"],
              "expected_class" => row["expected_class"],
              "expected_refusal" => refusal,
              "relevance" => Enum.map(relevance, &relevance!(&1, row["project"]))
            }
          end)

        require!(Enum.sum(Enum.map(rows, &length(&1["relevance"]))) <= 65_536, :relevance_limit)
        %{"version" => 1, "queries" => rows}
      end)
    end
  end

  defp relevance!(row, project) do
    require!(is_map(row), :invalid_relevance)
    require!(Map.get(row, "project", project) == project, :relevance_project)

    source = %{
      "project" => project,
      "source_id" => row["source_id"],
      "generation" => row["generation"],
      "version" => row["version"],
      "sha256" => row["sha256"]
    }

    require!(text?(source["source_id"], 256), :relevance_source)
    require!(uint?(source["generation"]) and source["generation"] > 0, :relevance_source)
    require!(version?(source["version"]) and hash?(source["sha256"]), :relevance_source)
    require!(is_integer(row["grade"]) and row["grade"] in 0..30, :relevance_grade)
    first = row["start_byte"]
    last = row["end_byte"]
    quote = row["quote"]

    require!(
      uint?(first) and uint?(last) and last > first and text?(quote, 8192) and
        last - first == byte_size(quote),
      :relevance_span
    )

    Map.merge(Map.take(row, ~w(grade start_byte end_byte quote)), %{"source" => source})
  end

  defp project(bytes, fun) do
    case Manifest.decode_json(bytes, 1_048_576) do
      {:ok, data} -> {:ok, fun.(data)}
      {:error, code} -> {:error, code}
    end
  catch
    {:evaluation_input, code} -> {:error, code}
  end

  defp excluded(rows, selected) do
    rows
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in selected))
    |> Enum.sort()
  end

  defp timestamp?(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> uint?(DateTime.to_unix(time, :millisecond))
      _ -> false
    end
  end

  defp timestamp?(_), do: false
  defp sha(bytes), do: Manifest.sha256(bytes)
  defp require!(true, _), do: :ok
  defp require!(_, code), do: throw({:evaluation_input, code})
  defp name?(value), do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..max

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp uint?(value), do: is_integer(value) and value in 0..@safe
  defp version?(value), do: (uint?(value) and value > 0) or text?(value, 64)

  defp list?(value, min, max),
    do: is_list(value) and length(value) >= min and length(value) <= max

  defp unique?(rows, key), do: length(rows) == length(Enum.uniq_by(rows, key))
end
