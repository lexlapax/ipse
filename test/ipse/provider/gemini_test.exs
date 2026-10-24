Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.GeminiTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.{Gemini, Registry}
  alias Ipse.Test.ProviderFixture, as: Fixture

  defp config(extra \\ %{}),
    do:
      Map.merge(
        %{
          provider: :gemini,
          model: "gemini-fixture",
          api_key: "fixture-gemini-key",
          timeout_ms: 3000
        },
        extra
      )

  defp chunk(parts, reason \\ nil),
    do: %{
      "modelVersion" => "gemini-fixture-001",
      "candidates" => [
        %{
          "index" => 0,
          "content" => %{"role" => "model", "parts" => parts},
          "finishReason" => reason
        }
      ]
    }

  defp answer, do: Fixture.sse(chunk([%{"text" => "done"}], "STOP"))

  defp consume(data) do
    ref = make_ref()
    parent = self()
    result = Gemini.consume(Gemini.new(), Fixture.sse(data), &send(parent, {ref, &1}))

    events =
      Stream.repeatedly(fn ->
        receive do
          {^ref, event} -> event
        after
          0 -> :end
        end
      end)
      |> Enum.take_while(&(&1 != :end))

    {result, events}
  end

  test "explicit validated model enters only the fixed stream path; destination hashes the query" do
    target =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-fixture:streamGenerateContent?alt=sse"

    assert Gemini.endpoint(config()) == target
    assert Gemini.endpoint(config(%{model: "models/gemini-fixture"})) == target

    assert {:ok,
            %{"origin" => "https://generativelanguage.googleapis.com", "target_sha256" => digest}} =
             Ipse.Provider.destination(config())

    assert digest == Ipse.JSON.sha256(target)
    refute digest == Ipse.JSON.sha256(String.replace_suffix(target, "?alt=sse", ""))

    for model <- [
          nil,
          "",
          "../",
          "gemini?key=x",
          "gemini#x",
          "gemini/x",
          "Gemini",
          "models/models/x",
          "a" <> String.duplicate("b", 128)
        ] do
      assert {:error, _} = Gemini.validate_request(config(%{model: model}))
      assert {:error, _} = Ipse.Provider.destination(config(%{model: model}))
    end

    for url <- [
          "https://generativelanguage.googleapis.com/v1beta?key=private",
          "http://example.com",
          "https://user:pass@example.com"
        ] do
      assert {:error, _} = Gemini.validate_request(config(%{base_url: url}))
    end

    for host <- [
          "aiplatform.googleapis.com",
          "us-central1-aiplatform.googleapis.com",
          "US-CENTRAL1-AIPLATFORM.GOOGLEAPIS.COM."
        ] do
      assert {:error, message} =
               Ipse.Config.Profiles.validate_profile(%{
                 "provider" => "gemini",
                 "model" => "gemini-fixture",
                 "base_url" => "https://#{host}/v1"
               })

      assert message =~ "Vertex AI is not supported yet"

      assert {:error, :invalid_provider_destination} =
               Ipse.Provider.destination(config(%{base_url: "https://#{host}/v1"}))
    end
  end

  test "actual wire body uses header-only credentials, native schemas and bounded generation controls" do
    {base, server} = Fixture.start(answer())
    selected = config(%{base_url: base, reasoning_effort: "high", max_output_tokens: 64})

    tools = [
      %{
        "type" => "function",
        "function" => %{
          "name" => "read",
          "description" => "Read",
          "parameters" => %{"type" => "object"}
        }
      }
    ]

    messages = [
      %{"role" => "system", "content" => "first"},
      %{"role" => "developer", "content" => "second"},
      %{"role" => "user", "content" => "task"}
    ]

    assert {:ok, %{"content" => "done"}, _} =
             Ipse.Provider.complete(selected, messages, tools, fn _ -> :ok end)

    {headers, body} = Task.await(server)
    [line | _] = String.split(headers, "\r\n")
    assert line == "POST /models/gemini-fixture:streamGenerateContent?alt=sse HTTP/1.1"
    refute line =~ selected.api_key
    assert headers =~ "x-goog-api-key: fixture-gemini-key"
    refute String.downcase(headers) =~ "authorization:"

    assert body == %{
             "systemInstruction" => %{"parts" => [%{"text" => "first\n\nsecond"}]},
             "contents" => [%{"role" => "user", "parts" => [%{"text" => "task"}]}],
             "generationConfig" => %{
               "maxOutputTokens" => 64,
               "thinkingConfig" => %{"thinkingLevel" => "HIGH", "includeThoughts" => false}
             },
             "tools" => [
               %{
                 "functionDeclarations" => [
                   %{
                     "name" => "read",
                     "description" => "Read",
                     "parametersJsonSchema" => %{"type" => "object"}
                   }
                 ]
               }
             ],
             "toolConfig" => %{"functionCallingConfig" => %{"mode" => "AUTO"}}
           }

    minimal = Gemini.request_body(config(), messages, [])
    for key <- ~w(tools toolConfig generationConfig), do: refute(Map.has_key?(minimal, key))
    assert Gemini.request_body(config(%{reasoning_effort: "none"}), messages, []) == minimal

    assert {:error, _} =
             Ipse.Provider.complete(Map.delete(selected, :api_key), messages, [], fn _ ->
               flunk("no request")
             end)

    for effort <- ~w(low medium high none),
        do: assert(:ok == Gemini.validate_request(config(%{reasoning_effort: effort})))

    for effort <- ~w(xhigh max),
        do: assert({:error, _} = Gemini.validate_request(config(%{reasoning_effort: effort})))
  end

  test "signed parallel calls and empty final signed text replay without merging or invented ids" do
    parts = [
      %{"text" => "PRIVATE_THOUGHT", "thought" => true, "thoughtSignature" => "opaque-thought"},
      %{
        "functionCall" => %{"name" => "read", "args" => %{"path" => "a"}},
        "thoughtSignature" => "opaque-call"
      },
      %{"functionCall" => %{"id" => "native-b", "name" => "read", "args" => %{"path" => "b"}}},
      %{"text" => "", "thoughtSignature" => "empty-final"}
    ]

    {{:ok, state}, events} =
      consume([chunk(Enum.take(parts, 2)), chunk(Enum.drop(parts, 2), "STOP")])

    assert events == []
    assert {:ok, assistant, _} = Gemini.finish(state)
    assert assistant["content"] == ""
    assert assistant["provider_data"]["content"] == %{"role" => "model", "parts" => parts}
    assert assistant["provider_data"]["reported_model"] == "gemini-fixture-001"
    [first, second] = assistant["tool_calls"]
    assert first["id"] =~ "gemini_"
    assert second["id"] == "native-b"

    results =
      for call <- [first, second],
          do: %{"role" => "tool", "tool_call_id" => call["id"], "content" => call["id"]}

    {base, server} = Fixture.start(answer())

    assert {:ok, _, _} =
             Ipse.Provider.complete(config(%{base_url: base}), [assistant | results], [], fn _ ->
               :ok
             end)

    {_, body} = Task.await(server)
    [replayed, responses] = body["contents"]
    assert Jason.encode!(replayed) == Jason.encode!(assistant["provider_data"]["content"])

    assert responses == %{
             "role" => "user",
             "parts" => [
               %{
                 "functionResponse" => %{
                   "name" => "read",
                   "response" => %{"content" => first["id"]}
                 }
               },
               %{
                 "functionResponse" => %{
                   "id" => "native-b",
                   "name" => "read",
                   "response" => %{"content" => "native-b"}
                 }
               }
             ]
           }

    refute Map.has_key?(hd(responses["parts"])["functionResponse"], "id")
    refute_receive {_, {:text, "PRIVATE_THOUGHT"}}
  end

  test "all text parts retain positions while only public text emits" do
    parts = [
      %{"text" => "one", "thoughtSignature" => "s1"},
      %{"text" => "PRIVATE_THOUGHT", "thought" => true},
      %{"text" => "two"},
      %{"text" => "", "thoughtSignature" => "s2"},
      %{"futureNative" => %{"opaque" => "keep"}}
    ]

    {{:ok, state}, events} = consume(chunk(parts, "STOP"))
    assert {:ok, message, _} = Gemini.finish(state)
    assert message["content"] == "onetwo"
    assert events == [{:text, "one"}, {:text, "two"}]
    assert message["provider_data"]["content"]["parts"] == parts
  end

  test "unsigned cross-provider history is rebuilt without a signature placeholder" do
    call = %{
      "id" => "imported-call",
      "type" => "function",
      "function" => %{"name" => "read", "arguments" => "{}"}
    }

    assistant = %{
      "role" => "assistant",
      "content" => "imported",
      "tool_calls" => [call],
      "provider_data" => %{"provider" => "other", "content" => "PRIVATE_OTHER"}
    }

    body =
      Gemini.request_body(
        config(),
        [
          assistant,
          %{"role" => "tool", "tool_call_id" => "imported-call", "content" => "result"}
        ],
        []
      )

    assert hd(body["contents"]) == %{
             "role" => "model",
             "parts" => [
               %{"text" => "imported"},
               %{"functionCall" => %{"id" => "imported-call", "name" => "read", "args" => %{}}}
             ]
           }

    refute Jason.encode!(body) =~ "thoughtSignature"
    refute Jason.encode!(body) =~ "PRIVATE_OTHER"
    {base, server} = Fixture.start("private rejection", 400)

    assert {:error, error} =
             Ipse.Provider.complete(config(%{base_url: base}), [assistant], [], fn _ -> :ok end)

    Task.await(server)
    assert error =~ "signed history; start a fresh session or hand off"
    refute error =~ "private rejection"
  end

  test "every terminal refusal retains prior cumulative usage and cannot return executable calls" do
    raw = %{
      "promptTokenCount" => 3,
      "toolUsePromptTokenCount" => 0,
      "candidatesTokenCount" => 1,
      "thoughtsTokenCount" => 0,
      "totalTokenCount" => 4
    }

    for reason <-
          ~w(MAX_TOKENS SAFETY RECITATION BLOCKLIST PROHIBITED_CONTENT SPII MALFORMED_FUNCTION_CALL OTHER CONTINUATION) do
      {result, events} = consume(chunk([], reason) |> Map.put("usageMetadata", raw))
      assert {:error, error} = result
      assert error =~ if(reason == "MAX_TOKENS", do: "generation limit", else: reason)
      assert events == [{:provider_usage, raw}]
    end

    assert {{:error, error}, []} = consume(%{"promptFeedback" => %{"blockReason" => "SAFETY"}})
    assert error =~ "SAFETY"
    {{:ok, state}, _} = consume(chunk([%{"text" => "partial"}]))
    assert {:error, _} = Gemini.finish(state)
    assert {{:error, _}, _} = consume([chunk([], "STOP"), chunk([%{"text" => "after-stop"}])])
    {{:ok, state}, events} = consume([chunk([], "STOP"), %{"usageMetadata" => raw}])
    assert {:ok, _, ^raw} = Gemini.finish(state)
    assert events == [{:provider_usage, raw}]

    assert {:error, _} =
             Gemini.consume(
               Gemini.new(),
               "data: {\"candidates\":[],\"candidates\":[]}\n\n",
               fn _ -> :ok end
             )
  end

  test "parts, calls, fields and parser lifetime are bounded" do
    assert {{:error, _}, _} = consume(chunk(List.duplicate(%{"text" => ""}, 4097)))

    calls =
      for i <- 1..33,
          do: %{"functionCall" => %{"id" => "call-#{i}", "name" => "read", "args" => %{}}}

    assert {{:error, _}, _} = consume(chunk(calls, "STOP"))

    for call <- [
          %{"name" => "", "args" => %{}},
          %{"name" => "read", "args" => []},
          %{"name" => "read"}
        ] do
      assert {{:error, _}, _} = consume(chunk([%{"functionCall" => call}], "STOP"))
    end

    {{:ok, state}, _} = consume(chunk([hd(calls), hd(calls)], "STOP"))
    assert {:error, _} = Gemini.finish(state)
    expired = Map.put(Gemini.new(), :stream_deadline, System.monotonic_time(:millisecond) - 1)
    assert {:error, _} = Gemini.consume(expired, answer(), fn _ -> flunk("expired") end)
  end

  test "usage includes separate tool prompt and thoughts; missing fields stay partial and overflow invalid" do
    raw = %{
      "promptTokenCount" => 7,
      "toolUsePromptTokenCount" => 2,
      "candidatesTokenCount" => 3,
      "thoughtsTokenCount" => 5,
      "totalTokenCount" => 17,
      "cachedContentTokenCount" => 4
    }

    normalized = Ipse.Usage.normalize(:gemini, raw)
    assert normalized["quality"] == "totals_known"

    assert Map.take(
             normalized["counts"],
             ~w(input_tokens output_tokens total_tokens input_cached_tokens output_reasoning_tokens)
           ) ==
             %{
               "input_tokens" => 9,
               "output_tokens" => 8,
               "total_tokens" => 17,
               "input_cached_tokens" => 4,
               "output_reasoning_tokens" => 5
             }

    for missing <-
          ~w(promptTokenCount toolUsePromptTokenCount candidatesTokenCount thoughtsTokenCount) do
      partial = Ipse.Usage.normalize(:gemini, Map.delete(raw, missing))
      assert partial["quality"] == "partial"
      assert Ipse.Usage.valid_usage?(partial)
    end

    for invalid <- [-1, "7", Ipse.Usage.counter_limit() + 1] do
      assert Ipse.Usage.normalize(:gemini, Map.put(raw, "promptTokenCount", invalid))["quality"] ==
               "invalid"
    end

    assert Ipse.Usage.normalize(
             :gemini,
             Map.put(raw, "promptTokenCount", Ipse.Usage.counter_limit())
           )["quality"] == "invalid"

    assert Registry.fetch!(:gemini).credential == {:env, "GEMINI_API_KEY"}
    assert Enum.all?(~w(GEMINI_API_KEY GOOGLE_API_KEY), &(&1 in Registry.secret_env()))
    refute Registry.embedding?(:gemini)
    assert Ipse.Usage.billing_mode(:gemini) == "api"
  end
end
