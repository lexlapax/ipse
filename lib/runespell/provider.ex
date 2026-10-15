defmodule Runespell.Provider do
  @moduledoc "Streaming model adapters. Messages and tool schemas use OpenAI chat keys."

  def complete(config, messages, tools, emit) when is_function(emit, 1) do
    adapter =
      case config[:provider] do
        provider when provider in [:openai, :chatgpt] -> Runespell.Provider.OpenAI
        :ollama -> Runespell.Provider.Ollama
        :anthropic -> Runespell.Provider.Anthropic
        _ -> nil
      end

    if adapter do
      try do
        apply(adapter, :complete, [config, messages, tools, emit])
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
    String.trim_trailing(config[:base_url] || default, "/") <> suffix
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
