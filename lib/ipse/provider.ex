defmodule Ipse.Provider do
  @moduledoc "Streaming model adapters. Messages and tool schemas use OpenAI chat keys."
  @test_endpoints Code.ensure_loaded?(Mix) and Mix.env() == :test

  def complete(config, messages, tools, emit) when is_function(emit, 1) do
    adapter = adapter(config[:provider])

    if adapter do
      try do
        with :ok <-
               Ipse.Profiles.reasoning(
                 to_string(config[:provider]),
                 config[:model],
                 config[:reasoning_effort]
               ),
             :ok <- Ipse.Provider.Limits.validate(config) do
          case apply(adapter, :complete, [config, messages, tools, emit]) do
            {:error, message} when is_binary(message) -> error(message, config)
            result -> result
          end
        end
      rescue
        error in Ipse.TextStream.RequiredFailure -> {:error, Exception.message(error)}
        _ -> {:error, "Provider request failed (invalid response or configuration)."}
      catch
        :exit, _ -> {:error, "Provider connection terminated."}
      end
    else
      {:error, "Unknown provider. Choose chatgpt, openai, ollama, or anthropic."}
    end
  end

  @doc "Non-secret egress origin and full wire-target digest, using the actual adapter route."
  def destination(%{operation: :embedding} = config),
    do: Ipse.Provider.Embedding.destination(config)

  def destination(config) do
    with module when not is_nil(module) <- adapter(config[:provider]),
         target = module.endpoint(config),
         {:ok, uri} <- URI.new(target),
         true <-
           is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
             is_nil(uri.query) and is_nil(uri.fragment),
         origin = URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}),
         facts = %{
           "origin" => origin,
           "target_sha256" => :crypto.hash(:sha256, target) |> Base.encode16(case: :lower)
         },
         true <- valid_destination?(facts) do
      {:ok, facts}
    else
      _ -> {:error, :invalid_provider_destination}
    end
  rescue
    _ -> {:error, :invalid_provider_destination}
  end

  def valid_destination?(%{"origin" => origin, "target_sha256" => digest} = facts) do
    with true <- map_size(facts) == 2 and is_binary(origin) and byte_size(origin) <= 512,
         true <- is_binary(digest) and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest),
         {:ok, uri} <- URI.new(origin) do
      uri.host not in [nil, ""] and is_nil(uri.userinfo) and is_nil(uri.query) and
        is_nil(uri.fragment) and uri.path in [nil, ""] and is_integer(uri.port) and
        uri.port in 1..65535 and
        (uri.scheme == "https" or
           (uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"])) and
        URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}) == origin
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_destination?(_), do: false

  defp adapter(provider) when provider in [:openai, :chatgpt], do: Ipse.Provider.OpenAI
  defp adapter(:ollama), do: Ipse.Provider.Ollama
  defp adapter(:anthropic), do: Ipse.Provider.Anthropic
  defp adapter(_), do: nil

  def endpoint(config, default, suffix) do
    base = config[:base_url] || default

    unless valid_base_url?(config[:provider], base),
      do: raise(ArgumentError, "Provider endpoint requires HTTPS or explicit HTTP loopback.")

    if config[:provider] == :chatgpt and base != "https://api.openai.com/v1" and
         not test_endpoint?(base) do
      raise ArgumentError, "Subscription credentials only go to the official OpenAI endpoint."
    end

    String.trim_trailing(base, "/") <> suffix
  end

  def valid_base_url?(_, nil), do: true

  def valid_base_url?(provider, url) when provider in [:chatgpt, "chatgpt"],
    do: url == "https://api.openai.com/v1" or test_endpoint?(url)

  def valid_base_url?(_, url) when is_binary(url) do
    with {:ok, uri} <- URI.new(url) do
      byte_size(url) <= 512 and uri.host not in [nil, ""] and is_nil(uri.userinfo) and
        is_nil(uri.query) and is_nil(uri.fragment) and is_integer(uri.port) and
        uri.port in 1..65535 and
        (uri.scheme == "https" or
           (uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost", "::1"]))
    else
      _ -> false
    end
  end

  def valid_base_url?(_, _), do: false

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
