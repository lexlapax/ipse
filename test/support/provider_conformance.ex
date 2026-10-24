Code.require_file("provider_fixture.ex", __DIR__)

defmodule Ipse.Test.ProviderConformance do
  @moduledoc false
  alias Ipse.Test.ProviderFixture

  defmacro __using__(opts) do
    quote do
      @conformance_provider unquote(Keyword.fetch!(opts, :provider))
      @conformance_adapter unquote(Keyword.fetch!(opts, :adapter))
      @conformance_events unquote(Keyword.fetch!(opts, :events))

      defp conform(
             scenario,
             options \\ %{},
             messages \\ [%{"role" => "user", "content" => "fixture"}]
           ) do
        Ipse.Test.ProviderConformance.run(
          @conformance_provider,
          @conformance_adapter,
          @conformance_events,
          scenario,
          options,
          messages
        )
      end

      test "conformance: fragmented text, exact visible deltas and private continuation" do
        {{:ok, message, raw}, _, _, events} = conform(:text)
        assert message["content"] == "Hello 雪"
        assert message["role"] == "assistant"
        assert get_in(message, ["provider_data", "reported_model"]) == "fixture"
        text = for {:text, value} <- events, do: value
        assert Enum.join(text) == "Hello 雪"
        refute Enum.join(text) =~ "PRIVATE_CONTINUATION"
        assert Jason.encode!(message["provider_data"]) =~ "PRIVATE_CONTINUATION"
        usage = for {:provider_usage, value} <- events, do: value
        assert usage != []
        assert List.last(usage) == raw
      end

      for count <- [1, 2] do
        @conformance_count count
        test "conformance: #{count} complete tool calls with exact arguments" do
          scenario = if @conformance_count == 1, do: :tool, else: :parallel
          {{:ok, message, _}, _, _, _} = conform(scenario)
          calls = message["tool_calls"]
          assert length(calls) == @conformance_count

          assert Enum.map(calls, & &1["id"]) ==
                   Enum.map(1..@conformance_count, &("call-" <> to_string(&1)))

          assert Enum.all?(calls, &(&1["function"]["name"] == "read"))

          assert Enum.map(calls, &Jason.decode!(&1["function"]["arguments"])) ==
                   Enum.map(1..@conformance_count, &%{"path" => to_string(&1)})
        end
      end

      test "conformance: native continuation and parallel tool-result order survive a second request" do
        {{:ok, assistant, _}, _, _, _} = conform(:parallel)

        results =
          for call <- assistant["tool_calls"],
              do: %{
                "role" => "tool",
                "tool_call_id" => call["id"],
                "content" => "result-" <> call["id"]
              }

        {{:ok, _, _}, _, request, _} = conform(:text, %{}, [assistant | results])
        assert @conformance_events.replayed?(request, assistant["provider_data"], results)
      end

      test "conformance: truncation refuses the response while retaining observed usage" do
        {{:error, message}, _, _, events} = conform(:length)
        assert is_binary(message)
        assert Enum.any?(events, &match?({:provider_usage, raw} when is_map(raw), &1))
      end

      test "conformance: a stream error is never a successful answer" do
        {{:error, message}, _, _, _} = conform(:error)
        assert is_binary(message)
        refute message =~ "conformance-private-key"
      end

      for status <- [401, 429, 503] do
        @conformance_status status
        test "conformance: HTTP #{status} refuses without retry" do
          {{:error, message}, _, _, events} = conform(:text, %{http_status: @conformance_status})
          assert message =~ "HTTP #{@conformance_status}"
          assert events == []
          refute message =~ "conformance-private-key"
        end
      end

      test "conformance: EOF without the provider terminal marker refuses" do
        {{:error, message}, _, _, _} = conform(:truncated)
        assert is_binary(message)
      end

      test "conformance: byte limit refuses before a parser can admit content" do
        {{:error, message}, _, _, events} = conform(:oversized, %{max_response_bytes: 64})
        assert message =~ "byte limit"
        assert events == []
      end
    end
  end

  def run(provider, adapter, events, scenario, options, messages) do
    ^adapter = Ipse.Provider.Registry.fetch!(provider).adapter
    {status, options} = Map.pop(options, :http_status, 200)
    body = if scenario == :oversized, do: String.duplicate("x", 1024), else: events.body(scenario)
    mode = if scenario == :oversized, do: :whole, else: :fragmented
    {base, task} = ProviderFixture.start(body, status, "", mode)
    ref = make_ref()
    owner = self()

    key =
      if Ipse.Provider.Registry.fetch!(provider).credential == :none,
        do: nil,
        else: "conformance-private-key"

    config =
      Map.merge(
        %{provider: provider, model: "fixture", base_url: base, api_key: key, timeout_ms: 5000},
        options
      )

    tools = [
      %{
        "type" => "function",
        "function" => %{
          "name" => "read",
          "description" => "Read a fixture",
          "parameters" => %{
            "type" => "object",
            "properties" => %{"path" => %{"type" => "string"}},
            "required" => ["path"],
            "additionalProperties" => false
          }
        }
      }
    ]

    result = Ipse.Provider.complete(config, messages, tools, &send(owner, {ref, &1}))
    {headers, request} = Task.await(task, 6000)
    {result, headers, request, collect(ref, [])}
  end

  defp collect(ref, events) do
    receive do
      {^ref, event} -> collect(ref, [event | events])
    after
      0 -> Enum.reverse(events)
    end
  end
end

