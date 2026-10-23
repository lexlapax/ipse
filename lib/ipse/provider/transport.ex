defmodule Ipse.Provider.Transport do
  @moduledoc "Bounded provider responses and allowlisted HTTP and stream errors."
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
        proxy = Ipse.HTTP.finch_options(uri)
        options = [transport_opts: [timeout: min(timeout, 30_000)]] ++ proxy

        Ipse.HTTP.with_finch(
          fn finch ->
            deadline = System.monotonic_time(:millisecond) + timeout
            state = if is_map(state), do: Map.put(state, :stream_deadline, deadline), else: state

            acc = %{
              state: state,
              status: nil,
              headers: [],
              bytes: 0,
              chunks: 0,
              body: "",
              error: nil,
              deadline: deadline
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
                with :ok <-
                       Ipse.Provider.Stream.check_deadline(%{stream_deadline: final.deadline}),
                     do: {:ok, final.state}

              {:ok, %{error: nil} = final} ->
                http_error(
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
    state = put_request_id(acc.state, request_id(headers))
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
    cond do
      acc.chunks >= 131_072 ->
        {:halt, %{acc | error: Ipse.Provider.Stream.error()}}

      acc.bytes + byte_size(bytes) > limit ->
        byte_limit(acc)

      true ->
        acc = %{acc | bytes: acc.bytes + byte_size(bytes), chunks: acc.chunks + 1}

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

  defdelegate bypass_proxy?(host), to: Ipse.HTTP, as: :bypass?

  @body_limit 32_768
  @codes %{
    "subscription_sharing_user_not_eligible" =>
      "ChatGPT plan usage is unavailable for this account, workspace, or policy. Check eligibility; the request was not retried.",
    "subscription_sharing_usage_limit_exceeded" =>
      "ChatGPT plan usage is blocked by a limit or app setting. Pause plan requests and check ChatGPT Settings > Usage; no reset time is inferred.",
    "subscription_sharing_usage_unavailable" =>
      "ChatGPT plan usage availability could not be checked. Preserve sign-in and try again later.",
    "subscription_sharing_unsupported_capability" =>
      "This request uses an unsupported ChatGPT plan capability. Check the parameter and adjust the request before trying again.",
    "subscription_sharing_route_not_supported" =>
      "ChatGPT plan usage does not support this method or endpoint. Verify that the request uses POST /v1/responses.",
    "subscription_sharing_invalid_user" =>
      "The ChatGPT subscriber context was rejected. Check the selected account and scopes; sign in again only after confirmed revocation or terminal refresh failure.",
    "chatpass_v2_scope_not_authorized" =>
      "The ChatGPT permission context does not authorize this operation. Check the client and grant configuration; billing was not changed.",
    "chatpass_v2_invalid_authorization_context" =>
      "The ChatGPT permission context does not authorize this operation. Check the client and grant configuration; billing was not changed.",
    "subscription_sharing_user_unavailable" =>
      "ChatGPT user or workspace information is temporarily unavailable. Preserve sign-in and try again later."
  }

  def http_error(status, body, headers, provider) do
    parsed = parse_body(body)
    error = error_object(parsed.value)
    code = get_field(error, "code") |> safe(:code)
    param = get_field(error, "param") |> safe(:param)
    request_id = response_request_id(headers, parsed.value)
    shape = parsed.shape

    if provider == :chatgpt do
      hint = hint(code, status, shape)

      {:error,
       "ChatGPT plan request failed (#{metadata(status, shape, code, param, request_id)}): #{hint}"}
    else
      {:error, "Provider returned HTTP #{status}."}
    end
  end

  def stream_error(data), do: stream_error(data, :chatgpt, nil)
  def stream_error(data, provider), do: stream_error(data, provider, nil)

  def stream_error(data, :chatgpt, header_request_id) when is_map(data) do
    error =
      cond do
        is_map(data["error"]) ->
          data["error"]

        is_map(data["response"]) and is_map(data["response"]["error"]) ->
          data["response"]["error"]

        true ->
          data
      end

    code = get_field(error, "code") |> safe(:code)
    param = get_field(error, "param") |> safe(:param)
    request_id = (header_request_id || get_field(data, "request_id")) |> safe(:request_id)
    status = data["status_code"] || get_field(data["response"], "status_code")
    shape = "error"
    hint = hint(code, status, shape)

    {:error,
     "ChatGPT plan stream failed (#{metadata(status, shape, code, param, request_id)}): #{hint}"}
  end

  def stream_error(_, _, _),
    do:
      {:error, "OpenAI stream failed or was incomplete. Check model access and request settings."}

  def request_id(headers), do: header_request_id(headers)

  defp hint(code, _status, _shape) when is_binary(code) and is_map_key(@codes, code),
    do: Map.fetch!(@codes, code)

  defp hint(_code, status, "detail") when status == 403,
    do:
      "Direct-route admission was denied. Check account, scopes, policy, or serving region; billing was not changed."

  defp hint(_code, status, _shape) when status == 503,
    do:
      "ChatGPT plan routing or usage availability is temporarily unavailable. Preserve sign-in and try again later."

  defp hint(_code, status, _shape) when status == 403,
    do:
      "A ChatGPT policy or permission check denied the request. Check account, scopes, and serving-region eligibility."

  defp hint(_code, status, _shape) when status == 400,
    do:
      "ChatGPT rejected the request. Check supported inputs, tools, model, and service-tier settings."

  defp hint(_code, status, _shape) when status == 429,
    do: "ChatGPT plan usage is limited. Pause plan requests and check ChatGPT Settings > Usage."

  defp hint(_code, status, _shape) when status == 401,
    do:
      "The ChatGPT subscriber context was not accepted. Check the selected account and granted scopes."

  defp hint(_code, _status, _shape),
    do:
      "Check ChatGPT plan access, account limits, and request settings. No billing path was changed."

  defp parse_body(body) when is_binary(body) and byte_size(body) <= @body_limit do
    case Jason.decode(body) do
      {:ok, %{"error" => _} = value} -> %{shape: "error", value: value}
      {:ok, %{"detail" => _} = value} -> %{shape: "detail", value: value}
      {:ok, value} when is_map(value) -> %{shape: "object", value: value}
      {:ok, _} -> %{shape: "json", value: nil}
      _ -> %{shape: "invalid", value: nil}
    end
  end

  defp parse_body(body) when is_binary(body), do: %{shape: "oversize", value: nil}
  defp parse_body(_), do: %{shape: "invalid", value: nil}

  defp error_object(%{"error" => error}) when is_map(error), do: error
  defp error_object(%{"detail" => detail}) when is_map(detail), do: detail
  defp error_object(_), do: %{}

  defp response_request_id(headers, body) do
    header = header_request_id(headers)
    header || get_field(body, "request_id") |> safe(:request_id)
  end

  defp header_request_id(headers) when is_list(headers) do
    Enum.find_value(headers, fn
      {key, value} ->
        if String.downcase(to_string(key)) in ["x-request-id", "openai-request-id"],
          do: safe(to_string(value), :request_id)

      _ ->
        nil
    end)
  end

  defp header_request_id(_), do: nil

  defp get_field(map, key) when is_map(map), do: Map.get(map, key)
  defp get_field(_, _), do: nil

  defp safe(value, kind) when is_binary(value) do
    max = if kind == :param, do: 96, else: 128

    pattern =
      if kind == :request_id,
        do: ~r/\A[A-Za-z0-9_-]{1,128}\z/,
        else: ~r/\A[A-Za-z0-9_.\[\]-]{1,128}\z/

    if String.valid?(value) and byte_size(value) <= max and Regex.match?(pattern, value) do
      lower = String.downcase(value)
      secret_like = Enum.any?(["sk-", "bearer", "eyj"], &String.starts_with?(lower, &1))
      if secret_like, do: nil, else: value
    else
      nil
    end
  end

  defp safe(_, _), do: nil

  defp metadata(status, shape, code, param, request_id) do
    fields = [
      if(is_integer(status) and status in 100..599, do: "HTTP #{status}"),
      if(is_binary(shape), do: "body=#{shape}"),
      if(code, do: "code=#{code}"),
      if(param, do: "param=#{param}"),
      if(request_id, do: "request_id=#{request_id}")
    ]

    fields |> Enum.reject(&is_nil/1) |> Enum.join("; ")
  end
end
