defmodule Ipse.Provider.LimitsTest do
  use ExUnit.Case, async: true
  alias Ipse.Provider.{Limits, OpenAI, Anthropic}

  test "caps validate provider capability and integer bounds without inventing a subscription limit" do
    for provider <- [:chatgpt, :openai, :anthropic, :ollama, :demo] do
      assert :ok = Limits.validate(%{provider: provider})
    end

    for {provider, minimum} <- [openai: 16, anthropic: 1, ollama: 1] do
      for value <- [minimum, Limits.maximum()] do
        assert :ok = Limits.validate(%{provider: provider, max_output_tokens: value})
      end

      for value <- [0, -1, 1.5, "32", false, Limits.maximum() + 1] do
        assert {:error, _} = Limits.validate(%{provider: provider, max_output_tokens: value})
      end
    end

    assert {:error, _} = Limits.validate(%{provider: :openai, max_output_tokens: 15})
    assert {:error, message} = Limits.validate(%{provider: :chatgpt, max_output_tokens: 128})
    assert message =~ "does not support"
    assert {:error, _} = Limits.validate(%{provider: :demo, max_output_tokens: 128})

    assert {:error, ^message} =
             Ipse.Provider.complete(%{provider: :chatgpt, max_output_tokens: 128}, [], [], fn _ ->
               flunk("unsupported request must not dispatch")
             end)
  end

  test "Responses API cap preserves native continuation and never reaches subscription requests" do
    native = [%{"type" => "reasoning", "encrypted_content" => "synthetic-opaque"}]

    messages = [
      %{"role" => "assistant", "provider_data" => %{"provider" => "openai", "output" => native}}
    ]

    config = %{provider: :openai, model: "fixture", max_output_tokens: 256}
    body = OpenAI.request_body(config, messages, [])
    assert body["max_output_tokens"] == 256
    assert body["input"] == native
    assert body["store"] == false

    refute Map.has_key?(
             OpenAI.request_body(Map.delete(config, :max_output_tokens), [], []),
             "max_output_tokens"
           )

    refute Map.has_key?(
             OpenAI.request_body(%{provider: :chatgpt, model: "fixture"}, [], []),
             "max_output_tokens"
           )

    assert_raise ArgumentError, fn ->
      OpenAI.request_body(%{config | provider: :chatgpt}, [], [])
    end
  end

  test "Anthropic cap narrows its existing bound and preserves the uncapped request shape" do
    config = %{provider: :anthropic, model: "fixture"}
    assert Anthropic.request_body(config, [], [])["max_tokens"] == 8192

    assert Anthropic.request_body(Map.put(config, :max_output_tokens, 32), [], [])["max_tokens"] ==
             32

    assert Anthropic.request_body(Map.put(config, :max_output_tokens, 20_000), [], [])[
             "max_tokens"
           ] == 8192

    assert Anthropic.request_body(
             Map.merge(config, %{max_tokens: 24, max_output_tokens: 32}),
             [],
             []
           )["max_tokens"] == 24
  end
end
