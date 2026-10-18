defmodule Ipse.Provider.StreamBoundsTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.{SSE, OpenAI, Anthropic}

  test "SSE bounds partial lines and ignored-line work before event dispatch" do
    assert {:error, message} = SSE.feed(SSE.new(), :binary.copy("x", 8_388_609))
    assert message =~ "stream limit"
    assert {:error, message} = SSE.feed(SSE.new(), :binary.copy(":\n", 131_073))
    assert message =~ "stream limit"
  end

  test "OpenAI refuses excessive item indexes and terminal call batches before admission" do
    assert {:error, message} =
             OpenAI.consume(
               OpenAI.new(),
               sse(%{
                 "type" => "response.output_item.added",
                 "output_index" => 256,
                 "item" => %{}
               }),
               fn _ -> :ok end
             )

    assert message =~ "stream limit"

    calls =
      for n <- 1..33,
          do: %{
            "type" => "function_call",
            "call_id" => "c#{n}",
            "name" => "read",
            "arguments" => "{}"
          }

    assert {:error, message} =
             OpenAI.consume(
               OpenAI.new(),
               sse(%{"type" => "response.completed", "response" => %{"output" => calls}}),
               fn _ -> :ok end
             )

    assert message =~ "stream limit"
  end

  test "Anthropic refuses out-of-range block indexes before retaining content" do
    state = %{
      sse: SSE.new(),
      blocks: %{},
      done: false,
      stop_reason: nil,
      usage: %{},
      reported_model: nil
    }

    assert {:error, message} =
             Anthropic.consume(
               state,
               sse(%{
                 "type" => "content_block_start",
                 "index" => 256,
                 "content_block" => %{"type" => "text", "text" => ""}
               }),
               fn _ -> :ok end
             )

    assert message =~ "stream limit"
  end

  defp sse(data), do: "data: " <> Jason.encode!(data) <> "\n\n"

  test "fragmented SSE lines retain exact bytes and multiline data until a delimiter" do
    bytes = :binary.copy("hé🙂", 1000)
    wire = "data: " <> bytes <> "\r\ndata: second\r\n\r\n"

    {events, _} =
      for <<byte <- wire>>, reduce: {[], SSE.new()} do
        {events, state} ->
          {next, state} = SSE.feed(state, <<byte>>)
          {Enum.reverse(next, events), state}
      end

    assert events == [%{event: nil, data: bytes <> "\nsecond"}]
  end

  test "SSE limits a never-dispatched multiline event and its fragmented partial line" do
    assert {:error, message} = SSE.feed(SSE.new(), :binary.copy("data:\n", 32_769))
    assert message =~ "stream limit"

    state =
      Enum.reduce(1..32_768, SSE.new(), fn _, state ->
        {[], state} = SSE.feed(state, "x")
        state
      end)

    assert {:error, message} = SSE.feed(state, "x")
    assert message =~ "stream limit"
  end

  test "OpenAI bounds argument fragments without dropping the terminal native arguments" do
    start =
      sse(%{
        "type" => "response.output_item.added",
        "output_index" => 0,
        "item" => %{
          "type" => "function_call",
          "call_id" => "one",
          "name" => "read",
          "arguments" => ""
        }
      })

    delta =
      sse(%{
        "type" => "response.function_call_arguments.delta",
        "output_index" => 0,
        "delta" => " "
      })

    {:ok, state} =
      OpenAI.consume(OpenAI.new(), start <> :binary.copy(delta, 32_768), fn _ -> :ok end)

    assert {:error, message} = OpenAI.consume(state, delta, fn _ -> :ok end)
    assert message =~ "stream limit"

    terminal = sse(%{"type" => "response.completed", "response" => %{"output" => []}})
    {:ok, state} = OpenAI.consume(state, terminal, fn _ -> :ok end)
    assert {:ok, message, _} = OpenAI.finish(state)
    assert hd(message["tool_calls"])["function"]["arguments"] == :binary.copy(" ", 32_768)
    assert hd(message["provider_data"]["output"])["arguments"] == :binary.copy(" ", 32_768)
  end

  test "Anthropic materializes text, tool JSON, thinking and signatures only into native output" do
    state = %{
      sse: SSE.new(),
      blocks: %{},
      done: false,
      stop_reason: nil,
      usage: %{},
      reported_model: nil
    }

    blocks = [
      %{"type" => "text", "text" => ""},
      %{"type" => "thinking", "thinking" => "", "signature" => ""},
      %{"type" => "tool_use", "id" => "one", "name" => "read", "input" => %{}}
    ]

    starts =
      Enum.with_index(blocks, fn block, index ->
        sse(%{"type" => "content_block_start", "index" => index, "content_block" => block})
      end)

    deltas =
      for {index, type, key, value} <- [
            {0, "text_delta", "text", "hé🙂"},
            {1, "thinking_delta", "thinking", "private"},
            {1, "signature_delta", "signature", "opaque"},
            {2, "input_json_delta", "partial_json", "{\"path\":\"a\"}"}
          ],
          do:
            sse(%{
              "type" => "content_block_delta",
              "index" => index,
              "delta" => %{"type" => type, key => value}
            })

    owner = self()

    wire =
      IO.iodata_to_binary(
        starts ++
          deltas ++
          [
            sse(%{"type" => "message_delta", "delta" => %{"stop_reason" => "tool_use"}}),
            sse(%{"type" => "message_stop"})
          ]
      )

    {:ok, state} = Anthropic.consume(state, wire, &send(owner, &1))
    assert {:ok, message, _} = Anthropic.finish(state)
    assert message["content"] == "hé🙂"

    assert message["provider_data"]["content"] == [
             %{"type" => "text", "text" => "hé🙂"},
             %{"type" => "thinking", "thinking" => "private", "signature" => "opaque"},
             %{"type" => "tool_use", "id" => "one", "name" => "read", "input" => %{"path" => "a"}}
           ]

    assert_received {:text, "hé🙂"}
    refute_received {:text, "private"}
    refute_received {:text, "opaque"}
  end

  test "a parser checks the request deadline before decoding and emitting each event" do
    state = Map.put(OpenAI.new(), :stream_deadline, System.monotonic_time(:millisecond) - 1)

    assert {:error, "Provider request timed out."} =
             OpenAI.consume(
               state,
               sse(%{"type" => "response.output_text.delta", "delta" => "not emitted"}),
               &send(self(), &1)
             )

    refute_received {:text, _}
  end

  test "Anthropic enforces the shared fragment bound for every streamed block field" do
    for {type, key} <- [
          {"text_delta", "text"},
          {"thinking_delta", "thinking"},
          {"signature_delta", "signature"},
          {"input_json_delta", "partial_json"}
        ] do
      state = %{
        sse: SSE.new(),
        blocks: %{},
        done: false,
        stop_reason: nil,
        usage: %{},
        reported_model: nil
      }

      delta =
        sse(%{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => type, key => " "}
        })

      {:ok, state} = Anthropic.consume(state, :binary.copy(delta, 32_768), fn _ -> :ok end)
      assert {:error, message} = Anthropic.consume(state, delta, fn _ -> :ok end)
      assert message =~ "stream limit"
    end
  end

  test "provider field bytes and decoded event count have independent hard limits" do
    alias Ipse.Provider.Fragments
    assert {:ok, buffer} = Fragments.append(Fragments.new(), :binary.copy("x", 8_388_608))
    assert {:error, _} = Fragments.append(buffer, "x")
    state = Map.put(OpenAI.new(), :stream_events, 65_536)
    assert {:error, message} = OpenAI.consume(state, sse(%{"type" => "unknown"}), fn _ -> :ok end)
    assert message =~ "stream limit"
  end
end
