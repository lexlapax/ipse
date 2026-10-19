defmodule Ipse.Provider.Request do
  @moduledoc "Shared credential resolution for owned provider tasks; callers own admission and history."
  def embed(%{operation: :embedding, provider: provider} = config, inputs, emit)
      when provider in [:openai, :ollama] do
    key = if provider == :openai, do: System.get_env("OPENAI_API_KEY")
    Ipse.Provider.Embedding.embed(Map.put(config, :api_key, key), inputs, emit)
  end

  def embed(_, _, _), do: {:error, "Unsupported embedding request."}

  def complete(config, messages, tools, emit) do
    provider =
      Map.get(
        config,
        :provider_module,
        if(config.provider == :demo, do: Ipse.Provider.Demo, else: Ipse.Provider)
      )

    credentials =
      if config.provider == :chatgpt do
        case Ipse.Auth.token(config.auth_dir) do
          {:ok, token} -> {:ok, Map.put(config, :api_key, token)}
          error -> error
        end
      else
        key =
          case config.provider do
            :openai -> System.get_env("OPENAI_API_KEY")
            :anthropic -> System.get_env("ANTHROPIC_API_KEY")
            _ -> nil
          end

        {:ok, Map.put_new(config, :api_key, key)}
      end

    with {:ok, config} <- credentials, do: provider.complete(config, messages, tools, emit)
  end
end
