Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.ChatCompletionsTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.{ChatCompletions, Registry}
  alias Ipse.Config.Profiles
  alias Ipse.Test.ProviderFixture, as: Fixture

  defp profile(extra \\ %{}),
    do:
      Map.merge(
        %{"provider" => "openrouter", "model" => "org/model", "upstream" => "openai"},
        extra
      )

  defp config(profile) do
    %{
      provider: Registry.fetch!(profile["provider"]).atom,
      model: profile["model"],
      api_key: "fixture-router-key",
      base_url: profile["base_url"],
      reasoning_effort: profile["reasoning_effort"],
      execution: Profiles.manifest("pinned", profile),
      timeout_ms: 2000
    }
    |> Map.merge(Registry.profile_runtime(profile))
  end

  defp chunk(delta, extra \\ %{}),
    do:
      Map.merge(
        %{
          "model" => "org/model",
          "provider" => "openai",
          "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => nil}]
        },
        extra
      )

  defp terminal(reason \\ "stop"),
    do: chunk(%{}, %{"choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => reason}]})

  defp answer, do: Fixture.sse([chunk(%{"content" => "done"}), terminal(), "[DONE]"])

  defp usage,
    do: %{
      "prompt_tokens" => 7,
      "completion_tokens" => 5,
      "total_tokens" => 12,
      "prompt_tokens_details" => %{"cached_tokens" => 2, "cache_write_tokens" => 0},
      "completion_tokens_details" => %{"reasoning_tokens" => 3},
      "cost" => 123.45,
      "cost_details" => %{"upstream_inference_cost" => 9.87}
    }

  test "only a pinned upstream, non-routing model and declared data policy are admitted" do
    assert Registry.fetch!(:openrouter).credential == {:env, "OPENROUTER_API_KEY"}
    assert "OPENROUTER_API_KEY" in Registry.secret_env()
    assert Registry.fetch!(:openrouter).billing_mode == "api"
    assert Registry.fetch!(:openai_compatible).billing_mode == "local"
    assert :ok = Profiles.validate_profile(profile())

    assert :ok =
             Profiles.validate_profile(
               profile(%{"data_collection" => "allow", "reasoning_effort" => "max"})
             )

    for bad <- [
          Map.delete(profile(), "upstream"),
          profile(%{"upstream" => "OpenAI"}),
          profile(%{"upstream" => "openai/region"}),
          profile(%{"upstream" => "bad\n"}),
          profile(%{"data_collection" => "sometimes"})
        ] do
      assert {:error, _} = Profiles.validate_profile(bad)
    end

    for model <- ["openrouter/auto", "org/model:nitro", "org/model:floor", "one,two"] do
      assert {:error, _} = Profiles.validate_profile(profile(%{"model" => model}))
    end

    assert {:error, _} =
             Profiles.validate_profile(%{
               "provider" => "openai",
               "model" => "fixture",
               "upstream" => "openai"
             })

    assert {:error, _} =
             ChatCompletions.validate_request(Map.delete(config(profile()), :execution))

    assert {:error, _} =
             ChatCompletions.validate_request(%{config(profile()) | upstream: "different"})
  end

  test "default destination is the actual completions route and comments do not affect identity" do
    selected = config(profile())
    target = "https://openrouter.ai/api/v1/chat/completions"
    assert ChatCompletions.endpoint(selected) == target

    assert {:ok, %{"origin" => "https://openrouter.ai", "target_sha256" => digest}} =
             Ipse.Provider.destination(selected)

    assert digest == Ipse.JSON.sha256(target)

    assert Ipse.Provider.destination(selected) ==
             Ipse.Provider.destination(%{selected | base_url: "https://openrouter.ai/api/v1"})

    bytes = ": OPENROUTER PROCESSING\n\n" <> answer()

    assert {:ok, state} =
             ChatCompletions.consume(ChatCompletions.new(selected), bytes, fn _ -> :ok end)

    assert {:ok, %{"content" => "done"}, _} = ChatCompletions.finish(state)
  end

  test "OpenAI's catalogued display name identifies the pinned slug without guessing other aliases" do
    for name <- ["openai", "OpenAI"] do
      bytes =
        Fixture.sse([
          Map.put(chunk(%{"content" => "done"}), "provider", name),
          Map.put(terminal(), "provider", name),
          "[DONE]"
        ])

      assert {:ok, state} =
               ChatCompletions.consume(ChatCompletions.new(config(profile())), bytes, fn _ ->
                 :ok
               end)

      assert {:ok, message, _} = ChatCompletions.finish(state)
      assert message["provider_data"]["reported_upstream"] == name
    end

    for name <- ["OPENAI", "Open AI", "Azure", "openai/other"] do
      assert {:error, _} =
               ChatCompletions.consume(
                 ChatCompletions.new(config(profile())),
                 Fixture.sse(Map.put(chunk(%{"content" => "untrusted"}), "provider", name)),
                 fn _ -> flunk("wrong upstream") end
               )
    end
  end

  test "local compatibility requires an explicit loopback endpoint and no reasoning or credential" do
    for url <- [
          nil,
          "https://example.com/v1",
          "http://192.168.1.2/v1",
          "http://localhost.example/v1",
          "http://localhost/v1?key=x"
        ] do
      refute Ipse.Provider.valid_base_url?(:openai_compatible, url)

      assert {:error, _} =
               Profiles.validate_profile(%{
                 "provider" => "openai_compatible",
                 "model" => "local",
                 "base_url" => url
               })
    end

    for host <- ["127.0.0.1", "localhost", "[::1]"] do
      assert Ipse.Provider.valid_base_url?(:openai_compatible, "http://#{host}:8000/v1")
    end

    local = %{provider: :openai_compatible, model: "local", base_url: "http://localhost:8000/v1"}
    assert :ok = ChatCompletions.validate_request(local)
    assert {:error, _} = ChatCompletions.validate_request(Map.put(local, :api_key, "private"))

    assert {:error, _} =
             ChatCompletions.validate_request(Map.put(local, :reasoning_effort, "high"))

    body =
      ChatCompletions.request_body(local, [%{"role" => "developer", "content" => "policy"}], [])

    assert body == %{
             "model" => "local",
             "messages" => [%{"role" => "system", "content" => "policy"}],
             "stream" => true,
             "stream_options" => %{"include_usage" => true}
           }
  end

  test "full wire body pins policy, sends only the selected key header and omits routing shortcuts" do
    {base, server} = Fixture.start(answer())

    selected =
      profile(%{"base_url" => base, "reasoning_effort" => "high", "data_collection" => "allow"})

    config = config(selected) |> Map.put(:max_output_tokens, 4096)

    messages = [
      %{"role" => "developer", "content" => "policy"},
      %{"role" => "user", "content" => "task"}
    ]

    tools = Ipse.Tools.definitions() |> Enum.take(1)

    assert {:ok, %{"content" => "done"}, _} =
             Ipse.Provider.complete(config, messages, tools, fn _ -> :ok end)

    {headers, body} = Task.await(server)
    assert headers =~ "POST /chat/completions HTTP/1.1"
    assert headers =~ "authorization: Bearer fixture-router-key"
    refute String.downcase(headers) =~ "referer"
    refute String.downcase(headers) =~ "x-title"

    assert body == %{
             "model" => "org/model",
             "messages" => [%{"role" => "system", "content" => "policy"}, List.last(messages)],
             "tools" => tools,
             "tool_choice" => "auto",
             "stream" => true,
             "stream_options" => %{"include_usage" => true},
             "max_tokens" => 4096,
             "reasoning" => %{"effort" => "high"},
             "provider" => %{
               "only" => ["openai"],
               "order" => ["openai"],
               "allow_fallbacks" => false,
               "require_parameters" => true,
               "data_collection" => "allow"
             }
           }

    minimal = ChatCompletions.request_body(config(profile()), [], [])
    assert minimal["provider"]["data_collection"] == "deny"

    for key <- ~w(tools tool_choice reasoning max_tokens models route transforms),
        do: refute(Map.has_key?(minimal, key))
  end

  test "first and later identity mismatches refuse before new visible content while retaining usage" do
    for field <- ["model", "provider"], late? <- [false, true] do
      mismatch = chunk(%{"content" => "UNTRUSTED"}, %{field => "different", "usage" => usage()})

      bytes =
        Fixture.sse(if(late?, do: [chunk(%{"content" => "earlier"}), mismatch], else: [mismatch]))

      owner = self()
      ref = make_ref()

      assert {:error, error} =
               ChatCompletions.consume(
                 ChatCompletions.new(config(profile())),
                 bytes,
                 &send(owner, {ref, &1})
               )

      assert error =~ if(field == "model", do: "different model", else: "different upstream")
      assert_receive {^ref, {:provider_usage, raw}}
      assert raw == usage()

      text =
        if late? do
          assert_receive {^ref, {:text, "earlier"}}
          "earlier"
        else
          ""
        end

      refute text =~ "UNTRUSTED"
      refute_receive {^ref, {:text, "UNTRUSTED"}}
    end

    assert {:error, _} =
             ChatCompletions.consume(
               ChatCompletions.new(config(profile())),
               Fixture.sse(%{"choices" => [%{"delta" => %{"content" => "UNTRUSTED"}}]}),
               fn _ -> flunk("unverified text") end
             )
  end

  test "ordered reasoning details, fragmented parallel calls and repeated final usage survive replay" do
    details = [
      %{"type" => "reasoning.encrypted", "data" => "opaque", "index" => 0},
      %{"type" => "reasoning.text", "text" => "PRIVATE_CONTINUATION", "index" => 1},
      %{"type" => "reasoning.summary", "summary" => "private summary", "index" => 2}
    ]

    first =
      chunk(%{
        "reasoning_details" => Enum.take(details, 2),
        "reasoning" => "private ",
        "tool_calls" => [
          %{
            "index" => 0,
            "id" => "call-a",
            "type" => "function",
            "function" => %{"name" => "re", "arguments" => "{\"path\":"}
          },
          %{
            "index" => 1,
            "id" => "call-b",
            "type" => "function",
            "function" => %{"name" => "read", "arguments" => "{\"path\":\"b\"}"}
          }
        ]
      })

    second =
      chunk(%{
        "reasoning_details" => Enum.drop(details, 2),
        "reasoning" => "thought",
        "tool_calls" => [
          %{"index" => 0, "function" => %{"name" => "ad", "arguments" => "\"a\"}"}}
        ]
      })

    accounting =
      terminal("tool_calls")
      |> Map.put("usage", usage())
      |> put_in(["choices", Access.at(0), "delta"], %{"role" => "assistant", "content" => ""})

    {base, server} =
      Fixture.start(Fixture.sse([first, second, terminal("tool_calls"), accounting, "[DONE]"]))

    assert {:ok, assistant, raw} =
             Ipse.Provider.complete(config(profile(%{"base_url" => base})), [], [], fn
               {:text, _} -> flunk("reasoning was displayed")
               _ -> :ok
             end)

    Task.await(server)
    assert raw == usage()
    native = assistant["provider_data"]["message"]
    assert native["reasoning_details"] == details
    assert native["reasoning"] == "private thought"

    assert Enum.map(assistant["tool_calls"], &Jason.decode!(&1["function"]["arguments"])) == [
             %{"path" => "a"},
             %{"path" => "b"}
           ]

    {base, server} = Fixture.start(answer())

    results =
      for call <- assistant["tool_calls"],
          do: %{"role" => "tool", "tool_call_id" => call["id"], "content" => "result"}

    assert {:ok, _, _} =
             Ipse.Provider.complete(
               config(profile(%{"base_url" => base})),
               [assistant | results],
               [],
               fn _ -> :ok end
             )

    {_, body} = Task.await(server)
    assert body["messages"] == [native | results]
    counts = Ipse.Usage.normalize(:openrouter, raw)
    assert counts["counts"]["input_tokens"] == 7
    assert counts["counts"]["output_reasoning_tokens"] == 3
    refute Jason.encode!(counts) =~ "123.45"
    refute Jason.encode!(counts) =~ "cost_details"
  end

  test "failed finishes, absent DONE, excess calls and malformed fragments never yield tools" do
    for reason <- ["length", "content_filter", "error", "unknown"] do
      assert {:error, _} =
               ChatCompletions.consume(
                 ChatCompletions.new(config(profile())),
                 Fixture.sse(terminal(reason)),
                 fn _ -> :ok end
               )
    end

    {:ok, unfinished} =
      ChatCompletions.consume(
        ChatCompletions.new(config(profile())),
        Fixture.sse(terminal()),
        fn _ -> :ok end
      )

    assert {:error, _} = ChatCompletions.finish(unfinished)

    for calls <- [
          Enum.map(0..32, &%{"index" => &1, "function" => %{}}),
          [%{"index" => 256}],
          [%{"index" => 0, "function" => "invalid"}]
        ] do
      assert {:error, _} =
               ChatCompletions.consume(
                 ChatCompletions.new(config(profile())),
                 Fixture.sse(chunk(%{"tool_calls" => calls})),
                 fn _ -> :ok end
               )
    end
  end

  test "choice error messages redact the key and retain a prior usage frame" do
    bytes =
      Fixture.sse(
        chunk(%{}, %{
          "usage" => usage(),
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{},
              "finish_reason" => "error",
              "error" => %{"message" => "failed fixture-router-key"}
            }
          ]
        })
      )

    owner = self()

    assert {:error, error} =
             ChatCompletions.consume(
               ChatCompletions.new(config(profile())),
               bytes,
               &send(owner, &1)
             )

    assert error =~ "details withheld"
    refute error =~ "fixture-router-key"
    assert_receive {:provider_usage, _}
  end

  test "upstream stream errors only retain safe diagnostic identifiers" do
    bytes =
      Fixture.sse(
        chunk(%{}, %{
          "error" => %{"message" => "upstream_unavailable", "code" => "capacity_exceeded"}
        })
      )

    assert {:error, diagnostic} =
             ChatCompletions.consume(ChatCompletions.new(config(profile())), bytes, fn _ ->
               :ok
             end)

    assert diagnostic =~ "upstream_unavailable"
    assert diagnostic =~ "code: capacity_exceeded"

    bytes =
      Fixture.sse(
        chunk(%{}, %{
          "error" => %{
            "message" => "Provider capacity is exhausted.",
            "code" => "capacity_exceeded"
          }
        })
      )

    assert {:error, diagnostic} =
             ChatCompletions.consume(ChatCompletions.new(config(profile())), bytes, fn _ ->
               :ok
             end)

    assert diagnostic =~ "details withheld"
    assert diagnostic =~ "code: capacity_exceeded"
    refute diagnostic =~ "Provider capacity is exhausted."

    for message <- [
          "private text\e[2J",
          "sk-private",
          "Bearer-token",
          String.duplicate("a", 129),
          <<255>>
        ] do
      # Invalid UTF-8 is tested at the filter boundary; JSON frames require UTF-8.
      assert Ipse.Provider.Transport.safe(message, :message) == nil
    end

    for message <- ["private text\e[2J", "sk-private", "Bearer-token", String.duplicate("a", 129)] do
      bytes = Fixture.sse(chunk(%{}, %{"error" => %{"message" => message}}))

      assert {:error, error} =
               ChatCompletions.consume(ChatCompletions.new(config(profile())), bytes, fn _ ->
                 :ok
               end)

      assert error =~ "details withheld"
      refute error =~ message
    end
  end

  test "router HTTP refusals give bounded cause-specific hints without server bodies" do
    for {status, hint} <- [
          {401, "OPENROUTER_API_KEY"},
          {402, "insufficient credits"},
          {404, "pinned model"},
          {429, "rate limited"},
          {503, "nothing was retried"}
        ] do
      assert {:error, message} =
               Ipse.Provider.Transport.http_error(status, "fixture-private-body", [], :openrouter)

      assert message =~ hint
      refute message =~ "fixture-private-body"
    end

    assert {:error, "Provider returned HTTP 402."} =
             Ipse.Provider.Transport.http_error(402, "body", [], :openai)
  end

  test "a terminal marker cannot admit partial tool JSON, and nullable reasoning does not invent continuation" do
    for arguments <- ["{", "[]", "{\"path\":1,\"path\":2}"] do
      delta = %{
        "tool_calls" => [
          %{
            "index" => 0,
            "id" => "call-1",
            "function" => %{"name" => "read", "arguments" => arguments}
          }
        ]
      }

      bytes = Fixture.sse([chunk(delta), terminal("tool_calls"), "[DONE]"])

      assert {:ok, state} =
               ChatCompletions.consume(ChatCompletions.new(config(profile())), bytes, fn _ ->
                 :ok
               end)

      assert {:error, _} = ChatCompletions.finish(state)
    end

    bytes =
      Fixture.sse([
        chunk(%{"reasoning" => nil, "reasoning_details" => nil}),
        terminal(),
        "[DONE]"
      ])

    assert {:ok, state} =
             ChatCompletions.consume(ChatCompletions.new(config(profile())), bytes, fn _ ->
               :ok
             end)

    assert {:ok, message, _} = ChatCompletions.finish(state)
    native = message["provider_data"]["message"]
    refute Map.has_key?(native, "reasoning")
    refute Map.has_key?(native, "reasoning_details")
  end
end
