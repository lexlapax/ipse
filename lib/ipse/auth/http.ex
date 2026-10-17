defmodule Ipse.Auth.HTTP do
  @moduledoc false
  @oauth_errors ~w(invalid_grant invalid_refresh_token token_expired refresh_token_expired refresh_token_invalidated refresh_token_reused invalid_client)

  @doc false
  def decode_response(status, body) when status in 200..299 and is_binary(body) do
    if body == "", do: {:ok, %{}}, else: decode(body)
  end

  def decode_response(status, body) when is_integer(status) do
    code =
      if status in 400..499 and status != 429 and is_binary(body) and
           byte_size(body) <= 1_048_576 do
        case Jason.decode(body) do
          {:ok, %{"error" => error}} when is_binary(error) -> error
          {:ok, %{"error" => %{"code" => error}}} when is_binary(error) -> error
          _ -> nil
        end
      end

    if code in @oauth_errors do
      {:error, {:oauth, code}}
    else
      {:error,
       "ChatGPT authorization returned HTTP #{status}. Sign in again if the session expired."}
    end
  end

  if Code.ensure_loaded?(Mix) and Mix.env() == :test do
    def with_transport(transport, fun) do
      key = {__MODULE__, :transport}
      previous = Process.put(key, transport)

      try do
        fun.()
      after
        if previous, do: Process.put(key, previous), else: Process.delete(key)
      end
    end

    def request(method, url, fields \\ []) do
      case Process.get({__MODULE__, :transport}) do
        nil -> real_request(method, url, fields)
        fun -> fun.(method, url, fields)
      end
    end
  else
    def request(method, url, fields \\ []), do: real_request(method, url, fields)
  end

  defp real_request(method, url, fields) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    uri = URI.parse(url)

    if uri.scheme == "https" and uri.host == "auth.openai.com" and is_nil(uri.userinfo) do
      Ipse.HTTPProfile.with_profile(fn profile ->
        proxy_options = configure_proxy(profile)

        options = [
          timeout: 15_000,
          connect_timeout: 10_000,
          autoredirect: false,
          ssl: [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            server_name_indication: ~c"auth.openai.com",
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]
        ]

        request =
          if method == :get do
            {String.to_charlist(url), []}
          else
            {String.to_charlist(url), [], ~c"application/x-www-form-urlencoded",
             URI.encode_query(fields)}
          end

        case :httpc.request(
               method,
               request,
               options ++ proxy_options,
               [body_format: :binary],
               profile
             ) do
          {:ok, {{_, status, _}, _, body}} ->
            decode_response(status, body)

          _ ->
            {:error, "Could not reach ChatGPT authorization. Check your network and retry."}
        end
      end)
    else
      {:error, "ChatGPT authorization endpoint is not trusted."}
    end
  rescue
    _ -> {:error, "ChatGPT authorization request failed."}
  end

  defp decode(body) when byte_size(body) <= 1_048_576 do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, "ChatGPT authorization returned an invalid response."}
    end
  end

  defp decode(_), do: {:error, "ChatGPT authorization response exceeded the size limit."}

  defp configure_proxy(profile),
    do: Ipse.HTTPProxy.httpc_options(profile, URI.parse("https://auth.openai.com"))
end
