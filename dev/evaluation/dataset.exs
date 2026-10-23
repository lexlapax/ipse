defmodule Ipse.Development.Evaluation.Dataset do
  @moduledoc """
  Bounded projections, delayed reference normalization and literal citation checks.

  Query projection returns only query ID, project and query text. It never returns
  relevance, expected answers or expected classes. Labels are a separate API for
  review and scoring phases after prediction hashes have been verified. Both are pure;
  the orchestrator owns file access and the freeze-before-input boundary.

  Each JSON member is at most 1 MiB, using the host's duplicate-rejecting decoder.
  Larger workloads refuse visibly rather than dropping documents or questions.
  """

  @document_fields ~w(document_id project source_id generation version title text created_at observed_at state sha256 byte_length media_type)
  @query_fields ~w(query_id project query)
  @contract "sealed_answers_v1"
  @answer_fields ~w(query_id project expected_class expected_refusal expected_answer relevance)
  @source_fields ~w(project source_id generation version sha256)

  @doc "Resolve authored source versions at the comparison's fixed observation time."
  def population(documents, at) do
    observed =
      documents
      |> Enum.filter(&(&1["source"]["observed_at_ms"] <= at))
      |> Enum.sort_by(&{&1["source"]["source_id"], &1["source"]["generation"]})

    suppressed =
      observed
      |> Enum.filter(&(&1["state"] in ~w(forgotten deleted suppressed)))
      |> MapSet.new(&{&1["identity"]["project"], &1["source"]["source_id"]})

    selected =
      observed
      |> Enum.group_by(&{&1["identity"]["project"], &1["source"]["source_id"]})
      |> Enum.map(fn {_, versions} -> Enum.max_by(versions, & &1["source"]["generation"]) end)
      |> Enum.sort_by(&{&1["source"]["source_id"], &1["source"]["generation"]})

    eligible =
      Enum.reject(selected, fn doc ->
        MapSet.member?(suppressed, {doc["identity"]["project"], doc["source"]["source_id"]}) or
          doc["state"] == "expired" or
          (doc["source"]["expires_at_ms"] != nil and doc["source"]["expires_at_ms"] <= at)
      end)

    eligible_keys = MapSet.new(eligible, & &1["key"])

    %{
      observed: observed,
      selected: selected,
      eligible: eligible,
      excluded: Enum.reject(documents, &MapSet.member?(eligible_keys, &1["key"]))
    }
  end

  def queries(bytes, split) do
    project(bytes, fn data ->
      sealed = is_map(data) and data["contract"] == @contract and Map.has_key?(data, "queries")

      require!(
        sealed or
          (is_map(data) and data["schema_version"] === 1 and !Map.has_key?(data, "contract")),
        :dataset_version
      )

      if sealed do
        require!(exact?(data, ~w(contract split queries)), :query_shape)
        require!(data["split"] == split and split == "heldout", :query_split)
      end

      rows = data["queries"]
      require!(list?(rows, 1, 1024), :query_limit)
      require!(text?(split, 64), :invalid_split)

      projected =
        Enum.map(rows, fn row ->
          if sealed,
            do: require!(exact?(row, @query_fields), :query_shape),
            else: require!(is_map(row) and row["split"] == split, :query_split)

          require!(text?(row["query_id"], 256) and name?(row["project"]), :query_identity)
          require!(text?(row["query"], 1024), :query_text)
          Map.take(row, @query_fields)
        end)

      require!(unique?(projected, & &1["query_id"]), :duplicate_query)

      result = %{
        "version" => 1,
        "queries" => projected,
        "excluded_fields" => excluded(rows, @query_fields)
      }

      if sealed, do: Map.put(result, "contract", @contract), else: result
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

          require!(
            Ipse.JSON.safe_uint?(row["generation"]) and row["generation"] > 0,
            :document_generation
          )

          require!(version?(row["version"]), :document_version)
          require!(text?(row["title"], 128) and text?(row["text"], 65_536), :document_text)
          require!(row["byte_length"] === byte_size(row["text"]), :document_length)

          require!(
            Ipse.JSON.sha256?(row["sha256"]) and Ipse.JSON.sha256(row["text"]) == row["sha256"],
            :document_hash
          )

          require!(
            timestamp?(row["created_at"]) and timestamp?(row["observed_at"]),
            :document_time
          )

          require!(text?(row["state"], 64) and text?(row["media_type"], 128), :document_metadata)
          Map.take(row, @document_fields)
        end)

      require!(
        unique?(documents, &Map.take(&1, ~w(project source_id generation))),
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
    project(bytes, fn data ->
      if is_map(data) and data["contract"] == @contract and Map.has_key?(data, "answers") do
        {labels, _answers} = sealed_answers!(data, split)
        labels
      else
        require!(!is_map(data) or !Map.has_key?(data, "contract"), :dataset_version)
        checked!(queries(bytes, split))
        legacy_labels!(data)
      end
    end)
  end

  def references(bytes, split, questions) do
    project(bytes, fn data ->
      {labels, answers} =
        if questions["contract"] == @contract do
          sealed_answers!(data, split)
        else
          require!(
            is_map(data) and data["schema_version"] === 1 and !Map.has_key?(data, "contract"),
            :dataset_version
          )

          checked!(queries(bytes, split))
          labels = legacy_labels!(data)

          answers =
            Map.new(data["queries"], fn row ->
              answer = row["expected_answer"]

              require!(
                is_nil(answer) or
                  (is_binary(answer) and String.valid?(answer) and byte_size(answer) <= 8192),
                :invalid_reference_answer
              )

              {row["query_id"], answer}
            end)

          {labels, answers}
        end

      identity = &Map.take(&1, ~w(query_id project))

      require!(
        Enum.sort(Enum.map(labels["queries"], identity)) ==
          Enum.sort(Enum.map(questions["queries"], identity)),
        :answer_join
      )

      by_id = Map.new(labels["queries"], &{&1["query_id"], &1})

      labels =
        Map.put(
          labels,
          "queries",
          Enum.map(questions["queries"], &Map.fetch!(by_id, &1["query_id"]))
        )

      %{"labels" => labels, "expected_answers" => answers}
    end)
  end

  def sources(bytes) do
    with {:ok, corpus} <- corpus(bytes) do
      {:ok, Map.new(corpus["documents"], &{unit(&1), &1})}
    end
  end

  def citation_checks(rows, sources) do
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

  def reference_checks(labels, sources) do
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

  defp unit(source), do: Enum.map(@source_fields, &source[&1])

  defp sealed_answers!(data, split) do
    require!(
      is_map(data) and data["contract"] == @contract and Map.has_key?(data, "answers"),
      :dataset_version
    )

    require!(
      exact?(data, ~w(contract split commitment_nonce answers)) and
        Ipse.JSON.sha256?(data["commitment_nonce"]),
      :answer_shape
    )

    require!(data["split"] == split and split == "heldout", :query_split)
    require!(list?(data["answers"], 1, 1024), :query_limit)

    rows =
      Enum.map(data["answers"], fn row ->
        require!(exact?(row, @answer_fields), :answer_shape)
        require!(text?(row["query_id"], 256) and name?(row["project"]), :query_identity)

        require!(
          is_nil(row["expected_answer"]) or
            (is_binary(row["expected_answer"]) and String.valid?(row["expected_answer"]) and
               byte_size(row["expected_answer"]) <= 8192),
          :invalid_reference_answer
        )

        require!(row["expected_class"] in ~w(answer conflict open abstain), :label_class)
        require!(is_boolean(row["expected_refusal"]), :label_refusal)
        require!(list?(row["relevance"], 0, 1024), :relevance_limit)

        spans =
          Enum.map(row["relevance"], fn span ->
            require!(
              exact?(span, ~w(source grade start_byte end_byte quote)) and
                exact?(span["source"], @source_fields),
              :invalid_relevance
            )

            relevance!(Map.merge(Map.delete(span, "source"), span["source"]), row["project"])
          end)

        require!(
          unique?(spans, &Map.take(&1, ~w(source start_byte end_byte))),
          :duplicate_relevance
        )

        row
        |> Map.take(~w(query_id project expected_class expected_refusal))
        |> Map.put("relevance", spans)
      end)

    require!(unique?(rows, & &1["query_id"]), :duplicate_query)
    require!(Enum.sum(Enum.map(rows, &length(&1["relevance"]))) <= 65_536, :relevance_limit)

    {%{"version" => 1, "queries" => rows},
     Map.new(data["answers"], &{&1["query_id"], &1["expected_answer"]})}
  end

  defp legacy_labels!(data) do
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

    require!(
      Ipse.JSON.safe_uint?(source["generation"]) and source["generation"] > 0,
      :relevance_source
    )

    require!(
      version?(source["version"]) and Ipse.JSON.sha256?(source["sha256"]),
      :relevance_source
    )

    require!(is_integer(row["grade"]) and row["grade"] in 0..30, :relevance_grade)
    first = row["start_byte"]
    last = row["end_byte"]
    quote = row["quote"]

    require!(
      Ipse.JSON.safe_uint?(first) and Ipse.JSON.safe_uint?(last) and last > first and
        text?(quote, 8192) and
        last - first == byte_size(quote),
      :relevance_span
    )

    Map.merge(Map.take(row, ~w(grade start_byte end_byte quote)), %{"source" => source})
  end

  defp project(bytes, fun) do
    case Ipse.JSON.decode_bounded(bytes, 1_048_576) do
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
      {:ok, time, _offset} -> Ipse.JSON.safe_uint?(DateTime.to_unix(time, :millisecond))
      _ -> false
    end
  end

  defp timestamp?(_), do: false
  defp require!(true, _), do: :ok
  defp require!(_, code), do: throw({:evaluation_input, code})
  defp name?(value), do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..max

  defp version?(value), do: (Ipse.JSON.safe_uint?(value) and value > 0) or text?(value, 64)

  defp list?(value, min, max),
    do: is_list(value) and length(value) >= min and length(value) <= max

  defp unique?(rows, key), do: length(rows) == length(Enum.uniq_by(rows, key))
  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp checked!({:ok, value}), do: value
  defp checked!({:error, code}), do: throw({:evaluation_input, code})
end
