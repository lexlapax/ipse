Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.StreamTest do
  import Ipse.Test.ProviderFixture, only: [sse: 1]
  use ExUnit.Case, async: false
  alias Ipse.Provider.Stream
  alias Ipse.Provider.OpenAI
  alias Ipse.Provider.Anthropic

  defmodule PrefixModel do
    def complete(config, _, _, emit) do
      send(config.test_pid, :prefix_model_called)

      state = %{
        sse: Ipse.Provider.Stream.new_sse(),
        blocks: %{},
        done: false,
        stop_reason: nil,
        usage: %{},
        reported_model: nil
      }

      usage = %{
        "type" => "message_start",
        "message" => %{
          "usage" => %{
            "input_tokens" => 60,
            "output_tokens" => 3,
            "cache_read_input_tokens" => 0,
            "cache_creation_input_tokens" => 0
          }
        }
      }

      wire = "data: " <> Jason.encode!(usage) <> "\n\n" <> :binary.copy("data:\n", 32_769)
      Ipse.Provider.Anthropic.consume(state, wire, emit)
    end
  end

  describe "provider/stream bounds" do
    test "usage preceding framing refusal remains durable and covered by the budget ledger on resume" do
      root = Path.join(System.tmp_dir!(), "ipse-stream-accounting-" <> Ipse.Usage.id())
      File.mkdir_p!(root)
      File.chmod!(root, 0o700)
      dir = Path.join(root, "sessions")

      config = %{
        provider: :anthropic,
        model: "fixture",
        provider_module: PrefixModel,
        test_pid: self(),
        home: Path.join(root, "home"),
        approval: :deny,
        budget: %{
          "version" => 1,
          "max_requests" => 2,
          "max_input_tokens" => 100,
          "reserve_input_tokens" => 40,
          "max_output_tokens" => 100,
          "reserve_output_tokens" => 32
        }
      }

      {:ok, pid} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Ipse.Session, config: config, cwd: root, state_dir: dir, subscriber: self()}
        )

      on_exit(fn ->
        if Process.alive?(pid), do: Ipse.Session.close(pid)
        File.rm_rf!(root)
      end)

      id = Ipse.Session.info(pid).id
      :ok = Ipse.Session.prompt(pid, "Synthetic prefix accounting")
      assert_receive :prefix_model_called, 5000
      assert_receive {:ipse, ^pid, {:done, :error}}, 5000
      {:ok, events} = Ipse.Journal.load(dir, id)
      [observed] = Enum.filter(events, &(&1["type"] == "request_usage_observed"))
      assert observed["usage"]["counts"]["input_tokens"] == 60
      {:ok, usage} = Ipse.Usage.restore(events, id)
      [request] = Map.values(usage.requests)
      assert request.completion["outcome"] == "failed"
      assert request.completion["usage"]["counts"]["input_tokens"] == 60
      {:ok, snapshot} = Ipse.Usage.Budget.saved(dir, id)
      assert Enum.find(snapshot["dimensions"], &(&1["unit"] == "input_tokens"))["booked"] == 60
      assert :ok = Ipse.Session.close(pid)
      before = File.read!(Path.join(dir, id <> ".jsonl"))

      {:ok, resumed} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Ipse.Session, id: id, config: config, cwd: root, state_dir: dir, subscriber: self()}
        )

      on_exit(fn -> if Process.alive?(resumed), do: Ipse.Session.close(resumed) end)
      assert File.read!(Path.join(dir, id <> ".jsonl")) == before
      refute_receive :prefix_model_called, 20
      assert :ok = Ipse.Session.close(resumed)
    end

    test "a valid usage prefix survives a later framing failure under either chunk boundary" do
      prefix =
        sse(%{"type" => "message_start", "message" => %{"usage" => %{"input_tokens" => 17}}})

      for suffix <- [:binary.copy("data:\n", 32_769), :binary.copy(":\n", 131_073)],
          chunks <- [[prefix <> suffix], [prefix, suffix]] do
        state = %{
          sse: Stream.new_sse(),
          blocks: %{},
          done: false,
          stop_reason: nil,
          usage: %{},
          reported_model: nil
        }

        owner = self()

        result =
          Enum.reduce_while(chunks, {:ok, state}, fn chunk, {:ok, state} ->
            case Anthropic.consume(state, chunk, &send(owner, &1)) do
              {:ok, state} -> {:cont, {:ok, state}}
              error -> {:halt, error}
            end
          end)

        assert {:error, message} = result
        assert message =~ "stream limit"
        assert_received {:provider_usage, %{"input_tokens" => 17}}
        refute_received {:provider_usage, _}
      end
    end

    test "an earlier provider error keeps precedence over a later framing failure" do
      prefix =
        sse(%{
          "type" => "error",
          "error" => %{
            "code" => "subscription_sharing_usage_limit_exceeded",
            "message" => "private-provider-prose"
          }
        })

      assert {:error, message} =
               OpenAI.consume(
                 OpenAI.new(:chatgpt),
                 prefix <> :binary.copy("data:\n", 32_769),
                 fn _ -> :ok end
               )

      assert message =~ "ChatGPT plan stream failed"
      refute message =~ "private-provider-prose"
    end

    test "a final event cannot admit a response after its usage callback exhausts the deadline" do
      deadline = System.monotonic_time(:millisecond) + 2000
      state = Map.put(OpenAI.new(), :stream_deadline, deadline)
      owner = self()

      emit = fn event ->
        send(owner, event)
        Process.sleep(max(deadline - System.monotonic_time(:millisecond) + 10, 0))
      end

      assert {:error, "Provider request timed out."} =
               OpenAI.consume(
                 state,
                 sse(%{
                   "type" => "response.completed",
                   "response" => %{"output" => [], "usage" => %{"input_tokens" => 7}}
                 }),
                 emit
               )

      assert_received {:provider_usage, %{"input_tokens" => 7}}
    end

    test "SSE bounds partial lines and ignored-line work before event dispatch" do
      assert {:error, message} = Stream.feed_sse(Stream.new_sse(), :binary.copy("x", 8_388_609))
      assert message =~ "stream limit"
      assert {:error, message} = Stream.feed_sse(Stream.new_sse(), :binary.copy(":\n", 131_073))
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
        sse: Stream.new_sse(),
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

    test "fragmented SSE lines retain exact bytes and multiline data until a delimiter" do
      bytes = :binary.copy("hé🙂", 1000)
      wire = "data: " <> bytes <> "\r\ndata: second\r\n\r\n"

      {events, _} =
        for <<byte <- wire>>, reduce: {[], Stream.new_sse()} do
          {events, state} ->
            {next, state} = Stream.feed_sse(state, <<byte>>)
            {Enum.reverse(next, events), state}
        end

      assert events == [%{event: nil, data: bytes <> "\nsecond"}]
    end

    test "SSE limits a never-dispatched multiline event and its fragmented partial line" do
      assert {:error, message} =
               Stream.feed_sse(Stream.new_sse(), :binary.copy("data:\n", 32_769))

      assert message =~ "stream limit"

      state =
        Enum.reduce(1..32_768, Stream.new_sse(), fn _, state ->
          {[], state} = Stream.feed_sse(state, "x")
          state
        end)

      assert {:error, message} = Stream.feed_sse(state, "x")
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
        sse: Stream.new_sse(),
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
               %{
                 "type" => "tool_use",
                 "id" => "one",
                 "name" => "read",
                 "input" => %{"path" => "a"}
               }
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
          sse: Stream.new_sse(),
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
      alias Ipse.Provider.Stream

      assert {:ok, buffer} =
               Stream.append_buffer(Stream.new_buffer(), :binary.copy("x", 8_388_608))

      assert {:error, _} = Stream.append_buffer(buffer, "x")
      state = Map.put(OpenAI.new(), :stream_events, 65_536)

      assert {:error, message} =
               OpenAI.consume(state, sse(%{"type" => "unknown"}), fn _ -> :ok end)

      assert message =~ "stream limit"
    end
  end

  describe "provider/sse" do
    test "arbitrary byte boundaries preserve UTF-8, CRLF, comments and multiline data" do
      wire = ": ping\r\nevent: message\r\ndata: héllo\r\ndata: second\r\n\r\ndata: last\n\n"
      expected = [%{event: "message", data: "héllo\nsecond"}, %{event: nil, data: "last"}]

      for size <- 1..byte_size(wire) do
        chunks = chunks(wire, size)

        {events, _} =
          Enum.reduce(chunks, {[], Stream.new_sse()}, fn chunk, {events, state} ->
            {new, state} = Stream.feed_sse(state, chunk)
            {events ++ new, state}
          end)

        assert events == expected
      end
    end

    test "CR-only delimiters dispatch; EOF does not invent an event" do
      assert {[%{event: nil, data: "yes"}], _} =
               Stream.feed_sse(Stream.new_sse(), "data: yes\r\r")

      {[], state} = Stream.feed_sse(Stream.new_sse(), "data: truncated")
      assert {[], ^state} = Stream.finish_sse(state)
    end
  end

  defp chunks("", _), do: []

  defp chunks(binary, size) when byte_size(binary) <= size, do: [binary]

  defp chunks(binary, size) do
    <<head::binary-size(^size), rest::binary>> = binary
    [head | chunks(rest, size)]
  end
end
