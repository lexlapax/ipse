defmodule Ipse.QuestionValidationTest do
  use ExUnit.Case, async: true
  alias Ipse.Tools.Questions

  test "operator questions require explicit availability and a root session" do
    assert Questions.enabled?(%{})
    assert Questions.enabled?(%{operator_questions: true})
    refute Questions.enabled?(%{operator_questions: false})
    refute Questions.enabled?(%{operator_questions: "true"})
    refute Questions.enabled?(%{operator_questions: true, delegation_origin: "parent"})
  end

  defp choice(kind \\ "single"),
    do: %{
      "id" => "stack",
      "prompt" => "Choose a stack",
      "kind" => kind,
      "options" => [
        %{"id" => "local", "label" => "Local"},
        %{"id" => "remote", "label" => "Remote"}
      ],
      "recommended" => "local"
    }

  test "question schema validates with existing bounded JSON Schema adapter" do
    assert :ok = Ipse.JSON.validate_schema(Questions.schema())
    assert {:ok, _} = Questions.validate(%{"questions" => [choice()]})
    assert {:error, _} = Questions.validate(%{"questions" => [choice(), choice()]})

    assert {:error, _} =
             Questions.validate(%{"questions" => [Map.put(choice(), "recommended", "absent")]})

    assert {:error, _} =
             Questions.validate(%{"questions" => [Map.put(choice(), "unexpected", true)]})

    assert {:error, _} =
             Questions.validate(%{
               "questions" => [Map.put(choice(), "prompt", String.duplicate("x", 2001))]
             })

    assert {:error, _} = Questions.validate(%{"questions" => [Map.put(choice(), "kind", "text")]})
  end

  test "new batches reject identical questions without invalidating historical receipts" do
    duplicate = Map.put(choice(), "id", "other")
    batch = %{"questions" => [choice(), duplicate]}
    assert {:ok, ^batch} = Questions.validate(batch)
    assert {:error, message} = Questions.validate_new(batch)
    assert message =~ "repeat"

    equivalent =
      duplicate
      |> Map.delete("recommended")
      |> put_in(["options", Access.at(0), "id"], "renamed_local")

    assert {:error, _} = Questions.validate_new(%{"questions" => [choice(), equivalent]})

    text = %{"id" => "one", "prompt" => "Describe it", "kind" => "text"}

    explicit_nil =
      text |> Map.put("id", "two") |> Map.put("options", nil) |> Map.put("recommended", nil)

    assert {:error, _} = Questions.validate_new(%{"questions" => [text, explicit_nil]})

    distinct = put_in(duplicate, ["options", Access.at(0), "label"], "On device")
    assert {:ok, _} = Questions.validate_new(%{"questions" => [choice(), distinct]})
  end

  test "only a validated answer in the current user turn suppresses an exact question" do
    first = %{"questions" => [choice()]}
    repeated = %{"questions" => [Map.put(choice(), "id", "other")]}

    assistant = %{
      "role" => "assistant",
      "tool_calls" => [
        %{
          "id" => "call",
          "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(first)}
        }
      ]
    }

    answer = %{
      "role" => "tool",
      "tool_call_id" => "call",
      "content" => Jason.encode!(%{"answers" => %{"stack" => "local"}}),
      "ipse_tool_outcome" => %{"status" => "result_recorded"}
    }

    user = %{"role" => "user", "content" => "Plan this"}
    assert Questions.repeated_answer?([user, assistant, answer], repeated)

    equivalent =
      update_in(repeated, ["questions", Access.at(0)], fn q ->
        q |> Map.delete("recommended") |> put_in(["options", Access.at(0), "id"], "new_id")
      end)

    assert Questions.repeated_answer?([user, assistant, answer], equivalent)
    refute Questions.repeated_answer?([user, assistant], repeated)

    refute Questions.repeated_answer?(
             [user, assistant, Map.put(answer, "content", "{}")],
             repeated
           )

    refute Questions.repeated_answer?([user, assistant, answer, user], repeated)
    unrelated = put_in(assistant, ["tool_calls", Access.at(0), "function", "name"], "read")
    refute Questions.repeated_answer?([user, unrelated, answer, assistant], repeated)
    changed = put_in(repeated, ["questions", Access.at(0), "prompt"], "Choose a region")
    refute Questions.repeated_answer?([user, assistant, answer], changed)

    described =
      put_in(
        repeated,
        ["questions", Access.at(0), "options", Access.at(0), "description"],
        "Uses this device"
      )

    refute Questions.repeated_answer?([user, assistant, answer], described)
  end

  test "single and multiple selections require explicit valid IDs, never recommendations" do
    args = %{"questions" => [choice()]}
    assert {:error, _} = Questions.validate_answers(args, %{})
    assert {:error, _} = Questions.validate_answers(args, %{"stack" => "unknown"})

    assert {:ok, %{"stack" => "remote"}} =
             Questions.validate_answers(args, %{"stack" => "remote"})

    assert {:ok, "remote"} = Questions.parse_line(choice(), "2")
    assert {:error, _} = Questions.parse_line(choice(), "")
    assert {:error, _} = Questions.parse_line(choice(), "1,2")
    assert {:ok, ["remote", "local"]} = Questions.parse_line(choice("multiple"), "2,1")
    assert {:error, _} = Questions.parse_line(choice("multiple"), "1,1")
    assert {:error, _} = Questions.parse_line(choice("multiple"), "99")
  end

  test "text is bounded and exact, with explicit CLI command escape" do
    q = %{"id" => "notes", "prompt" => "Anything else?", "kind" => "text"}
    assert {:ok, _} = Questions.validate(%{"questions" => [q]})

    assert {:ok, _} =
             Questions.validate(%{
               "questions" => [Map.merge(q, %{"options" => nil, "recommended" => nil})]
             })

    assert {:ok, "/exit"} = Questions.parse_line(q, "=/exit")

    assert {:ok, %{"notes" => "  quoted text  "}} =
             Questions.validate_answers(%{"questions" => [q]}, %{"notes" => "  quoted text  "})

    assert {:error, _} = Questions.validate_answers(%{"questions" => [q]}, %{"notes" => " "})

    assert {:error, _} =
             Questions.validate_answers(%{"questions" => [q]}, %{
               "notes" => String.duplicate("x", 8001)
             })

    assert Questions.render(q) =~ "No answer is selected automatically"
  end
end
