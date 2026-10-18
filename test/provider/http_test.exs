defmodule Ipse.Provider.HTTPTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider

  test "provider TLS preserves system trust and hostname verification with private Finch pools" do
    root = Path.join(System.tmp_dir!(), "ipse-provider-tls-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65537}],
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]
        ]
      })

    original =
      Enum.map(:public_key.cacerts_get(), fn
        {:cert, der, _} -> der
        der when is_binary(der) -> der
      end)

    pem = fn certs ->
      :public_key.pem_encode(Enum.map(certs, &{:Certificate, &1, :not_encrypted}))
    end

    saved = Path.join(root, "original.pem")
    trusted = Path.join(root, "fixture.pem")
    File.write!(saved, pem.(original))
    File.write!(trusted, pem.(certificate[:cacerts]))

    try do
      for {host, trust, expected} <- [
            {"localhost", trusted, :ok},
            {"127.0.0.1", trusted, :error},
            {"localhost", saved, :error}
          ] do
        :ok = :public_key.cacerts_load(trust)

        {:ok, listener} =
          :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)

        {:ok, {_, port}} = :ssl.sockname(listener)

        server =
          Task.async(fn ->
            {:ok, socket} = :ssl.transport_accept(listener, 3000)

            result =
              case :ssl.handshake(socket, 3000) do
                {:ok, tls} ->
                  {:ok, _} = :ssl.recv(tls, 0, 3000)

                  :ssl.send(
                    tls,
                    "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok"
                  )

                  :ok

                {:error, _} = error ->
                  error
              end

            :ssl.close(socket)
            :ssl.close(listener)
            result
          end)

        result =
          Provider.HTTP.stream(
            "https://#{host}:#{port}",
            [],
            %{},
            %{provider: :ollama, timeout_ms: 3000},
            "",
            fn acc, bytes -> {:ok, acc <> bytes} end
          )

        if expected == :ok do
          assert {:ok, "ok"} = result
          assert :ok = Task.await(server, 4000)
        else
          assert {:error, _} = result
          assert {:error, _} = Task.await(server, 4000)
        end
      end
    after
      :ok = :public_key.cacerts_load(saved)
      File.rm_rf!(root)
    end
  end

  for status <- [200, 201, 302, 429, 500], encoding <- [:length, :chunked] do
    test "HTTP #{status} #{encoding} reception stops at the byte bound before EOF" do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, {_, port}} = :inet.sockname(listener)
      limit = 65_536

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          request(socket, "")

          framing =
            if unquote(encoding) == :length,
              do: "content-length: 100000000\r\n",
              else: "transfer-encoding: chunked\r\n"

          :ok = :gen_tcp.send(socket, "HTTP/1.1 #{unquote(status)} Fixture\r\n#{framing}\r\n")
          bytes = String.duplicate("x", limit + 1)

          bytes =
            if unquote(encoding) == :chunked,
              do: [Integer.to_string(byte_size(bytes), 16), "\r\n", bytes, "\r\n"],
              else: bytes

          :gen_tcp.send(socket, bytes)
          # No body EOF or final chunk: the client must actively abort reception.
          result = :gen_tcp.recv(socket, 0, 5000)
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          result
        end)

      assert {:error, message} =
               Provider.HTTP.stream(
                 "http://127.0.0.1:#{port}",
                 [],
                 %{},
                 %{provider: :ollama, timeout_ms: 2000, max_response_bytes: limit},
                 0,
                 fn count, bytes -> {:ok, count + byte_size(bytes)} end
               )

      assert message =~ "byte limit"
      assert {:error, :closed} = Task.await(server, 6000)
    end
  end

  test "ordinary provider requests enforce a transport byte ceiling before parsing" do
    bytes = String.duplicate("x", 8_388_609)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        request(socket, "")

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(bytes)}\r\nconnection: close\r\n\r\n"
          )

        result = :gen_tcp.send(socket, bytes)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    assert {:error, message} =
             Ipse.Provider.HTTP.stream(
               "http://127.0.0.1:#{port}",
               [],
               %{},
               %{provider: :ollama, timeout_ms: 5000},
               0,
               fn count, chunk -> {:ok, count + byte_size(chunk)} end
             )

    assert message =~ "byte limit"
    assert Task.await(server) in [:ok, {:error, :closed}]
  end

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

    tools = [
      %{
        "type" => "function",
        "function" => %{
          "name" => "read",
          "description" => "Read a file",
          "parameters" => %{
            "type" => "object",
            "properties" => %{"path" => %{"type" => "string"}}
          }
        }
      }
    ]

    assert {:ok, message, %{"output_tokens" => 1}} =
             Provider.complete(
               config,
               [runtime_message(config), %{"role" => "user", "content" => "hi"}],
               tools,
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
    refute Map.has_key?(request, "tools")
    assert Enum.any?(request["input"], &(&1["role"] == "developer"))

    assert Enum.any?(request["input"], fn item ->
             item["type"] == "additional_tools" and item["role"] == "developer" and
               item["tools"] == [Map.put(hd(tools)["function"], "type", "function")]
           end)

    assert Enum.any?(request["input"], fn item ->
             is_binary(item["content"]) and item["content"] =~ "Ipse version:" and
               item["content"] =~ "Requested model: test"
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

  test "ChatGPT subscription failures stop with safe recovery details and no billing fallback" do
    for {status, code, hint} <- [
          {403, "subscription_sharing_user_not_eligible", "Check eligibility"},
          {429, "subscription_sharing_usage_limit_exceeded", "blocked by a limit or app setting"},
          {503, "subscription_sharing_usage_unavailable", "Preserve sign-in"}
        ] do
      body = Jason.encode!(%{"error" => %{"code" => code, "message" => "secret response prose"}})
      request_id = "req-chatgpt-#{status}"
      {base, server} = fixture(body, status, "x-request-id: #{request_id}\r\n")

      assert {:error, message} =
               Provider.complete(
                 %{
                   provider: :chatgpt,
                   model: "test",
                   base_url: base,
                   api_key: "test-secret",
                   timeout_ms: 5000
                 },
                 [],
                 [],
                 fn _ -> :ok end
               )

      assert message =~ "HTTP #{status}"
      assert message =~ "code=#{code}"
      assert message =~ "request_id=#{request_id}"
      assert message =~ hint
      refute message =~ "secret response prose"
      Task.await(server)
    end
  end

  test "ChatGPT direct 401 detail and generic 500 preserve safe HTTP metadata" do
    cases = [
      {401, %{"detail" => "private direct-route text"}, "body=detail",
       "selected account and granted scopes"},
      {500, %{"error" => %{"param" => "model", "message" => "private server text"}},
       "body=error; param=model", "Check ChatGPT plan access"}
    ]

    for {status, payload, metadata, hint} <- cases do
      request_id = "req-direct-#{status}"
      {base, server} = fixture(Jason.encode!(payload), status, "x-request-id: #{request_id}\r\n")

      assert {:error, message} =
               Provider.complete(
                 %{
                   provider: :chatgpt,
                   model: "test",
                   base_url: base,
                   api_key: "test-secret",
                   timeout_ms: 5000
                 },
                 [],
                 [],
                 fn _ -> :ok end
               )

      assert message =~ "HTTP #{status}; #{metadata}"
      assert message =~ "request_id=#{request_id}"
      assert message =~ hint
      refute message =~ "private"
      Task.await(server)
    end
  end

  test "required text delivery errors survive the real adapter boundary without being mislabelled" do
    body =
      Jason.encode!(%{
        "message" => %{"role" => "assistant", "content" => "synthetic text"},
        "done" => true
      }) <> "\n"

    {base, server} = fixture(body)

    assert {:error, error} =
             Provider.complete(
               %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 5000},
               [],
               [],
               fn
                 {:text, _} -> raise Ipse.TextStream.RequiredFailure
                 _ -> :ok
               end
             )

    assert error =~ "Required visible-text delivery failed"
    refute error =~ "invalid response"
    assert {_, _} = Task.await(server)
  end

  test "Ollama omitted counters stay unknown while optional cache and duration remain facts" do
    for metrics <- [
          %{},
          %{
            "prompt_eval_count" => 9,
            "eval_count" => 2,
            "prompt_eval_cached_count" => 3,
            "total_duration" => 500_000
          }
        ] do
      body =
        Jason.encode!(Map.merge(%{"message" => %{"content" => "done"}, "done" => true}, metrics)) <>
          "\n"

      {base, server} = fixture(body)
      owner = self()

      assert {:ok, _, usage} =
               Provider.complete(
                 %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 5000},
                 [],
                 [],
                 &send(owner, &1)
               )

      assert usage["input_tokens"] == metrics["prompt_eval_count"]
      assert usage["output_tokens"] == metrics["eval_count"]
      assert usage["input_cached_tokens"] == metrics["prompt_eval_cached_count"]
      assert usage["provider_duration_ns"] == metrics["total_duration"]
      assert_received {:provider_usage, ^usage}
      Task.await(server)
    end
  end

  test "OpenAI incomplete output retains reported usage without admitting tools or visible reasoning" do
    usage = %{"input_tokens" => 9, "output_tokens" => 2}

    body =
      event(%{
        "type" => "response.incomplete",
        "response" => %{
          "usage" => usage,
          "output" => [%{"type" => "reasoning", "text" => "synthetic-private-reasoning"}]
        }
      })

    {base, server} = fixture(body)
    owner = self()

    assert {:error, _} =
             Provider.complete(
               %{
                 provider: :openai,
                 model: "fixture",
                 api_key: "fixture-key",
                 base_url: base,
                 timeout_ms: 5000
               },
               [],
               [],
               &send(owner, &1)
             )

    assert_received {:provider_usage, ^usage}
    refute_received {:text, _}
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
               Ipse.Compaction.request_config(%{
                 provider: :ollama,
                 model: "test",
                 base_url: next_base,
                 timeout_ms: 5000
               }),
               [],
               [],
               fn _ -> :ok end
             )

    assert call["id"] != next_call["id"]
    {_, summary_request} = Task.await(next_server)
    assert summary_request["format"]["required"] == ~w(decisions facts open_questions)
    assert summary_request["think"] == false
    assert summary_request["options"]["num_predict"] == 4096
    refute Map.has_key?(request, "format")
    refute Map.has_key?(request, "think")
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

  test "configured child models reach each adapter without parent credentials or native continuation" do
    for provider <- ["openai", "ollama", "anthropic"] do
      body =
        case provider do
          "openai" ->
            event(%{
              "type" => "response.completed",
              "response" => %{"status" => "completed", "output" => []}
            })

          "ollama" ->
            Jason.encode!(%{
              "message" => %{"role" => "assistant", "content" => "ok"},
              "done" => true
            }) <> "\n"

          "anthropic" ->
            event(%{
              "type" => "message_start",
              "message" => %{"id" => "m", "role" => "assistant", "content" => [], "usage" => %{}}
            }) <>
              event(%{
                "type" => "message_delta",
                "delta" => %{"stop_reason" => "end_turn"},
                "usage" => %{}
              }) <>
              event(%{"type" => "message_stop"})
        end

      {base, server} = fixture(body)

      parent = %{
        provider: :chatgpt,
        model: "parent",
        api_key: "parent-private",
        base_url: "https://parent.invalid",
        profiles: %{
          "child" => %{
            "provider" => provider,
            "model" => "selected-child",
            "max_output_tokens" => 64,
            "base_url" => base,
            "timeout_ms" => 5000
          }
        }
      }

      assert {:ok, child} = Ipse.Profiles.child_config(parent, %{}, %{"profile" => "child"})
      refute Map.has_key?(child, :api_key)
      child = Map.put(child, :api_key, "child-fixture-key")

      assert {:ok, _, _} =
               Provider.complete(
                 child,
                 [%{"role" => "user", "content" => "selected task"}],
                 [],
                 fn _ -> :ok end
               )

      {headers, request} = Task.await(server)
      assert request["model"] == "selected-child"

      case provider do
        "openai" -> assert request["max_output_tokens"] == 64
        "ollama" -> assert request["options"]["num_predict"] == 64
        "anthropic" -> assert request["max_tokens"] == 64
      end

      refute headers <> Jason.encode!(request) =~ "parent-private"
      refute Map.has_key?(request, "reasoning")
    end
  end

  test "Ollama summary caps keep the lower bound and explicit length termination preserves usage without tools" do
    complete = Jason.encode!(%{"message" => %{"content" => "ok"}, "done" => true}) <> "\n"

    for {limit, expected} <- [{64, 64}, {9000, 4096}] do
      {base, server} = fixture(complete)

      config =
        Ipse.Compaction.request_config(%{
          provider: :ollama,
          model: "fixture",
          base_url: base,
          timeout_ms: 5000,
          max_output_tokens: limit
        })

      assert {:ok, _, _} = Provider.complete(config, [], [], fn _ -> :ok end)
      {_, request} = Task.await(server)
      assert request["options"] == %{"temperature" => 0, "num_predict" => expected}
      assert is_map(request["format"])
    end

    truncated =
      Jason.encode!(%{
        "message" => %{
          "content" => "",
          "thinking" => "synthetic-private",
          "tool_calls" => [%{"function" => %{"name" => "write", "arguments" => %{}}}]
        },
        "done" => true,
        "done_reason" => "length",
        "prompt_eval_count" => 8,
        "eval_count" => 64
      }) <> "\n"

    {base, server} = fixture(truncated)
    owner = self()

    assert {:error, message} =
             Provider.complete(
               %{
                 provider: :ollama,
                 model: "fixture",
                 base_url: base,
                 timeout_ms: 5000,
                 max_output_tokens: 64
               },
               [],
               [],
               &send(owner, &1)
             )

    assert message =~ "incomplete"
    refute message =~ "synthetic-private"
    assert_received {:provider_usage, %{"input_tokens" => 8, "output_tokens" => 64}}
    refute_received {:text, _}
    Task.await(server)
  end

  test "Ollama refuses excessive tool batches and preserves the order of admitted batches" do
    call = fn n ->
      %{"id" => "c#{n}", "function" => %{"name" => "read", "arguments" => %{"path" => "#{n}"}}}
    end

    for batches <- [[Enum.map(1..33, call)], Enum.map(1..33, &[call.(&1)])] do
      body =
        Enum.map_join(batches, fn calls ->
          Jason.encode!(%{"message" => %{"tool_calls" => calls}, "done" => false}) <> "\n"
        end) <> Jason.encode!(%{"message" => %{}, "done" => true}) <> "\n"

      {base, server} = fixture(body, 200, "", :whole)

      assert {:error, message} =
               Provider.complete(
                 %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 5000},
                 [],
                 [],
                 fn _ -> :ok end
               )

      assert message =~ "stream limit"
      Task.await(server)
    end

    body =
      Jason.encode!(%{
        "message" => %{
          "content" => "hé",
          "thinking" => "private",
          "tool_calls" => [call.(1), call.(2)]
        }
      }) <>
        "\n" <>
        Jason.encode!(%{
          "message" => %{"content" => "🙂", "thinking" => "-tail", "tool_calls" => [call.(3)]},
          "done" => true
        })

    {base, server} = fixture(body)
    owner = self()

    assert {:ok, message, _} =
             Provider.complete(
               %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 5000},
               [],
               [],
               &send(owner, &1)
             )

    assert message["content"] == "hé🙂"
    assert message["provider_data"]["message"]["thinking"] == "private-tail"
    assert Enum.map(message["tool_calls"], & &1["id"]) == ["c1", "c2", "c3"]

    assert Enum.map(message["provider_data"]["message"]["tool_calls"], & &1["id"]) == [
             "c1",
             "c2",
             "c3"
           ]

    assert_received {:text, "hé"}
    assert_received {:text, "🙂"}
    refute_received {:text, "private"}
    Task.await(server)
  end

  for status <- [200, 500] do
    test "HTTP #{status} refuses excessive data chunks below the byte ceiling before EOF" do
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, {_, port}} = :inet.sockname(listener)

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          request(socket, "")

          :gen_tcp.send(socket, [
            "HTTP/1.1 #{unquote(status)} Fixture\r\ntransfer-encoding: chunked\r\n\r\n",
            :binary.copy("1\r\nx\r\n", 131_073)
          ])

          result = :gen_tcp.recv(socket, 0, 5000)
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          result
        end)

      assert {:error, message} =
               Provider.HTTP.stream(
                 "http://127.0.0.1:#{port}",
                 [],
                 %{},
                 %{provider: :ollama, timeout_ms: 4000},
                 0,
                 fn count, _ -> {:ok, count + 1} end
               )

      assert message =~ "stream limit"
      assert {:error, :closed} = Task.await(server, 6000)
    end
  end

  defp fixture(body, status \\ 200, response_headers \\ "", send_mode \\ :fragmented) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {headers, payload} = request(socket, "")

        response =
          "HTTP/1.1 #{status} Fixture\r\ncontent-type: text/event-stream\r\n#{response_headers}content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n"

        :ok = :gen_tcp.send(socket, response)

        if send_mode == :whole do
          :ok = :gen_tcp.send(socket, body)
        else
          for <<byte <- body>>, do: :ok = :gen_tcp.send(socket, <<byte>>)
        end

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
