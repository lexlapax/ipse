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
