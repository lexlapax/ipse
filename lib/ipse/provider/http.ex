defmodule Ipse.Provider.HTTP do
  @moduledoc false
  @response_bytes 8_388_608
  @error_bytes 32_769

  def stream(url, headers, payload, config, state, consume) do
    limit =
      if is_nil(config[:max_response_bytes]),
        do: @response_bytes,
        else: config[:max_response_bytes]

    uri = URI.parse(url)

    cond do
      not (is_integer(limit) and limit in 1..@response_bytes) ->
        {:error, "Invalid provider response byte limit."}

      uri.scheme not in ["http", "https"] or is_nil(uri.host) or uri.userinfo ->
        {:error, "Invalid provider URL."}

      true ->
        timeout = config[:timeout_ms] || 120_000
        proxy = Ipse.HTTPProxy.finch_options(uri)
        options = [transport_opts: [timeout: min(timeout, 30_000)]] ++ proxy

        Ipse.HTTPProfile.with_finch(
          fn finch ->
            acc = %{
              state: state,
              status: nil,
              headers: [],
              bytes: 0,
              body: "",
              error: nil,
              deadline: System.monotonic_time(:millisecond) + timeout
            }

            request =
              Finch.build(
                :post,
                url,
                [{"content-type", "application/json"}, {"accept-encoding", "identity"} | headers],
                Jason.encode!(payload)
              )

            result =
              Finch.stream_while(
                request,
                finch,
                acc,
                fn event, acc -> receive_event(event, acc, limit, consume) end,
                pool_timeout: min(timeout, 2000),
                receive_timeout: timeout,
                request_timeout: timeout
              )

            case result do
              {:ok, %{error: nil, status: status} = final} when status in 200..299 ->
                {:ok, final.state}

              {:ok, %{error: nil} = final} ->
                Ipse.Provider.Error.http(
                  final.status,
                  final.body,
                  final.headers,
                  config[:provider]
                )

              {:ok, %{error: error}} ->
                error

              {:error, _, %{error: error}} when error != nil ->
                error

              {:error, _, _} ->
                {:error, "Provider connection failed or timed out."}
            end
          end,
          options
        )
    end
  end

  defp receive_event(event, acc, limit, consume) do
    if System.monotonic_time(:millisecond) >= acc.deadline,
      do: {:halt, %{acc | error: {:error, "Provider request timed out."}}},
      else: consume_event(event, acc, limit, consume)
  end

  defp consume_event({:status, status}, acc, _, _),
    do: {:cont, %{acc | status: status, headers: []}}

  defp consume_event({:headers, headers}, acc, limit, _) do
    state = put_request_id(acc.state, Ipse.Provider.Error.request_id(headers))
    acc = %{acc | headers: acc.headers ++ headers, state: state}

    oversized =
      Enum.any?(headers, fn {name, value} ->
        String.downcase(name) == "content-length" and
          case Integer.parse(value) do
            {size, ""} -> size > limit
            _ -> false
          end
      end)

    if oversized, do: byte_limit(acc), else: {:cont, acc}
  end

  defp consume_event({:data, bytes}, acc, limit, consume) do
    if acc.bytes + byte_size(bytes) > limit do
      byte_limit(acc)
    else
      acc = %{acc | bytes: acc.bytes + byte_size(bytes)}

      if acc.status in 200..299 do
        case consume.(acc.state, bytes) do
          {:ok, next} -> {:cont, %{acc | state: next}}
          {:error, _} = error -> {:halt, %{acc | error: error}}
        end
      else
        retained = min(byte_size(bytes), max(@error_bytes - byte_size(acc.body), 0))
        {:cont, %{acc | body: acc.body <> binary_part(bytes, 0, retained)}}
      end
    end
  end

  defp consume_event(_, acc, _, _), do: {:cont, acc}

  defp byte_limit(acc),
    do: {:halt, %{acc | error: {:error, "Provider response exceeds the configured byte limit."}}}

  defp put_request_id(state, request_id) when is_map(state) and is_binary(request_id),
    do: Map.put(state, :request_id, request_id)

  defp put_request_id(state, _), do: state

  defdelegate bypass_proxy?(host), to: Ipse.HTTPProxy, as: :bypass?
end
