defmodule Ipse.Tools.Questions do
  @moduledoc "Bounded operator clarification schemas, answer validation and tool-result messages."
  alias Ipse.JSON, as: Schema

  @doc "Whether this host can wait for explicit operator answers."
  def enabled?(config),
    do: Map.get(config, :operator_questions, true) == true and is_nil(config[:delegation_origin])

  def tool_result(call, content, status),
    do: %{
      "role" => "tool",
      "tool_call_id" => call["id"],
      "content" => content,
      "ipse_tool_outcome" => %{"status" => status, "approval" => "not_required"}
    }

  def definition do
    %{
      "type" => "function",
      "function" => %{
        "name" => "ask_operator",
        "strict" => false,
        "description" =>
          "Ask up to three operator clarification questions and wait for explicit answers. Supports single choice, multiple choice, and free text. Recommendations are not defaults; answers grant no tool permission. Use this call alone when input is required.",
        "parameters" => schema()
      }
    }
  end

  def schema do
    option =
      object(%{"id" => string(64), "label" => string(120), "description" => string(512)}, [
        "id",
        "label"
      ])

    question =
      object(
        %{
          "id" => string(64),
          "prompt" => string(2000),
          "kind" => %{"type" => "string", "enum" => ["single", "multiple", "text"]},
          "options" => %{
            "type" => ["array", "null"],
            "description" => "For choice questions only; omit or null for text.",
            "items" => option,
            "minItems" => 2,
            "maxItems" => 8
          },
          "recommended" =>
            Map.merge(string(64), %{
              "type" => ["string", "null"],
              "description" =>
                "Optional option ID, never a submitted answer. Omit or null for text."
            })
        },
        ["id", "prompt", "kind"]
      )

    object(
      %{
        "questions" => %{"type" => "array", "items" => question, "minItems" => 1, "maxItems" => 3}
      },
      ["questions"]
    )
  end

  def validate(arguments) do
    with :ok <- Schema.validate_arguments(schema(), arguments),
         questions = arguments["questions"],
         true <- unique?(Enum.map(questions, & &1["id"])),
         true <- Enum.all?(questions, &valid_question?/1) do
      {:ok, arguments}
    else
      _ ->
        {:error,
         "Invalid operator question: use unique IDs, nonblank prompts, and valid options/recommendations."}
    end
  end

  @doc "Validate a new question batch without rejecting historical receipts."
  def validate_new(arguments) do
    with {:ok, arguments} <- validate(arguments),
         questions = Enum.map(arguments["questions"], &question_identity/1),
         true <- unique?(questions) do
      {:ok, arguments}
    else
      false -> {:error, "Do not repeat the same question in one clarification request."}
      error -> error
    end
  end

  @doc "Detect equivalent questions already answered in the current visible user turn."
  def repeated_answer?(messages, arguments) when is_list(messages) do
    recent =
      messages
      |> Enum.reverse()
      |> Enum.reject(&Ipse.Session.Reference.reference?/1)
      |> Enum.take_while(&(&1["role"] != "user"))
      |> Enum.reverse()

    answered =
      for {%{"role" => "assistant", "tool_calls" => calls}, index} <- Enum.with_index(recent),
          is_list(calls),
          %{"id" => id, "function" => %{"name" => "ask_operator", "arguments" => raw}} <- calls,
          is_binary(raw),
          {:ok, prior} <- [Ipse.JSON.decode_unique(raw)],
          {:ok, ^prior} <- [validate(prior)],
          following = Enum.drop(recent, index + 1) |> Enum.take_while(&(&1["role"] == "tool")),
          Enum.any?(following, &answered_call?(&1, id, prior)),
          question <- prior["questions"],
          do: question_identity(question)

    Enum.any?(arguments["questions"], &(question_identity(&1) in answered))
  rescue
    _ -> false
  end

  # Wire IDs and recommendations do not change the choice being asked. Keep
  # prompt, kind, ordered labels and descriptions exact to avoid guessing that
  # differently worded or materially changed choices are equivalent.
  defp question_identity(question) do
    options =
      Enum.map(question["options"] || [], fn option ->
        {option["label"], option["description"]}
      end)

    {question["prompt"], question["kind"], options}
  end

  defp answered_call?(
         %{"role" => "tool", "tool_call_id" => id, "content" => content} = message,
         id,
         prior
       ) do
    with "result_recorded" <- get_in(message, ["ipse_tool_outcome", "status"]),
         {:ok, %{"answers" => answers}} <- Ipse.JSON.decode_unique(content),
         {:ok, ^answers} <- validate_answers(prior, answers) do
      true
    else
      _ -> false
    end
  end

  defp answered_call?(_, _, _), do: false

  def validate_answers(arguments, answers) when is_map(answers) do
    with {:ok, _} <- validate(arguments),
         questions = arguments["questions"],
         true <- Enum.sort(Map.keys(answers)) == Enum.sort(Enum.map(questions, & &1["id"])),
         true <- Enum.all?(questions, &valid_answer?(&1, answers[&1["id"]])),
         {:ok, encoded} <- Jason.encode(answers),
         true <- byte_size(encoded) <= 16_384 do
      {:ok, answers}
    else
      _ -> {:error, :invalid_answer}
    end
  end

  def validate_answers(_, _), do: {:error, :invalid_answer}

  def parse_line(%{"kind" => "text"}, text) when is_binary(text) do
    value = if String.starts_with?(text, "="), do: String.slice(text, 1..-1//1), else: text

    if nonblank?(value) and byte_size(value) <= 8000,
      do: {:ok, value},
      else: {:error, :invalid_answer}
  end

  def parse_line(%{"kind" => kind, "options" => options} = question, text)
      when kind in ["single", "multiple"] and is_binary(text) do
    entries = String.split(text, ",", trim: true) |> Enum.map(&String.trim/1)

    ids =
      Enum.map(entries, fn entry ->
        case Integer.parse(entry) do
          {index, ""} when index > 0 -> Enum.at(options, index - 1, %{})["id"]
          _ -> entry
        end
      end)

    value = if kind == "single" and length(ids) == 1, do: hd(ids), else: ids
    if valid_answer?(question, value), do: {:ok, value}, else: {:error, :invalid_answer}
  end

  def parse_line(_, _), do: {:error, :invalid_answer}

  def render(question) do
    options =
      Enum.with_index(Map.get(question, "options") || [], 1)
      |> Enum.map_join("\n", fn {option, n} ->
        recommended = if question["recommended"] == option["id"], do: " (recommended)", else: ""

        "  #{n}. #{option["label"]} [#{option["id"]}]#{recommended}" <>
          if(option["description"], do: " — " <> option["description"], else: "")
      end)

    hint =
      case question["kind"] do
        "single" -> "Enter one option number or ID."
        "multiple" -> "Enter comma-separated option numbers or IDs."
        "text" -> "Enter text; prefix = to answer with a literal slash command."
      end

    question["prompt"] <>
      "\n" <>
      options <> "\n" <> hint <> " No answer is selected automatically. /cancel stops this turn."
  end

  defp valid_question?(q) do
    options = Map.get(q, "options") || []
    ids = Enum.map(options, & &1["id"])

    id?(q["id"]) and nonblank?(q["prompt"]) and
      if q["kind"] == "text" do
        is_nil(q["options"]) and is_nil(q["recommended"])
      else
        length(options) in 2..8 and unique?(ids) and Enum.all?(ids, &id?/1) and
          Enum.all?(options, &nonblank?(&1["label"])) and
          (is_nil(q["recommended"]) or q["recommended"] in ids)
      end
  end

  defp valid_answer?(%{"kind" => "text"}, value),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) <= 8000 and nonblank?(value)

  defp valid_answer?(%{"kind" => "single", "options" => options}, value),
    do: is_binary(value) and Enum.any?(options, &(&1["id"] == value))

  defp valid_answer?(%{"kind" => "multiple", "options" => options}, value) when is_list(value),
    do:
      value != [] and length(value) <= 8 and unique?(value) and
        Enum.all?(value, fn id -> is_binary(id) and Enum.any?(options, &(&1["id"] == id)) end)

  defp valid_answer?(_, _), do: false
  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, value)

  defp nonblank?(value),
    do: is_binary(value) and String.valid?(value) and String.trim(value) != ""

  defp string(max), do: %{"type" => "string", "minLength" => 1, "maxLength" => max}

  defp object(properties, required),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
end
