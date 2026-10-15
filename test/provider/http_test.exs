defmodule Ipse.Provider.HTTPTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider

  test "Responses API streams locally and posts canonical tools and bearer credentials" do
    output = [
      %{"type" => "message", "content" => [%{"type" => "output_text", "text" => "hello"}]}
    ]

    body =
      event(%{"type" => "response.output_text.delta", "delta" => "hello"}) <>
        event(%{
          "type" => "response.completed",
          "response" => %{
            "status" => "completed",
            "model" => "openai-fixture-model",
            "output" => output,
            "usage" => %{"output_tokens" => 1}
          }
        })

    {base, server} = fixture(body)
    owner = self()

    config = %{
      provider: :chatgpt,
      model: "test",
      base_url: base,
      api_key: "test-secret",
      timeout_ms: 5000
    }

    assert {:ok, message, %{"output_tokens" => 1}} =
             Provider.complete(
               config,
               [runtime_message(config), %{"role" => "user", "content" => "hi"}],
               [],
               &send(owner, &1)
             )

    assert message["content"] == "hello"
    assert message["provider_data"]["reported_model"] == "openai-fixture-model"

    assert_received {:text, "hello"}
    {headers, request} = Task.await(server)
    assert headers =~ "POST /responses HTTP/1.1"
    assert String.downcase(headers) =~ "authorization: bearer test-secret"
    assert request["store"] == false
    assert request["stream"] == true

    assert Enum.any?(request["input"], fn item ->
             item["content"] =~ "Ipse version:" and item["content"] =~ "Requested model: test"
           end)
  end

  test "a clean HTTP EOF without a model completion is an error" do
    {base, server} =
      fixture(event(%{"type" => "response.output_text.delta", "delta" => "partial"}))

    assert {:error, message} =
             Provider.complete(
               %{
                 provider: :openai,
                 model: "test",
                 base_url: base,
                 api_key: "key",
                 timeout_ms: 5000
               },
               [],
               [],
               fn _ -> :ok end
             )

    assert message =~ "before response.completed"
    Task.await(server)
  end

  test "HTTP errors expose status without leaking provider response or credentials" do
    {base, server} = fixture("do not reveal test-secret", 401)

    assert {:error, "Provider returned HTTP 401."} =
             Provider.complete(
               %{
                 provider: :openai,
                 model: "test",
                 base_url: base,
                 api_key: "test-secret",
                 timeout_ms: 5000
               },
               [],
               [],
               fn _ -> :ok end
             )

    Task.await(server)
  end

  test "Ollama requires done and converts native tool arguments" do
    body =
      Jason.encode!(%{
        "message" => %{
          "content" => "",
          "tool_calls" => [%{"function" => %{"name" => "read", "arguments" => %{"path" => "a"}}}]
        },
        "model" => "ollama:fixture-model",
        "done" => true,
        "prompt_eval_count" => 7,
        "eval_count" => 3
      }) <> "\n"

    {base, server} = fixture(body)

    assert {:ok, message, %{"input_tokens" => 7}} =
             Provider.complete(
               %{provider: :ollama, model: "test", base_url: base, timeout_ms: 5000},
               [runtime_message(%{provider: :ollama, model: "test"})],
               [],
               fn _ -> :ok end
             )

    assert [call] = message["tool_calls"]
    assert message["provider_data"]["reported_model"] == "ollama:fixture-model"

    assert Jason.decode!(call["function"]["arguments"]) == %{"path" => "a"}
    {headers, request} = Task.await(server)
    assert headers =~ "POST /api/chat HTTP/1.1"

    assert Enum.any?(request["messages"], fn message ->
             message["content"] =~ "Ipse version:" and
               message["content"] =~ "Requested model: test"
           end)

    {next_base, next_server} = fixture(body)

    assert {:ok, %{"tool_calls" => [next_call]}, _} =
             Provider.complete(
               %{provider: :ollama, model: "test", base_url: next_base, timeout_ms: 5000},
               [],
               [],
               fn _ -> :ok end
             )

    assert call["id"] != next_call["id"]
    Task.await(next_server)
  end

  test "Anthropic streams tools and preserves native blocks" do
    body =
      [
        %{
          "type" => "message_start",
          "message" => %{"model" => "anthropic-fixture-model", "usage" => %{"input_tokens" => 4}}
        },
        %{
          "type" => "content_block_start",
          "index" => 0,
          "content_block" => %{
            "type" => "tool_use",
            "id" => "tool_a",
            "name" => "read",
            "input" => %{}
          }
        },
        %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "input_json_delta", "partial_json" => "{\"path\":"}
        },
        %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "input_json_delta", "partial_json" => "\"a\"}"}
        },
        %{
          "type" => "message_delta",
          "delta" => %{"stop_reason" => "tool_use"},
          "usage" => %{"output_tokens" => 2}
        },
        %{"type" => "message_stop"}
      ]
      |> Enum.map_join(&event/1)

    {base, server} = fixture(body)

    assert {:ok, message, %{"input_tokens" => 4, "output_tokens" => 2}} =
             Provider.complete(
               %{
                 provider: :anthropic,
                 model: "test",
                 base_url: base,
                 api_key: "key",
                 timeout_ms: 5000
               },
               [runtime_message(%{provider: :anthropic, model: "test"})],
               [],
               fn _ -> :ok end
             )

    assert [%{"id" => "tool_a", "function" => %{"arguments" => "{\"path\":\"a\"}"}}] =
             message["tool_calls"]

    assert [%{"input" => %{"path" => "a"}}] = message["provider_data"]["content"]
    assert message["provider_data"]["reported_model"] == "anthropic-fixture-model"
    {_headers, request} = Task.await(server)
    assert request["system"] =~ "Ipse version:"
    assert request["system"] =~ "Configured provider: anthropic"
    assert request["system"] =~ "Requested model: test"
  end

  test "loopback always bypasses proxies" do
    for host <- ["localhost", "127.0.0.1", "127.2.3.4", "::1"],
        do: assert(Provider.HTTP.bypass_proxy?(host))
  end

  defp fixture(body, status \\ 200) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {headers, payload} = request(socket, "")

        response =
          "HTTP/1.1 #{status} Fixture\r\ncontent-type: text/event-stream\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n"

        :ok = :gen_tcp.send(socket, response)
        for <<byte <- body>>, do: :ok = :gen_tcp.send(socket, <<byte>>)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        {headers, Jason.decode!(payload)}
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, rest(socket, body, String.to_integer(size))}

      [_] ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
        request(socket, buffer <> chunk)
    end
  end

  defp rest(_, body, size) when byte_size(body) >= size, do: body

  defp rest(socket, body, size) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
    rest(socket, body <> chunk, size)
  end

  defp event(data), do: "data: " <> Jason.encode!(data) <> "\n\n"

  defp runtime_message(config) do
    runtime = Ipse.RuntimeInfo.snapshot(config)
    %{"role" => "system", "content" => Ipse.Context.system(System.tmp_dir!(), [], runtime)}
  end
end
