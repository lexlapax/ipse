defmodule Ipse.Provider.Error do
  @moduledoc false

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

  def http(status, body, headers, provider) do
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

  def stream(data), do: stream(data, :chatgpt, nil)
  def stream(data, provider), do: stream(data, provider, nil)

  def stream(data, :chatgpt, header_request_id) when is_map(data) do
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

  def stream(_, _, _),
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
