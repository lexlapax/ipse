defmodule Runespell.Auth.HTTP do
  @moduledoc false

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

    if uri.scheme == "https" and uri.host == "auth.openai.com" and not uri.userinfo do
      with {:ok, profile} <- :inets.start(:httpc, [profile: :runespell_auth], :stand_alone) do
        Process.unlink(profile)
        owner = self()

        guardian =
          spawn(fn ->
            reference = Process.monitor(owner)

            receive do
              :finished -> Process.demonitor(reference, [:flush])
              {:DOWN, ^reference, :process, ^owner, _} -> :inets.stop(:stand_alone, profile)
            end
          end)

        try do
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
            {:ok, {{_, status, _}, _, body}} when status in 200..299 ->
              if body == "", do: {:ok, %{}}, else: decode(body)

            {:ok, {{_, status, _}, _, _}} ->
              {:error,
               "ChatGPT authorization returned HTTP #{status}. Sign in again if the session expired."}

            _ ->
              {:error, "Could not reach ChatGPT authorization. Check your network and retry."}
          end
        after
          :inets.stop(:stand_alone, profile)
          send(guardian, :finished)
        end
      else
        _ -> {:error, "Could not start ChatGPT authorization HTTP client."}
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

  defp configure_proxy(profile) do
    proxy = System.get_env("HTTPS_PROXY") || System.get_env("https_proxy")

    if proxy && proxy != "" && not Runespell.Provider.HTTP.bypass_proxy?("auth.openai.com") do
      uri = URI.parse(proxy)

      if uri.scheme == "http" and is_binary(uri.host) do
        :httpc.set_options(
          [https_proxy: {{String.to_charlist(uri.host), uri.port || 80}, []}],
          profile
        )

        if uri.userinfo do
          [user | password] = String.split(uri.userinfo, ":", parts: 2)

          [
            proxy_auth:
              {String.to_charlist(URI.decode(user)),
               String.to_charlist(URI.decode(List.first(password) || ""))}
          ]
        else
          []
        end
      else
        []
      end
    else
      []
    end
  end
end
