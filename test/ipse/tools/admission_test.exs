defmodule Ipse.ToolCallBudgetTest do
  use ExUnit.Case, async: true
  alias Ipse.Tools

  defp calls(n, arguments \\ "not json"),
    do:
      for(
        i <- 1..n,
        do: %{"id" => "call-#{i}", "function" => %{"name" => "read", "arguments" => arguments}}
      )

  test "all admitted attempts count, including malformed arguments, across response batches" do
    used =
      Enum.reduce(1..4, Tools.empty_call_budget(), fn _, used ->
        assert {:ok, next} = Tools.admit_calls(calls(32), used)
        next
      end)

    assert {:error, :tool_call_limit} = Tools.admit_calls(calls(1), used)
    assert {:ok, ^used} = Tools.admit_calls([], used)
  end

  test "argument bytes are bounded per response and per operator turn" do
    args = String.duplicate("a", 2 * 1024 * 1024)

    assert {:error, :tool_call_limit} =
             Tools.admit_calls(calls(2, args), Tools.empty_call_budget())

    used =
      Enum.reduce(1..4, Tools.empty_call_budget(), fn _, used ->
        assert {:ok, next} = Tools.admit_calls(calls(1, args), used)
        next
      end)

    assert {:error, :tool_call_limit} = Tools.admit_calls(calls(1, "x"), used)
  end

  test "restoration retains the current turn quota and a new prompt starts a new quota" do
    response = %{"role" => "assistant", "tool_calls" => calls(32)}
    messages = [%{"role" => "user", "content" => "first"} | List.duplicate(response, 4)]

    assert {:error, :tool_call_limit} =
             Tools.admit_calls(calls(1), Tools.restore_call_budget(messages))

    messages = messages ++ [%{"role" => "user", "content" => "next"}]
    assert {:ok, _} = Tools.admit_calls(calls(32), Tools.restore_call_budget(messages))
  end
end
