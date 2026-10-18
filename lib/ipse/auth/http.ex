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
    uri = URI.parse(url)

    if uri.scheme == "https" and uri.host == "auth.openai.com" and uri.port == 443 and
         is_nil(uri.userinfo) and is_nil(uri.fragment) and method in [:get, :post] do
      headers = [
        {"accept-encoding", "identity"},
        {"content-type", "application/x-www-form-urlencoded"}
      ]

      body = if method == :get, do: nil, else: URI.encode_query(fields)
      request = Finch.build(method, url, headers, body)

      case Ipse.HTTPProfile.bounded_request(request, 1_048_576) do
        {:ok, status, body} ->
          decode_response(status, body)

        {:error, :response_too_large} ->
          {:error, "ChatGPT authorization response exceeded the size limit."}

        _ ->
          {:error, "Could not reach ChatGPT authorization. Check your network and retry."}
      end
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
end
