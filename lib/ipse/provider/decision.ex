defmodule Ipse.Provider.Decision do
  @moduledoc "Pure wire subsets for advisory decision engines; no transport, credential or authority selection."
  alias Ipse.Decision

  def subset(:openai), do: "openai-decisions-text-v1"
  def subset(:system_one), do: "systemone-text-v1"
  def subset(_), do: nil

  def encode(engine, request, model) do
    with :ok <- Decision.validate_request(request),
         true <- not is_nil(subset(engine)),
         true <- is_binary(model) and Ipse.Provider.model_name(model) == model,
         true <- engine != :openai or model == "gpt-6-luna",
         true <- Enum.all?(request["questions"], &supported_question?/1) do
      {:ok, body(engine, request, model)}
    else
      _ -> {:error, :unsupported_decision_request}
    end
  end

  @doc "Validate the complete native result and preserve native confidence without calibration."
  def decode(engine, request, expected_model, response) do
    with {:ok, _body} <- encode(engine, request, expected_model),
         true <- keys?(response, ~w(model answers usage)),
         true <- response["model"] == expected_model and is_binary(expected_model),
         true <- usage?(response["usage"]),
         true <- byte_size(Jason.encode!(response)) <= 65_536,
         {:ok, answers} <- answers(engine, request["questions"], response["answers"]),
         result = %{"version" => 1, "answers" => answers},
         :ok <- Decision.validate_result(request, result) do
      {:ok, result,
       %{"model" => expected_model, "subset" => subset(engine), "usage" => response["usage"]}}
    else
      _ -> {:error, :invalid_decision_response}
    end
  rescue
    _ -> {:error, :invalid_decision_response}
  end

  defp body(:openai, request, model) do
    %{
      "model" => model,
      "input" => request["input"],
      "questions" => Enum.map(request["questions"], &openai_question/1),
      "prompt_cache_options" => %{"mode" => "explicit"}
    }
  end

  defp body(:system_one, request, model) do
    %{
      "model" => model,
      "state" => request["input"],
      "questions" => Map.new(request["questions"], &{&1["id"], system_one_question(&1)})
    }
  end

  defp openai_question(q) do
    base = %{"name" => q["id"], "type" => q["type"], "instructions" => q["instructions"]}

    case q["type"] do
      "predicate" -> base
      "choice" -> Map.put(base, "choices", Enum.map(q["choices"], &%{"value" => &1}))
      "score" -> Map.put(base, "levels", Enum.map(q["levels"], &%{"label" => &1}))
    end
  end

  defp system_one_question(q) do
    base = %{"type" => q["type"], "instructions" => q["instructions"]}

    case q["type"] do
      "predicate" -> Map.put(base, "type", "noul")
      "choice" -> Map.put(base, "criteria", Map.new(q["choices"], &{&1, nil}))
      "score" -> Map.put(base, "criteria", q["levels"])
    end
  end

  defp supported_question?(%{"type" => "score", "levels" => levels}), do: length(levels) <= 10
  defp supported_question?(_), do: true

  defp answers(:openai, questions, answers) when is_list(answers) do
    if length(questions) == length(answers) do
      collect(Enum.zip(questions, answers), &openai_answer/2)
    else
      {:error, :count}
    end
  end

  defp answers(:system_one, questions, answers) when is_map(answers) do
    if Enum.sort(Map.keys(answers)) == Enum.sort(Enum.map(questions, & &1["id"])) do
      collect(Enum.map(questions, &{&1, answers[&1["id"]]}), &system_one_answer/2)
    else
      {:error, :count}
    end
  end

  defp answers(_, _, _), do: {:error, :shape}

  defp collect(pairs, convert) do
    Enum.reduce_while(pairs, {:ok, []}, fn {q, a}, {:ok, acc} ->
      case convert.(q, a) do
        {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
        _ -> {:halt, {:error, :answer}}
      end
    end)
  end

  defp openai_answer(q, %{"name" => id, "type" => "refusal"} = a) do
    if id == q["id"] and keys?(a, ~w(name type)),
      do: {:ok, %{"id" => id, "type" => "refusal"}},
      else: {:error, :refusal}
  end

  defp openai_answer(q, a) when is_map(a) do
    if a["name"] == q["id"] and a["type"] == q["type"] do
      case q["type"] do
        "predicate" ->
          if keys?(a, ~w(name type probability)),
            do: {:ok, a |> Map.delete("name") |> Map.put("id", q["id"])},
            else: {:error, :fields}

        type when type in ~w(choice score) ->
          value_key = if type == "choice", do: "choice", else: "score"
          expected = ["name", "type", value_key, "confidence", "probabilities"]

          with true <- keys?(a, expected),
               rows when is_list(rows) <- a["probabilities"],
               true <- native_rows?(q, rows),
               distribution =
                 Enum.map(rows, &%{"id" => native_id(q, &1), "probability" => &1["probability"]})
                 |> order_distribution(q) do
            {:ok,
             a
             |> Map.delete("name")
             |> Map.put("id", q["id"])
             |> Map.put("probabilities", distribution)}
          else
            _ -> {:error, :distribution}
          end
      end
    else
      {:error, :identity}
    end
  end

  defp openai_answer(_, _), do: {:error, :shape}

  defp native_rows?(%{"type" => "choice"}, rows),
    do: Enum.all?(rows, &(keys?(&1, ~w(value probability)) and is_binary(&1["value"])))

  defp native_rows?(%{"type" => "score", "levels" => levels}, rows) do
    Enum.all?(rows, fn row ->
      keys?(row, ~w(value label probability)) and is_integer(row["value"]) and
        row["value"] >= 0 and row["value"] < length(levels) and
        Enum.at(levels, row["value"]) == row["label"]
    end)
  end

  defp native_id(%{"type" => "choice"}, row), do: row["value"]
  defp native_id(%{"type" => "score"}, row), do: Integer.to_string(row["value"])

  defp system_one_answer(q, a) when is_map(a) do
    case q["type"] do
      "predicate" ->
        if keys?(a, ~w(type noul)) and a["type"] == "noul",
          do: {:ok, %{"id" => q["id"], "type" => "predicate", "probability" => a["noul"]}},
          else: {:error, :fields}

      type when type in ~w(choice score) ->
        value_key = if type == "choice", do: "choice", else: "score"

        expected =
          ["type", value_key, "confidence", "probabilities"] ++
            if(type == "score", do: ["legend"], else: [])

        with true <- keys?(a, expected) and a["type"] == type,
             true <-
               type != "score" or
                 a["legend"] ==
                   Map.new(Enum.with_index(q["levels"]), fn {label, index} ->
                     {Integer.to_string(index), label}
                   end),
             rows when is_map(rows) <- a["probabilities"] do
          distribution =
            rows
            |> Enum.map(fn {id, p} -> %{"id" => id, "probability" => p} end)
            |> order_distribution(q)

          {:ok,
           a
           |> Map.delete("legend")
           |> Map.put("id", q["id"])
           |> Map.put("probabilities", distribution)}
        else
          _ -> {:error, :distribution}
        end
    end
  end

  defp system_one_answer(_, _), do: {:error, :shape}

  defp order_distribution(rows, q) do
    ids =
      if q["type"] == "choice",
        do: q["choices"],
        else: Enum.map(0..(length(q["levels"]) - 1), &Integer.to_string/1)

    ranks = ids |> Enum.with_index() |> Map.new()
    Enum.sort_by(rows, &Map.get(ranks, &1["id"], 99))
  end

  defp usage?(usage) when is_map(usage) do
    required = ~w(input_tokens output_tokens)
    allowed = required ++ ~w(input_tokens_details output_tokens_details total_tokens)

    Enum.all?(required, &Map.has_key?(usage, &1)) and
      Enum.all?(Map.keys(usage), &(&1 in allowed)) and
      Enum.all?(required, &Ipse.JSON.safe_uint?(usage[&1])) and
      (not Map.has_key?(usage, "total_tokens") or
         (Ipse.JSON.safe_uint?(usage["total_tokens"]) and
            usage["total_tokens"] === usage["input_tokens"] + usage["output_tokens"])) and
      details?(
        usage,
        "input_tokens_details",
        ~w(cached_tokens cache_write_tokens),
        usage["input_tokens"]
      ) and
      details?(usage, "output_tokens_details", ~w(reasoning_tokens), usage["output_tokens"])
  end

  defp usage?(_), do: false

  defp details?(usage, key, allowed, total) do
    case Map.fetch(usage, key) do
      :error ->
        true

      {:ok, details} when is_map(details) ->
        Enum.all?(Map.keys(details), &(&1 in allowed)) and
          Enum.all?(Map.values(details), &Ipse.JSON.safe_uint?/1) and
          Enum.sum(Map.values(details)) <= total

      _ ->
        false
    end
  end

  defp keys?(map, fields), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(fields)
end
