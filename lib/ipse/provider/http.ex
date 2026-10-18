defmodule Ipse.Provider.HTTP do
  @moduledoc false
  @response_bytes 8_388_608

  def stream(url, headers, payload, config, state, consume) do
    limit =
      if is_nil(config[:max_response_bytes]),
        do: @response_bytes,
        else: config[:max_response_bytes]

    case limit do
      limit when is_integer(limit) and limit in 1..@response_bytes ->
        bounded = fn {current, count}, bytes ->
          next_count = count + byte_size(bytes)

          if next_count <= limit do
            with {:ok, next} <- consume.(current, bytes), do: {:ok, {next, next_count}}
          else
            {:error, "Provider response exceeds the configured byte limit."}
          end
        end

        case stream_request(url, headers, payload, config, {state, 0}, bounded) do
          {:ok, {next, _}} -> {:ok, next}
          error -> error
        end

      _ ->
        {:error, "Invalid provider response byte limit."}
    end
  end

  defp stream_request(url, headers, payload, config, state, consume) do
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
              config[:provider],
              System.monotonic_time(:millisecond) + timeout
            )

          {:error, _} ->
            {:error, "Could not connect to provider."}
        end
      end)
    end
  end

  defp receive_stream(id, profile, state, consume, provider, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:http, {^id, :stream_start, headers}} ->
        state = put_request_id(state, Ipse.Provider.Error.request_id(headers))
        receive_stream(id, profile, state, consume, provider, deadline)

      {:http, {^id, :stream, bytes}} ->
        case consume.(state, IO.iodata_to_binary(bytes)) do
          {:ok, next} ->
            receive_stream(id, profile, next, consume, provider, deadline)

          {:error, _} = error ->
            :httpc.cancel_request(id, profile)
            error
        end

      {:http, {^id, :stream_end, _headers}} ->
        {:ok, state}

      {:http, {^id, {{_, status, _}, _headers, body}}} when status in 200..299 ->
        consume.(state, IO.iodata_to_binary(body))

      {:http, {^id, {{_, status, _}, headers, body}}} ->
        Ipse.Provider.Error.http(status, IO.iodata_to_binary(body), headers, provider)

      {:http, {^id, {:error, _reason}}} ->
        {:error, "Provider connection failed or timed out."}
    after
      remaining ->
        :httpc.cancel_request(id, profile)
        {:error, "Provider request timed out."}
    end
  end

  defp put_request_id({state, count}, request_id), do: {put_request_id(state, request_id), count}

  defp put_request_id(state, request_id) when is_map(state) and is_binary(request_id),
    do: Map.put(state, :request_id, request_id)

  defp put_request_id(state, _), do: state

  defp configure_proxy(profile, uri), do: Ipse.HTTPProxy.httpc_options(profile, uri)
  defdelegate bypass_proxy?(host), to: Ipse.HTTPProxy, as: :bypass?
end
