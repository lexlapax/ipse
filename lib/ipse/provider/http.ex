defmodule Ipse.Provider.HTTP do
  @moduledoc false

  def stream(url, headers, payload, config, state, consume) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    uri = URI.parse(url)

    if uri.scheme not in ["http", "https"] or is_nil(uri.host) or uri.userinfo do
      {:error, "Invalid provider URL."}
    else
      Ipse.HTTPProfile.with_profile(fn profile ->
        proxy_options = configure_proxy(profile, uri)
        timeout = config[:timeout_ms] || 120_000

        ssl = [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(uri.host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]

        request =
          {String.to_charlist(url),
           Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end),
           String.to_charlist("application/json"), Jason.encode!(payload)}

        options =
          [
            timeout: timeout,
            connect_timeout: min(timeout, 30_000),
            ssl: ssl,
            autoredirect: false
          ] ++ proxy_options

        case :httpc.request(
               :post,
               request,
               options,
               [sync: false, stream: :self, body_format: :binary],
               profile
             ) do
          {:ok, id} ->
            receive_stream(
              id,
              profile,
              state,
              consume,
              System.monotonic_time(:millisecond) + timeout
            )

          {:error, _} ->
            {:error, "Could not connect to provider."}
        end
      end)
    end
  end

  defp receive_stream(id, profile, state, consume, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:http, {^id, :stream_start, _headers}} ->
        receive_stream(id, profile, state, consume, deadline)

      {:http, {^id, :stream, bytes}} ->
        case consume.(state, IO.iodata_to_binary(bytes)) do
          {:ok, next} ->
            receive_stream(id, profile, next, consume, deadline)

          {:error, _} = error ->
            :httpc.cancel_request(id, profile)
            error
        end

      {:http, {^id, :stream_end, _headers}} ->
        {:ok, state}

      {:http, {^id, {{_, status, _}, _headers, body}}} when status in 200..299 ->
        consume.(state, IO.iodata_to_binary(body))

      {:http, {^id, {{_, status, _}, _headers, _body}}} ->
        {:error, "Provider returned HTTP #{status}."}

      {:http, {^id, {:error, _reason}}} ->
        {:error, "Provider connection failed or timed out."}
    after
      remaining ->
        :httpc.cancel_request(id, profile)
        {:error, "Provider request timed out."}
    end
  end

  defp configure_proxy(profile, uri) do
    if bypass_proxy?(uri.host) do
      []
    else
      name = if uri.scheme == "https", do: "HTTPS_PROXY", else: "HTTP_PROXY"
      proxy = System.get_env(name) || System.get_env(String.downcase(name))

      if proxy && proxy != "" do
        parsed = URI.parse(proxy)

        if parsed.host && parsed.scheme == "http" do
          option = if uri.scheme == "https", do: :https_proxy, else: :proxy

          :httpc.set_options(
            [{option, {{String.to_charlist(parsed.host), parsed.port || 80}, []}}],
            profile
          )

          if parsed.userinfo do
            [user | password] = String.split(parsed.userinfo, ":", parts: 2)

            [
              proxy_auth:
                {URI.decode(user) |> String.to_charlist(),
                 URI.decode(List.first(password) || "") |> String.to_charlist()}
            ]
          else
            []
          end
        else
          raise ArgumentError, "Unsupported proxy URL"
        end
      else
        []
      end
    end
  end

  def bypass_proxy?(host) do
    host = String.downcase(host)

    patterns =
      (System.get_env("NO_PROXY") || System.get_env("no_proxy") || "")
      |> String.split(",", trim: true)

    host in ["localhost", "::1", "[::1]"] or String.starts_with?(host, "127.") or
      Enum.any?(patterns, fn pattern ->
        pattern = pattern |> String.trim() |> String.downcase() |> String.replace(~r/:\d+$/, "")
        domain = String.trim_leading(pattern, ".")
        pattern == "*" or host == domain or String.ends_with?(host, "." <> domain)
      end)
  end
end
