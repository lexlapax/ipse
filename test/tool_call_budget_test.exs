defmodule Ipse.ToolCallBudgetTest do
  use ExUnit.Case, async: true
  alias Ipse.ToolCall

  defp calls(n, arguments \\ "not json"),
    do:
      for(
        i <- 1..n,
        do: %{"id" => "call-#{i}", "function" => %{"name" => "read", "arguments" => arguments}}
      )

  test "all admitted attempts count, including malformed arguments, across response batches" do
    used =
      Enum.reduce(1..4, ToolCall.empty_budget(), fn _, used ->
        assert {:ok, next} = ToolCall.admit(calls(32), used)
        next
      end)

    assert {:error, :tool_call_limit} = ToolCall.admit(calls(1), used)
    assert {:ok, ^used} = ToolCall.admit([], used)
  end

  test "argument bytes are bounded per response and per operator turn" do
    args = String.duplicate("a", 2 * 1024 * 1024)
    assert {:error, :tool_call_limit} = ToolCall.admit(calls(2, args), ToolCall.empty_budget())

    used =
      Enum.reduce(1..4, ToolCall.empty_budget(), fn _, used ->
        assert {:ok, next} = ToolCall.admit(calls(1, args), used)
        next
      end)

    assert {:error, :tool_call_limit} = ToolCall.admit(calls(1, "x"), used)
  end

  test "restoration retains the current turn quota and a new prompt starts a new quota" do
    response = %{"role" => "assistant", "tool_calls" => calls(32)}
    messages = [%{"role" => "user", "content" => "first"} | List.duplicate(response, 4)]

    assert {:error, :tool_call_limit} =
             ToolCall.admit(calls(1), ToolCall.restore_budget(messages))

    messages = messages ++ [%{"role" => "user", "content" => "next"}]
    assert {:ok, _} = ToolCall.admit(calls(32), ToolCall.restore_budget(messages))
  end
end
