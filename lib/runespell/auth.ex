defmodule Runespell.Auth do
  @moduledoc """
  Sign in with ChatGPT for an open-source, locally hosted Runespell instance.

  This version retains one selected ChatGPT registration. Reauthorization must
  match its verified account identity; logout retains the registration and host.

  Protocol: https://developers.openai.com/siwc/token-sharing-open-source/sign-in
  Sessions: https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
  """
  alias Runespell.Auth.{HTTP, JWT, Store}
  @issuer "https://auth.openai.com"
  @resource "https://api.openai.com/v1"
  @token_endpoint @issuer <> "/api/accounts/oauth/token"
  @scope "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
  @usage_scope "chatgpt.tokens.use.direct"

  @doc "Print a browser sign-in URL and await its loopback callback for five minutes."
  def login(auth_dir, opts \\ []) do
    Store.with_lock(auth_dir, fn ->
      with {:ok, existing} <- Store.read(auth_dir),
           {:ok, existing} <- ensure_host(auth_dir, existing),
           {:ok, listener} <-
             :gen_tcp.listen(0, [
               :binary,
               active: false,
               packet: :line,
               packet_size: 16_384,
               ip: {127, 0, 0, 1},
               reuseaddr: true,
               backlog: 5
             ]) do
        try do
          {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)

          pending = %{
            state: random(),
            nonce: random(),
            verifier: random(),
            redirect_uri: "http://127.0.0.1:#{port}/auth/callback",
            client_id: existing["client_id"]
          }

          url = authorization_url(existing, pending)
          # The printed URL never includes an ID token hint or credentials.
          output = Keyword.get(opts, :output, &IO.puts/1)

          output.(
            "Continue with ChatGPT:\n#{url}\nWaiting up to five minutes for browser sign-in…"
          )

          deadline = System.monotonic_time(:millisecond) + 300_000

          with {:ok, callback} <- await_callback(listener, pending, deadline),
               {:ok, response} <-
                 HTTP.request(:post, @token_endpoint, %{
                   "grant_type" => "authorization_code",
                   "client_id" => callback["client_id"],
                   "code" => callback["code"],
                   "code_verifier" => pending.verifier,
                   "redirect_uri" => pending.redirect_uri,
                   "resource" => @resource
                 }),
               {:ok, claims} <-
                 validate_identity(
                   response["id_token"],
                   callback["client_id"],
                   pending.nonce,
                   existing["subject"]
                 ),
               {:ok, record} <-
                 token_record(
                   Map.drop(existing, ["scopes", "access_token", "refresh_token", "id_token"]),
                   response,
                   callback["client_id"],
                   claims
                 ),
               :ok <- Store.write(auth_dir, record),
               :ok <- permitted(record) do
            :ok
          end
        after
          :gen_tcp.close(listener)
        end
      else
        {:error, reason} when is_binary(reason) -> {:error, reason}
        _ -> {:error, "Could not start the ChatGPT loopback callback listener."}
      end
    end)
  rescue
    _ -> {:error, "ChatGPT sign-in failed. Retry the login command."}
  end

  @doc "Return a usable access token, serializing refreshes across OS processes."
  def token(auth_dir) do
    Store.with_lock(auth_dir, fn ->
      with {:ok, record} <- Store.read(auth_dir),
           :ok <- signed_in(record),
           :ok <- permitted(record) do
        expires_at = record["expires_at"]

        if is_integer(expires_at) and expires_at > System.system_time(:second) + 60 do
          {:ok, record["access_token"]}
        else
          refresh(auth_dir, record)
        end
      end
    end)
  rescue
    _ -> {:error, "Could not load or refresh ChatGPT credentials. Sign in again."}
  end

  @doc "Return selected account information without tokens or secrets."
  def status(auth_dir) do
    with {:ok, record} <- Store.read(auth_dir), :ok <- signed_in(record) do
      {:ok,
       %{
         email: record["email"],
         client_id: record["client_id"],
         label: record["email"] || "ChatGPT account",
         expires_at: record["expires_at"],
         plan_usage: @usage_scope in (record["scopes"] || [])
       }}
    end
  rescue
    _ -> {:error, "Could not read ChatGPT account status."}
  end

  @doc "Revoke the renewable session and clear local tokens while retaining registration."
  def logout(auth_dir) do
    Store.with_lock(auth_dir, fn ->
      with {:ok, record} <- Store.read(auth_dir) do
        remote = revoke(record)

        clean =
          Map.drop(record, [
            "access_token",
            "refresh_token",
            "id_token",
            "expires_at",
            "expires_in",
            "scopes",
            "token_type",
            "saved_at"
          ])

        with :ok <- Store.write(auth_dir, clean) do
          case remote do
            :ok ->
              :ok

            _ ->
              {:error,
               "Signed out locally; remote revocation could not be confirmed. Disconnect Runespell in ChatGPT Settings to end remote access."}
          end
        end
      end
    end)
  rescue
    _ -> {:error, "Could not sign out of ChatGPT."}
  end

  defp signed_in(record) do
    if nonempty?(record["access_token"]) and nonempty?(record["client_id"]) and
         record["client_id"] != "dynamic_agent_client" and nonempty?(record["subject"]) do
      :ok
    else
      {:error, "No ChatGPT session. Run `runespell login`."}
    end
  end

  defp permitted(record) do
    if is_list(record["scopes"]) and @usage_scope in record["scopes"] do
      :ok
    else
      {:error,
       "ChatGPT plan usage was not authorized. Sign in again and allow plan usage in ChatGPT Settings."}
    end
  end

  defp refresh(auth_dir, record) do
    if nonempty?(record["refresh_token"]) do
      with {:ok, response} <-
             HTTP.request(:post, @token_endpoint, %{
               "grant_type" => "refresh_token",
               "client_id" => record["client_id"],
               "refresh_token" => record["refresh_token"],
               "resource" => @resource
             }),
           {:ok, claims} <- refresh_identity(response, record),
           {:ok, next} <- token_record(record, response, record["client_id"], claims),
           :ok <- Store.write(auth_dir, next),
           :ok <- permitted(next) do
        {:ok, next["access_token"]}
      end
    else
      {:error, "ChatGPT session cannot refresh. Run `runespell login`."}
    end
  end

  defp refresh_identity(response, record) do
    if nonempty?(response["id_token"]) do
      validate_identity(response["id_token"], record["client_id"], nil, record["subject"])
    else
      {:ok, %{"iss" => record["issuer"], "sub" => record["subject"], "email" => record["email"]}}
    end
  end

  defp token_record(existing, response, client_id, claims) do
    expires = response["expires_in"]
    type = response["token_type"]

    if nonempty?(response["access_token"]) and is_integer(expires) and expires > 0 and
         is_binary(type) and String.downcase(type) == "bearer" do
      # RFC 6749 permits omission of unchanged refresh_token and scope on renewal.
      scopes =
        case response["scope"] do
          value when is_binary(value) -> String.split(value, " ", trim: true)
          nil -> existing["scopes"] || []
          _ -> []
        end

      now = System.system_time(:second)

      {:ok,
       Map.merge(existing, %{
         "email" => claims["email"],
         "issuer" => claims["iss"],
         "subject" => claims["sub"],
         "client_id" => client_id,
         "access_token" => response["access_token"],
         "refresh_token" => response["refresh_token"] || existing["refresh_token"],
         "id_token" => response["id_token"] || existing["id_token"],
         "token_type" => "Bearer",
         "expires_in" => expires,
         "expires_at" => now + expires,
         "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
         "scopes" => scopes
       })}
    else
      {:error, "ChatGPT returned an invalid token response. Start a fresh login."}
    end
  end

  defp validate_identity(token, client_id, nonce, subject) do
    with true <- nonempty?(token),
         {:ok, discovery} <- discovery(),
         {:ok, jwks} <- HTTP.request(:get, discovery["jwks_uri"]) do
      JWT.validate(token, jwks, client_id, nonce, subject)
    else
      {:error, _} = error -> error
      _ -> {:error, "ChatGPT did not return an identity token."}
    end
  end

  defp discovery do
    with {:ok, doc} <- HTTP.request(:get, @issuer <> "/.well-known/openid-configuration"),
         true <- doc["issuer"] == @issuer,
         true <- trusted_endpoint?(doc["jwks_uri"]) do
      {:ok, doc}
    else
      {:error, _} = error -> error
      _ -> {:error, "ChatGPT identity discovery was invalid."}
    end
  end

  defp trusted_endpoint?(url) when is_binary(url) do
    uri = URI.parse(url)

    uri.scheme == "https" and uri.host == "auth.openai.com" and uri.port == 443 and
      is_nil(uri.userinfo) and is_nil(uri.fragment)
  end

  defp trusted_endpoint?(_), do: false

  defp revoke(record) do
    if nonempty?(record["refresh_token"]) do
      with {:ok, doc} <- discovery(), true <- trusted_endpoint?(doc["revocation_endpoint"]) do
        revoke_attempt(doc["revocation_endpoint"], record, 0)
      else
        _ -> {:error, :unconfirmed}
      end
    else
      :ok
    end
  end

  defp revoke_attempt(endpoint, record, attempt) do
    case HTTP.request(:post, endpoint, %{
           "token" => record["refresh_token"],
           "token_type_hint" => "refresh_token",
           "client_id" => record["client_id"]
         }) do
      {:ok, _} ->
        :ok

      _ when attempt < 2 ->
        Process.sleep(250 * (attempt + 1))
        revoke_attempt(endpoint, record, attempt + 1)

      _ ->
        {:error, :unconfirmed}
    end
  end

  defp ensure_host(dir, existing) do
    if nonempty?(existing["ext_agent_host_id"]) do
      {:ok, existing}
    else
      <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> = :crypto.strong_rand_bytes(16)

      hex = fn int, width ->
        int |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")
      end

      uuid =
        "#{hex.(a, 8)}-#{hex.(b, 4)}-#{hex.(Bitwise.bor(c, 0x4000), 4)}-#{hex.(Bitwise.bor(d, 0x8000), 4)}-#{hex.(e, 12)}"

      next = Map.put(existing, "ext_agent_host_id", "urn:uuid:" <> uuid)
      with :ok <- Store.write(dir, next), do: {:ok, next}
    end
  end

  defp authorization_url(existing, pending) do
    params = %{
      "client_id" => pending.client_id || "dynamic_agent_client",
      "ext_agent_host_id" => existing["ext_agent_host_id"],
      "response_type" => "code",
      "redirect_uri" => pending.redirect_uri,
      "scope" => @scope,
      "resource" => @resource,
      "state" => pending.state,
      "nonce" => pending.nonce,
      "code_challenge_method" => "S256",
      "code_challenge" =>
        :crypto.hash(:sha256, pending.verifier) |> Base.url_encode64(padding: false)
    }

    params =
      if pending.client_id, do: params, else: Map.put(params, "agent_name_hint", "Runespell")

    params =
      if nonempty?(existing["email"]),
        do: Map.put(params, "login_hint", existing["email"]),
        else: params

    @issuer <> "/api/accounts/authorize?" <> URI.encode_query(params)
  end

  defp await_callback(listener, pending, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case :gen_tcp.accept(listener, remaining) do
      {:ok, socket} ->
        result =
          try do
            parse_request(socket, pending, min(remaining, 2_000))
          after
            :gen_tcp.close(socket)
          end

        case result do
          :retry -> await_callback(listener, pending, deadline)
          result -> result
        end

      {:error, :timeout} ->
        {:error, "ChatGPT sign-in timed out after five minutes. Start a fresh login."}

      _ ->
        {:error, "ChatGPT callback listener stopped unexpectedly."}
    end
  end

  defp parse_request(socket, pending, timeout) do
    with {:ok, line} <- :gen_tcp.recv(socket, 0, timeout),
         ["GET", target, "HTTP/1.1"] <- line |> String.trim() |> String.split(" "),
         %URI{path: "/auth/callback", query: query, host: nil} when is_binary(query) <-
           URI.parse(target),
         {:ok, params} <- query_params(query),
         true <- JWT.secure_equal?(params["state"], pending.state) do
      result = callback_result(params, pending.client_id)

      case result do
        {:ok, _} ->
          respond(
            socket,
            200,
            "Authorization received. Return to Runespell; it will validate your account."
          )

        _ ->
          respond(socket, 400, "Authorization was declined or invalid. Return to Runespell.")
      end

      result
    else
      _ ->
        respond(socket, 400, "Invalid callback.")
        :retry
    end
  rescue
    _ ->
      respond(socket, 400, "Invalid callback.")
      :retry
  end

  defp query_params(query) do
    pairs = URI.query_decoder(query) |> Enum.to_list()
    keys = Enum.map(pairs, &elem(&1, 0))
    if length(keys) == length(Enum.uniq(keys)), do: {:ok, Map.new(pairs)}, else: :error
  end

  defp callback_result(params, selected_client) do
    cond do
      Map.has_key?(params, "error") ->
        {:error,
         "ChatGPT authorization was declined. Start a fresh login to authorize plan usage."}

      not nonempty?(params["code"]) ->
        {:error, "ChatGPT callback did not include an authorization code."}

      selected_client && params["client_id"] not in [nil, selected_client] ->
        {:error, "ChatGPT returned a different registration. The saved account was preserved."}

      is_nil(selected_client) and
          (not nonempty?(params["client_id"]) or params["client_id"] == "dynamic_agent_client") ->
        {:error, "ChatGPT registration did not return an issued client ID. Start a fresh login."}

      true ->
        {:ok, Map.put(params, "client_id", selected_client || params["client_id"])}
    end
  end

  defp respond(socket, status, body) do
    :gen_tcp.send(
      socket,
      "HTTP/1.1 #{status} #{if status == 200, do: "OK", else: "Bad Request"}\r\n" <>
        "Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n" <>
        "Content-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
    )
  end

  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp nonempty?(value), do: is_binary(value) and byte_size(value) > 0
end
