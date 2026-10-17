defmodule Ipse.Provider.Limits do
  @moduledoc "Explicit provider output ceilings; these are not aggregate budgets."

  @maximum 1_000_000
  def maximum, do: @maximum

  def validate(config) do
    case {config[:provider], config[:max_output_tokens]} do
      {_, nil} ->
        :ok

      {:chatgpt, _} ->
        {:error,
         "ChatGPT subscription does not support max_output_tokens; no provider or billing fallback was attempted."}

      {:openai, n} when is_integer(n) and n >= 16 and n <= @maximum ->
        :ok

      {provider, n}
      when provider in [:ollama, :anthropic] and is_integer(n) and n >= 1 and n <= @maximum ->
        :ok

      _ ->
        {:error,
         "Invalid max_output_tokens: use 16..1000000 for OpenAI API or 1..1000000 for Ollama/Anthropic; unsupported providers refuse a cap."}
    end
  end

  def output_tokens(config, existing \\ nil) do
    case validate(config) do
      :ok -> narrow(config[:max_output_tokens], existing)
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  def narrow(nil, other), do: other
  def narrow(value, nil), do: value
  def narrow(value, other), do: min(value, other)
end
