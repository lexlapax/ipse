defmodule ChatCompletionsDraftProjectionTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.{Draft, DraftNative}
  alias Ipse.Provider.{ChatCompletions, Stream}
  alias Ipse.JSON

  defp adapter_message(provider, calls \\ []) do
    {:ok, content} = Stream.append_buffer(Stream.new_buffer(), "draft proposal")
    {:ok, reasoning} = Stream.append_buffer(Stream.new_buffer(), "private reasoning")
    state = ChatCompletions.new(%{provider: provider})

    state = %{
      state
      | done: true,
        verified: true,
        finish_reason: if(calls == [], do: "stop", else: "tool_calls"),
        content: content,
        reasoning: reasoning,
        reasoning_seen: true,
        details: [%{"type" => "opaque", "data" => "private details"}],
        detail_count: 1,
        details_seen: true,
        calls:
          Map.new(Enum.with_index(calls), fn {c, n} ->
            {n,
             %{
               "id" => c["id"],
               "name" => c["function"]["name"],
               "arguments" => c["function"]["arguments"]
             }}
          end),
        reported_model: "vendor/model",
        reported_upstream: if(provider == :openrouter, do: "vendor", else: nil)
    }

    {:ok, message, _usage} = ChatCompletions.finish(state)
    message
  end

  defp call(id),
    do: %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => "read", "arguments" => "{}"}
    }

  defp projection(segment, prefix \\ [], kind \\ :cancelled) do
    after_message =
      if kind == :cancelled,
        do: %{"role" => "user", "content" => Draft.notice()},
        else: %{"role" => "user", "content" => "accepted user intent"}

    draft = %{
      status: kind,
      notice: true,
      accepted_message: true,
      prefix_count: length(prefix),
      prefix_sha256: JSON.digest(prefix),
      end_count: length(prefix) + length(segment),
      segment_sha256: JSON.digest(segment),
      tool_success_count: 0,
      tool_evidence: []
    }

    {draft, prefix ++ segment ++ [after_message, %{"role" => "user", "content" => "later task"}]}
  end

  test "actual adapter no-tool messages are withdrawn for both explicit providers" do
    for provider <- [:openrouter, :openai_compatible], kind <- [:cancelled, :consumed] do
      prefix = [
        %{"role" => "user", "content" => "old task"},
        %{"role" => "assistant", "content" => "old reply"}
      ]

      segment = [%{"role" => "user", "content" => "private draft"}, adapter_message(provider)]
      {draft, messages} = projection(segment, prefix, kind)
      assert DraftNative.policy(%{provider: provider}) == provider

      assert Draft.withdrawable?(
               %{draft | prefix_count: length(prefix), tool_success_count: 0},
               prefix ++ segment,
               MapSet.new(),
               provider
             )

      assert {:ok, projected} = Draft.project(draft, messages, MapSet.new(), provider)

      body =
        ChatCompletions.request_body(
          %{provider: provider, model: "vendor/model", upstream: "vendor"},
          projected,
          []
        )

      refute Jason.encode!(body) =~ "private draft"
      refute Jason.encode!(body) =~ "private reasoning"
      refute Jason.encode!(body) =~ "private details"
      assert length(body["messages"]) == 4
    end
  end

  test "adapter tool call, tool result, and reasoning are withheld together" do
    for provider <- [:openrouter, :openai_compatible] do
      call = call("private_call")

      segment = [
        %{"role" => "user", "content" => "private draft"},
        adapter_message(provider, [call]),
        %{"role" => "tool", "tool_call_id" => "private_call", "content" => "private tool result"},
        adapter_message(provider)
      ]

      {draft, messages} = projection(segment)
      assert {:ok, projected} = Draft.project(draft, messages, MapSet.new(), provider)

      body =
        ChatCompletions.request_body(
          %{provider: provider, model: "vendor/model", upstream: "vendor"},
          projected,
          []
        )

      for secret <- [
            "private draft",
            "private reasoning",
            "private details",
            "private_call",
            "private tool result"
          ],
          do: refute(Jason.encode!(body) =~ secret)
    end
  end

  test "retained native history remains intact and cross-interval ids refuse" do
    for provider <- [:openrouter, :openai_compatible] do
      prefix = [%{"role" => "user", "content" => "old"}, adapter_message(provider)]

      segment = [
        %{"role" => "user", "content" => "private"},
        adapter_message(provider, [call("same")]),
        %{"role" => "tool", "tool_call_id" => "same", "content" => "private"}
      ]

      {draft, messages} = projection(segment, prefix)
      assert {:ok, projected} = Draft.project(draft, messages, MapSet.new(), provider)
      assert Enum.at(projected, 1) == Enum.at(prefix, 1)

      outside = [
        adapter_message(provider, [call("same")]),
        %{"role" => "tool", "tool_call_id" => "same", "content" => "outside"}
      ]

      {draft2, messages2} = projection(segment, outside)

      assert {:error, :draft_projection_unsafe} =
               Draft.project(draft2, messages2, MapSet.new(), provider)
    end
  end

  test "foreign or forged native content and wrong provider refuse" do
    message = adapter_message(:openrouter)

    for malformed <- [
          put_in(message, ["provider_data", "message", "content"], "different"),
          put_in(message, ["provider_data", "message", "extra"], "untrusted"),
          put_in(message, ["provider_data", "provider"], "openai_compatible"),
          put_in(message, ["provider_data", "message", "reasoning_details"], ["not a map"])
        ] do
      {draft, messages} = projection([%{"role" => "user", "content" => "private"}, malformed])

      assert {:error, :draft_projection_unsafe} =
               Draft.project(draft, messages, MapSet.new(), :openrouter)
    end
  end

  test "malformed and unpaired tool calls cannot cross draft boundaries" do
    message = adapter_message(:openrouter, [call("x")])

    for segment <- [
          [message],
          [
            Map.put(message, "tool_calls", [call("other")]),
            %{"role" => "tool", "tool_call_id" => "other", "content" => "x"}
          ],
          [
            %{"role" => "assistant", "content" => "", "tool_calls" => [call("x")]},
            %{"role" => "tool", "tool_call_id" => "x", "content" => "x"}
          ]
        ] do
      {draft, messages} = projection(segment)

      assert {:error, :draft_projection_unsafe} =
               Draft.project(draft, messages, MapSet.new(), :openrouter)
    end
  end

  test "multiple completed draft intervals remain withdrawn" do
    for provider <- [:openrouter, :openai_compatible] do
      first_segment = [
        %{"role" => "user", "content" => "first private"},
        adapter_message(provider)
      ]

      second_segment = [
        %{"role" => "user", "content" => "second private"},
        adapter_message(provider)
      ]

      prefix = [%{"role" => "user", "content" => "prior task"}]
      notice = %{"role" => "user", "content" => Draft.notice()}
      second_prefix = prefix ++ first_segment ++ [notice]
      {first, _} = projection(first_segment, prefix)
      {second, messages} = projection(second_segment, second_prefix)

      assert {:ok, projected} =
               Draft.project(Map.put(second, :history, [first]), messages, MapSet.new(), provider)

      for secret <- ["first private", "second private", "private reasoning", "private details"],
          do: refute(Jason.encode!(projected) =~ secret)

      assert Enum.count(projected, &(&1 == notice)) == 2
    end
  end

  test "actual xAI Responses messages withdraw without mixing provider formats or billing modes" do
    for provider <- [:xai, :xai_oauth] do
      output = [
        %{
          "type" => "reasoning",
          "id" => "reason-1",
          "summary" => [],
          "encrypted_content" => "private encrypted"
        },
        %{
          "type" => "message",
          "id" => "message-1",
          "role" => "assistant",
          "content" => [%{"type" => "output_text", "text" => "draft proposal"}]
        }
      ]

      state = %{
        Ipse.Provider.OpenAI.new(provider)
        | terminal: true,
          response: %{
            "model" => "grok-fixture",
            "output" => output,
            "usage" => %{"cost_in_usd_ticks" => 42}
          }
      }

      assert {:ok, message, _} = Ipse.Provider.OpenAI.finish(state)
      assert get_in(message, ["provider_data", "provider"]) == "xai"
      assert get_in(message, ["provider_data", "reported_cost_usd_ticks"]) == 42
      assert DraftNative.policy(%{provider: provider}) == :xai
      segment = [%{"role" => "user", "content" => "private draft"}, message]
      {draft, messages} = projection(segment)
      assert {:ok, projected} = Draft.project(draft, messages, MapSet.new(), :xai)

      body =
        Ipse.Provider.OpenAI.request_body(
          %{provider: provider, model: "grok-fixture"},
          projected,
          []
        )

      refute Jason.encode!(body) =~ "private draft"
      refute Jason.encode!(body) =~ "private encrypted"

      {wrong_draft, wrong_messages} =
        projection([
          %{"role" => "user", "content" => "private"},
          put_in(message, ["provider_data", "provider"], "openai")
        ])

      assert {:error, :draft_projection_unsafe} =
               Draft.project(wrong_draft, wrong_messages, MapSet.new(), :xai)

      {wrong_cost_draft, wrong_cost_messages} =
        projection([
          %{"role" => "user", "content" => "private"},
          put_in(message, ["provider_data", "reported_cost_usd_ticks"], -1)
        ])

      assert {:error, :draft_projection_unsafe} =
               Draft.project(wrong_cost_draft, wrong_cost_messages, MapSet.new(), :xai)
    end
  end

  test "mixed-provider retained history follows the actual adapter boundaries" do
    foreign = adapter_message(:openrouter)

    segment = [
      %{"role" => "user", "content" => "private draft"},
      adapter_message(:openai_compatible)
    ]

    {draft, messages} = projection(segment, [%{"role" => "user", "content" => "past"}, foreign])
    assert {:ok, projected} = Draft.project(draft, messages, MapSet.new(), :openai_compatible)

    body =
      ChatCompletions.request_body(%{provider: :openai_compatible, model: "local"}, projected, [])

    assert Enum.at(body["messages"], 1) == %{"role" => "assistant", "content" => "draft proposal"}
    refute Jason.encode!(body) =~ "private reasoning"

    openai_foreign = %{
      "role" => "assistant",
      "content" => "past",
      "provider_data" => %{
        "provider" => "openai",
        "output" => [
          %{
            "type" => "message",
            "id" => "old",
            "role" => "assistant",
            "content" => [%{"type" => "output_text", "text" => "past"}]
          }
        ]
      }
    }

    xai_output = [
      %{
        "type" => "message",
        "id" => "new",
        "role" => "assistant",
        "content" => [%{"type" => "output_text", "text" => "draft proposal"}]
      }
    ]

    xai_state = %{
      Ipse.Provider.OpenAI.new(:xai)
      | terminal: true,
        response: %{"output" => xai_output}
    }

    {:ok, xai_message, _} = Ipse.Provider.OpenAI.finish(xai_state)

    {xai_draft, xai_messages} =
      projection([%{"role" => "user", "content" => "private"}, xai_message], [openai_foreign])

    assert {:error, :draft_projection_unsafe} =
             Draft.project(xai_draft, xai_messages, MapSet.new(), :xai)
  end
end
