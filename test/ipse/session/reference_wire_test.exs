defmodule Ipse.Session.ReferenceWireTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.Reference
  @session String.duplicate("d", 32)
  @turn String.duplicate("e", 32)
  @providers [
    :chatgpt,
    :openai,
    :ollama,
    :anthropic,
    :gemini,
    :openrouter,
    :xai,
    :xai_oauth,
    :openai_compatible
  ]

  defp wire_key(:gemini), do: "contents"
  defp wire_key(provider) when provider in [:chatgpt, :openai, :xai, :xai_oauth], do: "input"
  defp wire_key(_), do: "messages"

  defp tools do
    for name <- ["read", "saved_result_read"] do
      %{
        "type" => "function",
        "function" => %{
          "name" => name,
          "description" => "Synthetic read fixture",
          "parameters" => %{
            "type" => "object",
            "properties" => %{},
            "additionalProperties" => false
          }
        }
      }
    end
  end

  defp fixture do
    header = [
      %{"role" => "system", "content" => "fixed host rules"},
      %{"role" => "user", "content" => "admitted reference sources"}
    ]

    publishers = %{
      "runtime" => %{},
      "skills" => "",
      "workspace" => "admitted",
      "extensions" => ""
    }

    {:ok, state} =
      Reference.restore([%{"metadata" => %{"reference_layout" => Reference.layout()}}], @session)

    state = Reference.seed(state, header, publishers)

    history = [
      %{"role" => "user", "content" => "actual task"},
      %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          %{
            "id" => "native-a",
            "type" => "function",
            "function" => %{"name" => "read", "arguments" => "{}"}
          },
          %{
            "id" => "native-b",
            "type" => "function",
            "function" => %{"name" => "read", "arguments" => "{}"}
          }
        ]
      },
      %{"role" => "tool", "tool_call_id" => "native-b", "content" => "second result first"},
      %{"role" => "tool", "tool_call_id" => "native-a", "content" => "first result second"}
    ]

    changed = Map.put(publishers, "workspace", "nested source: é \"quoted\"\nnot permission")

    {:ok, _, _, [reference]} =
      Reference.prepare(state, @session, @turn, changed, tools(), history)

    {header ++ history, reference}
  end

  for provider <- @providers do
    test "#{provider} serializes an appended reference after unchanged native history and tools" do
      provider = unquote(provider)
      {history, reference} = fixture()
      adapter = Ipse.Provider.Registry.fetch!(provider).adapter

      config = %{
        provider: provider,
        model: "synthetic",
        upstream: "fixture",
        data_collection: "deny"
      }

      before = apply(adapter, :request_body, [config, history, tools()])
      after_reference = apply(adapter, :request_body, [config, history ++ [reference], tools()])
      key = wire_key(provider)

      assert Map.delete(before, key) == Map.delete(after_reference, key)
      assert Enum.take(after_reference[key], length(before[key])) == before[key]
      prefix = Jason.encode!(before[key]) |> String.trim_trailing("]")
      assert String.starts_with?(Jason.encode!(after_reference[key]), prefix)
      last = List.last(after_reference[key])
      assert last["role"] == "user"
      assert Jason.encode!(last) =~ "Current host reference selection."
      refute Jason.encode!(Map.delete(after_reference, key)) =~ "nested source"
      refute Jason.encode!(after_reference) =~ "ipse_reference"
      assert Reference.safe_tail?(history ++ [reference])
    end
  end

  test "signed Anthropic and Gemini continuation bytes remain identical before the new tail" do
    {history, reference} = fixture()

    anthropic = %{
      "role" => "assistant",
      "content" => "",
      "provider_data" => %{
        "provider" => "anthropic",
        "content" => [
          %{
            "type" => "thinking",
            "thinking" => "synthetic opaque",
            "signature" => "synthetic-signature"
          },
          %{"type" => "text", "text" => "visible"}
        ]
      }
    }

    gemini = %{
      "role" => "assistant",
      "content" => "",
      "provider_data" => %{
        "provider" => "gemini",
        "content" => %{
          "role" => "model",
          "parts" => [%{"text" => "visible", "thoughtSignature" => "synthetic-thought-signature"}]
        }
      }
    }

    for {adapter, config, key, native} <- [
          {Ipse.Provider.Anthropic, %{provider: :anthropic, model: "fixture"}, "messages",
           anthropic},
          {Ipse.Provider.Gemini, %{provider: :gemini, model: "fixture"}, "contents", gemini}
        ] do
      original = adapter.request_body(config, history ++ [native], tools())
      appended = adapter.request_body(config, history ++ [native, reference], tools())
      assert Enum.take(appended[key], length(original[key])) == original[key]
      assert Jason.encode!(List.last(original[key])) =~ "synthetic-"
      refute Jason.encode!(List.last(appended[key])) =~ "synthetic-"
    end
  end
end
