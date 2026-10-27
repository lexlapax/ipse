defmodule Ipse.Session.OperatorAnswerTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.OperatorAnswer
  alias Ipse.Tools.Questions

  defp question do
    args = %{
      "questions" => [
        %{
          "id" => "choice",
          "kind" => "single",
          "prompt" => "Choose safely\e",
          "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}]
        },
        %{"id" => "text", "kind" => "text", "prompt" => "Literal Unicode answer"}
      ]
    }

    call = %{
      "id" => "question_1",
      "type" => "function",
      "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
    }

    %{id: call["id"], call: call, arguments: args}
  end

  defp piece(question, item, client, answer) do
    {:ok, render} = OperatorAnswer.render(question, item, client)
    input = "answer #{render["code"]} #{answer}"

    observation = %{
      "version" => 2,
      "event_id" => Ipse.Usage.id(),
      "display_sha256" => Ipse.JSON.sha256(render["display"]),
      "text_sha256" => Ipse.JSON.sha256(input),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    {:ok, value, piece} = OperatorAnswer.parse(question, render, input, observation)
    {render, input, observation, value, piece}
  end

  test "exact native answer bytes and renderings bind the committed answer without permission" do
    question = question()
    client = Ipse.Usage.id()
    {render, _, _, choice, p1} = piece(question, "choice", client, "2")
    {_, _, _, text, p2} = piece(question, "text", client, "=/exit 雪 café  ")
    assert render["display"] =~ "\\u001b"
    assert p2["text"] == "=/exit 雪 café  "
    assert text == "/exit 雪 café  "

    message =
      Questions.tool_result(
        question.call,
        Jason.encode!(%{
          "answers" => %{"choice" => choice, "text" => text},
          "notice" => "Clarification only; no action permission."
        }),
        "result_recorded"
      )

    session = Ipse.Usage.id()
    assert {:ok, event} = OperatorAnswer.receipt(session, question, client, [p1, p2], message)
    assert event["origin"] == "native_operator_answer"
    assert OperatorAnswer.valid_receipt?(event, session, question, message)
    refute OperatorAnswer.valid_receipt?(event, Ipse.Usage.id(), question, message)

    refute OperatorAnswer.valid_receipt?(
             event,
             session,
             %{question | arguments: %{"questions" => []}},
             message
           )

    refute OperatorAnswer.valid_receipt?(
             event,
             session,
             question,
             Map.put(message, "content", "yes")
           )

    for damaged <- [
          Map.put(event, "version", 1.0),
          Map.put(event, "origin", "interactive_operator"),
          Map.put(event, "extra", true),
          Map.put(event, "pieces", [p2, p1]),
          put_in(event, ["pieces", Access.at(0), "text"], "1"),
          put_in(
            event,
            ["pieces", Access.at(0), "observation", "display_sha256"],
            String.duplicate("0", 64)
          ),
          Map.put(event, "pieces", [p1, p1])
        ] do
      refute OperatorAnswer.valid_receipt?(damaged, session, question, message)
    end
  end

  test "stale codes, changed renderings, forged observations and invalid UTF8 fail closed" do
    question = question()
    client = Ipse.Usage.id()
    {render, input, observation, _, _} = piece(question, "choice", client, "1")
    {:ok, refreshed} = OperatorAnswer.render(question, "choice", client)

    assert {:error, :invalid_operator_answer_origin} =
             OperatorAnswer.parse(question, refreshed, input, observation)

    for {r, i, o} <- [
          {Map.put(render, "display", "forged safe display"), input, observation},
          {render, input <> " ", observation},
          {render, <<255>>, observation},
          {render, input, Map.put(observation, "origin", "interactive_operator")},
          {render, input, Map.put(observation, "version", 1.0)},
          {render, input, Map.put(observation, "text_sha256", String.duplicate("0", 64))}
        ] do
      assert {:error, :invalid_operator_answer_origin} = OperatorAnswer.parse(question, r, i, o)
    end
  end

  test "atomic native answer publication requires the exact pending checkpoint and committed message" do
    question = question()
    client = Ipse.Usage.id()
    {_, _, _, choice, p1} = piece(question, "choice", client, "2")
    {_, _, _, text, p2} = piece(question, "text", client, "exact café")

    message =
      Questions.tool_result(
        question.call,
        Jason.encode!(%{
          "answers" => %{"choice" => choice, "text" => text},
          "notice" => "Clarification only; no action permission."
        }),
        "result_recorded"
      )

    session = Ipse.Usage.id()
    {:ok, origin} = OperatorAnswer.receipt(session, question, client, [p1, p2], message)

    answer = %{
      "type" => "operator_answer",
      "version" => 2,
      "id" => question.id,
      "message" => message,
      "origin" => origin
    }

    assistant = %{"role" => "assistant", "content" => "", "tool_calls" => [question.call]}

    checkpoint = %{
      "type" => "operator_question",
      "version" => 1,
      "id" => question.id,
      "call" => question.call,
      "arguments" => question.arguments,
      "steps" => 1,
      "covered_messages" => 1,
      "prefix_sha256" => Ipse.JSON.digest([assistant])
    }

    prefix = [
      %{"type" => "session", "metadata" => %{}},
      %{"type" => "message", "message" => assistant},
      checkpoint
    ]

    assert :ok = OperatorAnswer.validate_events(prefix ++ [answer], session)
    assert {:ok, _} = Ipse.Session.Saved.context(prefix ++ [answer])
    assert {:ok, _} = Ipse.Session.Saved.context(prefix)

    for damaged <- [
          [answer],
          [checkpoint, answer, checkpoint, answer],
          prefix ++ [put_in(answer, ["message", "content"], "changed")],
          prefix ++ [Map.put(answer, "version", 1)],
          prefix ++ [Map.delete(answer, "origin")],
          prefix ++ [Map.put(answer, "extra", true)]
        ] do
      assert {:error, :invalid_operator_answer_origin} =
               OperatorAnswer.validate_events(damaged, session)
    end
  end
end
