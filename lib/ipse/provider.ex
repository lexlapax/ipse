defmodule Ipse.Provider do
  @moduledoc "Streaming model adapters. Messages and tool schemas use OpenAI chat keys."
  @test_endpoints Code.ensure_loaded?(Mix) and Mix.env() == :test

  def complete(config, messages, tools, emit) when is_function(emit, 1) do
    adapter =
      case config[:provider] do
        provider when provider in [:openai, :chatgpt] -> Ipse.Provider.OpenAI
        :ollama -> Ipse.Provider.Ollama
        :anthropic -> Ipse.Provider.Anthropic
        _ -> nil
      end

    if adapter do
      try do
        with :ok <-
               Ipse.Profiles.reasoning(
                 to_string(config[:provider]),
                 config[:model],
                 config[:reasoning_effort]
               ) do
          case apply(adapter, :complete, [config, messages, tools, emit]) do
            {:error, message} when is_binary(message) -> error(message, config)
            result -> result
          end
        end
      rescue
        _ -> {:error, "Provider request failed (invalid response or configuration)."}
      catch
        :exit, _ -> {:error, "Provider connection terminated."}
      end
    else
      {:error, "Unknown provider. Choose chatgpt, openai, ollama, or anthropic."}
    end
  end

  def endpoint(config, default, suffix) do
    base = config[:base_url] || default

    if config[:provider] == :chatgpt and base != "https://api.openai.com/v1" and
         not test_endpoint?(base) do
      raise ArgumentError, "Subscription credentials only go to the official OpenAI endpoint."
    end

    String.trim_trailing(base, "/") <> suffix
  end

  defp test_endpoint?(base) do
    if @test_endpoints and is_binary(base) do
      uri = URI.parse(base)

      uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"] and
        is_nil(uri.userinfo) and is_nil(uri.fragment)
    else
      false
    end
  end

  def error(message, config) do
    text = to_string(message)

    text =
      if config[:api_key] && config[:api_key] != "",
        do: String.replace(text, config[:api_key], "[redacted]"),
        else: text

    {:error, String.slice(text, 0, 500)}
  end
end
