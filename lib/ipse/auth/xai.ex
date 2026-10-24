defmodule Ipse.Auth.XAI do
  @moduledoc "Registered xAI public-client device authorization; credentials never fall back to API billing."
  @issuer "https://auth.x.ai"
  @scope "api:access offline_access"
  @limit 65_536
  @device_grant "urn:ietf:params:oauth:grant-type:device_code"

  def login(dir, opts \\ []) do
    client = System.get_env("IPSE_XAI_CLIENT_ID")

    with true <- client_id?(client) || missing_client(),
         {:ok, original} <- read(dir),
         {:ok, device} <-
           request("/oauth2/device/code", %{"client_id" => client, "scope" => @scope}),
         :ok <- valid_device(device) do
      output = Keyword.get(opts, :output, &IO.puts/1)

      output.(
        "Continue with Grok / xAI (subscription; entitlement required):\n#{device["verification_uri"]}\nEnter code: #{device["user_code"]}\nOnly approve access for your registered Ipse client. No API-key fallback will occur."
      )

      deadline = now() + min(device["expires_in"] * 1000, 300_000)

      with {:ok, response} <-
             poll(client, device["device_code"], device["interval"] || 5, deadline) do
        locked(dir, fn ->
          with {:ok, current} <- read(dir),
               true <-
                 current == original ||
                   {:error, "xAI credentials changed while login was pending; retry login."},
               {:ok, record} <- token_record(client, response, nil),
               :ok <- save(dir, record) do
            :ok
          end
        end)
      end
    else
      {:error, _} = error -> friendly(error)
      _ -> {:error, "xAI device authorization was refused; no credentials were saved."}
    end
  rescue
    _ -> {:error, "xAI authorization failed; no API-key fallback was attempted."}
  end

  def token(dir) do
    locked(dir, fn ->
      with {:ok, record} <- read(dir),
           :ok <- signed_in(record) do
        cond do
          record["refresh_pending"] == true ->
            {:error,
             "An xAI refresh was interrupted and its outcome is unknown. Run ipse login --provider xai_oauth; the refresh will not be replayed."}

          record["expires_at"] > System.system_time(:second) + 30 ->
            {:ok, record["access_token"]}

          true ->
            refresh(dir, record)
        end
      end
    end)
  end

  def status(dir) do
    with {:ok, record} <- read(dir), :ok <- signed_in(record) do
      {:ok,
       %{
         provider: "xai_oauth",
         client_id: record["client_id"],
         expires_at: record["expires_at"],
         refresh_pending: record["refresh_pending"] == true
       }}
    end
  end

  def logout(dir) do
    locked(dir, fn ->
      with {:ok, record} <- read(dir) do
        remote =
          if token_string?(record["refresh_token"]) and client_id?(record["client_id"]) do
            request("/oauth2/revoke", %{
              "client_id" => record["client_id"],
              "token" => record["refresh_token"],
              "token_type_hint" => "refresh_token"
            })
          else
            {:ok, %{}}
          end

        with :ok <- save(dir, %{}) do
          case {record["refresh_pending"], remote} do
            {pending, {:ok, _}} when pending != true ->
              :ok

            _ ->
              {:error,
               "Local xAI credentials were removed; remote revocation is unconfirmed. Revoke the Ipse app in your xAI account settings."}
          end
        end
      end
    end)
  end

  defp refresh(dir, record) do
    with :ok <- save(dir, Map.put(record, "refresh_pending", true)) do
      case request("/oauth2/token", %{
             "grant_type" => "refresh_token",
             "client_id" => record["client_id"],
             "scope" => record["scope"],
             "refresh_token" => record["refresh_token"]
           }) do
        {:ok, response} ->
          tokens = token_record(record["client_id"], response, record)

          with {:ok, next} <- tokens,
               :ok <- save(dir, next) do
            {:ok, next["access_token"]}
          end

        {:oauth_error, code}
        when code in ["invalid_grant", "invalid_client", "unauthorized_client"] ->
          with :ok <- save(dir, %{}),
               do:
                 {:error,
                  "xAI authorization was revoked or the client was refused. Run ipse login --provider xai_oauth."}

        {:oauth_error, _} ->
          with :ok <- save(dir, record),
               do:
                 {:error,
                  "xAI refresh was refused; credentials retained and no fallback attempted."}

        _ ->
          {:error,
           "xAI refresh outcome is unknown. Credentials are marked pending; sign in again before continuing."}
      end
    end
  end

  defp poll(client, code, interval, deadline) do
    if now() + interval * 1000 >= deadline do
      {:error, "xAI device authorization expired; run login again."}
    else
      sleep(interval * 1000)

      case request("/oauth2/token", %{
             "grant_type" => @device_grant,
             "client_id" => client,
             "device_code" => code
           }) do
        {:oauth_error, "authorization_pending"} ->
          poll(client, code, interval, deadline)

        {:oauth_error, "slow_down"} ->
          poll(client, code, interval + 5, deadline)

        {:oauth_error, "access_denied"} ->
          {:error, "xAI authorization was denied; no credentials saved."}

        {:oauth_error, "expired_token"} ->
          {:error, "xAI device authorization expired; run login again."}

        result ->
          friendly(result)
      end
    end
  end

  defp valid_device(device) do
    uri = URI.parse(device["verification_uri"] || "")

    if token_string?(device["device_code"]) and is_binary(device["user_code"]) and
         Regex.match?(~r/\A[A-Za-z0-9 -]{1,64}\z/, device["user_code"]) and
         uri.scheme == "https" and uri.host in ["auth.x.ai", "accounts.x.ai"] and
         uri.port == 443 and is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
         is_binary(uri.path) and Regex.match?(~r/\A\/[A-Za-z0-9_\/-]*\z/, uri.path) and
         is_integer(device["expires_in"]) and device["expires_in"] in 1..3600 and
         (is_nil(device["interval"]) or
            (is_integer(device["interval"]) and device["interval"] in 1..60)),
       do: :ok,
       else: {:error, "xAI returned an invalid or untrusted device authorization response."}
  end

  defp token_record(client, response, previous) do
    previous = previous || %{}
    requested = previous["scope"] || @scope
    refresh = response["refresh_token"] || previous["refresh_token"]
    scope = response["scope"] || requested
    granted = if is_binary(scope), do: String.split(scope), else: []

    if response["token_type"] in ["Bearer", "bearer"] and token_string?(response["access_token"]) and
         token_string?(refresh) and is_integer(response["expires_in"]) and
         response["expires_in"] in 1..31_536_000 and
         "api:access" in granted and Enum.all?(granted, &(&1 in String.split(requested))) do
      {:ok,
       %{
         "version" => 1,
         "issuer" => @issuer,
         "client_id" => client,
         "access_token" => response["access_token"],
         "refresh_token" => refresh,
         "expires_at" => System.system_time(:second) + response["expires_in"],
         "scope" => scope
       }}
    else
      {:error, "xAI returned an invalid token response or unexpected scopes; sign in again."}
    end
  end

  defp signed_in(record) do
    if record["version"] == 1 and record["issuer"] == @issuer and client_id?(record["client_id"]) and
         token_string?(record["access_token"]) and token_string?(record["refresh_token"]) and
         is_integer(record["expires_at"]) and record["expires_at"] > 0 and
         is_binary(record["scope"]) and "api:access" in String.split(record["scope"]),
       do: :ok,
       else:
         {:error,
          "No usable xAI subscription credentials. Run ipse login --provider xai_oauth with your registered Ipse client ID."}
  end

  defp read(dir) do
    path = Path.join(dir, "xai.json")

    with {:ok, record} <- Ipse.Auth.read_credentials(dir, :xai),
         true <- map_size(record) == 0 or owner?(path),
         do: {:ok, record},
         else: (_ ->
                  {:error,
                   "xAI credential file is unsafe or unreadable; inspect owner and permissions."})
  end

  defp owner?(path) do
    with {:ok, uid} <- Ipse.Runner.current_uid(),
         {:ok, %{uid: ^uid}} <- File.lstat(path),
         do: true,
         else: (_ -> false)
  end

  defp save(dir, record), do: friendly(Ipse.Auth.write_credentials(dir, record, :xai))
  defp locked(dir, fun), do: friendly(Ipse.Auth.with_credential_lock(dir, fun, 10_000, :xai))

  defp missing_client,
    do:
      {:error,
       "xAI OAuth requires an approved Ipse client registration. Set IPSE_XAI_CLIENT_ID to that public client ID; no Grok Build or Hermes client ID is bundled. No request was sent."}

  defp client_id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._:-]{0,199}\z/, value)

  defp token_string?(value),
    do:
      is_binary(value) and byte_size(value) in 1..16_384 and
        not Regex.match?(~r/[\x00-\x20\x7f]/, value)

  defp friendly({:oauth_error, _}),
    do:
      {:error,
       "xAI authorization was refused; check your Ipse client registration and account entitlement."}

  defp friendly({:error, message}) when is_binary(message),
    do: {:error, String.replace(message, "ChatGPT", "xAI")}

  defp friendly(result), do: result

  defp real_request(path, fields)
       when path in ["/oauth2/device/code", "/oauth2/token", "/oauth2/revoke"] do
    request =
      Finch.build(
        :post,
        @issuer <> path,
        [
          {"content-type", "application/x-www-form-urlencoded"},
          {"accept", "application/json"},
          {"accept-encoding", "identity"}
        ],
        URI.encode_query(fields)
      )

    case Ipse.HTTP.bounded_request(request, @limit) do
      {:ok, status, bytes} when status in 200..299 and bytes == "" and path == "/oauth2/revoke" ->
        {:ok, %{}}

      {:ok, status, bytes} ->
        decode(status, bytes)

      _ ->
        {:error, "Could not reach xAI authorization; no fallback was attempted."}
    end
  end

  @doc false
  def decode(status, bytes) when is_binary(bytes) and byte_size(bytes) <= @limit do
    case Jason.decode(bytes) do
      {:ok, value} when is_map(value) and status in 200..299 ->
        {:ok, value}

      {:ok, %{"error" => code}} when status in [400, 401, 403] and is_binary(code) ->
        {:oauth_error, code}

      _ ->
        {:error, "xAI authorization returned an invalid response."}
    end
  end

  def decode(_, _), do: {:error, "xAI authorization response exceeded its limit."}

  if Code.ensure_loaded?(Mix) and Mix.env() == :test do
    def with_fixture(transport, sleeper, fun) do
      key = {__MODULE__, :fixture}
      old = Process.get(key)
      Process.put(key, {transport, sleeper})

      try do
        fun.()
      after
        if old, do: Process.put(key, old), else: Process.delete(key)
      end
    end

    defp request(path, fields) do
      case Process.get({__MODULE__, :fixture}) do
        {transport, _} -> transport.(@issuer <> path, fields)
        _ -> real_request(path, fields)
      end
    end

    defp sleep(ms) do
      case Process.get({__MODULE__, :fixture}) do
        {_, sleeper} -> sleeper.(ms)
        _ -> Process.sleep(ms)
      end
    end
  else
    defp request(path, fields), do: real_request(path, fields)
    defp sleep(ms), do: Process.sleep(ms)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