defmodule Ipse.Test.ProviderConformance.OpenAI do
  alias Ipse.Test.ProviderFixture

  def body(scenario) do
    output =
      [%{"type" => "reasoning", "encrypted_content" => "PRIVATE_CONTINUATION", "summary" => []}] ++
        if scenario in [:tool, :parallel, :length] do
          for i <- 1..if(scenario == :tool, do: 1, else: 2),
              do: %{
                "type" => "function_call",
                "call_id" => "call-#{i}",
                "name" => "read",
                "arguments" => Jason.encode!(%{"path" => "#{i}"})
              }
        else
          [
            %{
              "type" => "message",
              "role" => "assistant",
              "content" => [%{"type" => "output_text", "text" => "Hello 雪"}]
            }
          ]
        end

    prefix =
      if scenario in [:text, :truncated, :error],
        do:
          for(
            text <- ["Hello ", "雪"],
            do: %{"type" => "response.output_text.delta", "delta" => text}
          ),
        else: []

    usage = %{"input_tokens" => 3, "output_tokens" => 2, "total_tokens" => 5}

    terminal =
      case scenario do
        :truncated ->
          []

        :error ->
          [
            %{
              "type" => "response.failed",
              "response" => %{"usage" => usage, "error" => %{"message" => "fixture"}}
            }
          ]

        :length ->
          [
            %{
              "type" => "response.incomplete",
              "response" => %{"usage" => usage, "output" => output}
            }
          ]

        _ ->
          [
            %{
              "type" => "response.completed",
              "response" => %{
                "model" => "fixture",
                "status" => "completed",
                "output" => output,
                "usage" => usage
              }
            }
          ]
      end

    ProviderFixture.sse(prefix ++ terminal)
  end

  def replayed?(body, native, results) do
    expected =
      native["output"] ++
        Enum.map(
          results,
          &%{
            "type" => "function_call_output",
            "call_id" => &1["tool_call_id"],
            "output" => &1["content"]
          }
        )

    body["input"] == expected
  end
end

defmodule Ipse.Test.ProviderConformance.Anthropic do
  alias Ipse.Test.ProviderFixture

  def body(scenario) do
    prefix = [
      %{
        "type" => "message_start",
        "message" => %{"model" => "fixture", "usage" => %{"input_tokens" => 3}}
      },
      %{
        "type" => "content_block_start",
        "index" => 0,
        "content_block" => %{
          "type" => "thinking",
          "thinking" => "PRIVATE_CONTINUATION",
          "signature" => "fixture-signature"
        }
      }
    ]

    blocks =
      if scenario in [:tool, :parallel, :length] do
        for i <- 1..if(scenario == :tool, do: 1, else: 2),
            do: %{
              "type" => "content_block_start",
              "index" => i,
              "content_block" => %{
                "type" => "tool_use",
                "id" => "call-#{i}",
                "name" => "read",
                "input" => %{"path" => "#{i}"}
              }
            }
      else
        [
          %{
            "type" => "content_block_start",
            "index" => 1,
            "content_block" => %{"type" => "text", "text" => ""}
          }
        ] ++
          for text <- ["Hello ", "雪"],
              do: %{
                "type" => "content_block_delta",
                "index" => 1,
                "delta" => %{"type" => "text_delta", "text" => text}
              }
      end

    terminal =
      case scenario do
        :truncated ->
          []

        :error ->
          [%{"type" => "error", "error" => %{"type" => "fixture_error"}}]

        _ ->
          [
            %{
              "type" => "message_delta",
              "delta" => %{
                "stop_reason" =>
                  if(scenario == :length,
                    do: "max_tokens",
                    else: if(scenario in [:tool, :parallel], do: "tool_use", else: "end_turn")
                  )
              },
              "usage" => %{"output_tokens" => 2}
            },
            %{"type" => "message_stop"}
          ]
      end

    ProviderFixture.sse(prefix ++ blocks ++ terminal)
  end

  def replayed?(body, native, results) do
    expected =
      [%{"role" => "assistant", "content" => native["content"]}] ++
        Enum.map(
          results,
          &%{
            "role" => "user",
            "content" => [
              %{
                "type" => "tool_result",
                "tool_use_id" => &1["tool_call_id"],
                "content" => &1["content"]
              }
            ]
          }
        )

    body["messages"] == expected
  end
end

defmodule Ipse.Test.ProviderConformance.Ollama do
  alias Ipse.Test.ProviderFixture

  def body(scenario) do
    calls =
      if scenario in [:tool, :parallel, :length] do
        for i <- 1..if(scenario == :tool, do: 1, else: 2),
            do: %{
              "id" => "call-#{i}",
              "function" => %{"name" => "read", "arguments" => %{"path" => "#{i}"}}
            }
      else
        []
      end

    prefix =
      if calls == [] do
        for text <- ["Hello ", "雪"],
            do: %{
              "model" => "fixture",
              "message" => %{"role" => "assistant", "content" => text},
              "done" => false
            }
      else
        []
      end

    native = %{
      "role" => "assistant",
      "content" => "",
      "thinking" => "PRIVATE_CONTINUATION",
      "tool_calls" => calls
    }

    terminal =
      case scenario do
        :truncated ->
          []

        :error ->
          [%{"error" => "fixture"}]

        _ ->
          [
            %{
              "model" => "fixture",
              "message" => native,
              "done" => true,
              "done_reason" => if(scenario == :length, do: "length", else: "stop"),
              "prompt_eval_count" => 3,
              "eval_count" => 2
            }
          ]
      end

    ProviderFixture.ndjson(prefix ++ terminal)
  end

  def replayed?(body, native, results) do
    expected =
      [native["message"]] ++
        Enum.map(results, &%{"role" => "tool", "content" => &1["content"], "tool_name" => "read"})

    body["messages"] == expected
  end
end
