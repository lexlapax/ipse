defmodule Ipse.Session.OperatorAnswer do
  @moduledoc "Exact native question renderings and durable answer-origin receipts. No receipt grants effect permission."

  alias Ipse.{JSON, Usage}
  alias Ipse.Tools.Questions

  @doc false
  def render(question, question_id, client_id) do
    with {:ok, _} <- Questions.validate(question.arguments),
         true <- id?(client_id),
         item when is_map(item) <-
           Enum.find(question.arguments["questions"], &(&1["id"] == question_id)) do
      code = Usage.id()

      {:ok,
       %{
         "version" => 1,
         "question_id" => question.id,
         "question_sha256" => question_hash(question),
         "item_id" => question_id,
         "client_id" => client_id,
         "render_id" => Usage.id(),
         "code" => code,
         "display" => display(item, code)
       }}
    else
      _ -> {:error, :invalid_operator_render}
    end
  end

  @doc false
  def parse(question, render, input, observation) do
    with true <- valid_render?(question, render),
         true <- is_binary(input) and String.valid?(input) and byte_size(input) <= 8192,
         prefix = "answer #{render["code"]} ",
         true <- String.starts_with?(input, prefix),
         text = binary_part(input, byte_size(prefix), byte_size(input) - byte_size(prefix)),
         item = Enum.find(question.arguments["questions"], &(&1["id"] == render["item_id"])),
         {:ok, answer} <- Questions.parse_line(item, text),
         true <- valid_observation?(observation, input, render["display"]) do
      {:ok, answer,
       %{
         "item_id" => render["item_id"],
         "render_id" => render["render_id"],
         "code" => render["code"],
         "input" => input,
         "input_sha256" => JSON.sha256(input),
         "text" => text,
         "text_sha256" => JSON.sha256(text),
         "observation" => observation
       }}
    else
      _ -> {:error, :invalid_operator_answer_origin}
    end
  end

  @doc false
  def receipt(session_id, question, client_id, pieces, message) do
    event = %{
      "type" => "operator_answer_origin",
      "version" => 1,
      "session_id" => session_id,
      "source_id" => Usage.id(),
      "question_id" => question.id,
      "question_sha256" => question_hash(question),
      "client_id" => client_id,
      "pieces" => pieces,
      "message_sha256" => JSON.digest([message]),
      "origin" => "native_operator_answer"
    }

    if valid_receipt?(event, session_id, question, message),
      do: {:ok, event},
      else: {:error, :invalid_operator_answer_origin}
  end

  @doc false
  def valid_receipt?(event, session_id, question, message) do
    with true <-
           keys?(
             event,
             ~w(type version session_id source_id question_id question_sha256 client_id pieces message_sha256 origin)
           ),
         true <- event["type"] == "operator_answer_origin" and event["version"] === 1,
         true <- event["origin"] == "native_operator_answer",
         true <-
           id?(event["session_id"]) and (session_id == nil or event["session_id"] == session_id),
         true <- id?(event["source_id"]) and id?(event["client_id"]),
         true <- event["question_id"] == question.id,
         true <- event["question_sha256"] == question_hash(question),
         true <- event["message_sha256"] == JSON.digest([message]),
         true <-
           Map.delete(message, "content") ==
             Map.delete(Questions.tool_result(question.call, "", "result_recorded"), "content"),
         {:ok,
          %{"answers" => answers, "notice" => "Clarification only; no action permission."} = value} <-
           JSON.decode_bounded(message["content"]),
         true <- map_size(value) == 2,
         {:ok, ^answers} <- Questions.validate_answers(question.arguments, answers),
         pieces when is_list(pieces) <- event["pieces"],
         true <- length(pieces) == length(question.arguments["questions"]),
         true <- unique?(pieces, "render_id") and unique?(pieces, "code"),
         true <- unique_observations?(pieces) do
      Enum.zip(question.arguments["questions"], pieces)
      |> Enum.all?(fn {item, piece} ->
        valid_piece?(question, item, piece, event["client_id"], answers[item["id"]])
      end)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc false
  def question_hash(question),
    do:
      JSON.digest([
        %{"id" => question.id, "call" => question.call, "arguments" => question.arguments}
      ])

  @doc false
  def validate_events(events, session_id \\ nil) do
    Enum.reduce_while(events, {nil, MapSet.new()}, fn
      %{"type" => "operator_question"} = e, {_, seen} ->
        {:cont, {%{id: e["id"], call: e["call"], arguments: e["arguments"]}, seen}}

      %{"type" => "input_received", "observation" => %{"event_id" => id}}, {q, seen} ->
        if MapSet.member?(seen, id),
          do: {:halt, {:error, :invalid_operator_answer_origin}},
          else: {:cont, {q, MapSet.put(seen, id)}}

      %{"type" => "operator_answer", "version" => 2} = e, {q, seen} ->
        origin = e["origin"]

        if keys?(e, ~w(type version id message origin)) and e["version"] === 2 and
             is_map(q) and e["id"] == q.id and valid_receipt?(origin, session_id, q, e["message"]) do
          ids = [
            origin["source_id"]
            | Enum.map(origin["pieces"], &get_in(&1, ["observation", "event_id"]))
          ]

          if Enum.any?(ids, &MapSet.member?(seen, &1)) or length(ids) != length(Enum.uniq(ids)),
            do: {:halt, {:error, :invalid_operator_answer_origin}},
            else: {:cont, {nil, Enum.reduce(ids, seen, &MapSet.put(&2, &1))}}
        else
          {:halt, {:error, :invalid_operator_answer_origin}}
        end

      %{"type" => "operator_answer"} = e, {_, seen} ->
        if Map.has_key?(e, "origin"),
          do: {:halt, {:error, :invalid_operator_answer_origin}},
          else: {:cont, {nil, seen}}

      %{"type" => "operator_question_closed"}, {_, seen} ->
        {:cont, {nil, seen}}

      _, state ->
        {:cont, state}
    end)
    |> case do
      {_, %MapSet{}} -> :ok
      error -> error
    end
  rescue
    _ -> {:error, :invalid_operator_answer_origin}
  end

  defp valid_piece?(question, item, piece, client_id, answer) do
    with true <-
           keys?(
             piece,
             ~w(item_id render_id code input input_sha256 text text_sha256 observation)
           ),
         true <- piece["item_id"] == item["id"],
         true <- id?(piece["render_id"]) and id?(piece["code"]),
         true <- is_binary(piece["input"]) and is_binary(piece["text"]),
         true <- piece["input_sha256"] == JSON.sha256(piece["input"]),
         true <- piece["text_sha256"] == JSON.sha256(piece["text"]),
         render = %{
           "version" => 1,
           "question_id" => question.id,
           "question_sha256" => question_hash(question),
           "item_id" => item["id"],
           "client_id" => client_id,
           "code" => piece["code"],
           "render_id" => piece["render_id"],
           "display" => display(item, piece["code"])
         },
         {:ok, ^answer, ^piece} <- parse(question, render, piece["input"], piece["observation"]) do
      true
    else
      _ -> false
    end
  end

  defp valid_render?(question, render) do
    keys?(
      render,
      ~w(version question_id question_sha256 item_id client_id render_id code display)
    ) and
      render["version"] === 1 and render["question_id"] == question.id and
      render["question_sha256"] == question_hash(question) and id?(render["client_id"]) and
      id?(render["render_id"]) and id?(render["code"]) and is_binary(render["display"]) and
      String.valid?(render["display"]) and
      Enum.any?(question.arguments["questions"], fn item ->
        item["id"] == render["item_id"] and render["display"] == display(item, render["code"])
      end)
  end

  defp display(item, code) do
    Ipse.CLI.Terminal.escape(
      Questions.render(item) <>
        "\nType answer #{code} followed by your answer. This grants no action permission.\nanswer> "
    )
  end

  defp valid_observation?(o, input, display) do
    is_map(o) and o["version"] === 2 and Ipse.Session.Input.valid_observation?(o, input, 2) and
      o["display_sha256"] == JSON.sha256(display)
  end

  defp unique_observations?(pieces) do
    ids = Enum.map(pieces, &get_in(&1, ["observation", "event_id"]))
    length(ids) == length(Enum.uniq(ids))
  end

  defp unique?(values, key) do
    ids = Enum.map(values, &Map.get(&1, key))
    length(ids) == length(Enum.uniq(ids))
  end

  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
