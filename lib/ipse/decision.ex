defmodule Ipse.Decision do
  @moduledoc "Bounded typed advisory decisions. Validation establishes structure, never truth or authority."

  @request_keys ~w(version profile input questions)
  @sum_tolerance 0.000001

  def validate_request(request) do
    with true <- keys?(request, @request_keys),
         true <- request["version"] === 1 and id?(request["profile"]),
         true <- text?(request["input"], 16_384),
         questions when is_list(questions) <- request["questions"],
         true <- length(questions) in 1..32,
         true <- Enum.all?(questions, &question?/1),
         true <- unique?(questions, & &1["id"]),
         true <- byte_size(Jason.encode!(request)) <= 32_768 do
      :ok
    else
      _ -> {:error, :invalid_decision_request}
    end
  rescue
    _ -> {:error, :invalid_decision_request}
  end

  @doc "Require one typed answer or explicit refusal per question, in the original order."
  def validate_result(request, result) do
    with :ok <- validate_request(request),
         true <- keys?(result, ~w(version answers)),
         true <- result["version"] === 1,
         answers when is_list(answers) <- result["answers"],
         true <- length(answers) == length(request["questions"]),
         true <-
           Enum.all?(Enum.zip(request["questions"], answers), fn {q, a} -> answer?(q, a) end),
         true <- byte_size(Jason.encode!(result)) <= 32_768 do
      :ok
    else
      _ -> {:error, :invalid_decision_result}
    end
  rescue
    _ -> {:error, :invalid_decision_result}
  end

  @doc "Deterministic advice over already-permitted alternatives; thresholds are consumer policy."
  def select(request, result, question_id, alternatives, minimum_probability)
      when is_list(alternatives) do
    with :ok <- validate_result(request, result),
         true <- probability?(minimum_probability),
         true <- alternatives != [] and Enum.all?(alternatives, &id?/1),
         true <- length(alternatives) == length(Enum.uniq(alternatives)),
         %{"type" => "choice", "choices" => choices} <-
           Enum.find(request["questions"], &(&1["id"] == question_id)),
         true <- Enum.all?(alternatives, &(&1 in choices)),
         %{"type" => "choice", "choice" => choice, "probabilities" => distribution} <-
           Enum.find(result["answers"], &(&1["id"] == question_id)),
         true <- choice in alternatives,
         %{"probability" => p} <- Enum.find(distribution, &(&1["id"] == choice)),
         true <- p >= minimum_probability do
      {:ok, choice}
    else
      _ -> {:defer, :unusable_advice}
    end
  end

  def select(_, _, _, _, _), do: {:defer, :unusable_advice}

  defp question?(%{"type" => "predicate"} = q),
    do: keys?(q, ~w(id type instructions)) and common?(q)

  defp question?(%{"type" => "choice"} = q),
    do:
      keys?(q, ~w(id type instructions choices)) and common?(q) and
        options?(q["choices"], &id?/1)

  defp question?(%{"type" => "score"} = q),
    do:
      keys?(q, ~w(id type instructions levels)) and common?(q) and
        options?(q["levels"], &text?(&1, 256))

  defp question?(_), do: false
  defp common?(q), do: id?(q["id"]) and text?(q["instructions"], 1_024)

  defp answer?(q, %{"type" => "refusal"} = a),
    do: keys?(a, ~w(id type)) and a["id"] == q["id"]

  defp answer?(%{"type" => "predicate"} = q, %{"type" => "predicate"} = a),
    do:
      keys?(a, ~w(id type probability)) and a["id"] == q["id"] and
        probability?(a["probability"])

  defp answer?(%{"type" => "choice"} = q, %{"type" => "choice"} = a) do
    with true <- keys?(a, ~w(id type choice confidence probabilities)),
         true <- a["id"] == q["id"] and a["choice"] in q["choices"],
         true <- probability?(a["confidence"]),
         true <- distribution?(a["probabilities"], q["choices"]),
         selected = Enum.find(a["probabilities"], &(&1["id"] == a["choice"])),
         true <-
           Enum.all?(
             a["probabilities"],
             &(&1["probability"] <= selected["probability"] + @sum_tolerance)
           ) do
      true
    else
      _ -> false
    end
  end

  defp answer?(%{"type" => "score"} = q, %{"type" => "score"} = a) do
    ids = Enum.map(0..(length(q["levels"]) - 1), &Integer.to_string/1)

    with true <- keys?(a, ~w(id type score confidence probabilities)),
         true <- a["id"] == q["id"] and probability?(a["confidence"]),
         true <- finite?(a["score"]) and a["score"] >= 0 and a["score"] <= length(ids) - 1,
         true <- distribution?(a["probabilities"], ids),
         mean =
           Enum.sum(
             Enum.map(a["probabilities"], &(String.to_integer(&1["id"]) * &1["probability"]))
           ),
         true <- abs(mean - a["score"]) <= @sum_tolerance do
      true
    else
      _ -> false
    end
  end

  defp answer?(_, _), do: false

  defp distribution?(distribution, ids) when is_list(distribution) do
    length(distribution) == length(ids) and
      Enum.all?(distribution, fn row ->
        keys?(row, ~w(id probability)) and row["id"] in ids and probability?(row["probability"])
      end) and unique?(distribution, & &1["id"]) and
      abs(Enum.sum(Enum.map(distribution, & &1["probability"])) - 1) <= @sum_tolerance
  end

  defp distribution?(_, _), do: false

  defp options?(values, valid) when is_list(values),
    do: length(values) in 2..16 and Enum.all?(values, valid) and unique?(values, & &1)

  defp options?(_, _), do: false
  defp unique?(values, by), do: length(values) == length(Enum.uniq_by(values, by))
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp id?(value),
    do: text?(value, 64) and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/, value)

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..max

  defp probability?(value), do: finite?(value) and value >= 0 and value <= 1
  defp finite?(value) when is_integer(value), do: abs(value) <= 9_007_199_254_740_991
  defp finite?(value) when is_float(value), do: value == value and abs(value) <= 1.0e100
  defp finite?(_), do: false
end
