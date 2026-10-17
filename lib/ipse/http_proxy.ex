defmodule Ipse.HTTPProxy do
  @moduledoc "Shared explicit proxy policy for isolated OTP and Finch clients."

  def httpc_options(profile, uri) do
    case selected(uri) do
      nil ->
        []

      proxy ->
        option = if uri.scheme == "https", do: :https_proxy, else: :proxy

        :ok =
          :httpc.set_options(
            [{option, {{String.to_charlist(proxy.host), proxy.port}, []}}],
            profile
          )

        if proxy.userinfo do
          {user, password} = credentials(proxy.userinfo)
          [proxy_auth: {String.to_charlist(user), String.to_charlist(password)}]
        else
          []
        end
    end
  end

  def finch_options(uri) do
    case selected(uri) do
      nil ->
        []

      proxy ->
        headers =
          if proxy.userinfo do
            {user, password} = credentials(proxy.userinfo)
            [{"proxy-authorization", "Basic " <> Base.encode64(user <> ":" <> password)}]
          else
            []
          end

        [proxy: {:http, proxy.host, proxy.port, []}, proxy_headers: headers]
    end
  end

  defp selected(uri) do
    name = if uri.scheme == "https", do: "HTTPS_PROXY", else: "HTTP_PROXY"
    value = System.get_env(name) || System.get_env(String.downcase(name))

    if bypass?(uri.host) or value in [nil, ""] do
      nil
    else
      case URI.new(value) do
        {:ok, proxy} ->
          if proxy.scheme == "http" and proxy.host not in [nil, ""] and
               is_integer(proxy.port) and proxy.port in 1..65535 and
               proxy.path in [nil, "", "/"] and is_nil(proxy.query) and is_nil(proxy.fragment) do
            proxy
          else
            raise ArgumentError, "Unsupported proxy URL"
          end

        _ ->
          raise ArgumentError, "Unsupported proxy URL"
      end
    end
  end

  defp credentials(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, password] -> {URI.decode(user), URI.decode(password)}
      [user] -> {URI.decode(user), ""}
    end
  end

  def bypass?(host) do
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
