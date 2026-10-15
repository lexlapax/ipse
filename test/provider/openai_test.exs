defmodule Ipse.Provider.OpenAITest do
  use ExUnit.Case, async: true
  alias Ipse.Provider.OpenAI

  test "native output including opaque reasoning survives the next request" do
    output = [
      %{"type" => "reasoning", "encrypted_content" => "opaque", "summary" => []},
      %{
        "type" => "function_call",
        "call_id" => "call_a",
        "name" => "read",
        "arguments" => "{\"path\":\"a\"}"
      }
    ]

    {:ok, state} =
      OpenAI.consume(
        OpenAI.new(),
        sse(%{
          "type" => "response.completed",
          "response" => %{
            "status" => "completed",
            "output" => output,
            "usage" => %{"input_tokens" => 5}
          }
        }),
        fn _ -> :ok end
      )

    assert {:ok, message, %{"input_tokens" => 5}} = OpenAI.finish(state)

    assert [
             %{
               "id" => "call_a",
               "function" => %{"name" => "read", "arguments" => "{\"path\":\"a\"}"}
             }
           ] = message["tool_calls"]

    body =
      OpenAI.request_body(
        %{model: "model"},
        [message, %{"role" => "tool", "tool_call_id" => "call_a", "content" => "result"}],
        []
      )

    assert body["input"] ==
             output ++
               [%{"type" => "function_call_output", "call_id" => "call_a", "output" => "result"}]

    assert body["store"] == false
    assert body["stream"] == true
  end

  test "interleaved tool fragments accumulate by output index" do
    events = [
      %{
        "type" => "response.output_item.added",
        "output_index" => 1,
        "item" => %{
          "type" => "function_call",
          "call_id" => "b",
          "name" => "second",
          "arguments" => ""
        }
      },
      %{
        "type" => "response.output_item.added",
        "output_index" => 0,
        "item" => %{
          "type" => "function_call",
          "call_id" => "a",
          "name" => "first",
          "arguments" => ""
        }
      },
      %{
        "type" => "response.function_call_arguments.delta",
        "output_index" => 0,
        "delta" => "{\"x\":"
      },
      %{"type" => "response.function_call_arguments.delta", "output_index" => 1, "delta" => "{}"},
      %{"type" => "response.function_call_arguments.delta", "output_index" => 0, "delta" => "1}"},
      %{"type" => "response.completed", "response" => %{"status" => "completed"}}
    ]

    {:ok, state} = OpenAI.consume(OpenAI.new(), Enum.map_join(events, &sse/1), fn _ -> :ok end)
    assert {:ok, message, %{}} = OpenAI.finish(state)
    assert Enum.map(message["tool_calls"], & &1["function"]["arguments"]) == ["{\"x\":1}", "{}"]
  end

  test "partial text and [DONE] cannot substitute for response.completed" do
    owner = self()

    {:ok, state} =
      OpenAI.consume(
        OpenAI.new(),
        sse(%{"type" => "response.output_text.delta", "delta" => "hello"}),
        &send(owner, &1)
      )

    assert_received {:text, "hello"}
    assert {:error, _} = OpenAI.finish(state)

    assert {:error, _} =
             OpenAI.consume(state, sse(%{"type" => "response.incomplete"}), fn _ -> :ok end)
  end

  test "empty terminal output retains completed streamed text, tools and continuation" do
    output = [
      %{"type" => "reasoning", "encrypted_content" => "opaque", "summary" => []},
      %{"type" => "message", "content" => [%{"type" => "output_text", "text" => "Ready"}]},
      %{
        "type" => "function_call",
        "call_id" => "call_a",
        "name" => "write",
        "arguments" => "{\"path\":\"check.txt\",\"content\":\"before\\n\"}"
      }
    ]

    events =
      Enum.with_index(output, fn item, index ->
        %{"type" => "response.output_item.done", "output_index" => index, "item" => item}
      end) ++
        [
          %{
            "type" => "response.completed",
            "response" => %{"status" => "completed", "output" => []}
          }
        ]

    {:ok, state} = OpenAI.consume(OpenAI.new(), Enum.map_join(events, &sse/1), fn _ -> :ok end)
    assert {:ok, message, %{}} = OpenAI.finish(state)
    assert message["content"] == "Ready"
    assert [%{"id" => "call_a", "function" => %{"name" => "write"}}] = message["tool_calls"]
    assert OpenAI.request_body(%{model: "m"}, [message], [])["input"] == output
  end

  test "tool definitions use Responses function schema" do
    tool = %{
      "type" => "function",
      "function" => %{
        "name" => "read",
        "description" => "Read",
        "parameters" => %{"type" => "object"}
      }
    }

    assert [%{"type" => "function", "name" => "read", "parameters" => %{}}] =
             OpenAI.request_body(%{model: "m"}, [], [tool])["tools"]
  end

  defp sse(data), do: "data: " <> Jason.encode!(data) <> "\n\n"
end
