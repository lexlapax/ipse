defmodule Ipse.Provider do
  @moduledoc "Streaming model adapters. Messages and tool schemas use OpenAI chat keys."
  @test_endpoints Code.ensure_loaded?(Mix) and Mix.env() == :test
  alias Ipse.Provider.Registry

  @choices (Registry.chat_ids() |> Enum.drop(-1) |> Enum.join(", ")) <>
             ", or " <> List.last(Registry.chat_ids())

  def complete(config, messages, tools, emit) when is_function(emit, 1) do
    adapter = adapter(config[:provider])

    if adapter do
      try do
        with :ok <- response_contract(config),
             :ok <- Registry.validate_request(config),
             :ok <-
               Ipse.Config.Profiles.reasoning(
                 to_string(config[:provider]),
                 config[:model],
                 config[:reasoning_effort]
               ),
             :ok <- validate_output_limit(config) do
          case apply(adapter, :complete, [config, messages, tools, emit]) do
            {:error, message} when is_binary(message) ->
              error(message, config)

            {:ok, _, _} = result ->
              Ipse.Provider.CompletionWitness.native_complete(config, :text)
              result

            result ->
              result
          end
        end
      rescue
        error in Ipse.Session.TextStream.RequiredFailure -> {:error, Exception.message(error)}
        _ -> {:error, "Provider request failed (invalid response or configuration)."}
      catch
        :exit, _ -> {:error, "Provider connection terminated."}
      end
    else
      {:error, "Unknown provider. Choose #{@choices}."}
    end
  end

  defp response_contract(config) do
    if not Map.has_key?(config, :extension_response_schema) or
         (Registry.supports?(config[:provider], :structured_output?) and
            is_map(config[:extension_response_schema]) and
            not Map.has_key?(config, :summary_schema)) do
      :ok
    else
      {:error, "Structured extension output requires native Ollama without a summary schema."}
    end
  end

  @doc "Non-secret egress origin and full wire-target digest, using the actual adapter route."
  def destination(%{operation: :embedding} = config),
    do: Ipse.Provider.Embedding.destination(config)

  def destination(config) do
    with module when not is_nil(module) <- adapter(config[:provider]),
         target = apply(module, :endpoint, [config]),
         {:ok, uri} <- URI.new(target),
         true <-
           is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
             uri.query == Registry.fetch!(config[:provider]).wire_query and is_nil(uri.fragment),
         origin = URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}),
         facts = %{
           "origin" => origin,
           "target_sha256" => Ipse.JSON.sha256(target)
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

  defp adapter(provider) do
    case Registry.fetch(provider) do
      # Demo requests use their direct entry point; they have no HTTP destination.
      {:ok, %{billing_mode: "none"}} -> nil
      {:ok, spec} -> spec.adapter
      _ -> nil
    end
  end

  def endpoint(config, default, suffix) do
    base = config[:base_url] || default

    unless valid_base_url?(config[:provider], base),
      do: raise(ArgumentError, "Provider endpoint requires HTTPS or explicit HTTP loopback.")

    if Registry.auth?(config[:provider]) and
         base != Registry.fetch!(config[:provider]).default_base_url and
         not test_endpoint?(base) do
      raise ArgumentError,
            if(config[:provider] == :chatgpt,
              do: "Subscription credentials only go to the official OpenAI endpoint.",
              else: "xAI subscription credentials only go to the official xAI endpoint."
            )
    end

    String.trim_trailing(base, "/") <> suffix
  end

  def valid_base_url?(provider, nil) do
    case Registry.fetch(provider) do
      {:ok, %{base_url_policy: :loopback_only}} -> false
      _ -> true
    end
  end

  def valid_base_url?(provider, url) when is_binary(url) do
    case Registry.fetch(provider) do
      {:ok, %{base_url_policy: :fixed, default_base_url: fixed}} ->
        url == fixed or test_endpoint?(url)

      {:ok, %{base_url_policy: :loopback_only}} ->
        valid_endpoint_url?(url) and URI.parse(url).host in ["127.0.0.1", "localhost", "::1"]

      _ ->
        valid_endpoint_url?(url)
    end
  end

  def valid_base_url?(_, _), do: false

  defp valid_endpoint_url?(url) do
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

  def request_embedding(%{operation: :embedding, provider: provider} = config, inputs, emit) do
    if Registry.embedding?(provider) do
      Ipse.Provider.Embedding.embed(
        Map.put(config, :api_key, environment_key(provider)),
        inputs,
        emit
      )
    else
      {:error, "Unsupported embedding request."}
    end
  end

  def request_embedding(_, _, _), do: {:error, "Unsupported embedding request."}

  def request_complete(config, messages, tools, emit) do
    provider =
      Map.get(
        config,
        :provider_module,
        if(Registry.fetch!(config.provider).billing_mode == "none",
          do: Registry.fetch!(config.provider).adapter,
          else: Ipse.Provider
        )
      )

    credentials =
      case Registry.fetch!(config.provider).credential do
        credential when credential in [:chatgpt_auth, :xai_auth] ->
          auth = if credential == :chatgpt_auth, do: Ipse.Auth, else: Ipse.Auth.XAI

          case auth.token(config.auth_dir) do
            {:ok, token} -> {:ok, Map.put(config, :api_key, token)}
            error -> error
          end

        _ ->
          {:ok, Map.put_new(config, :api_key, environment_key(config.provider))}
      end

    with {:ok, config} <- credentials, do: provider.complete(config, messages, tools, emit)
  end

  defp environment_key(provider) do
    case Registry.fetch(provider) do
      {:ok, %{credential: {:env, name}}} -> System.get_env(name)
      _ -> nil
    end
  end

  @maximum 1_000_000
  def max_output_tokens, do: @maximum

  def validate_output_limit(config) do
    provider = config[:provider]
    value = config[:max_output_tokens]

    limit =
      case Registry.fetch(provider) do
        {:ok, spec} -> spec.output_limit
        _ -> :refuse_cap
      end

    cond do
      is_nil(value) ->
        :ok

      provider == :chatgpt ->
        {:error,
         "ChatGPT subscription does not support max_output_tokens; no provider or billing fallback was attempted."}

      is_struct(limit, Range) and is_integer(value) and value in limit ->
        :ok

      is_struct(limit, Range) ->
        {:error,
         "Invalid max_output_tokens for #{Registry.fetch!(provider).id}: use #{limit.first}..#{limit.last}. No request was sent."}

      true ->
        {:error, "The selected provider does not support max_output_tokens; no request was sent."}
    end
  end

  def output_tokens(config, existing \\ nil) do
    case validate_output_limit(config) do
      :ok -> narrow_output_tokens(config[:max_output_tokens], existing)
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  def narrow_output_tokens(nil, other), do: other
  def narrow_output_tokens(value, nil), do: value
  def narrow_output_tokens(value, other), do: min(value, other)

  def model_name(value) when is_binary(value) and byte_size(value) in 1..200 do
    if Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._:\/@+\-]*\z/, value), do: value
  end

  def model_name(_), do: nil
end
